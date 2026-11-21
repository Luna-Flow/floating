import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import gate_lock
import run_ci
import verify

LIVE = 4242
DEAD = 4343


def alive(pid: int) -> bool:
    return pid == LIVE


def write_lock(root: Path, pid: int, started: str = "2026-11-21T22:00:00+0900", command: str = "run_ci.py quick 4") -> Path:
    lock = root / gate_lock.LOCK_RELATIVE
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.write_text(json.dumps({"pid": pid, "started": started, "command": command}), encoding="utf-8")
    return lock


class DecideTest(unittest.TestCase):
    def test_the_three_cases(self) -> None:
        holder = gate_lock.Holder(1, "t", "c")
        self.assertEqual(gate_lock.decide(holder, True), "busy")
        self.assertEqual(gate_lock.decide(holder, False), "stale")
        self.assertEqual(gate_lock.decide(None, False), "stale")  # a file that is not a lock

    def test_parse(self) -> None:
        self.assertEqual(gate_lock.parse_holder('{"pid": 3, "started": "s", "command": "c"}'), gate_lock.Holder(3, "s", "c"))
        for text in ("", "nope", "{}", '{"pid": "x", "started": 1, "command": 2}'):
            self.assertIsNone(gate_lock.parse_holder(text), text)

    def test_the_real_pid_check(self) -> None:
        self.assertTrue(gate_lock.pid_alive(os.getpid()))
        self.assertFalse(gate_lock.pid_alive(2**22 + 12345))


class HoldTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.lines: list[str] = []

    def test_a_free_worktree_is_taken_and_released(self) -> None:
        lock = self.root / gate_lock.LOCK_RELATIVE
        with gate_lock.hold(self.root, "run_ci.py quick 4", pid=LIVE, alive=alive, out=self.lines.append):
            self.assertEqual(gate_lock.parse_holder(lock.read_text()).pid, LIVE)  # type: ignore[union-attr]
        self.assertFalse(lock.exists())
        self.assertEqual(self.lines, [])
        self.assertEqual(sorted(p.name for p in lock.parent.iterdir()), [])  # no temporary file left

    def test_a_second_run_refuses_at_once_with_one_line_naming_the_holder_and_leaves_it_alone(self) -> None:
        lock = write_lock(self.root, LIVE, started="2026-11-21T22:00:00+0900")
        before = lock.read_text()
        with self.assertRaises(gate_lock.GateBusy) as raised:
            with gate_lock.hold(self.root, "run_ci.py pr", pid=999, alive=alive, out=self.lines.append):
                self.fail("a busy worktree must not run")
        message = str(raised.exception)
        self.assertIn(f"pid {LIVE}", message)
        self.assertIn("2026-11-21T22:00:00+0900", message)
        self.assertNotIn("\n", message)
        self.assertEqual(lock.read_text(), before)  # the holder's lock is untouched

    def test_a_lock_of_a_dead_pid_is_taken_over_with_a_line_saying_so(self) -> None:
        lock = write_lock(self.root, DEAD, started="2026-11-21T21:00:00+0900")
        with gate_lock.hold(self.root, "run_ci.py quick 4", pid=LIVE, alive=alive, out=self.lines.append):
            self.assertEqual(gate_lock.parse_holder(lock.read_text()).pid, LIVE)  # type: ignore[union-attr]
        self.assertEqual(len(self.lines), 1)
        self.assertIn(f"pid {DEAD}", self.lines[0])
        self.assertIn("gone", self.lines[0])
        self.assertFalse(lock.exists())

    def test_a_file_that_is_not_a_lock_is_taken_over(self) -> None:
        lock = self.root / gate_lock.LOCK_RELATIVE
        lock.parent.mkdir(parents=True)
        lock.write_text("garbage", encoding="utf-8")
        with gate_lock.hold(self.root, "c", pid=LIVE, alive=alive, out=self.lines.append):
            pass
        self.assertIn("not a lock file", self.lines[0])

    def test_a_lock_is_released_when_the_run_raises_and_is_not_removed_if_it_is_another_runs(self) -> None:
        lock = self.root / gate_lock.LOCK_RELATIVE
        with self.assertRaises(RuntimeError):
            with gate_lock.hold(self.root, "c", pid=LIVE, alive=alive):
                raise RuntimeError("stage failed")
        self.assertFalse(lock.exists())
        with gate_lock.hold(self.root, "c", pid=LIVE, alive=alive):
            write_lock(self.root, 7)  # someone replaced it (a takeover): ours must not delete theirs
        self.assertEqual(gate_lock.parse_holder(lock.read_text()).pid, 7)  # type: ignore[union-attr]

    def test_two_runs_with_real_pids(self) -> None:
        with gate_lock.hold(self.root, "first"):
            with self.assertRaises(gate_lock.GateBusy) as raised:
                with gate_lock.hold(self.root, "second", pid=os.getpid() + 1):
                    pass
            self.assertIn(f"pid {os.getpid()}", str(raised.exception))

    def test_guarded_does_not_run_a_busy_worktree_and_returns_the_busy_status(self) -> None:
        write_lock(self.root, os.getpid())
        ran: list[int] = []
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = gate_lock.guarded(self.root, "run_ci.py pr", lambda: ran.append(1) or 0)
        self.assertEqual((status, ran), (gate_lock.EXIT_BUSY, []))
        self.assertEqual(len(stderr.getvalue().strip().splitlines()), 1)

    def test_guarded_returns_what_the_run_returns(self) -> None:
        self.assertEqual(gate_lock.guarded(self.root, "c", lambda: 3), 3)
        self.assertFalse((self.root / gate_lock.LOCK_RELATIVE).exists())


class EntryPointsTest(unittest.TestCase):
    """`just pr`, `just gate` and `just verify` go through the lock; a dry run takes none."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_run_ci_refuses_a_busy_worktree_without_running_a_stage(self) -> None:
        write_lock(self.root, os.getpid())
        with patch.object(run_ci, "REPO_ROOT", self.root), patch.object(run_ci, "run_stages", side_effect=AssertionError("ran")):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(run_ci.run("quick", 3), gate_lock.EXIT_BUSY)

    def test_run_ci_dry_run_takes_no_lock_and_ignores_a_busy_one(self) -> None:
        lock = write_lock(self.root, os.getpid())
        before = lock.read_text()
        with patch.object(run_ci, "REPO_ROOT", self.root), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(run_ci.run("quick", 3, dry_run=True), 0)
        self.assertIn("TEST: native", out.getvalue())
        self.assertEqual(lock.read_text(), before)

    def test_run_ci_takes_the_lock_while_it_runs_and_releases_it(self) -> None:
        seen: list[bool] = []
        lock = self.root / gate_lock.LOCK_RELATIVE

        def stages(*_: object) -> int:
            seen.append(lock.exists())
            return 0

        with patch.object(run_ci, "REPO_ROOT", self.root), patch.object(run_ci, "run_stages", stages):
            self.assertEqual(run_ci.run("quick", 3), 0)
        self.assertEqual(seen, [True])
        self.assertFalse(lock.exists())

    def test_verify_refuses_a_busy_worktree_and_its_dry_and_plan_runs_take_no_lock(self) -> None:
        lock = write_lock(self.root, os.getpid())
        with patch.object(verify, "REPO_ROOT", self.root):
            with patch.object(verify, "run_unlocked", side_effect=AssertionError("ran")), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(verify.run("binary", 3), gate_lock.EXIT_BUSY)
            with patch.object(verify, "run_unlocked", return_value=0) as unlocked:
                self.assertEqual(verify.run("binary", 3, dry_run=True), 0)
                self.assertEqual(verify.run("binary", 3, plan_only=True), 0)
                self.assertEqual(unlocked.call_count, 2)
        self.assertTrue(lock.exists())


if __name__ == "__main__":
    unittest.main()
