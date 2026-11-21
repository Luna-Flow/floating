import tempfile
import unittest
from pathlib import Path

import incremental as inc
import native_units as nu

L = nu.LIBRARY
T = nu.TOOLING


OK = (0, "Total tests: 10, passed: 10, failed: 0.\n")
FAILED = (1, "Total tests: 10, passed: 9, failed: 1.\n")
# the real texts of moon 0.1.2026 for a `-p` name that selects nothing (measured by the manager)
NOT_FOUND_TEXT = "Warning: package `Luna-Flow/floating/nonexistent` not found\nTotal tests: 0, passed: 0, failed: 0.\n"
SILENT_TEXT = "Total tests: 23, passed: 23, failed: 0.\n"


def pkg(pid: str, *imports: str) -> nu.Package:
    return nu.Package(pid, pid.replace(L, "library/src").replace(T, "tooling/src"), tuple(imports))


def graph() -> dict[str, nu.Package]:
    items = [
        pkg(f"{L}/def"),
        pkg(f"{L}/bin_float", f"{L}/def", "moonbitlang/core/bigint"),
        pkg(f"{L}/interval", f"{L}/bin_float", "moonbitlang/core/debug"),
        pkg(f"{L}/small", f"{L}/def"),
        pkg(f"{T}/bench", f"{L}/interval", "moonbitlang/x/fs"),
        pkg(f"{T}/frontend", f"{L}/bin_float"),
    ]
    return {p.id: p for p in items}


class GraphTest(unittest.TestCase):
    def test_closure_follows_internal_imports_only(self) -> None:
        self.assertEqual(nu.closure(f"{L}/interval", graph()), {f"{L}/interval", f"{L}/bin_float", f"{L}/def"})

    def test_a_missing_package_is_an_error_not_a_smaller_closure(self) -> None:
        g = graph()
        g[f"{L}/small"] = pkg(f"{L}/small", f"{L}/ghost")
        with self.assertRaises(KeyError):
            nu.closure(f"{L}/small", g)

    def test_the_tools_module_is_not_a_prefix_match_of_the_library(self) -> None:
        self.assertTrue(nu.internal_package(f"{T}/bench"))
        self.assertTrue(nu.internal_package(L))
        self.assertFalse(nu.internal_package("Luna-Flow/floatingX/a"))

    def test_impure_imports_are_found_through_the_closure(self) -> None:
        self.assertEqual(nu.impure_imports([f"{T}/bench"], graph()), ["moonbitlang/x/fs"])
        self.assertEqual(nu.impure_imports([f"{L}/interval"], graph()), [])

    def test_units_split_heavy_keyed_rest_and_not_keyed(self) -> None:
        units = nu.make_units(graph(), heavy=(f"{L}/interval", f"{L}/bin_float"))
        names = [u.name for u in units]
        self.assertEqual(names, [f"{L}/interval", f"{L}/bin_float", "rest", "rest (not keyed)"])
        rest = {u.name: u for u in units}
        self.assertEqual(rest["rest"].members, (f"{T}/frontend", f"{L}/def", f"{L}/small"))
        self.assertEqual(rest["rest (not keyed)"].members, (f"{T}/bench",))
        self.assertFalse(rest["rest (not keyed)"].keyed)
        # every package is in exactly one unit
        members = [m for u in units for m in u.members]
        self.assertEqual(sorted(members), sorted(graph()))

    def test_a_heavy_package_that_does_not_exist_is_an_error(self) -> None:
        with self.assertRaises(KeyError):
            nu.make_units(graph(), heavy=(f"{L}/nothing",))

    def test_files_of_a_unit_cover_its_closure(self) -> None:
        unit = nu.Unit("u", (f"{L}/interval",), True)
        self.assertEqual(nu.unit_files(unit, graph()), ["library/src/bin_float", "library/src/def", "library/src/interval"])


class KeyTest(unittest.TestCase):
    unit = nu.Unit("u", (f"{L}/interval",), True)

    def key(self, **change: str) -> str:
        base = dict(closure_digest="c", compile_commands="x", module_digest="m", wrapper_digest="w", toolchain="t", verifier="v", ambient="")
        base.update(change)
        return nu.unit_key(self.unit, **base)[0]

    def test_every_part_changes_the_key(self) -> None:
        reference = self.key()
        for part, value in (
            ("closure_digest", "c2"), ("compile_commands", "y"), ("module_digest", "m2"),
            ("wrapper_digest", "w2"), ("toolchain", "t2"), ("verifier", "v2"), ("ambient", "LUNA_FLOATING_LIMBS=c"),
        ):
            self.assertNotEqual(self.key(**{part: value}), reference, part)

    def test_the_members_are_in_the_key(self) -> None:
        other = nu.Unit("u", (f"{L}/interval", f"{L}/def"), True)
        a = nu.unit_key(self.unit, "c", "x", "m", "w", "t", "v", "")[0]
        b = nu.unit_key(other, "c", "x", "m", "w", "t", "v", "")[0]
        self.assertNotEqual(a, b)


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ledger = inc.Ledger(Path(self.tmp.name) / "l.jsonl")
        self.units = nu.make_units(graph(), heavy=(f"{L}/interval", f"{L}/bin_float"))
        self.original_unchanged = nu.unchanged
        nu.unchanged = lambda plan, unit: True  # type: ignore[assignment]  # the files are not on disk here
        self.addCleanup(setattr, nu, "unchanged", self.original_unchanged)

    def plan(self, actions: dict[str, str]) -> nu.Plan:
        keys = {u.name: f"key-{i}" for i, u in enumerate(self.units) if u.keyed}
        parts = {n: {"unit": n} for n in keys}
        plan = nu.Plan(self.units, keys, parts, actions, {n: "d" for n in keys}, "m", "", self.ledger, 1, 0.02, "c0ffee", False, Path(self.tmp.name))
        plan.packages = graph()
        return plan

    def test_to_run_splits_run_and_sampled_and_never_repeats_a_package(self) -> None:
        first, second = nu.to_run(self.units, {f"{L}/interval": "run", f"{L}/bin_float": "sample", "rest": "reuse", "rest (not keyed)": "reuse"})
        self.assertEqual(first, [f"{L}/interval"])
        self.assertEqual(second, [f"{L}/bin_float"])
        first, second = nu.to_run(self.units, {f"{L}/interval": "run", f"{L}/bin_float": "sample", "rest": "run", "rest (not keyed)": "run"})
        self.assertFalse(set(first) & set(second))

    def test_all_reused_runs_nothing_and_says_reused(self) -> None:
        actions = {u.name: "reuse" for u in self.units if u.keyed}
        actions["rest (not keyed)"] = "run"
        plan = self.plan(actions)
        for name, key in plan.keys.items():
            self.ledger.append([{"kind": "result", "key": key, "unit": name, "commit": "abcdef0123456789", "result": {"passed": True}}])
        calls: list[tuple[str, ...]] = []
        lines: list[str] = []
        status, tally, commits = nu.run_plan(plan, 3, lambda c: calls.append(c) or OK, lines.append)
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 1)  # only the unit that is not keyed
        self.assertEqual(calls[0][calls[0].index("-p") + 1:calls[0].index("--target")], (f"{T}/bench",))
        self.assertEqual((tally.reused, tally.ran, tally.not_keyed), (3, 1, 1))
        self.assertEqual(sum("REUSED" in line for line in lines), 3)
        self.assertEqual(commits, {"abcdef0123456789": 3})

    def test_a_pass_records_every_keyed_unit_of_the_run(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        status, tally, _ = nu.run_plan(plan, 3, lambda c: OK, lambda line: None)
        self.assertEqual(status, 0)
        self.assertEqual(tally.ran, 4)
        recorded = [plan.ledger.result(k) for k in plan.keys.values()]
        self.assertTrue(all(r is not None and r["result"]["passed"] for r in recorded))
        self.assertEqual(len(plan.keys), 3)

    def test_a_failure_records_nothing(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        status, tally, _ = nu.run_plan(plan, 3, lambda c: FAILED, lambda line: None)
        self.assertEqual(status, 1)
        self.assertEqual(tally.failed, 1)
        self.assertTrue(all(plan.ledger.result(k) is None for k in plan.keys.values()))

    def test_a_failing_sampled_rerun_is_a_defect_of_the_system(self) -> None:
        actions = {u.name: "reuse" for u in self.units}
        actions[f"{L}/interval"] = "sample"
        actions["rest (not keyed)"] = "run"
        plan = self.plan(actions)
        lines: list[str] = []
        status, tally, _ = nu.run_plan(plan, 3, lambda c: FAILED if f"{L}/interval" in c else OK, lines.append)
        self.assertEqual(status, inc.EXIT_DEFECT)
        self.assertTrue(any(line.startswith("DEFECT") for line in lines))

    def test_the_run_invocation_comes_before_the_sampled_one(self) -> None:
        actions = {u.name: "reuse" for u in self.units}
        actions[f"{L}/interval"] = "sample"
        actions[f"{L}/bin_float"] = "run"
        actions["rest (not keyed)"] = "run"
        plan = self.plan(actions)
        for key in plan.keys.values():
            self.ledger.append([{"kind": "result", "key": key, "unit": "x", "commit": "c1", "result": {"passed": True}}])
        calls: list[tuple[str, ...]] = []
        nu.run_plan(plan, 3, lambda c: calls.append(c) or OK, lambda line: None)
        packages = [c[c.index("-p") + 1:c.index("--target")] for c in calls]
        self.assertEqual(packages, [(f"{T}/bench", f"{L}/bin_float"), (f"{L}/interval",)])

    def test_a_disabled_plan_runs_the_whole_stage(self) -> None:
        plan = self.plan({})
        plan.disabled = "no key can be formed: x"
        calls: list[tuple[str, ...]] = []
        lines: list[str] = []
        status, tally, _ = nu.run_plan(plan, 2, lambda c: calls.append(c) or OK, lines.append)
        self.assertEqual(calls, [nu.whole_command(2)])
        self.assertNotIn("-p", calls[0])
        self.assertIn("not reusable", nu.summary_line(tally, 1, 0.02, {}))

    def test_a_unit_changed_during_the_run_is_not_recorded(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        plan.digests[f"{L}/interval"] = "stale"
        nu.unchanged = lambda p, u: p.digests[u.name] != "stale"  # type: ignore[assignment]
        status, tally, _ = nu.run_plan(plan, 3, lambda c: OK, lambda line: None)
        self.assertEqual(tally.unrecorded, 1)
        self.assertIsNone(plan.ledger.result(plan.keys[f"{L}/interval"]))


class JudgeTest(unittest.TestCase):
    def test_a_real_pass(self) -> None:
        self.assertEqual(nu.judge(*OK), (0, ""))

    def test_exit_zero_with_a_package_not_found_is_a_failure(self) -> None:
        status, why = nu.judge(0, NOT_FOUND_TEXT)
        self.assertEqual(status, 1)
        self.assertIn("not found", why)

    def test_exit_zero_with_zero_tests_and_with_no_total_line_is_a_failure(self) -> None:
        self.assertEqual(nu.judge(0, "Total tests: 0, passed: 0, failed: 0.\n")[0], 1)
        self.assertEqual(nu.judge(0, "nothing\n")[0], 1)

    def test_failed_tests_and_a_failing_status_are_failures(self) -> None:
        self.assertEqual(nu.judge(*FAILED)[0], 1)
        self.assertEqual(nu.judge(2, "Total tests: 5, passed: 5, failed: 0.")[0], 2)

    def test_every_total_line_counts_not_only_the_last(self) -> None:
        good = "Total tests: 5, passed: 5, failed: 0.\n"
        for bad in ("Total tests: 0, passed: 0, failed: 0.\n", "Total tests: 3, passed: 2, failed: 1.\n"):
            self.assertEqual(nu.judge(0, bad + good)[0], 1, bad)
            self.assertEqual(nu.judge(0, good + bad)[0], 1, bad)
        self.assertEqual(nu.judge(0, good + good), (0, ""))
        self.assertEqual(nu.test_count(good + good), 10)

    def test_the_test_count_is_read(self) -> None:
        self.assertEqual(nu.test_count(SILENT_TEXT), 23)
        self.assertEqual(nu.test_count("none"), 0)

    def test_the_wrong_name_dropped_silently_is_not_caught_by_the_output_alone(self) -> None:
        # moon drops an unknown name next to a known one without a word (23 tests, no warning):
        # that case is covered by the manifest check, not by `judge`
        self.assertEqual(nu.judge(0, SILENT_TEXT), (0, ""))


class ManifestTest(unittest.TestCase):
    def test_the_manifests_of_this_repository_match_the_constants(self) -> None:
        nu.check_manifests(nu.REPO_ROOT)

    def test_a_renamed_module_or_source_directory_is_a_problem(self) -> None:
        good = 'name = "Luna-Flow/floating"\n'
        self.assertIsNone(nu.manifest_problem(good, nu.LIBRARY, "library/src", "library/moon.mod"))
        self.assertIn("names the module", nu.manifest_problem('name = "Luna-Flow/other"\n', nu.LIBRARY, "library/src", "library/moon.mod") or "")
        self.assertIn("source directory", nu.manifest_problem(good + 'source = "lib"\n', nu.LIBRARY, "library/src", "library/moon.mod") or "")
        self.assertIsNone(nu.manifest_problem('name = "Luna-Flow/floating-tools"\nsource = "src"\n', nu.TOOLING, "tooling/src", "tooling/moon.mod"))

    def test_a_mismatch_disables_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, text in (("library/moon.mod", 'name = "Luna-Flow/renamed"\n'), ("tooling/moon.mod", 'name = "Luna-Flow/floating-tools"\n')):
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(text)
            plan = nu.make_plan(root, inc.Ledger(root / "l.jsonl"), 1, environ={}, run=lambda *a, **k: "dry")
            self.assertIn("names the module", plan.disabled)

    def test_a_dry_run_that_says_not_found_disables_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            MutationTest.build(root)
            plan = nu.make_plan(root, inc.Ledger(root / "l.jsonl"), 1, environ={}, run=lambda *a, **k: "Warning: package `x/y` not found", heavy=(f"{L}/low", f"{L}/top"))
            self.assertIn("did not find a package", plan.disabled)


class RunOutputTest(RunTest):
    def test_exit_zero_with_a_package_not_found_fails_the_stage_and_records_nothing(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        lines: list[str] = []
        status, tally, _ = nu.run_plan(plan, 3, lambda c: (0, NOT_FOUND_TEXT), lines.append)
        self.assertEqual(status, 1)
        self.assertTrue(all(plan.ledger.result(k) is None for k in plan.keys.values()))
        self.assertTrue(any("not found" in line for line in lines))

    def test_zero_tests_and_no_total_line_fail_the_stage(self) -> None:
        for text in ("Total tests: 0, passed: 0, failed: 0.\n", "no total\n"):
            plan = self.plan({u.name: "run" for u in self.units})
            status, _, _ = nu.run_plan(plan, 3, lambda c: (0, text), lambda line: None)
            self.assertEqual(status, 1, text)
            self.assertTrue(all(plan.ledger.result(k) is None for k in plan.keys.values()))

    def test_a_sampled_rerun_with_zero_tests_is_a_defect(self) -> None:
        actions = {u.name: "reuse" for u in self.units}
        actions["rest (not keyed)"] = "run"
        actions[f"{L}/interval"] = "sample"
        plan = self.plan(actions)
        status, _, _ = nu.run_plan(plan, 3, lambda c: OK if f"{L}/interval" not in c else (0, NOT_FOUND_TEXT), lambda line: None)
        self.assertEqual(status, inc.EXIT_DEFECT)

    def test_the_test_count_is_in_the_pass_line_and_the_record(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        lines: list[str] = []
        nu.run_plan(plan, 3, lambda c: OK, lines.append)
        self.assertTrue(any(line.startswith("PASS") and "10 tests" in line for line in lines))
        record = plan.ledger.result(plan.keys[f"{L}/interval"])
        self.assertEqual(record["result"]["tests_in_the_run"], 10)

    def test_no_reuse_runs_the_whole_stage_and_records_every_keyed_unit(self) -> None:
        plan = self.plan({u.name: "run" for u in self.units})
        plan.reuse = False
        calls: list[tuple[str, ...]] = []
        lines: list[str] = []
        status, tally, _ = nu.run_plan(plan, 2, lambda c: calls.append(c) or OK, lines.append)
        self.assertEqual(calls, [nu.whole_command(2)])
        self.assertEqual((status, tally.ran), (0, 4))
        self.assertTrue(any(line.startswith("PASS") and "whole stage" in line and "10 tests" in line for line in lines))
        self.assertTrue(all(plan.ledger.result(k) is not None for k in plan.keys.values()))
        self.assertEqual(plan.ledger.result(plan.keys[f"{L}/interval"])["result"]["tests_in_the_run"], 10)


class MutationTest(unittest.TestCase):
    """The keys of a small repository of the same shape: which units a change reaches."""

    @staticmethod
    def build(root: Path) -> None:
        files = {
            "library/moon.mod": "name = \"Luna-Flow/floating\"\n",
            "tooling/moon.mod": "name = \"Luna-Flow/floating-tools\"\nsource = \"src\"\n",
            "moon.work": "members = []\n",
            nu.WRAPPER: "exec moon \"$@\"\n",
            "library/src/def/moon.pkg": "",
            "library/src/def/a.mbt": "fn a() -> Int { 1 }\n",
            "library/src/low/moon.pkg": f'import {{ "{L}/def" }}\n',
            "library/src/low/b.mbt": "fn b() -> Int { 2 }\n",
            "library/src/top/moon.pkg": f'import {{ "{L}/low" }}\n',
            "library/src/top/c.mbt": "fn c() -> Int { 3 }\n",
            "library/src/other/moon.pkg": f'import {{ "{L}/def" }}\n',
            "library/src/other/d.mbt": "fn d() -> Int { 4 }\n",
            "tooling/src/t/moon.pkg": f'import {{ "{L}/top" }}\n',
            "tooling/src/t/e.mbt": "fn e() -> Int { 5 }\n",
            "tooling/src/fs/moon.pkg": 'import { "moonbitlang/x/fs" }\n',
            "tooling/src/fs/f.mbt": "fn f() -> Int { 6 }\n",
        }
        for name, text in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.build(self.root)
        self.heavy = (f"{L}/low", f"{L}/top")

    def keys(self, environ: dict[str, str] | None = None, dry: str = "dry") -> dict[str, str]:
        ledger = inc.Ledger(self.root / "ledger.jsonl")
        plan = nu.make_plan(self.root, ledger, 1, environ=environ or {}, run=lambda *a, **k: dry, heavy=self.heavy)
        self.assertEqual(plan.disabled, "")
        return plan.keys

    def changed(self, before: dict[str, str], after: dict[str, str]) -> set[str]:
        return {u for u in after if before.get(u) != after[u]}

    def edit(self, name: str, text: str) -> None:
        with (self.root / name).open("a") as stream:
            stream.write(text)

    def test_a_change_reaches_exactly_the_units_that_import_it(self) -> None:
        base = self.keys()
        self.assertEqual(set(base), {f"{L}/low", f"{L}/top", "rest"})
        self.edit("library/src/def/a.mbt", "// comment\n")
        self.assertEqual(self.changed(base, self.keys()), {f"{L}/low", f"{L}/top", "rest"})
        base = self.keys()
        self.edit("library/src/low/b.mbt", "// comment\n")
        # `top` and the tools package that imports it see it; `other` is in the rest unit, which holds `t`
        self.assertEqual(self.changed(base, self.keys()), {f"{L}/low", f"{L}/top", "rest"})
        base = self.keys()
        self.edit("library/src/top/c.mbt", "// comment\n")
        self.assertEqual(self.changed(base, self.keys()), {f"{L}/top", "rest"})

    def test_a_change_to_a_package_nothing_in_the_unit_imports_does_not_reach_it(self) -> None:
        base = self.keys()
        self.edit("library/src/other/d.mbt", "// comment\n")
        self.assertEqual(self.changed(base, self.keys()), {"rest"})

    def test_an_added_file_a_module_file_the_wrapper_the_environment_and_the_dry_run_reach_every_unit(self) -> None:
        base = self.keys()
        everything = set(base)
        (self.root / "library/src/def/new.mbt").write_text("fn n() {}\n")
        self.assertEqual(self.changed(base, self.keys()), everything)
        base = self.keys()
        self.edit("library/moon.mod", "// x\n")
        self.assertEqual(self.changed(base, self.keys()), everything)
        base = self.keys()
        self.edit("moon.work", "// x\n")
        self.assertEqual(self.changed(base, self.keys()), everything)
        base = self.keys()
        self.edit(nu.WRAPPER, "# x\n")
        self.assertEqual(self.changed(base, self.keys()), everything)
        base = self.keys()
        self.assertEqual(self.changed(base, self.keys({"LUNA_FLOATING_LIMBS": "c"})), everything)
        self.assertEqual(self.changed(base, self.keys(dry="another command line")), everything)

    def test_a_package_that_imports_the_file_system_is_not_keyed(self) -> None:
        plan = nu.make_plan(self.root, inc.Ledger(self.root / "l.jsonl"), 1, environ={}, run=lambda *a, **k: "d", heavy=self.heavy)
        names = {u.name: u.keyed for u in plan.units}
        self.assertFalse(names["rest (not keyed)"])
        self.assertNotIn("rest (not keyed)", plan.keys)
        self.assertEqual(plan.actions["rest (not keyed)"], "run")

    def test_a_dry_run_that_prints_nothing_disables_reuse(self) -> None:
        plan = nu.make_plan(self.root, inc.Ledger(self.root / "l.jsonl"), 1, environ={}, run=lambda *a, **k: "", heavy=self.heavy)
        self.assertIn("could not print", plan.disabled)


class RealRepositoryTest(unittest.TestCase):
    def test_the_packages_of_this_repository_form_units(self) -> None:
        packages = nu.discover_packages(nu.REPO_ROOT)
        units = nu.make_units(packages)
        self.assertEqual(sorted(m for u in units for m in u.members), sorted(packages))
        self.assertTrue(all(h in packages for h in nu.HEAVY))
        for unit in units:
            if unit.keyed:
                self.assertEqual(nu.impure_imports(unit.members, packages), [], unit.name)

    def test_the_six_heavy_packages_are_keyed(self) -> None:
        units = {u.name: u for u in nu.make_units(nu.discover_packages(nu.REPO_ROOT))}
        for heavy in nu.HEAVY:
            self.assertTrue(units[heavy].keyed, heavy)


if __name__ == "__main__":
    unittest.main()
