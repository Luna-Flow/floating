"""One gate run per worktree.

Two runs of the quick gate (`just pr`) or of a gate (`just gate <scope>`, `just verify <scope>`)
in one worktree share the target directory `_build` and write throwaway sources into the same
tracked trees (the generated IEEE fixtures, the manual examples' packages), so a stage of one run
fails on files the other is writing or deleting: formatting, regenerated test files (#728).
Separate worktrees do not share any of that.

A run takes `<worktree>/.tmp/gate.lock` for its whole length (the lock of the checkout the tools
run from, never the shared `.tmp` of the main checkout). A second run in the same worktree
refuses at once with one line that names the pid and the start time of the holder: it never
waits and never ends the other run. A lock whose pid is dead (a run that was killed) is taken
over, with a line that says so. `--dry-run` runs take none.

The lock file is created with its content in one step (a temporary file linked into place, which
fails if the lock exists), so a second run never reads a half-written lock. A pid that was reused
by an unrelated process reads as a live holder: the message gives the file to delete.

The decision (`decide`) is pure; the file and process calls are in `hold` and `pid_alive`.
"""

from __future__ import annotations

import contextlib
import dataclasses
import json
import os
import sys
import time
from collections.abc import Callable, Iterator
from pathlib import Path

LOCK_RELATIVE = Path(".tmp") / "gate.lock"
EXIT_BUSY = 75  # EX_TEMPFAIL: nothing ran, try again later


@dataclasses.dataclass(frozen=True)
class Holder:
    pid: int
    started: str
    command: str


class GateBusy(Exception):
    """Another run holds the lock of this worktree."""


def parse_holder(text: str) -> Holder | None:
    """The holder written in a lock file, or None when the text is not one."""
    try:
        data = json.loads(text)
        return Holder(int(data["pid"]), str(data["started"]), str(data["command"]))
    except (ValueError, KeyError, TypeError):
        return None


def decide(holder: Holder | None, alive: bool) -> str:
    """`free` (no lock), `busy` (a live holder) or `stale` (a dead holder, or a file that is not a lock)."""
    if holder is None:
        return "stale"
    return "busy" if alive else "stale"


def busy_message(holder: Holder, lock: Path) -> str:
    return (
        f"gate: another gate run holds this worktree (pid {holder.pid}, started {holder.started}, "
        f"`{holder.command}`); not started. Use another worktree or wait for it; if that pid is not a gate "
        f"run, delete {lock}"
    )


def stale_message(holder: Holder | None, lock: Path) -> str:
    if holder is None:
        return f"gate: {lock} is not a lock file; taking it over"
    return f"gate: taking over the lock of pid {holder.pid} (started {holder.started}, `{holder.command}`): that process is gone"


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # it exists, owned by someone else
    except OSError:
        return False
    return True


def _create(lock: Path, holder: Holder) -> bool:
    """Create the lock with its content in one step; False when it exists."""
    lock.parent.mkdir(parents=True, exist_ok=True)
    temporary = lock.with_name(f"{lock.name}.{holder.pid}.tmp")
    temporary.write_text(json.dumps(dataclasses.asdict(holder)), encoding="utf-8")
    try:
        os.link(temporary, lock)
        return True
    except FileExistsError:
        return False
    finally:
        temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def hold(
    root: Path,
    command: str,
    pid: int | None = None,
    alive: Callable[[int], bool] = pid_alive,
    out: Callable[[str], None] = lambda line: print(line, file=sys.stderr),
    clock: Callable[[], str] = lambda: time.strftime("%Y-%m-%dT%H:%M:%S%z"),
) -> Iterator[None]:
    """Hold the gate lock of the worktree `root` or raise `GateBusy`."""
    me = Holder(os.getpid() if pid is None else pid, clock(), command)
    lock = root / LOCK_RELATIVE
    for _ in range(3):
        if _create(lock, me):
            break
        try:
            holder = parse_holder(lock.read_text(encoding="utf-8"))
        except FileNotFoundError:
            continue  # released meanwhile: try again
        if decide(holder, holder is not None and alive(holder.pid)) == "busy":
            assert holder is not None
            raise GateBusy(busy_message(holder, lock))
        out(stale_message(holder, lock))
        lock.unlink(missing_ok=True)
    else:
        raise GateBusy(f"gate: could not take {lock}: it kept changing hands")
    try:
        yield
    finally:
        held = parse_holder(lock.read_text(encoding="utf-8")) if lock.exists() else None
        if held is not None and held.pid == me.pid:
            lock.unlink(missing_ok=True)


def guarded(root: Path, command: str, run: Callable[[], int]) -> int:
    """Run `run()` while holding the lock; a busy worktree prints the one line and returns `EXIT_BUSY`."""
    try:
        with hold(root, command):
            return run()
    except GateBusy as busy:
        print(busy, file=sys.stderr)
        return EXIT_BUSY
