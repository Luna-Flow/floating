#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_pi_oracle.py."""

from __future__ import annotations

import sys
import unittest
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_pi_oracle as oracle  # noqa: E402


class PiBoundsTest(unittest.TestCase):
    def test_known_digits(self) -> None:
        # The first 40 decimals of pi, written out (not computed by this program).
        digits = Fraction(31415926535897932384626433832795028841971, 10**40)
        lo, hi = oracle.pi_bounds()
        scale = 1 << oracle.FRACTION_BITS
        self.assertLess(abs(Fraction(lo, scale) - digits), Fraction(1, 10**39))
        self.assertLessEqual(lo, hi)
        self.assertLessEqual(hi - lo, 2)

    def test_hex_prefix(self) -> None:
        # pi = 0x3.243F6A8885A308D313198A2E03707344A4093822299F31D0 in hexadecimal.
        lo, _ = oracle.pi_bounds()
        self.assertTrue(f"{lo:x}".startswith("3243f6a8885a308d313198a2e03707344a4093822299f31d"))

    def test_lower_precision_bounds_are_consistent(self) -> None:
        lo, hi = oracle.pi_bounds(256)
        lo2, hi2 = oracle.pi_bounds(512)
        self.assertLessEqual(Fraction(lo, 1 << 256) - Fraction(1, 1 << 256), Fraction(lo2, 1 << 512))
        self.assertGreaterEqual(Fraction(hi, 1 << 256), Fraction(hi2, 1 << 512) - Fraction(1, 1 << 256))


class RoundingClaimTest(unittest.TestCase):
    def test_the_claim_holds_for_every_precision(self) -> None:
        lo, hi = oracle.pi_bounds()
        oracle.check_rounding_claim(lo, hi)

    def test_a_wide_pair_is_refused_with_the_precision(self) -> None:
        lo, hi = oracle.pi_bounds()
        with self.assertRaisesRegex(ValueError, "p = 2010 bits"):
            oracle.check_rounding_claim(lo, hi + (1 << 40))


class RatioTest(unittest.TestCase):
    def test_ratio_bounds_enclose_pi_times_the_ratio(self) -> None:
        lo, hi = oracle.pi_bounds()
        for num, den in oracle.RATIOS:
            r_lo, r_hi = oracle.ratio_bounds(lo, hi, num, den)
            self.assertLess(r_lo * den, lo * num + den)
            self.assertLessEqual(r_lo * den, lo * num)
            self.assertGreaterEqual(r_hi * den, hi * num)
            self.assertLess(r_hi - r_lo, 3)

    def test_ratio_of_six(self) -> None:
        # pi / 6 = 0.5235987755982988...: 2^2048 * that, written to 10 digits by integer arithmetic
        lo, hi = oracle.pi_bounds()
        r_lo, _ = oracle.ratio_bounds(lo, hi, 1, 6)
        self.assertEqual((r_lo * 10**10) >> 2048, 5235987755)


if __name__ == "__main__":
    unittest.main()
