#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_point_elementary_oracle.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_point_elementary_oracle as oracle  # noqa: E402


class RowsTest(unittest.TestCase):
    def test_operand(self) -> None:
        self.assertEqual(oracle.operand(5, -3, False), "0x5p-3")
        self.assertEqual(oracle.operand(5, -3, True), "-0x5p-3")

    def test_rows_are_deterministic(self) -> None:
        self.assertEqual(oracle.generate_rows(), oracle.generate_rows())

    def test_ln_rows_are_positive_and_exp_rows_stay_in_range(self) -> None:
        for op, p, text in oracle.generate_rows():
            self.assertIn(op, ("exp", "ln"))
            self.assertIn(p, oracle.PRECISIONS)
            if op == "ln":
                self.assertFalse(text.startswith("-"))
            else:
                number, exponent = text.lstrip("-").removeprefix("0x").split("p")
                top = int(exponent) + int(number, 16).bit_length() - 1
                self.assertTrue(abs(top) <= 20 or int(exponent) == -oracle.EDGE_EXPONENT)

    def test_every_precision_and_both_operations_appear(self) -> None:
        rows = oracle.generate_rows()
        for p in oracle.PRECISIONS:
            self.assertTrue(any(r[0] == "exp" and r[1] == p for r in rows))
            self.assertTrue(any(r[0] == "ln" and r[1] == p for r in rows))

    def test_input_text(self) -> None:
        self.assertEqual(oracle.input_text([("exp", 53, "0x1p0")]), "exp 53 0x1p0\n")


if __name__ == "__main__":
    unittest.main()
