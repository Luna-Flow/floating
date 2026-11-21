import random
import tempfile
import unittest
from pathlib import Path
from typing import Any

import incremental as inc
import kernel_units as ku
import verify

STAGES = [
    ("BINARY: TestFloat + MPFR", ("python3", "tools/conformance.py", "run", "--backend", "binary")),
    ("BINARY: kernel product routes (default)", ("sh", "tools/run_moon_clean_exec.sh", "test", "a.mbt")),
    ("BINARY: kernel product routes (C rows)", ("env", "LUNA_FLOATING_LIMBS=c", "sh", "tools/run_moon_clean_exec.sh", "test", "a.mbt")),
    ("BINARY: kernel oracle tables", ("python3", "tools/kernel_oracle.py", "--check", "--all")),
]


def make_repo(root: Path, imports: str = '"moonbitlang/core/debug"') -> None:
    pkg = root / ku.KERNEL_PACKAGE
    pkg.mkdir(parents=True)
    (pkg / "moon.pkg").write_text("import {\n  " + imports + ",\n}\n")
    (pkg / "a.mbt").write_text("fn f() -> Int { 1 }\n")
    (pkg / "a_wbtest.mbt").write_text('test "a" { assert_eq(1, 1) }\n')
    (pkg / "luna_limbs.c").write_text("int x;\n")
    (root / "library" / "src" / "bin_float").mkdir(parents=True)
    (root / "library" / "src" / "bin_float" / "b.mbt").write_text("fn g() -> Int { 2 }\n")
    (root / "library" / "moon.mod").write_text('name = "x"\n')
    (root / "tools").mkdir()
    (root / "tools" / "kernel_oracle.py").write_text("import math\nprint(math.gcd(4, 6))\n")
    (root / "tools" / "run_moon_clean_exec.sh").write_text('exec moon --target-dir "$T" "$@"\n')


def fake_run(command: Any, cwd: Any = None) -> str:
    return "moonc build-package ./library/src/internal/bin_kernel/a.mbt -g -O0\n"


class KeyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        make_repo(self.root)
        self.units = {u.name: u for u in ku.kernel_units(STAGES)}

    def key(
        self, name: str, toolchain: str = "t", verifier: str = "v", compile_commands: str = "c", python: str = "3.13", ambient: str = ""
    ) -> str:
        unit = self.units[name]
        package = ku.content_digest(self.root, ku.package_files(self.root))
        extra = ku.content_digest(self.root, [self.root / f for f in unit.extra_files])
        return ku.unit_key(unit, package, extra, compile_commands, toolchain, verifier, python, ambient)[0]

    def test_only_the_kernel_stages_are_units(self) -> None:
        self.assertEqual(sorted(self.units), sorted(n for n, _ in STAGES if n.startswith("BINARY: kernel")))
        self.assertEqual(self.units["BINARY: kernel oracle tables"].kind, "python")

    def test_a_package_file_changes_every_key_a_file_outside_changes_none(self) -> None:
        before = {n: self.key(n) for n in self.units}
        (self.root / "library/src/bin_float/b.mbt").write_text("fn g() -> Int { 3 }\n")
        self.assertEqual(before, {n: self.key(n) for n in self.units})
        (self.root / ku.KERNEL_PACKAGE / "a.mbt").write_text("fn f() -> Int { 2 }\n")
        after = {n: self.key(n) for n in self.units}
        for name in self.units:
            self.assertNotEqual(before[name], after[name], name)

    def test_a_test_file_a_comment_a_stub_and_the_module_file_change_every_key(self) -> None:
        base = {n: self.key(n) for n in self.units}
        for relative, text in (
            (f"{ku.KERNEL_PACKAGE}/a_wbtest.mbt", 'test "a" { assert_eq(2, 2) }\n'),
            (f"{ku.KERNEL_PACKAGE}/a.mbt", "// only a comment\nfn f() -> Int { 1 }\n"),
            (f"{ku.KERNEL_PACKAGE}/luna_limbs.c", "int y;\n"),
            ("library/moon.mod", 'name = "y"\n'),
        ):
            path = self.root / relative
            original = path.read_text()
            path.write_text(text)
            changed = {n: self.key(n) for n in self.units}
            self.assertTrue(all(changed[n] != base[n] for n in self.units), relative)
            path.write_text(original)
        self.assertEqual(base, {n: self.key(n) for n in self.units})

    def test_the_state_is_in_the_key_through_the_command(self) -> None:
        self.assertNotEqual(
            self.key("BINARY: kernel product routes (default)"), self.key("BINARY: kernel product routes (C rows)")
        )

    def test_the_toolchain_the_verifier_and_the_build_commands_are_in_every_key(self) -> None:
        base = self.key("BINARY: kernel product routes (default)")
        self.assertNotEqual(base, self.key("BINARY: kernel product routes (default)", toolchain="other"))
        self.assertNotEqual(base, self.key("BINARY: kernel product routes (default)", verifier="other"))
        self.assertNotEqual(base, self.key("BINARY: kernel product routes (default)", compile_commands="-O2"))

    def test_the_moon_wrapper_is_in_every_moon_key_and_not_in_the_oracle_tables_key(self) -> None:
        moon, tables = "BINARY: kernel product routes (default)", "BINARY: kernel oracle tables"
        before_moon, before_tables = self.key(moon), self.key(tables)
        (self.root / ku.MOON_WRAPPER).write_text('exec moon --target-dir "$T" --other "$@"\n')
        self.assertNotEqual(before_moon, self.key(moon))
        self.assertNotEqual(self.key("BINARY: kernel product routes (C rows)"), before_moon)
        self.assertEqual(before_tables, self.key(tables))

    def test_the_ambient_variables_of_moon_and_the_stubs_are_in_the_key(self) -> None:
        moon = "BINARY: kernel product routes (default)"
        base = self.key(moon)
        env = {"HOME": "/x", "MOON_HOME": "/m", "CODEX_MOON_TARGET_DIR": "/t", "LUNA_FLOATING_LIMBS": "c", "PATH": "/bin"}
        text = ku.ambient_environment(env)
        self.assertEqual(text.count("\n"), 2)
        self.assertNotIn("HOME=/x", text)
        self.assertNotEqual(base, self.key(moon, ambient=text))
        self.assertNotEqual(self.key(moon, ambient=text), self.key(moon, ambient=ku.ambient_environment({**env, "MOON_HOME": "/other"})))
        self.assertEqual(base, self.key(moon, ambient=ku.ambient_environment({"HOME": "/y"})))

    def test_the_oracle_tables_depend_on_their_program_and_the_python_version_only_there(self) -> None:
        tables = "BINARY: kernel oracle tables"
        base = self.key(tables)
        (self.root / "tools/kernel_oracle.py").write_text("print(2)\n")
        self.assertNotEqual(base, self.key(tables))
        self.assertNotEqual(self.key(tables), self.key(tables, python="3.14"))
        moon = "BINARY: kernel product routes (default)"
        self.assertEqual(self.key(moon), self.key(moon, python="3.14"))

    def test_a_python_unit_that_imports_outside_the_standard_library_is_flagged(self) -> None:
        path = self.root / "tools" / "kernel_oracle.py"
        self.assertIsNone(ku.python_unit_problem(path))
        path.write_text("import math\nimport corpus_common\n")
        problem = ku.python_unit_problem(path)
        assert problem is not None
        self.assertIn("corpus_common", problem)
        path.write_text("from . import sibling\n")
        self.assertIsNotNone(ku.python_unit_problem(path))
        path.write_text("def (:\n")
        self.assertIn("cannot be read", ku.python_unit_problem(path) or "")

    def test_a_package_that_imports_the_repository_is_not_a_leaf(self) -> None:
        self.assertIsNone(ku.leaf_problem(["moonbitlang/core/debug", "moonbitlang/core/string"]))
        problem = ku.leaf_problem(["moonbitlang/core/debug", "Luna-Flow/floating/def"])
        assert problem is not None
        self.assertIn("Luna-Flow/floating/def", problem)


class PlanTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        make_repo(self.root)
        self.ledger = inc.Ledger(self.root / "ledger.jsonl")

    def plan(self, seed: int = 1, rate: float = 0.0) -> ku.Plan:
        return ku.make_plan(STAGES, self.root, self.ledger, seed, rate, run=fake_run)

    def test_without_records_every_unit_runs_and_a_pass_is_recorded(self) -> None:
        plan = self.plan()
        self.assertEqual(set(plan.actions.values()), {"run"})
        for unit in plan.units:
            ku.record_pass(plan, unit, 1.5)
        again = self.plan()
        self.assertEqual(set(again.actions.values()), {"reuse"})
        self.assertEqual(again.keys, plan.keys)
        record = self.ledger.result(plan.keys[plan.units[0].name])
        assert record is not None
        self.assertEqual(sorted(record["parts"]), ["ambient", "command", "compile", "extra", "package", "python", "toolchain", "unit", "verifier", "version"])

    def test_an_edit_of_the_package_makes_every_unit_run_again(self) -> None:
        for unit in (plan := self.plan()).units:
            ku.record_pass(plan, unit, 1.0)
        (self.root / ku.KERNEL_PACKAGE / "a.mbt").write_text("fn f() -> Int { 9 }\n")
        self.assertEqual(set(self.plan().actions.values()), {"run"})

    def test_an_edit_outside_the_package_leaves_every_unit_reusable(self) -> None:
        for unit in (plan := self.plan()).units:
            ku.record_pass(plan, unit, 1.0)
        (self.root / "library/src/bin_float/b.mbt").write_text("fn g() -> Int { 7 }\n")
        self.assertEqual(set(self.plan().actions.values()), {"reuse"})

    def test_a_python_unit_with_an_outside_import_always_runs_and_is_never_recorded(self) -> None:
        (self.root / "tools" / "kernel_oracle.py").write_text("import corpus_common\n")
        plan = self.plan()
        name = "BINARY: kernel oracle tables"
        self.assertIn("corpus_common", plan.unit_disabled[name])
        unit = next(u for u in plan.units if u.name == name)
        self.assertFalse(ku.record_pass(plan, unit, 1.0))
        self.assertEqual(self.plan().actions[name], "run")

    def test_a_pass_is_not_recorded_when_the_files_changed_during_the_run(self) -> None:
        plan = self.plan()
        unit = plan.units[0]
        (self.root / ku.KERNEL_PACKAGE / "a.mbt").write_text("fn f() -> Int { 5 }\n")  # edited while the stage ran
        self.assertFalse(ku.record_pass(plan, unit, 1.0))
        self.assertIsNone(self.ledger.result(plan.keys[unit.name]))
        (self.root / ku.KERNEL_PACKAGE / "a.mbt").write_text("fn f() -> Int { 1 }\n")  # restored: the key holds again
        self.assertTrue(ku.record_pass(plan, unit, 1.0))

    def test_a_wrapper_edit_during_the_run_is_seen_too(self) -> None:
        plan = self.plan()
        unit = next(u for u in plan.units if u.kind == "moon")
        (self.root / ku.MOON_WRAPPER).write_text("changed\n")
        self.assertFalse(ku.record_pass(plan, unit, 1.0))

    def test_a_package_that_is_not_a_leaf_disables_reuse(self) -> None:
        (self.root / ku.KERNEL_PACKAGE / "moon.pkg").write_text('import {\n  "Luna-Flow/floating/def",\n}\n')
        plan = self.plan()
        self.assertIn("not a leaf", plan.disabled)
        self.assertEqual(set(plan.actions.values()), {"run"})

    def test_moon_that_prints_nothing_disables_reuse(self) -> None:
        plan = ku.make_plan(STAGES, self.root, self.ledger, 1, 0.0, run=lambda command, cwd=None: "")
        self.assertIn("could not print", plan.disabled)

    def test_the_sample_is_drawn_per_unit_with_the_seed(self) -> None:
        keys = {f"u{i}": f"k{i}" for i in range(7)}
        def drawn(seed: int) -> dict[str, str]:
            return ku.decide_units(keys, lambda k: True, random.Random(seed), 0.5)

        self.assertEqual(drawn(3), drawn(3))
        self.assertNotEqual(drawn(3), drawn(4))
        self.assertEqual(set(ku.decide_units(keys, lambda k: True, random.Random(1), 0.0).values()), {"reuse"})
        self.assertEqual(set(ku.decide_units(keys, lambda k: False, random.Random(1), 1.0).values()), {"run"})
        self.assertEqual(set(ku.decide_units(keys, lambda k: True, random.Random(1), 1.0).values()), {"sample"})


class RunStagesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        make_repo(self.root)
        self.ledger = inc.Ledger(self.root / "ledger.jsonl")
        self.stages = [(n, c, False) for n, c in STAGES]
        self.executed: list[str] = []
        self.lines: list[str] = []

    def plan(self, rate: float = 0.0, seed: int = 1) -> ku.Plan:
        return ku.make_plan(STAGES, self.root, self.ledger, seed, rate, run=fake_run)

    def execute(self, fail: str = "") -> Any:
        def run(command: tuple[str, ...]) -> int:
            self.executed.append(" ".join(command))
            return 1 if fail and fail in " ".join(command) else 0

        return run

    def test_second_run_reuses_the_stages_and_says_so(self) -> None:
        status, tally, _ = verify.run_stages(self.stages, self.plan(), self.execute(), self.lines.append)
        self.assertEqual((status, tally.ran, tally.reused), (0, 3, 0))
        self.executed.clear()
        self.lines.clear()
        status, tally, commits = verify.run_stages(self.stages, self.plan(), self.execute(), self.lines.append)
        self.assertEqual((status, tally.ran, tally.reused), (0, 0, 3))
        self.assertEqual(len(self.executed), 1)  # only the non-kernel stage
        self.assertEqual(sum(1 for l in self.lines if l.startswith("REUSED")), 3)
        self.assertFalse(any(l.startswith("PASS") and "kernel" in l for l in self.lines))
        self.assertEqual(sum(commits.values()), 3)

    def test_a_stage_that_passes_after_an_edit_during_the_run_is_reported_as_not_recorded(self) -> None:
        plan = self.plan()

        def run(command: tuple[str, ...]) -> int:
            (self.root / ku.KERNEL_PACKAGE / "a.mbt").write_text("fn f() -> Int { 8 }\n")
            return 0

        status, tally, _ = verify.run_stages(self.stages, plan, run, self.lines.append)
        self.assertEqual(status, 0)
        self.assertEqual(tally.unrecorded, 3)
        self.assertEqual(sum(1 for l in self.lines if l.startswith("NOTE")), 3)
        self.assertIn("not recorded 3", ku.summary_line(tally, 1, 0.02, {}))

    def test_a_failing_stage_is_not_recorded_and_stops_the_run(self) -> None:
        status, tally, _ = verify.run_stages(self.stages, self.plan(), self.execute(fail="LUNA_FLOATING_LIMBS=c"), self.lines.append)
        self.assertNotEqual(status, 0)
        self.assertEqual(tally.failed, 1)
        plan = self.plan()
        self.assertEqual(plan.actions["BINARY: kernel product routes (C rows)"], "run")
        self.assertEqual(plan.actions["BINARY: kernel product routes (default)"], "reuse")

    def test_a_sampled_stage_that_fails_is_a_defect_of_the_system(self) -> None:
        verify.run_stages(self.stages, self.plan(), self.execute(), self.lines.append)
        status, tally, _ = verify.run_stages(self.stages, self.plan(rate=1.0), self.execute(fail="kernel_oracle"), self.lines.append)
        self.assertEqual(status, inc.EXIT_DEFECT)
        self.assertTrue(any(l.startswith("DEFECT") for l in self.lines))

    def test_a_sampled_stage_that_passes_counts_as_sampled(self) -> None:
        verify.run_stages(self.stages, self.plan(), self.execute(), self.lines.append)
        self.executed.clear()
        status, tally, _ = verify.run_stages(self.stages, self.plan(rate=1.0), self.execute(), self.lines.append)
        self.assertEqual((status, tally.sampled, tally.reused, tally.ran), (0, 3, 0, 0))
        self.assertEqual(len(self.executed), 4)

    def test_without_a_plan_everything_runs_as_before(self) -> None:
        status, tally, _ = verify.run_stages(self.stages, None, self.execute(), self.lines.append)
        self.assertEqual((status, len(self.executed)), (0, 4))

    def test_the_summary_line_names_the_rule_and_never_mixes(self) -> None:
        line = ku.summary_line(ku.KernelTally(ran=1, reused=6, sampled=0), 7, 0.02, {"abcdef0123456": 6})
        self.assertIn("ran 1", line)
        self.assertIn("reused 6 [6 from abcdef0123]", line)
        self.assertIn("probability 0.02", line)
        self.assertIn("seed 7", line)
        self.assertNotIn("passed", line.lower())
        self.assertIn("not reusable", ku.summary_line(ku.KernelTally(disabled="why"), 1, 0.02, {}))


if __name__ == "__main__":
    unittest.main()
