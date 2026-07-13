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
    def test_plan_uses_unified_runner_shape(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(run_ieee_decimal.main(["--plan", "--target", "wasm"]), 0)
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["runner"], "ieee-decimal-oracles")
        self.assertEqual(plan["targets"], ["wasm"])
        self.assertEqual(plan["checks"]["dpdDeclets"], 1024)

    def test_json_report_uses_unified_summary_shape(self) -> None:
        checks = {
            "cases": 23,
            "operations": 36,
            "declets": 1024,
            "encodingBridge": 11,
            "staticExamples": 19,
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
