"""Tests of the pure functions of `generate_decimal_conversion_rows.py`."""

import unittest
from fractions import Fraction

import generate_decimal_conversion_rows as generator


class DecimalTextInRangeTest(unittest.TestCase):
    def test_exponent_field_at_the_int32_boundaries(self) -> None:
        self.assertTrue(generator.decimal_text_in_range("1e2147483647"))
        self.assertTrue(generator.decimal_text_in_range("1e+2147483647"))
        self.assertTrue(generator.decimal_text_in_range("1e-2147483647"))
        self.assertTrue(generator.decimal_text_in_range("-1.5E2147483647"))

    def test_exponent_field_beyond_the_boundaries_is_rejected(self) -> None:
        self.assertFalse(generator.decimal_text_in_range("1e2147483648"))
        self.assertFalse(generator.decimal_text_in_range("1e+2147483648"))
        self.assertFalse(generator.decimal_text_in_range("1e-2147483648"))
        self.assertFalse(generator.decimal_text_in_range("-1e2147483648"))
        self.assertFalse(generator.decimal_text_in_range("1E+99999999999"))
        self.assertFalse(generator.decimal_text_in_range("0.5e-10000000000"))

    def test_literals_without_an_exponent_field_are_kept(self) -> None:
        self.assertTrue(generator.decimal_text_in_range("12345"))
        self.assertTrue(generator.decimal_text_in_range("-0.001"))
        self.assertTrue(generator.decimal_text_in_range("1e0"))
        self.assertTrue(generator.decimal_text_in_range("1e-0"))

    def test_small_exponents_are_kept(self) -> None:
        self.assertTrue(generator.decimal_text_in_range("1e5"))
        self.assertTrue(generator.decimal_text_in_range("1E-323228600"))


class RoundIntegerTest(unittest.TestCase):
    def test_exact_quotient_is_not_rounded(self) -> None:
        for mode in ("ties_even", "toward_zero", "toward_positive", "half_up", "floor"):
            self.assertEqual(generator.round_integer(6, 3, False, mode), 2)

    def test_ties(self) -> None:
        self.assertEqual(generator.round_integer(5, 2, False, "ties_even"), 2)
        self.assertEqual(generator.round_integer(7, 2, False, "ties_even"), 4)
        self.assertEqual(generator.round_integer(5, 2, False, "ties_away"), 3)
        self.assertEqual(generator.round_integer(5, 2, True, "half_up"), 3)

    def test_directed_modes_depend_on_the_sign(self) -> None:
        self.assertEqual(generator.round_integer(13, 10, False, "toward_zero"), 1)
        self.assertEqual(generator.round_integer(13, 10, False, "toward_positive"), 2)
        self.assertEqual(generator.round_integer(13, 10, True, "toward_positive"), 1)
        self.assertEqual(generator.round_integer(13, 10, True, "toward_negative"), 2)
        self.assertEqual(generator.round_integer(13, 10, False, "toward_negative"), 1)
        self.assertEqual(generator.round_integer(13, 10, True, "floor"), 2)


class BinaryRoundTest(unittest.TestCase):
    def test_exact_value_is_not_inexact(self) -> None:
        kind, coefficient, exponent, inexact, overflow, underflow = generator.binary_round(Fraction(3, 2), 11, -14, 15, "ties_even")
        self.assertEqual(kind, "finite")
        self.assertEqual(coefficient * Fraction(2) ** exponent, Fraction(3, 2))
        self.assertFalse(inexact or overflow or underflow)

    def test_overflow_goes_to_infinity_or_the_largest_number(self) -> None:
        huge = Fraction(2) ** 20
        self.assertEqual(generator.binary_round(huge, 11, -14, 15, "ties_even")[0], "inf")
        kind, coefficient, exponent, _, overflow, _ = generator.binary_round(huge, 11, -14, 15, "toward_zero")
        self.assertEqual((kind, overflow), ("finite", True))
        self.assertEqual(coefficient, (1 << 11) - 1)
        self.assertEqual(exponent, 15 - 10)

    def test_tiny_inexact_value_underflows(self) -> None:
        result = generator.binary_round(Fraction(1, 3) * Fraction(2) ** -30, 11, -14, 15, "ties_even")
        self.assertTrue(result[3] and result[5])


class DecimalRoundTest(unittest.TestCase):
    def test_zero(self) -> None:
        self.assertEqual(generator.decimal_round(Fraction(0), 7, -95, 96, "half_even"), ("finite", 0, 0, False, False, False))

    def test_exact_integer_takes_the_preferred_exponent_zero(self) -> None:
        self.assertEqual(generator.decimal_round(Fraction(1024), 7, -95, 96, "half_even"), ("finite", 1024, 0, False, False, False))

    def test_inexact_value_keeps_the_full_precision(self) -> None:
        kind, coefficient, exponent, inexact, _, _ = generator.decimal_round(Fraction(1, 3), 7, -95, 96, "half_even")
        self.assertEqual((kind, coefficient, exponent, inexact), ("finite", 3333333, -7, True))

    def test_overflow(self) -> None:
        self.assertEqual(generator.decimal_round(Fraction(10) ** 200, 7, -95, 96, "half_even")[0], "inf")
        kind, coefficient, exponent, _, overflow, _ = generator.decimal_round(Fraction(10) ** 200, 7, -95, 96, "down")
        self.assertEqual((kind, coefficient, exponent, overflow), ("finite", 9999999, 90, True))


class ExactCohortTest(unittest.TestCase):
    def test_small_integer_is_not_rounded(self) -> None:
        self.assertEqual(generator.exact_cohort(5, 0, 7), (5, 0, False))

    def test_trailing_zeros_move_toward_exponent_zero(self) -> None:
        self.assertEqual(generator.exact_cohort(1, 3, 7), (1000, 0, False))

    def test_integer_that_needs_the_whole_precision_keeps_its_exponent(self) -> None:
        # 1234567 * 10^2 has seven digits, so no member with a smaller exponent exists
        self.assertEqual(generator.exact_cohort(1234567, 2, 7), (1234567, 2, True))


class TextHelpersTest(unittest.TestCase):
    def test_hex_literal(self) -> None:
        self.assertEqual(generator.hex_literal(255, -3), "0xffp-3")
        self.assertEqual(generator.hex_literal(-255, 4), "-0xffp4")

    def test_quote(self) -> None:
        self.assertEqual(generator.q("n"), '"n"')


if __name__ == "__main__":
    unittest.main()
