"""Tests of the pure part of `generate_decimal_gda_endpoint_rows.py` (values checked by hand)."""

from __future__ import annotations

import unittest

import generate_decimal_gda_endpoint_rows as generator


class ExactTextTest(unittest.TestCase):
    def test_positive_exponent(self) -> None:
        self.assertEqual(generator.exact_text(False, 1, 10), "1024")

    def test_negative_exponent_with_sign(self) -> None:
        self.assertEqual(generator.exact_text(True, 3, -2), "-0.75")

    def test_trailing_zeros_are_removed_while_the_exponent_is_negative(self) -> None:
        self.assertEqual(generator.exact_text(False, 2, -1), "1")


class OverUnderTest(unittest.TestCase):
    def test_narrow_context_upper_end(self) -> None:
        # 2^336 = 10^101.15 is above 10^(99 + 2), 2^333 = 10^100.2 is below
        self.assertEqual(generator.over_under(1, 336, 1), (True, False))
        self.assertEqual(generator.over_under(1, 333, 1), (False, False))

    def test_narrow_context_lower_end(self) -> None:
        # etiny = -99 - 7 + 1 = -105: 2^-355 = 10^-106.9 is above 10^-107, 2^-356 = 10^-107.17 below
        self.assertEqual(generator.over_under(1, -355, 1), (False, False))
        self.assertEqual(generator.over_under(1, -356, 1), (False, True))

    def test_wide_context_is_decided_by_the_sign_of_the_limit(self) -> None:
        self.assertEqual(generator.over_under(3, 1500, 0), (False, False))


class LimbRowsTest(unittest.TestCase):
    def test_first_rows(self) -> None:
        rows = generator.build_limbs()
        self.assertEqual(rows[0], ("ones", 0, 1, "0", "0"))
        self.assertIn(("one", 1, 1, "1", "1"), rows)
        self.assertIn(("ones", 1, 3, "255", "255"), rows)

    def test_digit_count_of_two_to_the_eight_times_length_minus_one(self) -> None:
        by_key = {(p, n): count for p, n, count, _h, _t in generator.build_limbs()}
        self.assertEqual(by_key[("one", 2)], 3)  # 256
        self.assertEqual(by_key[("ones", 2)], 5)  # 65535


if __name__ == "__main__":
    unittest.main()
