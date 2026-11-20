import unittest
import json
import subprocess
import tempfile
from contextlib import redirect_stdout
from pathlib import Path
from io import StringIO
from unittest.mock import patch

import run_ieee_decimal


class IeeeDecimalCorpusTests(unittest.TestCase):
    def test_split_fixture_test_keeps_every_test_and_the_prelude_once(self) -> None:
        source = "fn helper() -> Unit {\n}\n\ntest \"a\" {\n}\n\ntest \"b\" {\n}\n\ntest \"c\" {\n}\n"
        chunks = run_ieee_decimal.split_fixture_test(source, per_file=2)
        self.assertEqual(len(chunks), 2)
        self.assertTrue(chunks[0].startswith("fn helper()"))
        self.assertNotIn("fn helper()", chunks[1])
        joined = "".join(chunks)
        for name in ('"a"', '"b"', '"c"'):
            self.assertEqual(joined.count(name), 1)

    def test_plan_uses_unified_runner_shape(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(run_ieee_decimal.main(["--plan", "--target", "wasm"]), 0)
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["runner"], "ieee-decimal-oracles")
        self.assertEqual(plan["targets"], ["wasm"])
        self.assertEqual(plan["checks"]["dpdDeclets"], 1024)
        self.assertEqual(plan["checks"]["certifiedElementaryOracle"], 4896)

    def test_json_report_uses_unified_summary_shape(self) -> None:
        checks = {
            "cases": 23,
            "operations": 36,
            "declets": 1024,
            "encodingBridge": 11,
            "staticExamples": 19,
            "elementaryOracle": 2784,
            "totalOrderPairs": 18816,
        }
        targets = [{"target": "native", "totalCases": 2, "passedCases": 2, "failedCases": 0, "exitCode": 0}]
        with tempfile.TemporaryDirectory() as directory, patch.object(
            run_ieee_decimal, "collect_corpus_checks", return_value=checks
        ), patch.object(
            run_ieee_decimal, "check_standard_excerpt", return_value=42
        ), patch.object(
            run_ieee_decimal, "decimal_oracles"
        ) as oracles, patch.object(
            run_ieee_decimal, "run_targets", return_value=targets
        ), patch.object(
            run_ieee_decimal, "run_row_tables", return_value=[]
        ):
            oracles.probe.return_value = {"exact-gmp-rational": {"available": True}}
            output = StringIO()
            with redirect_stdout(output):
                self.assertEqual(
                    run_ieee_decimal.main(["--json", "--output", directory]),
                    0,
                )
            report = json.loads(output.getvalue())
            self.assertEqual(report["runner"], "ieee-decimal-oracles")
            self.assertEqual(report["summary"]["failedCases"], 0)
            self.assertTrue((Path(directory) / "summary.json").exists())

    def test_smoke_skips_the_full_row_table_and_full_gate_runs_it(self) -> None:
        checks = {"cases": 23, "operations": 36, "declets": 1024, "encodingBridge": 11,
                  "staticExamples": 19, "elementaryOracle": 4896, "totalOrderPairs": 18816}
        targets = [{"target": "native", "totalCases": 2, "passedCases": 2, "failedCases": 0, "exitCode": 0}]
        table = [{"target": "native", "table": "pi_inverse", "totalCases": 19134,
                  "passedCases": 19134, "failedCases": 0, "failedIds": []}]
        for smoke, expected_calls in ((True, 0), (False, 1)):
            with tempfile.TemporaryDirectory() as directory, patch.object(
                run_ieee_decimal, "collect_corpus_checks", return_value=checks
            ), patch.object(run_ieee_decimal, "check_standard_excerpt", return_value=42), patch.object(
                run_ieee_decimal, "decimal_oracles"
            ) as oracles, patch.object(
                run_ieee_decimal, "run_targets", return_value=targets
            ), patch.object(
                run_ieee_decimal, "run_row_tables", return_value=table
            ) as runner:
                oracles.probe.return_value = {}
                arguments = ["--json", "--output", directory] + (["--smoke"] if smoke else [])
                output = StringIO()
                with redirect_stdout(output):
                    self.assertEqual(run_ieee_decimal.main(arguments), 0)
                self.assertEqual(runner.call_count, expected_calls)
                report = json.loads(output.getvalue())
                self.assertEqual(len(report["rowTables"]), expected_calls)

    def test_failed_row_table_fails_the_gate(self) -> None:
        checks = {"cases": 1, "operations": 1, "declets": 1, "encodingBridge": 1,
                  "staticExamples": 1, "elementaryOracle": 1, "totalOrderPairs": 1}
        targets = [{"target": "native", "totalCases": 2, "passedCases": 2, "failedCases": 0, "exitCode": 0}]
        table = [{"target": "js", "table": "pi_inverse", "totalCases": 10,
                  "passedCases": 9, "failedCases": 1, "failedIds": ["pi_inverse-00003"]}]
        report = run_ieee_decimal._report(checks, 42, targets, {}, 1.0, table)
        self.assertEqual(report["summary"]["failedCases"], 1)
        self.assertEqual(report["summary"]["failedIds"], ["pi_inverse@js"])

    def test_checked_in_corpus(self) -> None:
        cases, operations, declets = run_ieee_decimal.check_corpus()
        self.assertEqual(cases, 23)
        self.assertEqual(operations, 36)
        self.assertEqual(declets, 1024)

    def test_standard_excerpt_is_checked_against_decimal_context(self) -> None:
        self.assertEqual(run_ieee_decimal.check_standard_excerpt(), 42)

    def test_dpd_bid_bridge_round_trips_checked_cases(self) -> None:
        self.assertEqual(run_ieee_decimal.check_encoding_bridge(), 11)

    def test_conformance_matrix_is_explicit(self) -> None:
        required, recommended = run_ieee_decimal.check_conformance_matrix()
        self.assertGreaterEqual(required, 15)
        self.assertGreaterEqual(recommended, 8)

    def test_all_dpd_declets_round_trip(self) -> None:
        redundant = 0
        for code in range(1024):
            digits = run_ieee_decimal.dpd_decode(code)
            if run_ieee_decimal.dpd_encode(*digits) != code:
                redundant += 1
        self.assertEqual(redundant, 24)

    def test_runner_rejects_unknown_target(self) -> None:
        with self.assertRaises(run_ieee_decimal.CorpusError):
            run_ieee_decimal.run_targets(["llvm"])

    def test_target_process_failure_cannot_report_as_pass(self) -> None:
        process = subprocess.CompletedProcess(
            ["moon", "test"],
            2,
            stdout="Total tests: 2, passed: 2, failed: 0.\n",
            stderr="backend failure",
        )
        result = run_ieee_decimal._target_result("wasm", process)
        self.assertEqual(result["passedCases"], 2)
        self.assertEqual(result["failedCases"], 1)
        self.assertEqual(result["totalCases"], 3)

    def test_generated_count_survives_splitting(self) -> None:
        source = run_ieee_decimal.render_moon_fixture_test()
        chunks = run_ieee_decimal.split_fixture_test(source)
        self.assertGreater(len(chunks), 1)
        self.assertEqual(
            run_ieee_decimal.count_generated_tests(chunks),
            source.count("\ntest ") + source.startswith("test "),
        )

    def test_executed_count_must_equal_generated_count(self) -> None:
        ok = {"target": "js", "totalCases": 288, "passedCases": 288, "failedCases": 0, "exitCode": 0}
        self.assertEqual(run_ieee_decimal.check_executed_count(ok, 288), ok)
        for executed in (287, 289):
            short = {**ok, "totalCases": executed, "passedCases": executed}
            checked = run_ieee_decimal.check_executed_count(short, 288)
            self.assertEqual(checked["failedCases"], 1)
            self.assertNotEqual(checked["exitCode"], 0)

    def test_run_targets_runs_only_generated_files(self) -> None:
        calls: list[list[str]] = []

        def fake_run(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            total = run_ieee_decimal.count_generated_tests(
                run_ieee_decimal.split_fixture_test(run_ieee_decimal.render_moon_fixture_test())
            )
            return subprocess.CompletedProcess(
                command, 0, stdout=f"Total tests: {total}, passed: {total}, failed: 0.\n", stderr=""
            )

        with patch.object(run_ieee_decimal.subprocess, "run", fake_run):
            results = run_ieee_decimal.run_targets(["native"], generated_only=True)
        self.assertEqual(results[0]["failedCases"], 0)
        paths = [item for item in calls[0] if item.endswith(".mbt")]
        self.assertTrue(paths)
        self.assertTrue(all("ieee_corpus_generated_" in item for item in paths))
        self.assertNotIn("library/src/decimal", calls[0])

    def test_full_run_keeps_whole_package_on_every_target(self) -> None:
        calls: list[list[str]] = []

        def fake_run(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            return subprocess.CompletedProcess(
                command, 0, stdout="Total tests: 518, passed: 518, failed: 0.\n", stderr=""
            )

        with patch.object(run_ieee_decimal.subprocess, "run", fake_run):
            results = run_ieee_decimal.run_targets(["native", "js"])
        self.assertEqual([r["totalCases"] for r in results], [518, 518])
        self.assertTrue(all("library/src/decimal" in call for call in calls))

    def test_format_context_uses_normal_exponent_bounds(self) -> None:
        self.assertEqual(run_ieee_decimal.decimal_context("decimal32").Emin, -95)
        self.assertEqual(run_ieee_decimal.decimal_context("decimal64").Emin, -383)
        self.assertEqual(run_ieee_decimal.decimal_context("decimal128").Emin, -6143)

    def test_fixture_rejects_flag_drift(self) -> None:
        source = run_ieee_decimal.FIXTURE_ROOT / "decimal32_dpd.json"
        fixture = json.loads(source.read_text(encoding="utf-8"))
        fixture["operations"][0]["flags"] = ["Inexact"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / source.name
            path.write_text(json.dumps(fixture), encoding="utf-8")
            with self.assertRaisesRegex(run_ieee_decimal.CorpusError, "expected flags"):
                run_ieee_decimal.check_fixture(path, {"format": "decimal32", "encoding": "DPD"})

    def test_fixture_rejects_case_drift(self) -> None:
        source = run_ieee_decimal.FIXTURE_ROOT / "decimal32_bid.json"
        fixture = json.loads(source.read_text(encoding="utf-8"))
        fixture["cases"][0]["coefficient"] = "1"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / source.name
            path.write_text(json.dumps(fixture), encoding="utf-8")
            with self.assertRaisesRegex(run_ieee_decimal.CorpusError, "decoded coefficient"):
                run_ieee_decimal.check_fixture(path, {"format": "decimal32", "encoding": "BID"})


if __name__ == "__main__":
    unittest.main()
