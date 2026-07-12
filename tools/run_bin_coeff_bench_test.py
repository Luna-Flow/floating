#!/usr/bin/env python3
"""Unit tests for the binary coefficient benchmark runner."""

from __future__ import annotations

import unittest
from unittest.mock import patch

if __package__:
    from . import run_bin_coeff_bench as bench
    from .run_bin_coeff_bench import (
        aggregate_process_results,
        benchmark_command,
        benchmark_commands,
        extract_marked_payloads,
        paired_median_ratio,
        pair_binfloat_vs_legacy,
        pair_coeff_vs_bigint,
        run_release_benchmarks,
        unstable_benchmark_records,
        validate_benchmark_records,
    )
else:
    import run_bin_coeff_bench as bench
    from run_bin_coeff_bench import (
        aggregate_process_results,
        benchmark_command,
        benchmark_commands,
        extract_marked_payloads,
        paired_median_ratio,
        pair_binfloat_vs_legacy,
        pair_coeff_vs_bigint,
        run_release_benchmarks,
        unstable_benchmark_records,
        validate_benchmark_records,
    )


def record(
    name: str, median: float, mad_pct: float = 1.0, runs: int = 9
) -> dict[str, object]:
    return {
        "name": name,
        "median": median,
        "median_abs_dev_pct": mad_pct,
        "runs": runs,
        "batch_size": 100,
    }


class ExtractMarkedPayloadsTest(unittest.TestCase):
    def test_extracts_array_from_prefixed_line(self) -> None:
        payload = '[{"name":"coeff/add/53/dense","median":2.0}]'
        extracted = extract_marked_payloads(
            f"test output: BIN_COEFF_BENCH_JSON={payload} trailing text"
        )
        self.assertEqual(
            extracted,
            [
                (
                    "bin_coeff",
                    [{"name": "coeff/add/53/dense", "median": 2.0}],
                )
            ],
        )


class BenchmarkCommandTest(unittest.TestCase):
    def test_benchmark_build_uses_release_optimizations(self) -> None:
        command = benchmark_command("native")
        self.assertIn("--release", command)
        self.assertEqual(command[-2:], ["--target", "native"])
        commands = benchmark_commands("native")
        self.assertEqual(commands["bin_float"][-2:], ["-f", "BinFloat contextual arithmetic baseline"])


class PairCoeffVsBigintTest(unittest.TestCase):
    def test_pairs_by_operation_bits_and_shape(self) -> None:
        records = [
            record("bigint/add/53/dense", 10.0, 2.5),
            record("coeff/from_bigint/53/dense", 3.0, 1.5),
            record("coeff/add/53/dense", 8.0, 1.25),
        ]
        pairs, unpaired = pair_coeff_vs_bigint(records)
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0]["operation"], "add")
        self.assertEqual(pairs[0]["bits"], 53)
        self.assertEqual(pairs[0]["shape"], "dense")
        self.assertAlmostEqual(pairs[0]["median_ratio"], 0.8)
        self.assertEqual(
            [item["name"] for item in unpaired],
            ["coeff/from_bigint/53/dense"],
        )

    def test_rejects_fewer_than_nine_runs(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least 9"):
            validate_benchmark_records(
                [record("coeff/add/53/dense", 8.0, runs=8)]
            )


class PairBinFloatVsLegacyTest(unittest.TestCase):
    def test_pairs_candidate_with_same_process_legacy(self) -> None:
        records = [
            record("legacy/div/113/sparse", 20.0, 1.0),
            record("binfloat/div/113/sparse", 16.0, 1.5),
            record("bigint_oracle/rounded_div/113/near_equal", 5.0),
        ]
        pairs, unpaired = pair_binfloat_vs_legacy(records)
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0]["operation"], "div")
        self.assertAlmostEqual(pairs[0]["median_ratio"], 0.8)
        self.assertEqual(pairs[0]["binfloat"]["median"], 16.0)
        self.assertEqual(pairs[0]["legacy"]["median"], 20.0)
        self.assertEqual(
            [item["name"] for item in unpaired],
            ["bigint_oracle/rounded_div/113/near_equal"],
        )

    def test_uses_same_process_pair_ratios(self) -> None:
        legacy = record("legacy/div/113/sparse", 20.0)
        candidate = record("binfloat/div/113/sparse", 12.0)
        legacy["process_medians"] = [10.0, 30.0, 20.0]
        candidate["process_medians"] = [8.0, 12.0, 40.0]
        self.assertAlmostEqual(paired_median_ratio(candidate, legacy), 0.8)
        pairs, _ = pair_binfloat_vs_legacy([legacy, candidate])
        self.assertAlmostEqual(pairs[0]["median_ratio"], 0.8)


class ReleaseProcessGateTest(unittest.TestCase):
    def test_marks_mad_above_five_percent_unstable(self) -> None:
        results = {
            "bin_coeff": [record("coeff/add/53/dense", 8.0, mad_pct=5.01)],
            "bin_float": [record("binfloat/add/53/dense", 8.0)],
        }
        unstable = unstable_benchmark_records(results)
        self.assertEqual(len(unstable), 1)
        self.assertIn("coeff/add/53/dense", unstable[0])

    def test_aggregates_three_independent_processes(self) -> None:
        results = [
            {
                "bin_coeff": [record("coeff/add/53/dense", 10.0)],
                "bin_float": [record("binfloat/add/53/dense", 15.0)],
            },
            {
                "bin_coeff": [record("coeff/add/53/dense", 20.0)],
                "bin_float": [record("binfloat/add/53/dense", 25.0)],
            },
            {
                "bin_coeff": [record("coeff/add/53/dense", 30.0)],
                "bin_float": [record("binfloat/add/53/dense", 35.0)],
            },
        ]
        aggregate = aggregate_process_results(results)
        coefficient = aggregate["bin_coeff"][0]
        self.assertEqual(coefficient["median"], 20.0)
        self.assertEqual(coefficient["process_count"], 3)
        self.assertEqual(coefficient["process_medians"], [10.0, 20.0, 30.0])

    def test_retries_unstable_process(self) -> None:
        unstable = {
            "bin_coeff": [record("coeff/add/53/dense", 8.0, mad_pct=5.1)],
            "bin_float": [record("binfloat/add/53/dense", 9.0)],
        }
        stable = {
            "bin_coeff": [record("coeff/add/53/dense", 8.0)],
            "bin_float": [record("binfloat/add/53/dense", 9.0)],
        }
        with patch.object(
            bench,
            "run_benchmark_suites",
            side_effect=[unstable, stable, stable, stable],
        ) as mocked_run:
            aggregate = run_release_benchmarks(
                {"bin_coeff": ["benchmark"], "bin_float": ["benchmark"]}
            )
        self.assertEqual(mocked_run.call_count, 4)
        self.assertEqual(aggregate["bin_float"][0]["process_count"], 3)


if __name__ == "__main__":
    unittest.main()
