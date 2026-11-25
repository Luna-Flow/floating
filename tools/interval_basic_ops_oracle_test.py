#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_basic_ops_oracle.py."""

from __future__ import annotations

import sys
import unittest
from fractions import Fraction as F
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_basic_ops_oracle as o  # noqa: E402


class RoundingTest(unittest.TestCase):
    def test_directed(self) -> None:
        third = F(1, 3)
        self.assertLess(o.round_directed(third, 8, False), third)
        self.assertGreater(o.round_directed(third, 8, True), third)
        self.assertEqual(o.round_directed(F(3, 8), 4, True), F(3, 8))
        self.assertEqual(o.round_directed(F(-1, 3), 3, True), F(-5, 16))  # -0.3125 is above -1/3
        self.assertEqual(o.round_directed(F(-1, 3), 3, False), F(-3, 8))

    def test_nearest_ties_to_even(self) -> None:
        self.assertEqual(o.round_nearest(F(9, 8), 3), F(1))  # 1.001b at 3 bits: tie, 1.00 is even
        self.assertEqual(o.round_nearest(F(11, 8), 3), F(3, 2))  # 1.011b: tie, 1.10 is even
        self.assertEqual(o.round_nearest(F(-1, 10), 2), F(-3, 32))


class HullTest(unittest.TestCase):
    def test_mul(self) -> None:
        self.assertEqual(o.mul_hull((F(-2), F(3)), (F(1), F(4)), 53), (F(-8), F(12)))
        self.assertEqual(o.mul_hull((F(0), F(3)), (F(2), "inf"), 53), (F(0), "inf"))
        self.assertEqual(o.mul_hull((F(0), F(0)), ("-inf", "inf"), 53), (F(0), F(0)))

    def test_div(self) -> None:
        self.assertEqual(o.div_hull((F(1), F(2)), (F(1), "inf"), 53), (F(0), F(2)))
        self.assertEqual(o.div_hull(("-inf", F(3)), (F(1), F(2)), 53), ("-inf", F(3)))
        lo, hi = o.div_hull((F(1), F(1)), (F(3), F(3)), 4)
        self.assertEqual((lo, hi), (F(5, 16), F(11, 32)))

    def test_pown(self) -> None:
        self.assertEqual(o.pown_hull((F(-2), F(3)), 2, 53), (F(0), F(9)))
        self.assertEqual(o.pown_hull((F(-2), F(3)), 3, 53), (F(-8), F(27)))
        self.assertEqual(o.pown_hull(("-inf", F(1)), 2, 53), (F(0), "inf"))

    def test_fmt(self) -> None:
        self.assertEqual(o.fmt(F(3, 4)), "0x3p-2")
        self.assertEqual(o.fmt(F(-6)), "-0x6p0")
        self.assertEqual(o.fmt(F(0)), "0x0p0")

    def test_rows_are_deterministic(self) -> None:
        self.assertEqual(o.rows(), o.rows())


if __name__ == "__main__":
    unittest.main()
