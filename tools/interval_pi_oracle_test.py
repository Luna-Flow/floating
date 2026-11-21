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


if __name__ == "__main__":
    unittest.main()
