from __future__ import annotations

import unittest
from fractions import Fraction

import generate_hex_agree_rows as gen


class HexAgreeRowsTest(unittest.TestCase):
    def test_parse_forms(self) -> None:
        self.assertEqual(gen.parse_hex("0x.8p1"), (False, Fraction(1)))
        self.assertEqual(gen.parse_hex("-0x1.8p0"), (True, Fraction(3, 2)))
        self.assertEqual(gen.parse_hex("0xAp-1"), (False, Fraction(5)))
        self.assertEqual(gen.parse_hex("-0x0.0p5"), (True, Fraction(0)))

    def test_rounding(self) -> None:
        self.assertEqual(gen.expected("0x1.8p0", 1), "1p1")  # 1.5 at p=1 is a tie, to even: 2
        self.assertEqual(gen.expected("0x1.8p0", 2), "3p-1")  # exact
        self.assertEqual(gen.expected("-0x0.0p5", 11), "-0")
        self.assertEqual(gen.expected("0x1.0000018p0", 24), "8388609p-23")  # above the midpoint

    def test_table_size(self) -> None:
        self.assertEqual(len(gen.rows()), 60)


if __name__ == "__main__":
    unittest.main()
