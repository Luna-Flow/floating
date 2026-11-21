import unittest
from unittest.mock import patch

import ci_schedule
import run_ci


class RunCiTests(unittest.TestCase):
    def test_decimal_scope_only_runs_ieee_suite(self) -> None:
        stages = run_ci.stages_for("decimal", 3)
        self.assertEqual(len(stages), 2)
        self.assertIn("tools/conformance.py", stages[1].command)
        backend_index = stages[1].command.index("--backend") + 1
        self.assertEqual(stages[1].command[backend_index], "decimal")
        self.assertEqual(
            [
                stages[1].command[index + 1]
                for index, value in enumerate(stages[1].command)
                if value == "--run-target"
            ],
            ["native", "wasm", "wasm-gc", "js"],
        )

    def test_decimal_gda_scope_only_runs_dectest_suite(self) -> None:
        stages = run_ci.stages_for("decimal_gda", 3)
        self.assertEqual(len(stages), 5)
        self.assertIn("Luna-Flow/floating/decimal_gda", stages[1].command)
        self.assertIn("Luna-Flow/floating-tools/frontend/gda_expr", stages[2].command)
        self.assertIn("tools/conformance.py", stages[3].command)
        backend_index = stages[3].command.index("--backend") + 1
        self.assertEqual(stages[3].command[backend_index], "decimal_gda")
        self.assertIn("official0", stages[4].command)

    def test_every_scope_fetches_dependencies_first(self) -> None:
        # `moon update` only refreshes the registry index, so a scope whose first
        # command passes `--frozen` used to fail on a clean checkout.
        for scope in ("all", "quick", "decimal", "decimal_gda", "binary", "interval", "elementary"):
            with self.subTest(scope=scope):
                first = run_ci.stages_for(scope, 2)[0]
                self.assertEqual(first.name, "DEPENDENCIES: fetch")
                self.assertIn("check", first.command)
                self.assertNotIn("install", first.command)
                self.assertNotIn("--frozen", first.command)

    def test_binary_scope_uses_binary_backend(self) -> None:
        command = run_ci.stages_for("binary", 2)[1].command
        backend_index = command.index("--backend") + 1
        self.assertEqual(command[backend_index], "binary")

    def test_all_scope_covers_repository_and_three_suites(self) -> None:
        stages = run_ci.stages_for("all", 5)
        self.assertEqual(len(stages), 26)
        self.assertEqual(
            [stage.name.split(": ")[0] for stage in stages],
            [
                "DEPENDENCIES",
                "IMPORTS",
                "CONTEXTS",
                "FORMAT",
                "PACKAGE",
                "DOCS",
                "CHECK",
                "CHECK",
                "CHECK",
                "INFO",
                "TEST",
                "TEST",
                "TEST",
                "TEST",
                "DECIMAL",
                "DECIMAL_GDA",
                "DECIMAL_GDA",
                "DECIMAL_GDA",
                "DECIMAL_GDA",
                "BINARY",
                "BINARY",
                "BINARY",
                "BINARY",
                "INTERVAL",
                "INTERVAL",
                "INTERVAL",
            ],
        )

    def test_dependency_stage_is_the_denying_native_check(self) -> None:
        command = run_ci.DEPENDENCY_STAGE.command
        self.assertEqual(command[2:], ("check", "--target", "native", "--deny-warn"))
        self.assertNotIn("--frozen", command)  # it fetches; later stages are frozen

    def test_native_is_checked_once_and_the_test_stage_stays_frozen(self) -> None:
        for scope in ("quick", "all"):
            stages = run_ci.stages_for(scope, 4)
            native_checks = [
                stage.name
                for stage in stages
                if stage.command[2:3] == ("check",) and "native" in stage.command
            ]
            self.assertEqual(native_checks, ["DEPENDENCIES: fetch"], scope)
            test = next(stage for stage in stages if stage.name == "TEST: native")
            self.assertIn("--frozen", test.command)
            self.assertIn("--deny-warn", test.command)

    def test_quick_scope_runs_native_tools_and_four_smokes(self) -> None:
        stages = run_ci.stages_for("quick", 4)
        names = [stage.name for stage in stages]
        self.assertEqual(
            sorted(name.split(": ")[0] for name in names),
            sorted(
                [
                    "DEPENDENCIES",
                    "CHECK",
                    "IMPORTS",
                    "CONTEXTS",
                    "FORMAT",
                    "PACKAGE",
                    "DOCS",
                    "DOCS",
                    "TEST",
                    "SMOKE",
                    "TEST",
                    "SMOKE",
                    "SMOKE",
                    "SMOKE",
                    "SMOKE",
                ]
            ),
        )
        by_name = {stage.name: stage.command for stage in stages}
        self.assertEqual(by_name["IMPORTS: package independence"][1], "tools/check_imports.py")
        self.assertEqual(by_name["CONTEXTS: corpus"][1], "tools/check_corpus_contexts.py")
        self.assertEqual(
            by_name["PACKAGE: published contents"][1:],
            ("tools/check_package_contents.py", "--module", "all"),
        )
        self.assertIn("--quality-only", by_name["DOCS: manual quality"])
        self.assertIn("--examples-only", by_name["DOCS: manual examples"])
        self.assertIn("--skip-package-tests", by_name["DOCS: manual examples"])
        self.assertIn("native", by_name["TEST: native"])
        self.assertIn("--deny-warn", by_name["TEST: native"])
        self.assertEqual(by_name["TEST: Python tooling"][1], "tools/run_python_tests.py")
        self.assertEqual(by_name["SMOKE: DecimalGDA"][-1], "decimal_gda")
        self.assertEqual(by_name["SMOKE: Binary"][-1], "binary")
        self.assertEqual(by_name["SMOKE: Random differential"][1], "tools/random_differential.py")
        self.assertEqual(by_name["SMOKE: Random differential"][2], "smoke")
        self.assertEqual(by_name["SMOKE: Interval"][-2:], ("interval", "--strict-supported"))

    def test_quick_lanes_keep_moon_stages_in_one_lane_in_order(self) -> None:
        stages = run_ci.stages_for("quick", 4)
        lanes: dict[str, list[str]] = {}
        for stage in stages:
            lanes.setdefault(stage.lane, []).append(stage.name)
        self.assertEqual(
            lanes["moon"],
            [
                "DEPENDENCIES: fetch",
                "CHECK: other targets",
                "PACKAGE: published contents",
                "DOCS: manual examples",
                "FORMAT: MoonBit sources",
                "TEST: native",
                "SMOKE: IEEE 754",
            ],
        )
        self.assertEqual(
            lanes["python"],
            ["IMPORTS: package independence", "CONTEXTS: corpus", "DOCS: manual quality", "TEST: Python tooling"],
        )
        self.assertEqual(lanes["conformance"][0], "SMOKE: DecimalGDA")
        ci_schedule.validate_plan(stages)
        first = next(stage for stage in stages if stage.lane == "conformance")
        self.assertEqual(first.after, "DOCS: manual examples")

    def test_other_targets_are_checked_with_deny_warn_in_the_quick_gate(self) -> None:
        command = next(
            stage.command
            for stage in run_ci.stages_for("quick", 4)
            if stage.name == "CHECK: other targets"
        )
        self.assertEqual(command[command.index("--target") + 1], "wasm,wasm-gc,js")
        self.assertIn("--frozen", command)
        self.assertIn("--deny-warn", command)

    def test_pure_python_lane_never_runs_moon(self) -> None:
        for stage in run_ci.stages_for("quick", 4):
            if stage.lane == "python":
                self.assertNotIn("run_moon_clean_exec.sh", " ".join(stage.command))

    def test_the_quick_gate_tests_no_other_target_until_one_is_named(self) -> None:
        self.assertEqual(run_ci.QUICK_TEST_TARGETS, ())
        names = [stage.name for stage in run_ci.stages_for("quick", 4)]
        self.assertFalse([name for name in names if name in ("TEST: js", "TEST: wasm", "TEST: wasm-gc")])

    def test_naming_js_adds_its_frozen_test_stage_after_native_in_the_moon_lane(self) -> None:
        from unittest.mock import patch

        with patch.object(run_ci, "QUICK_TEST_TARGETS", ("js",)):
            stages = run_ci.stages_for("quick", 4)
        names = [stage.name for stage in stages]
        self.assertEqual(names[names.index("TEST: native") + 1], "TEST: js")
        stage = next(stage for stage in stages if stage.name == "TEST: js")
        self.assertEqual(stage.lane, "moon")
        self.assertEqual(stage.command[stage.command.index("--target") + 1], "js")
        self.assertIn("--frozen", stage.command)
        self.assertIn("--deny-warn", stage.command)
        ci_schedule.validate_plan(stages)

    def test_every_quick_stage_has_a_lane_and_the_plan_is_complete(self) -> None:
        with self.assertRaises(ValueError):
            run_ci.assign_lanes([run_ci.Stage("UNKNOWN: stage", ("true",))])

    def test_children_terminate_stops_a_running_stage_and_its_group(self) -> None:
        import subprocess
        import sys
        import time as _time

        children = run_ci.Children()
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            start_new_session=True,
        )
        children.add(process)
        children.terminate()
        deadline = _time.monotonic() + 10
        while process.poll() is None and _time.monotonic() < deadline:
            _time.sleep(0.05)
        self.assertIsNotNone(process.poll())
        self.assertNotEqual(process.returncode, 0)

    def test_run_captured_returns_output_and_status(self) -> None:
        import sys

        children = run_ci.Children()
        stage = run_ci.Stage("t", (sys.executable, "-c", "print('x'); raise SystemExit(4)"))
        outcome = run_ci.run_captured(stage, children)
        self.assertEqual((outcome.returncode, outcome.output.strip()), (4, "x"))

    def test_native_test_stage_over_the_budget_warns_and_names_the_tool(self) -> None:
        stage = run_ci.Stage(run_ci.NATIVE_TEST_STAGE_NAME, ("true",))
        self.assertEqual(run_ci.NATIVE_TEST_WARN_SECONDS, 150.0)
        self.assertIsNone(run_ci.slow_stage_warning(stage, 150.0))
        warning = run_ci.slow_stage_warning(stage, 151.0)
        assert warning is not None
        self.assertIn("native_test_timing.py", warning)
        self.assertIn("2m 31s", warning)
        other = run_ci.Stage("TEST: Python tooling", ("true",))
        self.assertIsNone(run_ci.slow_stage_warning(other, 1000.0))

    def test_other_scopes_stay_sequential(self) -> None:
        for scope in ("all", "decimal", "binary", "interval", "elementary", "decimal_gda"):
            self.assertEqual({stage.lane for stage in run_ci.stages_for(scope, 2)}, {"main"}, scope)

    def test_repository_scopes_exclude_performance_comparisons(self) -> None:
        for scope in ("quick", "all"):
            commands = [stage.command for stage in run_ci.stages_for(scope, 4)]
            flattened = [item for command in commands for item in command]
            self.assertNotIn("tools/run_elementary_performance_gate.py", flattened)
            self.assertFalse(
                any(
                    command[-2:] == ("tools/benchmark.py", "elementary")
                    for command in commands
                )
            )

    def test_binary_gate_locks_level_and_both_tininess_modes(self) -> None:
        command = run_ci.stages_for("binary", 2)[1].command
        self.assertEqual(command[command.index("--level") + 1], "1")
        self.assertEqual(
            [command[index + 1] for index, value in enumerate(command) if value == "--tininess"],
            ["after", "before"],
        )

    def test_interval_gate_uses_declared_strict_phases(self) -> None:
        command = run_ci.stages_for("interval", 2)[1].command
        self.assertIn("--strict-supported", command)
        self.assertIn("elementary-core", command)
        self.assertIn("trigonometric", command)
        self.assertIn("hyperbolic", command)
        self.assertIn("inverse-trigonometric", command)
        self.assertIn("atan2", command)
        self.assertIn("general-power", command)
        self.assertNotIn("reverse", command)

    def test_interval_gate_runs_the_oracle_checks_with_the_corpus_required(self) -> None:
        stages = run_ci.stages_for("interval", 2)
        self.assertEqual(stages[-1].name, "INTERVAL: oracle checks")
        self.assertEqual(stages[-1].command[1:], ("tools/itl_oracle_checks.py", "--require-corpus"))

    def test_elementary_gate_pairs_correctness_and_performance(self) -> None:
        stages = run_ci.stages_for("elementary", 2)
        self.assertEqual(len(stages), 4)
        self.assertIn("Luna-Flow/floating-tools/bench/bin_float", stages[1].command)
        self.assertNotIn("--include-skipped", stages[1].command)
        self.assertEqual(
            stages[2].command[-1], "tools/run_elementary_performance_gate.py"
        )
        self.assertEqual(stages[3].command[-2:], ("tools/benchmark.py", "elementary"))

    def test_elementary_scope_is_accepted_by_cli(self) -> None:
        with patch.object(run_ci, "run", return_value=0) as run:
            self.assertEqual(run_ci.main(["elementary", "2"]), 0)
        run.assert_called_once_with("elementary", 2, False)


if __name__ == "__main__":
    unittest.main()
