#!/usr/bin/env python3
"""Tests for the isolated Decimal benchmark runner."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

if __package__:
    from . import run_decimal_bench as bench
else:
    import run_decimal_bench as bench


def record(name: str, median: float, mad: float = 1.0, runs: int = 9) -> dict[str, object]:
    return {"name": name, "median": median, "median_abs_dev_pct": mad, "runs": runs}


class ValidationTests(unittest.TestCase):
    def test_requires_nine_samples(self) -> None:
        with self.assertRaisesRegex(ValueError, "fewer than 9"):
            bench.validate_records([record("mul/decimal64/dense", 1.0, runs=8)])

    def test_extracts_last_marker(self) -> None:
        payload = json.dumps([record("mul/decimal64/dense", 2.0)])
        output = "noise\nDECIMAL_BENCH_CHECKSUM=fixture-v1\nDECIMAL_BENCH_JSON=" + payload
        self.assertEqual(bench.extract_checksum(output), "fixture-v1")
        self.assertEqual(bench.extract_records(output)[0]["name"], "mul/decimal64/dense")

    def test_expands_backend_placeholder_without_shell(self) -> None:
        self.assertEqual(
            bench._expand_command(["moon", "--target", "{target}"], "wasm-gc"),
            ["moon", "--target", "wasm-gc"],
        )


class SnapshotTests(unittest.TestCase):
    def test_hash_tree_changes_for_file_contents(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a").write_text("one", encoding="utf-8")
            first = bench.hash_tree(root)
            (root / "a").write_text("two", encoding="utf-8")
            self.assertNotEqual(first, bench.hash_tree(root))


class ScheduleTests(unittest.TestCase):
    def test_ab_ba_ab_runs_three_pairs_and_aggregates_process_mad(self) -> None:
        records = {
            "baseline": [record("mul/decimal64/dense", 10.0)],
            "candidate": [record("mul/decimal64/dense", 9.0)],
        }
        order: list[str] = []

        def run_fixture(_command: list[str], root: Path, _checksum: str | None) -> list[dict[str, object]]:
            order.append(root.name)
            return records[root.name]

        with patch.object(bench, "_run_command", side_effect=run_fixture) as run:
            result = bench.run_target("native", Path("baseline"), Path("candidate"), ["fixture", "{target}"])
        self.assertEqual(run.call_count, 6)
        self.assertEqual(order, ["baseline", "candidate", "candidate", "baseline", "baseline", "candidate"])
        self.assertEqual(result["cells"][0]["name"], "mul/decimal64/dense")
        self.assertAlmostEqual(result["cells"][0]["ratio"], 0.9)

class ManifestTests(unittest.TestCase):
    def test_manifest_pins_supported_targets_and_nine_runs(self) -> None:
        manifest = json.loads((Path(__file__).parents[1] / "testdata/decimal/performance_baseline.json").read_text())
        self.assertEqual(tuple(manifest["targets"]), bench.TARGETS)
        self.assertEqual(manifest["benchmark"]["minimum_runs"], 9)
        self.assertNotIn("llvm", manifest["targets"])

    def test_fixture_matches_manifest_checksum_and_sample_count(self) -> None:
        manifest = json.loads((Path(__file__).parents[1] / "testdata/decimal/performance_baseline.json").read_text())
        fixture = (Path(__file__).parents[0] / "fixtures/decimal_performance_bench_wbtest.mbt").read_text()
        self.assertIn(f'DECIMAL_BENCH_CHECKSUM={manifest["benchmark"]["checksum"]}', fixture)
        self.assertGreaterEqual(fixture.count("count=9"), 1)
        self.assertIn("fn[T] decimal_performance_warmup", fixture)
        self.assertIn("fn[T] decimal_performance_pair", fixture)
        self.assertIn("bencher.keep(sink)", fixture)
        self.assertIn("for _ in 1..<repetitions", fixture)
        self.assertNotIn("fn() { bencher.keep(dec_coeff_", fixture)


if __name__ == "__main__":
    unittest.main()
