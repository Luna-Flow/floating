import json
import random
import subprocess
import tempfile
import types
import unittest
from pathlib import Path
from typing import Any

import code_fingerprint as cf
import incremental as inc

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS = "_M0FP411Luna_2dFlow16floating_2dtools"
LIB = "_M0MP311Luna_2dFlow8floating6binary6Binary"


def program_text(
    add_body: str = "return a + b;",
    sub_body: str = "return a - b;",
    execute_body: str = "return arm(x);",
    init_value: int = 1,
    silent_sub: bool = False,
    arms: bool = True,
) -> str:
    note = f"{TOOLS}8frontend15testfloat__expr9note__arm"
    arm = "arm" if arms else "plain"
    sub_note = "" if silent_sub else f"{note}(1); "
    return "\n".join(
        [
            f"static int32_t {LIB}8add__ctx(int32_t a, int32_t b) {{ {add_body} }}",
            f"static int32_t {LIB}8sub__ctx(int32_t a, int32_t b) {{ {sub_body} }}",
            f"static void {note}(int32_t n) {{ (void)n; }}",
            f"static int32_t {TOOLS}8frontend15testfloat__expr8{arm}__add(int32_t a, int32_t b) {{",
            f"  {note}(0); return {LIB}8add__ctx(a, b);",
            "}",
            f"static int32_t {TOOLS}8frontend15testfloat__expr8{arm}__sub(int32_t a, int32_t b) {{",
            f"  {sub_note}return {LIB}8sub__ctx(a, b);",
            "}",
            f"static int32_t {TOOLS}8frontend15testfloat__expr12execute__case(int32_t op, int32_t a, int32_t b) {{",
            f"  if (op == 0) {{ return {TOOLS}8frontend15testfloat__expr8{arm}__add(a, b); }}",
            f"  return {TOOLS}8frontend15testfloat__expr8{arm}__sub(a, b);",
            "}",
            f"static int32_t {TOOLS}8frontend10mpfr__expr12execute__data(int32_t x) {{ {execute_body.replace('arm(x)', 'x')} }}",
            f"static int32_t {TOOLS}3cli20testfloat__expr__cli3run(int32_t x) {{",
            f"  return {TOOLS}8frontend15testfloat__expr12execute__case(x, 1, 2);",
            "}",
            f"static int32_t {TOOLS}3cli15mpfr__expr__cli3run(int32_t x) {{",
            f"  return {TOOLS}8frontend10mpfr__expr12execute__data(x);",
            "}",
            f"static int32_t {TOOLS}3cli8dispatch8dispatch(int32_t x) {{",
            f"  return {TOOLS}3cli20testfloat__expr__cli3run(x) + {TOOLS}3cli15mpfr__expr__cli3run(x);",
            "}",
            f"static int32_t g_{init_value};",
            "void moonbit_init() {",
            f"  g_{init_value} = {init_value};",
            "}",
            "int main(int argc, char** argv) {",
            "  moonbit_init();",
            f"  return {TOOLS}3cli8dispatch8dispatch(argc);",
            "}",
            "",
        ]
    )


def builder(text: str | None = None, toolchain: str = "tc", verifier: str = "v") -> inc.KeyBuilder:
    return inc.KeyBuilder(cf.parse_program(text or program_text()), toolchain, verifier)


class KeyTests(unittest.TestCase):
    def test_digest_is_prefix_free(self) -> None:
        self.assertNotEqual(inc.digest("ab", "c"), inc.digest("a", "bc"))
        self.assertEqual(inc.digest("a", "b"), inc.digest("a", "b"))

    def test_arms_are_found_by_name(self) -> None:
        arms = inc.arm_definitions(builder().program, inc.FRONTENDS["testfloat"].arm or "")
        self.assertEqual(sorted(arms), ["add", "sub"])

    def test_derived_closures_are_not_arms(self) -> None:
        text = program_text() + f"static int32_t {TOOLS}8frontend15testfloat__expr8arm__addC1l2(int32_t a) {{ return a; }}\n"
        text = text.replace("return {0}8add__ctx(a, b);".format(LIB), "return a;")  # keep the text valid
        arms = inc.arm_definitions(cf.parse_program(text), inc.FRONTENDS["testfloat"].arm or "")
        self.assertEqual(sorted(arms), ["add", "sub"])

    def test_an_arm_change_leaves_the_pre_key_and_changes_only_its_result_key(self) -> None:
        a, b = builder(), builder(program_text(add_body="return a + b + 0;"))
        pre_a, pre_b = a.pre_key("testfloat", "in", "args"), b.pre_key("testfloat", "in", "args")
        self.assertEqual(pre_a, pre_b)
        self.assertNotEqual(a.result_key("testfloat", pre_a, ["add"]), b.result_key("testfloat", pre_b, ["add"]))
        self.assertEqual(a.result_key("testfloat", pre_a, ["sub"]), b.result_key("testfloat", pre_b, ["sub"]))

    def test_a_change_the_arm_reaches_through_the_library_is_seen_by_its_arm(self) -> None:
        b = builder(program_text(sub_body="return a - b - 0;"))
        a = builder()
        pre = a.pre_key("testfloat", "in", "args")
        self.assertEqual(pre, b.pre_key("testfloat", "in", "args"))
        self.assertNotEqual(a.result_key("testfloat", pre, ["sub"]), b.result_key("testfloat", pre, ["sub"]))
        self.assertEqual(a.result_key("testfloat", pre, ["add"]), b.result_key("testfloat", pre, ["add"]))

    def test_a_rerouting_in_the_dispatcher_changes_the_pre_key(self) -> None:
        a = builder()
        b = builder(program_text().replace("if (op == 0) {", "if (op == 1) {"))
        self.assertNotEqual(a.pre_key("testfloat", "in", "args"), b.pre_key("testfloat", "in", "args"))

    def test_a_changed_initialiser_changes_every_pre_key(self) -> None:
        a, b = builder(program_text(init_value=1)), builder(program_text(init_value=2))
        self.assertNotEqual(a.pre_key("testfloat", "in", "args"), b.pre_key("testfloat", "in", "args"))
        self.assertNotEqual(a.pre_key("mpfr", "in", "args"), b.pre_key("mpfr", "in", "args"))

    def test_the_other_frontend_does_not_change_a_testfloat_key(self) -> None:
        a = builder()
        b = builder(program_text(execute_body="return x + 1;"))
        self.assertEqual(a.pre_key("testfloat", "in", "args"), b.pre_key("testfloat", "in", "args"))
        self.assertNotEqual(a.pre_key("mpfr", "in", "args"), b.pre_key("mpfr", "in", "args"))

    def test_input_arguments_toolchain_and_verifier_are_in_the_key(self) -> None:
        base = builder().pre_key("testfloat", "in", "args")
        self.assertNotEqual(base, builder().pre_key("testfloat", "in2", "args"))
        self.assertNotEqual(base, builder().pre_key("testfloat", "in", "args2"))
        self.assertNotEqual(base, builder(toolchain="other").pre_key("testfloat", "in", "args"))
        self.assertNotEqual(base, builder(verifier="other").pre_key("testfloat", "in", "args"))

    def test_an_arm_without_a_definition_has_no_key(self) -> None:
        b = builder()
        self.assertIsNone(b.result_key("testfloat", "pre", ["add", "ghost"]))

    def test_a_coarse_frontend_has_a_key_from_the_pre_key_alone(self) -> None:
        b = builder()
        pre = b.pre_key("mpfr", "in", "args")
        self.assertEqual(b.result_key("mpfr", pre, []), b.result_key("mpfr", pre, ["ignored"]))

    def test_an_unmatched_entry_pattern_is_an_error(self) -> None:
        text = program_text().replace("mpfr__expr__cli3run", "other__cli3run")
        with self.assertRaises(cf.UnknownEntryError):
            builder(text).pre_key("mpfr", "in", "args")


def record(kind: str, key: str, **extra: Any) -> dict[str, Any]:
    return {"kind": kind, "key": key, "unit": "u", "commit": "c0ffee", **extra}


class LedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "sub" / "ledger.jsonl"

    def test_append_and_read_back(self) -> None:
        ledger = inc.Ledger(self.path)
        ledger.append([record("arms", "p", arms=["add"]), record("result", "r", result={"passedCases": 3})])
        again = inc.Ledger(self.path)
        self.assertEqual(again.recorded_arms("p"), ["add"])
        result = again.result("r")
        assert result is not None
        self.assertEqual(result["result"]["passedCases"], 3)
        self.assertIsNone(again.result("missing"))
        self.assertIsNone(again.recorded_arms("missing"))

    def test_the_first_record_of_a_key_counts_and_the_file_only_grows(self) -> None:
        ledger = inc.Ledger(self.path)
        ledger.append([record("result", "r", result={"n": 1})])
        before = self.path.read_text()
        ledger.append([record("result", "r", result={"n": 2})])
        self.assertEqual(self.path.read_text(), before)
        ledger.append([record("result", "s", result={"n": 3})])
        self.assertTrue(self.path.read_text().startswith(before))
        result = inc.Ledger(self.path).result("r")
        assert result is not None
        self.assertEqual(result["result"]["n"], 1)

    def test_two_arm_sets_for_one_key_are_a_defect(self) -> None:
        ledger = inc.Ledger(self.path)
        ledger.append([record("arms", "p", arms=["add"])])
        with self.assertRaises(inc.SystemDefect):
            ledger.append([record("arms", "p", arms=["add", "sub"])])
        ledger.append([record("arms", "p", arms=["add"])])  # the same set again is fine

    def test_appends_see_each_other_and_leave_no_temporary_file(self) -> None:
        one, two = inc.Ledger(self.path), inc.Ledger(self.path)
        one.append([record("result", "a", result={})])
        two.append([record("result", "b", result={})])
        merged = inc.Ledger(self.path)
        self.assertIsNotNone(merged.result("a"))
        self.assertIsNotNone(merged.result("b"))
        leftovers = [p.name for p in self.path.parent.iterdir() if p.name.startswith(".ledger.")]
        self.assertEqual(leftovers, [])

    def test_ledger_path_override_and_main_checkout(self) -> None:
        self.assertEqual(inc.ledger_path(Path("."), {"LUNA_VERIFICATION_LEDGER": "/x/l.jsonl"}), Path("/x/l.jsonl"))
        repo = Path(self.tmp.name) / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        self.assertEqual(inc.main_checkout(repo).resolve(), repo.resolve())
        self.assertEqual(inc.ledger_path(repo, {}).resolve(), (repo / ".tmp/verification-ledger/ledger.jsonl").resolve())


class DecideTests(unittest.TestCase):
    def lookups(self, reusable: int, fresh: int) -> dict[str, tuple[str, dict[str, Any] | None]]:
        table: dict[str, tuple[str, dict[str, Any] | None]] = {}
        for i in range(reusable):
            table[f"r{i}"] = ("", {"commit": "c"})
        for i in range(fresh):
            table[f"f{i}"] = ("no record", None)
        return table

    def test_units_without_a_record_run(self) -> None:
        decisions = inc.decide(self.lookups(0, 3), random.Random(1))
        self.assertEqual([d.action for d in decisions], ["run"] * 3)

    def test_two_percent_of_the_reusable_units_are_sampled_at_least_one(self) -> None:
        for reusable, expected in ((1, 1), (3, 1), (50, 1), (51, 2), (534, 11)):
            decisions = inc.decide(self.lookups(reusable, 2), random.Random(7))
            self.assertEqual(sum(d.action == "sample" for d in decisions), expected, reusable)
            self.assertEqual(sum(d.action == "reuse" for d in decisions), reusable - expected)
            self.assertEqual(sum(d.action == "run" for d in decisions), 2)

    def test_a_rate_of_zero_samples_nothing(self) -> None:
        decisions = inc.decide(self.lookups(10, 0), random.Random(1), rate=0.0)
        self.assertEqual([d.action for d in decisions], ["reuse"] * 10)

    def test_the_seed_decides_the_sample(self) -> None:
        def pick(seed: int) -> list[str]:
            return [d.unit for d in inc.decide(self.lookups(100, 0), random.Random(seed)) if d.action == "sample"]

        self.assertEqual(pick(5), pick(5))
        self.assertNotEqual(pick(5), pick(6))

    def test_a_result_that_differs_is_reported_by_field(self) -> None:
        self.assertEqual(inc.compare_result({"passedCases": 1}, {"passedCases": 1}), [])
        self.assertEqual(len(inc.compare_result({"failedCases": 0, "failedIds": []}, {"failedCases": 1, "failedIds": ["x"]})), 2)


class ArmConventionTests(unittest.TestCase):
    """An arm that does not record itself, or a build without arms, makes the frontend coarse."""

    def test_arms_that_reference_the_note_function_are_used(self) -> None:
        b = builder()
        self.assertTrue(b.has_arms("testfloat"))
        self.assertEqual(b.warnings, [])

    def test_an_arm_that_does_not_note_itself_makes_the_frontend_one_coarse_unit_and_is_reported(self) -> None:
        silent = builder(program_text(silent_sub=True))
        self.assertFalse(silent.has_arms("testfloat"))
        self.assertTrue(any("sub" in w and "do not reference" in w for w in silent.warnings))
        # coarse: a change of an arm now changes the pre key of every unit of the frontend
        changed = builder(program_text(silent_sub=True, add_body="return a + b + 0;"))
        self.assertNotEqual(silent.pre_key("testfloat", "in", "a"), changed.pre_key("testfloat", "in", "a"))

    def test_a_build_without_arm_functions_is_coarse_and_reported(self) -> None:
        plain = builder(program_text(arms=False))
        self.assertFalse(plain.has_arms("testfloat"))
        self.assertTrue(any("no arm function" in w for w in plain.warnings))
        pre = plain.pre_key("testfloat", "in", "a")
        self.assertIsNotNone(plain.result_key("testfloat", pre, []))


class RecordTests(unittest.TestCase):
    def test_the_ledger_keeps_the_components_of_a_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ledger.jsonl"
            env = inc.Environment(inc.Ledger(path), builder(), "aaaa", False, "logs", 1, clock=lambda: "now")
            unit = inc.UnitSpec("u", "testfloat", "in", "args")

            def run(units: Any) -> list[dict[str, Any]]:
                return [{"frontend": "testfloat", "totalCases": 1, "selectedCases": 1, "passedCases": 1, "failedCases": 0, "failedIds": [], "arms": ["add"]}]

            inc.run_units([unit], env, run)
            records = [json.loads(line) for line in path.read_text().splitlines()]
            result = next(r for r in records if r["kind"] == "result")
            self.assertEqual(sorted(result["parts"]), ["args", "frame", "input", "toolchain", "verifier", "version"])
            self.assertEqual(list(result["arm_fingerprints"]), ["add"])
            self.assertEqual(result["pre_key"], env.builder.pre_key("testfloat", "in", "args"))


class RouteTests(unittest.TestCase):
    def test_a_process_that_ran_another_frontend_is_a_defect(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env = inc.Environment(inc.Ledger(Path(tmp) / "l.jsonl"), builder(), "aaaa", False, "logs", 1)
            unit = inc.UnitSpec("u", "testfloat", "in", "args")

            def run(units: Any) -> list[dict[str, Any]]:
                return [{"frontend": "mpfr", "failedCases": 0, "arms": ["add"]}]

            with self.assertRaises(inc.SystemDefect):
                inc.run_units([unit], env, run)

            def silent(units: Any) -> list[dict[str, Any]]:
                return [{"failedCases": 0, "arms": ["add"]}]

            with self.assertRaises(inc.SystemDefect):
                inc.run_units([unit], env, silent)


class KeyErrorTests(unittest.TestCase):
    def test_an_entry_pattern_that_matches_nothing_is_keys_unavailable_and_runs_nothing(self) -> None:
        text = program_text().replace("testfloat__expr__cli3run", "other__cli3run")
        ran: list[str] = []
        with tempfile.TemporaryDirectory() as tmp:
            env = inc.Environment(inc.Ledger(Path(tmp) / "l.jsonl"), builder(text), "aaaa", False, "logs", 1)

            def run(units: Any) -> list[dict[str, Any]]:
                ran.extend(u.name for u in units)
                return []

            with self.assertRaises(inc.KeysUnavailable):
                inc.run_units([inc.UnitSpec("u", "testfloat", "in", "a")], env, run)
            self.assertEqual(ran, [])
            self.assertFalse((Path(tmp) / "l.jsonl").exists())

    def test_load_context_turns_a_missing_c_file_into_keys_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(inc.KeysUnavailable):
                inc.load_context(Path(tmp), Path(tmp) / "absent.c", Path(tmp) / "t")

    def test_two_entries_that_match_are_an_error_too(self) -> None:
        text = program_text() + f"static int32_t _M0FP5Other3cli20testfloat__expr__cli3run(int32_t x) {{ return 0; }}\n"
        with self.assertRaises(cf.UnknownEntryError):
            builder(text).frame("testfloat")


class BindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.exe = self.dir / "x-conformance.exe"
        self.c = self.dir / "cli.c"
        self.exe.write_bytes(b"exe")
        self.c.write_text("c")

    def test_a_missing_build_record_disables_incremental(self) -> None:
        self.assertIn("no build record", inc.binding_problem(self.exe, self.c) or "")

    def test_a_matching_record_binds_the_c_file_to_the_executable(self) -> None:
        import conformance_cli

        conformance_cli.write_build_record(self.exe, self.c)
        self.assertIsNone(inc.binding_problem(self.exe, self.c))

    def test_a_rebuild_after_the_copy_or_a_changed_executable_is_seen(self) -> None:
        import conformance_cli

        conformance_cli.write_build_record(self.exe, self.c)
        self.c.write_text("c rebuilt")
        self.assertIn("not the C file", inc.binding_problem(self.exe, self.c) or "")
        self.c.write_text("c")
        self.assertIsNone(inc.binding_problem(self.exe, self.c))
        self.exe.write_bytes(b"other exe")
        self.assertIn("not the executable", inc.binding_problem(self.exe, self.c) or "")

    def test_an_unreadable_record_is_a_problem(self) -> None:
        (self.dir / "x-conformance.exe.build.json").write_text("not json")
        self.assertIn("unreadable", inc.binding_problem(self.exe, self.c) or "")


class VerifierTests(unittest.TestCase):
    def test_the_judge_is_the_set_of_imported_tool_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "tools").mkdir()
            judge, other = repo / "tools" / "judge.py", repo / "tools" / "unrelated.py"
            judge.write_text("a")
            other.write_text("b")
            outside = repo / "elsewhere.py"
            outside.write_text("c")
            modules = {
                "judge": types.SimpleNamespace(__file__=str(judge)),
                "outside": types.SimpleNamespace(__file__=str(outside)),
                "builtin": types.SimpleNamespace(),
            }
            self.assertEqual([p.name for p in inc.imported_tool_files(repo, modules)], ["judge.py"])
            first = inc.verifier_digest(repo, modules)
            judge.write_text("a changed")
            self.assertNotEqual(first, inc.verifier_digest(repo, modules))
            modules["unrelated"] = types.SimpleNamespace(__file__=str(other))
            self.assertEqual([p.name for p in inc.imported_tool_files(repo, modules)], ["judge.py", "unrelated.py"])

    def test_a_module_added_later_is_covered_without_a_list(self) -> None:
        self.assertIn("incremental.py", [p.name for p in inc.imported_tool_files(REPO_ROOT)])
        self.assertIn("code_fingerprint.py", [p.name for p in inc.imported_tool_files(REPO_ROOT)])


class EnvironmentTests(unittest.TestCase):
    def test_the_limb_tier_states_give_different_toolchain_digests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo, home = Path(tmp) / "repo", Path(tmp) / "moon"
            (repo / "library/src/k").mkdir(parents=True)
            (repo / "tooling").mkdir()
            (home / "lib/runtime").mkdir(parents=True)
            (home / "include").mkdir()
            (repo / "library/src/k/stub.c").write_text('int x = getenv("LUNA_FLOATING_PORTABLE") != 0 && getenv("LUNA_FLOATING_LIMBS");\n')
            digests = {}
            for name, environ in (("default", {}), ("portable", {"LUNA_FLOATING_PORTABLE": "1"}), ("c", {"LUNA_FLOATING_LIMBS": "c"})):
                parts = cf.collect_toolchain(repo, home, lambda command: "v", environ=environ)
                digests[name] = cf.toolchain_digest(parts)
            self.assertEqual(len(set(digests.values())), 3)


class FlowTests(unittest.TestCase):
    """The whole flow with a fake runner: first run, reuse, sample, change, defect."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "ledger.jsonl"
        self.ran: list[str] = []

    def environment(self, b: inc.KeyBuilder, seed: int = 1, commit: str = "aaaa") -> inc.Environment:
        return inc.Environment(inc.Ledger(self.path), b, commit, False, "logs", seed, clock=lambda: "now")

    def units(self) -> list[inc.UnitSpec]:
        out = [inc.UnitSpec(f"f16_add_{i}", "testfloat", f"in{i}", f"add{i}") for i in range(60)]
        out += [inc.UnitSpec(f"f16_sub_{i}", "testfloat", f"sin{i}", f"sub{i}") for i in range(60)]
        out.append(inc.UnitSpec("mpfr_sqrt", "mpfr", "file", "mpfr"))
        return out

    def runner(self, fail: set[str] | None = None, tamper: set[str] | None = None) -> Any:
        def run(units: Any) -> list[dict[str, Any]]:
            payloads = []
            for unit in units:
                self.ran.append(unit.name)
                arms = ["add"] if "add" in unit.name else ["sub"] if "sub" in unit.name else []
                bad = unit.name in (fail or set())
                passed = 0 if bad else 10
                if unit.name in (tamper or set()):
                    passed = 9
                payloads.append(
                    {"frontend": unit.frontend, "totalCases": 10, "selectedCases": 10, "passedCases": passed, "failedCases": 10 - passed, "failedIds": ["x"] if bad else [], "arms": arms}
                )
            return payloads

        return run

    def test_first_run_records_second_run_reuses_all_but_the_sample(self) -> None:
        b = builder()
        outcomes, tally = inc.run_units(self.units(), self.environment(b), self.runner())
        self.assertEqual((tally.ran, tally.reused, tally.sampled), (121, 0, 0))
        self.ran.clear()
        outcomes, tally = inc.run_units(self.units(), self.environment(b, commit="bbbb"), self.runner())
        self.assertEqual((tally.ran, tally.reused, tally.sampled, tally.failed), (0, 118, 3, 0))
        self.assertEqual(len(self.ran), 3)
        self.assertEqual(inc.reused_by_commit(outcomes), {"aaaa": 118})
        self.assertTrue(all(o.commit == "aaaa" for o in outcomes if o.status in ("reused", "sampled")))

    def test_an_arm_change_reruns_exactly_the_units_that_recorded_it(self) -> None:
        inc.run_units(self.units(), self.environment(builder()), self.runner())
        self.ran.clear()
        changed = builder(program_text(add_body="return a + b + 0;"))
        _, tally = inc.run_units(self.units(), self.environment(changed, seed=3), self.runner())
        add_units = {u.name for u in self.units() if "add" in u.name}
        self.assertEqual(tally.ran, 60)
        self.assertEqual({n for n in self.ran if n in add_units}, add_units)
        self.assertEqual(len([n for n in self.ran if n not in add_units]), tally.sampled)

    def test_a_dispatcher_change_reruns_everything(self) -> None:
        inc.run_units(self.units(), self.environment(builder()), self.runner())
        self.ran.clear()
        rerouted = builder(program_text().replace("if (op == 0) {", "if (op == 1) {"))
        _, tally = inc.run_units(self.units(), self.environment(rerouted), self.runner())
        self.assertEqual((tally.ran, tally.reused), (120, 0))  # the mpfr unit is outside the dispatcher edge

    def test_a_failing_unit_is_not_recorded(self) -> None:
        b = builder()
        _, tally = inc.run_units(self.units(), self.environment(b), self.runner(fail={"f16_add_3"}))
        self.assertEqual(tally.failed, 1)
        self.ran.clear()
        _, tally = inc.run_units(self.units(), self.environment(b, seed=9), self.runner())
        self.assertIn("f16_add_3", self.ran)

    def test_a_sampled_rerun_that_differs_is_a_defect(self) -> None:
        b = builder()
        inc.run_units(self.units(), self.environment(b), self.runner())
        every = {u.name for u in self.units()}
        with self.assertRaises(inc.SystemDefect):
            inc.run_units(self.units(), self.environment(b, seed=2), self.runner(tamper=every))

    def test_a_unit_whose_arm_has_no_definition_is_not_recorded(self) -> None:
        b = builder()
        unit = inc.UnitSpec("odd", "testfloat", "in", "args")

        def run(units: Any) -> list[dict[str, Any]]:
            return [{"frontend": "testfloat", "totalCases": 1, "selectedCases": 1, "passedCases": 1, "failedCases": 0, "failedIds": [], "arms": ["ghost"]}]

        _, tally = inc.run_units([unit], self.environment(b), run)
        self.assertEqual((tally.ran, tally.unrecorded), (1, 1))

    def test_the_summary_line_never_mixes_run_and_reused(self) -> None:
        line = inc.summary_line(inc.Tally(ran=3, reused=531, sampled=11, failed=0), 42, {"abcdef0123456789": 531})
        self.assertIn("ran 3", line)
        self.assertIn("reused 531", line)
        self.assertIn("abcdef0123", line)
        self.assertIn("seed 42", line)
        self.assertNotIn("passed", line.lower())


if __name__ == "__main__":
    unittest.main()
