"""Tests of the pure part of `generate_decimal_gda_exp_rows.py` (values checked by hand)."""

from __future__ import annotations

import decimal
import unittest

import generate_decimal_gda_exp_rows as generator


class ExpectedTest(unittest.TestCase):
    def test_exp_of_one_half_at_three_digits(self) -> None:
        self.assertEqual(generator.expected(3, -99, 99, True, False, "HalfEven", "0.5"), ("1.65", "xr......"))

    def test_directed_rounding_of_exp_one_half(self) -> None:
        self.assertEqual(generator.expected(3, -99, 99, True, False, "Down", "0.5"), ("1.64", "xr......"))
        self.assertEqual(generator.expected(3, -99, 99, True, False, "Up", "0.5"), ("1.65", "xr......"))

    def test_overflow_in_the_extended_arithmetic(self) -> None:
        self.assertEqual(generator.expected(1, -9, 9, True, False, "HalfEven", "100"), ("inf", "xr..o..."))

    def test_the_subset_arithmetic_has_no_value_after_an_overflow(self) -> None:
        self.assertEqual(generator.expected(1, -9, 9, False, False, "HalfEven", "100")[0], "?")

    def test_infinity_text(self) -> None:
        self.assertEqual(generator.text(decimal.Decimal("-Infinity")), "-inf")


class BuildTest(unittest.TestCase):
    def test_rows_are_deterministic_and_cover_four_groups(self) -> None:
        rows = generator.build()
        self.assertEqual(rows, generator.build())
        self.assertEqual({row[0] for row in rows}, {0, 1, 2, 3, 4, 5})
        self.assertEqual(sum(1 for row in rows if row[0] == 2), 8 * 8 * 3)
        self.assertEqual(sum(1 for row in rows if row[0] == 3), 3 * len(generator.LARGE))

    def test_edge_arguments_surround_the_thresholds(self) -> None:
        arguments = generator.edge_arguments(7, -95, 96)
        # emax + 1 = 97: ln(10) * 97 = 223.35, etiny = -101: ln(10) * 101 = 232.56; guards 291 and 306
        for expected in ("223", "221", "226", "-233", "-230", "291", "-306", "-1000"):
            self.assertIn(expected, arguments)
        self.assertEqual(len(arguments), len(set(arguments)))

    def test_known_defect_rows_are_beyond_the_guards_with_a_directed_result(self) -> None:
        down_over = generator.row(4, (7, -95, 96, True, True), "Down", "300")
        self.assertTrue(generator.known_defect(down_over, -95, 96, 7))
        nearest_over = generator.row(4, (7, -95, 96, True, True), "HalfEven", "300")
        self.assertFalse(generator.known_defect(nearest_over, -95, 96, 7))
        below_guard = generator.row(4, (7, -95, 96, True, True), "Down", "290")
        self.assertFalse(generator.known_defect(below_guard, -95, 96, 7))
        up_under = generator.row(4, (7, -95, 96, True, True), "Up", "-306")
        self.assertTrue(generator.known_defect(up_under, -95, 96, 7))


if __name__ == "__main__":
    unittest.main()
