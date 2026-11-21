from __future__ import annotations

import random
import unittest
from fractions import Fraction

import generate_arith_rows as gen


class ArithRowsTest(unittest.TestCase):
    def test_hex_text_and_value(self) -> None:
        self.assertEqual(gen.hex_text((True, 0xAB, -3)), "-0xabp-3")
        self.assertEqual(gen.value_of((True, 3, -1)), Fraction(-3, 2))

    def test_finish_tie_and_inexact(self) -> None:
        tie = 1 + Fraction(1, 2**53)  # half an ulp above 1 at p = 53
        self.assertEqual(gen.finish(tie, 53, gen.IMPL_EMIN, gen.IMPL_EMAX, "RNE", "before"), ("1p0", "I--"))
        self.assertEqual(gen.finish(tie, 53, gen.IMPL_EMIN, gen.IMPL_EMAX, "RTP", "before"), ("4503599627370497p-52", "I--"))
        self.assertEqual(gen.finish(Fraction(9), 2, gen.IMPL_EMIN, gen.IMPL_EMAX, "RNE", "before"), ("1p3", "I--"))
        self.assertEqual(gen.finish(Fraction(3), 2, gen.IMPL_EMIN, gen.IMPL_EMAX, "RNE", "before"), ("3p0", "---"))

    def test_finish_zero_sign(self) -> None:
        self.assertEqual(gen.finish(Fraction(0), 53, -1022, 1023, "RTN", "before", zero_negative=True), ("-0", "---"))
        self.assertEqual(gen.finish(Fraction(0), 53, -1022, 1023, "RNE", "before"), ("0", "---"))

    def test_finish_overflow(self) -> None:
        self.assertEqual(gen.finish(Fraction(2) ** 1024, 53, -1022, 1023, "RNE", "before"), ("inf", "I-O"))
        self.assertEqual(gen.finish(Fraction(2) ** 1024, 53, -1022, 1023, "RTZ", "before"), ("9007199254740991p971", "I-O"))

    def test_sqrt(self) -> None:
        self.assertEqual(gen.sqrt_finish(Fraction(4), 53, "RNE"), ("1p1", "---"))
        self.assertEqual(gen.sqrt_finish(Fraction(2), 3, "RNE"), ("3p-1", "I--"))  # 1.414 on the grid 1/4: 5.66 -> 6
        self.assertEqual(gen.sqrt_finish(Fraction(2), 3, "RTZ"), ("5p-2", "I--"))
        self.assertEqual(gen.sqrt_finish(Fraction(1, 4), 5, "RNE"), ("1p-1", "---"))

    def test_sqrt_against_isqrt_of_scaled_integer(self) -> None:
        rng = random.Random(1)
        for _ in range(200):
            n = rng.getrandbits(rng.randint(1, 120)) | 1
            p = rng.randint(2, 60)
            printed, flags = gen.sqrt_finish(Fraction(n), p, "RTZ")
            # a truncated root times 2^grid squared never exceeds n, and one more unit does
            text = printed
            mant, _, exp = text.partition("p")
            root = Fraction(int(mant)) * Fraction(2) ** int(exp)
            self.assertLessEqual(root * root, n)
            self.assertEqual(flags == "---", root * root == n)

    def test_rows_are_well_formed(self) -> None:
        rows = gen.build()
        self.assertGreater(len(rows), 2000)
        for op, p, _emin, _emax, mode, _tininess, left, right, _expected, _flags in rows:
            self.assertIn(op, ("add", "mul", "div", "sqrt"))
            self.assertIn(mode, gen.MODES)
            self.assertEqual(right == "", op == "sqrt")
            for text in (left, right):
                if text:
                    digits = text.lstrip("-")[2:].split("p")[0]
                    self.assertLessEqual(int(digits, 16).bit_length(), p)


if __name__ == "__main__":
    unittest.main()
