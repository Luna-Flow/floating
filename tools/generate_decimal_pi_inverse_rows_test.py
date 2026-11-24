"""Tests of the comparison in `generate_decimal_pi_inverse_rows.py --check`."""

from __future__ import annotations

import unittest

import generate_decimal_pi_inverse_rows as generator

FILE_TEXT = """# mpfr-decimal-random-v2 table=pi_inverse generator=x
# id op rounding precision emax a b n expected flags
pi_inverse-00000 asinpi half_even 1 999999 1 - 0 0.5 -
pi_inverse-00001 atan2pi down 7 999 -3 2 0 -0.2 x
"""

TUPLES = """
  ("asinpi", "half_even", 1, -999998, 999999, true, "b", "1", "-", "0.5", "-"),
  ("atan2pi", "down", 7, -998, 999, true, "b", "-3", "2", "-0.2", "x"),
"""


class ComparisonTest(unittest.TestCase):
    def test_file_rows_map_to_the_compiled_tuples(self) -> None:
        expected = {
            ("asinpi", "half_even", "1", "-999998", "999999", "true", "b", "1", "-", "0.5", "-"),
            ("atan2pi", "down", "7", "-998", "999", "true", "b", "-3", "2", "-0.2", "x"),
        }
        self.assertEqual(generator.full_tokens(FILE_TEXT), expected)

    def test_compiled_tuples_agree_with_the_file(self) -> None:
        sampled = generator.sampled_tokens(TUPLES)
        self.assertEqual(len(sampled), 2)
        self.assertEqual(generator.rows_not_in_full(sampled, generator.full_tokens(FILE_TEXT)), [])

    def test_an_altered_row_is_named(self) -> None:
        sampled = generator.sampled_tokens(TUPLES.replace('"-0.2"', '"-0.3"'))
        self.assertEqual(
            generator.rows_not_in_full(sampled, generator.full_tokens(FILE_TEXT)),
            [("atan2pi", "down", "7", "-998", "999", "true", "b", "-3", "2", "-0.3", "x")],
        )

    def test_a_wrong_derived_field_is_named(self) -> None:
        sampled = generator.sampled_tokens(TUPLES.replace("-998, 999", "-999, 999"))
        self.assertEqual(len(generator.rows_not_in_full(sampled, generator.full_tokens(FILE_TEXT))), 1)


if __name__ == "__main__":
    unittest.main()
