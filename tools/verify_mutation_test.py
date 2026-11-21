import unittest
from pathlib import Path

import incremental_test as fx
import verify_mutation as vm

REPO_ROOT = Path(__file__).resolve().parent.parent


class MutationFileTests(unittest.TestCase):
    def test_every_mutation_applies_to_the_current_sources_exactly_once(self) -> None:
        for mutation in vm.MUTATIONS:
            text = (REPO_ROOT / mutation.path).read_text(encoding="utf-8")
            changed = vm.apply_mutation(text, mutation)
            self.assertNotEqual(changed, text, mutation.name)

    def test_mutation_names_are_unique_and_kinds_known(self) -> None:
        names = [m.name for m in vm.MUTATIONS]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue({m.kind for m in vm.MUTATIONS} <= {"behavioural", "comment", "format", "key-only"})
        kinds = {m.kind for m in vm.MUTATIONS}
        self.assertEqual(kinds, {"behavioural", "comment", "format", "key-only"})

    def test_the_required_places_are_covered(self) -> None:
        paths = " ".join(m.path for m in vm.MUTATIONS)
        for part in ("internal/bin_kernel", "bin_float/", "ball_float/", "src/decimal/", "decimal_gda/", "tooling/src/frontend"):
            self.assertIn(part, paths)

    def test_a_missing_or_repeated_old_text_is_refused(self) -> None:
        mutation = vm.Mutation("m", "p", "f", "s", "x", "y", "behavioural")
        with self.assertRaises(ValueError):
            vm.apply_mutation("nothing", mutation)
        with self.assertRaises(ValueError):
            vm.apply_mutation("x x", mutation)
        self.assertEqual(vm.apply_mutation("a x b", mutation), "a y b")


class ExpectationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.builder = fx.builder()
        self.closures = {
            "add_unit": vm.unit_closure(self.builder, "testfloat", ["add"]),
            "sub_unit": vm.unit_closure(self.builder, "testfloat", ["sub"]),
            "mpfr_unit": vm.unit_closure(self.builder, "mpfr", []),
        }
        self.definitions = list(self.builder.program.definitions)

    def test_an_arm_function_is_reached_by_its_units_only(self) -> None:
        self.assertEqual(vm.expected_ran(self.closures, r"8add__ctx$", self.definitions), {"add_unit"})
        self.assertEqual(vm.expected_ran(self.closures, r"8sub__ctx$", self.definitions), {"sub_unit"})

    def test_the_dispatcher_and_the_start_up_code_are_reached_by_every_testfloat_unit(self) -> None:
        self.assertEqual(
            vm.expected_ran(self.closures, r"testfloat__expr12execute__case$", self.definitions), {"add_unit", "sub_unit"}
        )
        self.assertEqual(vm.expected_ran(self.closures, r"^moonbit_init$", self.definitions), set(self.closures))

    def test_the_other_frontend_is_not_reached_by_testfloat_units(self) -> None:
        self.assertEqual(vm.expected_ran(self.closures, r"mpfr__expr12execute__data$", self.definitions), {"mpfr_unit"})

    def test_the_expectation_agrees_with_the_keys_for_every_function(self) -> None:
        """Membership in a closure and a change of the key give the same set (two computations)."""
        mutated = (
            ("8add__ctx", fx.builder(fx.program_text(add_body="return a + b + 0;"))),
            ("8sub__ctx", fx.builder(fx.program_text(sub_body="return a - b - 0;"))),
        )
        for symbol, changed in mutated:
            expected = vm.expected_ran(self.closures, symbol + "$", self.definitions)
            by_key = set()
            for unit, arms, frontend in (("add_unit", ["add"], "testfloat"), ("sub_unit", ["sub"], "testfloat")):
                pre = self.builder.pre_key(frontend, "in", "a")
                if self.builder.result_key(frontend, pre, arms) != changed.result_key(frontend, changed.pre_key(frontend, "in", "a"), arms):
                    by_key.add(unit)
            self.assertEqual(expected, by_key, symbol)


class BindingJudgeTests(unittest.TestCase):
    summary = {"testfloat": {"tasks": [1, 2]}, "mpfr": [3]}

    def test_a_disabled_run_that_executed_everything_and_recorded_nothing_holds(self) -> None:
        self.assertEqual(vm.judge_binding(self.summary, {"a", "b", "c"}, "x", "x"), [])

    def test_an_incremental_run_a_partial_run_or_a_recorded_result_is_a_problem(self) -> None:
        self.assertTrue(vm.judge_binding({**self.summary, "incremental": {}}, {"a", "b", "c"}, "x", "x"))
        self.assertTrue(vm.judge_binding(self.summary, {"a", "b", "c", "d"}, "x", "x"))
        self.assertTrue(vm.judge_binding(self.summary, {"a", "b", "c"}, "x", "xy"))

    def test_tampering_breaks_and_restores_the_record(self) -> None:
        import json
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            scratch = Path(tmp)
            sidecar = scratch / "_build/conformance/testfloat/native/release/build/testfloat-conformance.exe.build.json"
            sidecar.parent.mkdir(parents=True)
            sidecar.write_text(json.dumps({"exe_sha256": "a", "cli_c_sha256": "b"}))
            c_file = scratch / "_build/conformance/cli/native/release/build/Luna-Flow/floating-tools/cli/cli.c"
            c_file.parent.mkdir(parents=True)
            c_file.write_text("c")
            for kind in vm.BINDING_TAMPERS:
                before = (sidecar.read_text(), c_file.read_text())
                restore = vm.tamper(scratch, kind)
                self.assertNotEqual(before, (sidecar.read_text(), c_file.read_text()))
                restore()
                self.assertEqual(before, (sidecar.read_text(), c_file.read_text()))


class ScratchTests(unittest.TestCase):
    def test_a_scratch_worktree_on_another_commit_or_dirty_is_refused(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            scratch = Path(tmp)
            self.assertIn("no commit", vm.scratch_problem(scratch) or "")  # not a repository


class JudgeTests(unittest.TestCase):
    behavioural = vm.Mutation("m", "p", "f", "s", "o", "n", "behavioural")

    def test_a_held_mutation_has_no_problem(self) -> None:
        self.assertEqual(vm.judge(self.behavioural, {"a"}, {"a"}, {"a"}, {"a", "b"}, ["d"], {"a"}), [])

    def test_a_surviving_mutation_is_a_problem(self) -> None:
        self.assertTrue(vm.judge(self.behavioural, {"a"}, {"a"}, set(), {"a", "b"}, ["d"], set()))

    def test_a_unit_that_fails_on_the_mutated_build_but_was_reused_is_a_false_reuse(self) -> None:
        # `expected` and `ran` agree (both miss the unit `b`), only the full run sees that b fails
        problems = vm.judge(self.behavioural, {"a"}, {"a"}, {"a"}, {"a", "b"}, ["d"], {"a", "b"})
        self.assertEqual(len(problems), 1)
        self.assertIn("FALSE REUSE", problems[0])
        self.assertIn("b", problems[0])

    def test_a_mutation_without_a_full_run_has_no_false_reuse_check(self) -> None:
        key_only = vm.Mutation("m", "p", "f", "s", "o", "n", "key-only")
        self.assertEqual(vm.judge(key_only, {"a"}, {"a"}, set(), {"a", "b"}, ["d"]), [])

    def test_a_key_set_that_differs_from_the_reach_is_a_problem(self) -> None:
        self.assertTrue(vm.judge(self.behavioural, {"a"}, {"a", "b"}, {"a"}, {"a", "b"}, ["d"], {"a"}))
        self.assertTrue(vm.judge(self.behavioural, {"a", "b"}, {"a"}, {"a"}, {"a", "b"}, ["d"], {"a"}))

    def test_an_edit_that_changes_no_code_must_run_nothing(self) -> None:
        comment = vm.Mutation("m", "p", "f", "s", "o", "n", "comment")
        self.assertEqual(vm.judge(comment, set(), set(), set(), {"a"}, ["d"]), [])
        self.assertTrue(vm.judge(comment, {"a"}, {"a"}, set(), {"a"}, ["d"]))

    def test_an_outside_mutation_must_reach_nothing(self) -> None:
        outside = vm.Mutation("m", "p", "f", "s", "o", "n", "key-only")
        self.assertEqual(vm.judge(outside, set(), set(), set(), {"a"}, ["d"]), [])
        self.assertTrue(vm.judge(outside, set(), {"a"}, set(), {"a"}, ["d"]))

    def test_a_wrong_symbol_is_a_problem(self) -> None:
        self.assertTrue(vm.judge(self.behavioural, set(), set(), set(), {"a"}, [], set()))

    def test_the_table_has_one_row_per_mutation(self) -> None:
        row = {"name": "n", "kind": "k", "function": "f", "expected": 1, "ran": 1, "failed": 1, "reused_failing": 0, "verdict": "held"}
        self.assertEqual(len(vm.format_table([row, row]).splitlines()), 4)


if __name__ == "__main__":
    unittest.main()
