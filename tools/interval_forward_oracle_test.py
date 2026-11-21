#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_forward_oracle.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_forward_oracle as oracle  # noqa: E402


class RowsTest(unittest.TestCase):
    def test_hex_value(self) -> None:
        self.assertEqual(oracle.hex_value(0, 5), "0x0p0")
        self.assertEqual(oracle.hex_value(-255, -3), "-0xffp-3")

    def test_round_down_bits(self) -> None:
        self.assertEqual(oracle.round_down_bits(0b1011011, 0, 4), (0b1011, 3))
        self.assertEqual(oracle.round_down_bits(5, 2, 8), (5, 2))

    def test_near_multiples_of_pi_half(self) -> None:
        # The binary64 numbers next to pi/2 and pi, written out: 0x1.921fb54442d18p0 and 0x1.921fb54442d18p1.
        half, whole = oracle.near_multiples_of_pi_half(53)
        self.assertEqual(half, "0x1921fb54442d18p-52")
        self.assertEqual(whole, "0x1921fb54442d18p-51")

    def test_rows_are_deterministic_and_cover_every_operation(self) -> None:
        rows = oracle.generate_rows()
        self.assertEqual(rows, oracle.generate_rows())
        self.assertEqual({op for op, _, _ in rows}, {"asin", "acos", "atan", "atan2", "pow", "tan", "cot"})
        for op, _, y in rows:
            self.assertEqual(y is not None, op in ("pow", "atan2"))

    def test_input_text(self) -> None:
        self.assertEqual(oracle.input_text([("pow", "0x1p0", "0x1p1")]), "pow 200 0x1p0 0x1p1\n")


if __name__ == "__main__":
    unittest.main()
