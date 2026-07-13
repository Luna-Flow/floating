from __future__ import annotations

import unittest

from decimal_dispatch_model import (
    DispatchObservation,
    fit_dispatch_model,
    isotonic_decreasing,
    one_sided_sign_p_value,
)


class DecimalDispatchModelTest(unittest.TestCase):
    def test_model_requires_five_processes_and_5000_bootstraps(self) -> None:
        observations = [
            DispatchObservation(size, (1.0, 1.0, 1.0, 1.0))
            for size in (80, 88)
        ]
        with self.assertRaisesRegex(ValueError, "at least 5"):
            fit_dispatch_model(observations, bootstrap_samples=5000)
        observations = [
            DispatchObservation(size, (1.0, 1.0, 1.0, 1.0, 1.0))
            for size in (80, 88)
        ]
        with self.assertRaisesRegex(ValueError, "5000"):
            fit_dispatch_model(observations, bootstrap_samples=4999)

    def test_isotonic_fit_is_non_increasing(self) -> None:
        fitted = isotonic_decreasing(
            [0.2, 0.1, 0.15, -0.2],
            [1.0, 1.0, 1.0, 1.0],
        )
        self.assertGreaterEqual(fitted[0], fitted[1])
        self.assertGreaterEqual(fitted[1], fitted[2])
        self.assertGreaterEqual(fitted[2], fitted[3])
        self.assertAlmostEqual(fitted[1], 0.125)
        self.assertAlmostEqual(fitted[2], 0.125)

    def test_five_process_unanimous_sign_test_is_significant(self) -> None:
        self.assertEqual(one_sided_sign_p_value(5, 5), 0.03125)
        self.assertGreater(one_sided_sign_p_value(4, 5), 0.05)

    def test_model_selects_conservative_change_point(self) -> None:
        observations = [
            DispatchObservation(80, (1.15, 1.12, 1.10, 1.14, 1.11)),
            DispatchObservation(88, (1.05, 1.02, 1.03, 1.01, 1.04)),
            DispatchObservation(96, (0.95, 0.94, 0.96, 0.93, 0.95)),
            DispatchObservation(104, (0.90, 0.92, 0.91, 0.89, 0.90)),
        ]
        model = fit_dispatch_model(
            observations,
            bootstrap_samples=5000,
            seed=7,
        )
        self.assertEqual(model["threshold"]["selected"], 96)
        fitted = [point["fitted_ratio"] for point in model["points"]]
        self.assertEqual(fitted, sorted(fitted, reverse=True))

    def test_model_refuses_switch_without_process_consensus(self) -> None:
        observations = [
            DispatchObservation(80, (1.1, 1.1, 1.1, 1.1, 1.1)),
            DispatchObservation(88, (0.94, 0.95, 1.02, 0.93, 1.01)),
            DispatchObservation(96, (0.90, 0.92, 0.91, 0.89, 0.90)),
        ]
        model = fit_dispatch_model(
            observations,
            bootstrap_samples=5000,
            seed=11,
        )
        self.assertEqual(model["threshold"]["selected"], 96)

    def test_bootstrap_uses_process_columns_across_sizes(self) -> None:
        observations = [
            DispatchObservation(80, (1.2, 0.8, 1.2, 0.8, 1.2)),
            DispatchObservation(88, (1.2, 0.8, 1.2, 0.8, 1.2)),
            DispatchObservation(96, (0.8, 1.2, 0.8, 1.2, 0.8)),
        ]
        model = fit_dispatch_model(
            observations,
            bootstrap_samples=5000,
            seed=19,
        )
        self.assertEqual(model["process_count"], 5)
        self.assertIn("upper_confidence", model["threshold"])


if __name__ == "__main__":
    unittest.main()
