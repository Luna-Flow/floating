from __future__ import annotations

import json
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path

import run_decimal_threshold_bench as threshold_bench


class DecimalThresholdBenchTest(unittest.TestCase):
    def test_extract_records(self) -> None:
        payload = json.dumps(
            [
                {
                    "name": "schoolbook",
                    "median": 10.0,
                    "median_abs_dev_pct": 1.0,
                    "runs": 9,
                },
                {
                    "name": "karatsuba",
                    "median": 8.0,
                    "median_abs_dev_pct": 1.5,
                    "runs": 9,
                },
            ]
        )
        records = threshold_bench.extract_records(
            "noise\n" + threshold_bench.MARKER + payload + "\n"
        )
        self.assertEqual(records, {"schoolbook": 10.0, "karatsuba": 8.0})

    def test_bisection_requires_two_consecutive_wins(self) -> None:
        transition = threshold_bench.Transition("test", "a", "b", 0, 80, 8)
        ratios = {
            0: 1.2,
            8: 1.1,
            16: 1.05,
            24: 0.95,
            32: 1.02,
            40: 0.96,
            48: 0.95,
            56: 0.9,
            64: 0.8,
            72: 0.7,
            80: 0.6,
        }
        boundary, rejected, measured = threshold_bench.bisect_transition(
            transition, ratios.__getitem__, 0.03
        )
        self.assertEqual(boundary, 40)
        self.assertLess(rejected, boundary)
        self.assertIn(48, measured)

    def test_generated_probe_alternates_algorithm_order(self) -> None:
        source = threshold_bench.dense_source(96, ("karatsuba", "schoolbook"))
        self.assertLess(source.index('name="karatsuba"'), source.index('name="schoolbook"'))
        self.assertIn("dec_coeff_test_dense_pattern(96", source)

    def test_benchmark_sample_floor_is_enforced(self) -> None:
        with self.assertRaisesRegex(ValueError, "nine"):
            threshold_bench.probe_source(96, ("karatsuba", "schoolbook"), sample_count=8)
        source = threshold_bench.probe_source(
            96, ("karatsuba", "schoolbook"), sample_count=27
        )
        self.assertIn('count=27', source)

    def test_grid_probe_uses_balanced_abba_order(self) -> None:
        transition = threshold_bench.Transition(
            "test", "schoolbook", "karatsuba", 80, 96, 8
        )
        source = threshold_bench.dense_grid_source(
            transition, [80, 88, 96], reverse_order=False
        )
        names = [
            'name="schoolbook/80/0"',
            'name="karatsuba/80/0"',
            'name="karatsuba/80/1"',
            'name="schoolbook/80/1"',
        ]
        offsets = [source.index(name) for name in names]
        self.assertEqual(offsets, sorted(offsets))

    def test_size_order_rotates_and_reverses(self) -> None:
        self.assertEqual(threshold_bench.rotated_sizes([1, 2, 3, 4], 0), [1, 2, 3, 4])
        self.assertEqual(threshold_bench.rotated_sizes([1, 2, 3, 4], 1), [1, 4, 3, 2])

    def test_grid_rejects_padding_band_crossing(self) -> None:
        transition = threshold_bench.Transition(
            "square-ntt", "square-karatsuba", "square-ntt", 512, 1792, 64
        )
        args = SimpleNamespace(model_low=512, model_high=1792, model_step=64, shape="dense")
        with self.assertRaisesRegex(ValueError, "padding band"):
            threshold_bench.model_grid(transition, args)

    def test_grid_accepts_one_ntt_band_and_emits_sparse_operands(self) -> None:
        transition = threshold_bench.Transition(
            "mul-ntt", "toom3", "ntt", 1024, 1792, 64
        )
        args = SimpleNamespace(model_low=1024, model_high=1792, model_step=64, shape="sparse")
        self.assertEqual(threshold_bench.model_grid(transition, args), list(range(1024, 1793, 64)))
        source = threshold_bench.grid_source(transition, [1024], False, "sparse")
        self.assertIn("dec_coeff_test_sparse_pattern", source)

    def test_named_padding_band_defaults_do_not_cross_cliffs(self) -> None:
        args = SimpleNamespace(
            model_low=None, model_high=None, model_step=None, shape="dense"
        )
        for transition in threshold_bench.TRANSITIONS:
            if transition.name.endswith(("-1k", "-2k", "-4k", "-8k", "-16k", "-32k", "-64k")):
                with self.subTest(transition=transition.name):
                    self.assertGreater(len(threshold_bench.model_grid(transition, args)), 1)

    def test_unbalanced_shape_scales_only_the_long_operand(self) -> None:
        transition = threshold_bench.Transition(
            "mul-unbalanced", "schoolbook", "karatsuba", 16, 32, 8
        )
        source = threshold_bench.probe_source(16, ("schoolbook", "karatsuba"), "unbalanced")
        self.assertIn("dec_coeff_test_dense_pattern(16, 17)", source)
        self.assertIn("dec_coeff_test_dense_pattern(48, 31)", source)

    def test_snapshot_excludes_build_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            snapshot = threshold_bench.make_snapshot(Path(root))
            self.assertFalse((snapshot / "_build").exists())


if __name__ == "__main__":
    unittest.main()
