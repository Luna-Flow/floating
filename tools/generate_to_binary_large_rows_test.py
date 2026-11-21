"""Tests of `generate_to_binary_large_rows.py`."""

from __future__ import annotations

import unittest
from fractions import Fraction

import generate_to_binary_large_rows as generator

P = 24


class RoundTest(unittest.TestCase):
    def test_exact_value_is_kept(self) -> None:
        self.assertEqual(generator.ieee_round(3, -1, False, "TowardZero", P), ("fin", 3, -1))

    def test_tie_to_even_and_away(self) -> None:
        # 2^24 + 1 needs 25 bits: a tie between 2^24 and 2^24 + 2
        m = (1 << 24) + 1
        self.assertEqual(generator.ieee_round(m, 0, False, "ToNearestEven", P), ("fin", 1, 24))
        self.assertEqual(generator.ieee_round(m, 0, False, "ToNearestAway", P), ("fin", (1 << 23) + 1, 1))
        # 2^24 + 3 is a tie between 2^24 + 2 and 2^24 + 4: even is 2^24 + 4
        m = (1 << 24) + 3
        self.assertEqual(generator.ieee_round(m, 0, False, "ToNearestEven", P), ("fin", (1 << 22) + 1, 2))

    def test_directions_follow_the_sign(self) -> None:
        m = (1 << 24) + 1
        self.assertEqual(generator.ieee_round(m, 0, True, "TowardPositive", P), ("fin", 1, 24))
        self.assertEqual(generator.ieee_round(m, 0, True, "TowardNegative", P), ("fin", (1 << 23) + 1, 1))

    def test_underflow_and_subnormal_grid(self) -> None:
        smallest = generator.E_MIN - P + 1
        # a quarter of the smallest subnormal: zero except away from zero
        self.assertEqual(generator.ieee_round(1, smallest - 2, False, "ToNearestEven", P), ("zero",))
        self.assertEqual(generator.ieee_round(1, smallest - 2, False, "TowardPositive", P), ("fin", 1, smallest))
        # exactly half: ties to even gives zero, ties away the smallest subnormal
        self.assertEqual(generator.ieee_round(1, smallest - 1, False, "ToNearestEven", P), ("zero",))
        self.assertEqual(generator.ieee_round(1, smallest - 1, False, "ToNearestAway", P), ("fin", 1, smallest))

    def test_overflow(self) -> None:
        s = generator.E_MAX + 1
        self.assertEqual(generator.ieee_round(1, s, False, "ToNearestEven", P), ("inf",))
        largest = ("fin", (1 << P) - 1, generator.E_MAX - P + 1)
        self.assertEqual(generator.ieee_round(1, s, False, "TowardZero", P), largest)
        self.assertEqual(generator.ieee_round(1, s, True, "TowardPositive", P), largest)
        self.assertEqual(generator.ieee_round(1, s, True, "TowardNegative", P), ("inf",))


class EnclosureTest(unittest.TestCase):
    def bounds(self, c: int, e: int):
        (ml, sl), (mh, sh) = generator.value_enclosure(c, e)
        return Fraction(ml) * Fraction(2) ** sl, Fraction(mh) * Fraction(2) ** sh

    def test_enclosure_contains_the_value_beyond_the_exact_limit(self) -> None:
        for e in (20001, 25000, -20001, -25000):
            low, high = self.bounds(7, e)
            self.assertLessEqual(low, Fraction(7) * Fraction(10) ** e)
            self.assertLessEqual(Fraction(7) * Fraction(10) ** e, high)

    def test_enclosure_is_tight(self) -> None:
        low, high = self.bounds(3, 30000)
        self.assertLess((high - low) / low, Fraction(1, 2**500))

    def test_exact_path_for_small_exponents(self) -> None:
        self.assertEqual(generator.value_enclosure(3, 2), ((75, 2), (75, 2)))

    def test_interval_path_agrees_with_the_exact_path(self) -> None:
        saved = generator.EXACT_LIMIT
        try:
            for c, e in ((1, 5000), (9999999999999999999999999999999999, -5000), (7, 4097)):
                generator.EXACT_LIMIT = 10**9
                exact = generator.convert(c, e, False, "ToNearestEven", 113)
                generator.EXACT_LIMIT = 10
                wide = generator.convert(c, e, False, "ToNearestEven", 113)
                self.assertEqual(exact, wide)
        finally:
            generator.EXACT_LIMIT = saved


class RowsTest(unittest.TestCase):
    def test_expected_text(self) -> None:
        self.assertEqual(generator.expected_text(("inf",), True), "-inf")
        self.assertEqual(generator.expected_text(("zero",), True), "-0")
        self.assertEqual(generator.expected_text(("fin", 5, -3), True), "-5p-3")

    def test_rows_are_deterministic_and_counted(self) -> None:
        rows = generator.all_rows()
        self.assertEqual(rows, generator.all_rows())
        self.assertEqual(len(rows), 2580)


if __name__ == "__main__":
    unittest.main()
