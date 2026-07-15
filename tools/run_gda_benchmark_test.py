from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import run_gda_benchmark as benchmark


class GdaBenchmarkTest(unittest.TestCase):
    def test_extract_records_accepts_quick_samples(self) -> None:
        records = [
            {
                "name": "gda/add/9",
                "runs": 3,
                "median": 0.04,
                "median_abs_dev_pct": 1.0,
            }
        ]
        output = (
            "GDA_PERFORMANCE_CHECKSUM=gda-quick-v1\n"
            "GDA_PERFORMANCE_JSON=" + json.dumps(records)
        )
        self.assertEqual(benchmark.extract_records(output), records)

    def test_extract_records_rejects_duplicate_names(self) -> None:
        record = {
            "name": "gda/add/9",
            "runs": 3,
            "median": 0.04,
            "median_abs_dev_pct": 1.0,
        }
        output = (
            "GDA_PERFORMANCE_CHECKSUM=gda-quick-v1\n"
            "GDA_PERFORMANCE_JSON=" + json.dumps([record, record])
        )
        with self.assertRaisesRegex(ValueError, "unique"):
            benchmark.extract_records(output)

    def test_normalize_records_reports_single_operation_time(self) -> None:
        records = benchmark.normalize_records(
            [
                {
                    "name": "gda/add/9",
                    "runs": 3,
                    "median": 131_072.0,
                    "median_abs_dev_pct": 1.0,
                }
            ]
        )
        self.assertEqual(records[0]["operationsPerInvocation"], 131_072)
        self.assertEqual(records[0]["medianPerOperationMicros"], 1.0)

    def test_inject_fixture_adds_benchmark_import_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            package = destination / "src/decimal_gda/moon.pkg"
            package.parent.mkdir(parents=True)
            package.write_text('import {\n  "moonbitlang/core/bigint",\n}\n', encoding="utf-8")
            benchmark.inject_fixture(destination)
            benchmark.inject_fixture(destination)
            text = package.read_text(encoding="utf-8")
            self.assertEqual(text.count('"moonbitlang/core/bench"'), 1)


if __name__ == "__main__":
    unittest.main()
