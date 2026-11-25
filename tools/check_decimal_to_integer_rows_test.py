"""Tests of `check_decimal_to_integer_rows.py`."""

import unittest
from fractions import Fraction

import check_decimal_to_integer_rows as checker


class RoundedTest(unittest.TestCase):
    def test_ties(self) -> None:
        half = Fraction(5, 2)
        self.assertEqual(checker.rounded(half, "half_even"), 2)
        self.assertEqual(checker.rounded(half, "half_up"), 3)
        self.assertEqual(checker.rounded(half, "half_down"), 2)
        self.assertEqual(checker.rounded(-half, "half_even"), -2)
        self.assertEqual(checker.rounded(-half, "half_up"), -3)
        self.assertEqual(checker.rounded(-half, "half_down"), -2)

    def test_directed(self) -> None:
        value = Fraction(-13, 10)
        self.assertEqual(checker.rounded(value, "down"), -1)
        self.assertEqual(checker.rounded(value, "up"), -2)
        self.assertEqual(checker.rounded(value, "ceiling"), -1)
        self.assertEqual(checker.rounded(value, "floor"), -2)

    def test_zero_five_up(self) -> None:
        self.assertEqual(checker.rounded(Fraction(51, 10), "05up"), 6)
        self.assertEqual(checker.rounded(Fraction(41, 10), "05up"), 4)
        self.assertEqual(checker.rounded(Fraction(1, 10), "05up"), 1)

    def test_range_and_specials(self) -> None:
        self.assertEqual(checker.expected("-1", "down"), (["-1", "-1", "none", "none"], False))
        self.assertEqual(checker.expected("4294967296", "down")[0], ["none", "4294967296", "none", "4294967296"])
        self.assertEqual(checker.expected("sNaN", "down"), (["none"] * 4, False))

    def test_disagreement_is_reported(self) -> None:
        row = '("2.5", "half_even", "3", "3", "3", "3", true),'
        self.assertEqual(len(checker.check(row)), 2)


if __name__ == "__main__":
    unittest.main()
