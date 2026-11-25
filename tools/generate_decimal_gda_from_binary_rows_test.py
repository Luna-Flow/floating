"""Tests of the pure part of `generate_decimal_gda_from_binary_rows.py` (values checked by hand)."""

from __future__ import annotations

import unittest

import generate_decimal_gda_from_binary_rows as generator


class ExactPartsTest(unittest.TestCase):
    def test_positive_exponent_is_an_integer_with_exponent_zero(self) -> None:
        self.assertEqual(generator.exact_parts(5, 1), (10, 0))

    def test_negative_exponent_multiplies_by_powers_of_five(self) -> None:
        self.assertEqual(generator.exact_parts(1, -3), (125, -3))

    def test_trailing_zeros_are_removed_while_the_exponent_is_negative(self) -> None:
        self.assertEqual(generator.exact_parts(2, -1), (1, 0))
        self.assertEqual(generator.exact_parts(4, -3), (5, -1))


class ConvertTest(unittest.TestCase):
    def test_exact_value_keeps_the_exponent(self) -> None:
        self.assertEqual(generator.convert(False, 125, -3, 34, "HalfEven"), ("15.625", -3))

    def test_directed_and_nearest_rounding_of_1024_to_one_digit(self) -> None:
        self.assertEqual(generator.convert(True, 1, 10, 1, "HalfEven"), ("-1E+3", 3))
        self.assertEqual(generator.convert(False, 1, 10, 1, "Up"), ("2E+3", 3))
        self.assertEqual(generator.convert(True, 1, 10, 1, "Ceiling"), ("-1E+3", 3))

    def test_tie_2_5_to_one_digit(self) -> None:
        self.assertEqual(generator.convert(False, 5, -1, 1, "HalfEven"), ("2", 0))
        self.assertEqual(generator.convert(False, 5, -1, 1, "HalfUp"), ("3", 0))
        self.assertEqual(generator.convert(False, 5, -1, 1, "HalfDown"), ("2", 0))


class BuildTest(unittest.TestCase):
    def test_hex_has_an_even_length(self) -> None:
        self.assertEqual(generator.hex_of(255), "ff")
        self.assertEqual(generator.hex_of(256), "0100")

    def test_rows_are_deterministic_and_well_formed(self) -> None:
        rows = generator.build()
        self.assertEqual(rows, generator.build())
        self.assertGreater(len(rows), 3000)
        for _negative, hexa, _e2, precision, mode, _text, _exponent in rows:
            self.assertEqual(len(hexa) % 2, 0)
            self.assertIn(mode, generator.MODES)
            self.assertGreaterEqual(precision, 1)


if __name__ == "__main__":
    unittest.main()
