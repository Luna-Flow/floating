"""Tests of the pure part of `generate_decimal_gda_power_half_rows.py` (values checked by hand)."""

from __future__ import annotations

import decimal
import unittest

import generate_decimal_gda_power_half_rows as generator

CLAMPED_SMALL = generator.CONTEXTS[0]  # precision 5, emin -10, emax 0, clamp
DECIMAL32 = generator.CONTEXTS[3]


class PowerHalfTest(unittest.TestCase):
    def test_exact_root_is_padded_to_the_precision(self) -> None:
        self.assertEqual(generator.power_half(DECIMAL32, "half_even", "4", "0.5"), ("2.000000", "xr......"))

    def test_reciprocal_root(self) -> None:
        self.assertEqual(generator.power_half(DECIMAL32, "half_even", "4", "-0.5"), ("0.5000000", "xr......"))

    def test_inexact_root_directed_rounding(self) -> None:
        self.assertEqual(generator.power_half(DECIMAL32, "down", "2", "0.5"), ("1.414213", "xr......"))
        self.assertEqual(generator.power_half(DECIMAL32, "up", "2", "0.5"), ("1.414214", "xr......"))

    def test_overflow_gives_infinity(self) -> None:
        self.assertEqual(generator.power_half(CLAMPED_SMALL, "half_even", "1E+20", "0.5"), ("Infinity", "xr..o..."))

    def test_padded_result_is_not_clamped_but_zero_is(self) -> None:
        small = generator.CONTEXTS[1]  # precision 3, emin -5, emax 1
        self.assertEqual(generator.power_half(small, "half_even", "1E+20", "-0.5"), ("0E-7", "xr...usc"))
        self.assertEqual(generator.power_half(CLAMPED_SMALL, "half_even", "4", "0.5")[1], "xr......")


class BuildTest(unittest.TestCase):
    def test_1200_rows_in_a_fixed_order(self) -> None:
        rows = generator.build()
        self.assertEqual(len(rows), 6 * 5 * 10 * 4)
        self.assertEqual(rows[0][:4], ("clamped e_max < precision - 1", "half_even", "0.01", "0.5"))

    def test_value_text_of_zero_and_infinity(self) -> None:
        self.assertEqual(generator.value_text(decimal.Decimal("-Infinity"), 5, -14), "-Infinity")
        self.assertEqual(generator.value_text(decimal.Decimal("0E-7"), 3, -7), "0E-7")


if __name__ == "__main__":
    unittest.main()
