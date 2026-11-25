#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_corner_oracle.py."""

from __future__ import annotations

import math
import sys
import unittest
from fractions import Fraction as F
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_corner_oracle as o  # noqa: E402


class HexTest(unittest.TestCase):
    def test_hex_text(self) -> None:
        self.assertEqual(o.hex_text(F(0)), "0x0p0")
        self.assertEqual(o.hex_text(F(3, 2)), "0x3p-1")
        self.assertEqual(o.hex_text(F(-12)), "-0x3p2")
        self.assertEqual(o.hex_text(F(1, 8)), "0x1p-3")

    def test_mpfr_value(self) -> None:
        self.assertEqual(o.mpfr_value("0x1.8p+1"), F(3))
        self.assertEqual(o.mpfr_value("-0x1p-2"), F(-1, 4))
        self.assertEqual(o.mpfr_value("0x3p-1"), F(3, 2))
        self.assertEqual(o.mpfr_value("-0x0p+0"), F(0))


class ExtremaTest(unittest.TestCase):
    def test_sinpi(self) -> None:
        self.assertEqual(o.pi_scaled_extrema("sinpi", F(0), F(1, 4)), (False, False))
        self.assertEqual(o.pi_scaled_extrema("sinpi", F(0), F(1, 2)), (False, True))  # sinpi(1/2) = 1
        self.assertEqual(o.pi_scaled_extrema("sinpi", F(1), F(3, 2)), (True, False))  # sinpi(3/2) = -1
        self.assertEqual(o.pi_scaled_extrema("sinpi", F(-1, 2), F(-1, 2)), (True, False))  # sinpi(-1/2) = -1
        self.assertEqual(o.pi_scaled_extrema("sinpi", F(0), F(2)), (True, True))

    def test_cospi(self) -> None:
        self.assertEqual(o.pi_scaled_extrema("cospi", F(1, 4), F(3, 4)), (False, False))
        self.assertEqual(o.pi_scaled_extrema("cospi", F(0), F(1, 2)), (False, True))
        self.assertEqual(o.pi_scaled_extrema("cospi", F(1, 2), F(1)), (True, False))
        self.assertEqual(o.pi_scaled_extrema("cospi", F(-1), F(-1)), (True, False))
        self.assertEqual(o.pi_scaled_extrema("cospi", F(-3, 2), F(3, 2)), (True, True))

    def test_against_dense_samples(self) -> None:
        for op, f in (("sinpi", math.sin), ("cospi", math.cos)):
            for a in (F(-5, 2), F(-1), F(-1, 3), F(0), F(1, 4), F(1, 2), F(7, 4)):
                for b in (F(-1, 3), F(0), F(1, 2), F(1), F(9, 4), F(7, 2)):
                    if b < a:
                        continue
                    has_min, has_max = o.pi_scaled_extrema(op, a, b)
                    n = 4000
                    vals = [f(math.pi * (float(a) + (float(b) - float(a)) * i / n)) for i in range(n + 1)]
                    self.assertEqual(has_min, min(vals) < -1 + 1e-6, (op, a, b))
                    self.assertEqual(has_max, max(vals) > 1 - 1e-6, (op, a, b))


def angle_samples(ylo: F, yhi: F, xlo: F, xhi: F, n: int = 24) -> list[float]:
    """Angles of a grid of the box (the half-line y = 0, x < 0 taken at y = +0, the origin skipped)."""
    out = []
    for i in range(n + 1):
        for j in range(n + 1):
            x = float(xlo) + (float(xhi) - float(xlo)) * i / n
            y = float(ylo) + (float(yhi) - float(ylo)) * j / n
            if x == 0 and y == 0:
                continue
            out.append(math.atan2(0.0 if y == 0 else y, x))
    return out


class Atan2PlanTest(unittest.TestCase):
    def test_special(self) -> None:
        self.assertEqual(o.atan2_plan(F(0), F(0), F(0), F(0)), "empty")
        self.assertEqual(o.atan2_plan(F(-1), F(1), F(-1), F(1)), "full")
        self.assertEqual(o.atan2_plan(F(-1), F(0), F(-2), F(-1)), "full")  # y reaches 0 on the cut
        self.assertEqual(o.atan2_plan(F(-1), F(-1, 2), F(-2), F(-1)), [
            (F(-2), F(-1)), (F(-2), F(-1, 2)), (F(-1), F(-1)), (F(-1), F(-1, 2))])  # fmt: skip

    def test_origin_corner_is_skipped(self) -> None:
        plan = o.atan2_plan(F(0), F(1), F(0), F(1))
        assert isinstance(plan, list)
        self.assertNotIn((F(0), F(0)), plan)
        self.assertIn((F(1), F(0)), plan)  # angle 0
        self.assertIn((F(0), F(1)), plan)  # angle pi/2

    def test_hull_against_a_dense_grid(self) -> None:
        values = [F(v, 2) for v in range(-4, 5)]
        for ylo in values:
            for yhi in values:
                for xlo in values:
                    for xhi in values:
                        if ylo > yhi or xlo > xhi:
                            continue
                        plan = o.atan2_plan(ylo, yhi, xlo, xhi)
                        samples = angle_samples(ylo, yhi, xlo, xhi)
                        if plan == "empty":
                            self.assertEqual(samples, [])
                            continue
                        if plan == "full":
                            lo, hi = -math.pi, math.pi
                            self.assertGreater(min(samples), -math.pi - 1e-12)
                            self.assertLess(max(samples), math.pi + 1e-12)
                            continue
                        angles = [math.atan2(float(y), float(x)) for (x, y) in plan]  # type: ignore[union-attr]
                        lo, hi = min(angles), max(angles)
                        # the plan's hull contains every sampled angle ...
                        self.assertGreaterEqual(min(samples), lo - 1e-12, (ylo, yhi, xlo, xhi))
                        self.assertLessEqual(max(samples), hi + 1e-12, (ylo, yhi, xlo, xhi))
                        # ... and its ends are angles of points of the box
                        self.assertLessEqual(hi - lo, math.pi + 1e-12)

    def test_full_is_needed(self) -> None:
        # a box across the cut has samples near -pi and at pi
        samples = angle_samples(F(-1), F(1), F(-2), F(-1), n=200)
        self.assertLess(min(samples), -3.1)
        self.assertGreater(max(samples), 3.1)


class CombineTest(unittest.TestCase):
    def test_sinpi_with_extremum(self) -> None:
        row = ("sinpi", 5, (F(0), F(1, 2)))
        lo, hi = o.combine(row, [("0x0p+0", "0x0p+0"), ("0x1p+0", "0x1p+0")])
        self.assertEqual((lo, hi), ("0x0p+0", "0x1p+0"))

    def test_cospi_negative_extremum(self) -> None:
        row = ("cospi", 5, (F(0), F(1)))
        lo, hi = o.combine(row, [("0x1p+0", "0x1p+0"), ("-0x1p+0", "-0x1p+0")])
        self.assertEqual((lo, hi), ("-0x1p+0", "0x1p+0"))

    def test_full_range_uses_the_upper_pi_at_both_ends(self) -> None:
        row = ("atan2", 5, (F(-1), F(1), F(-1), F(1)))
        self.assertEqual(o.combine(row, [("0x1.9p+1", "0x1.98p+1")]), ("-0x1.98p+1", "0x1.98p+1"))

    def test_rows_are_distinct_and_counted(self) -> None:
        rows = o.generate_rows()
        keys = [(op, p, operands) for op, p, operands in rows]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual(sum(1 for r in rows if r[0] == "sinpi"), 2 * 253)


if __name__ == "__main__":
    unittest.main()
