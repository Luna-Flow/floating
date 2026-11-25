"""Tests of `generate_decimal_oracle_rows.py`."""

from __future__ import annotations

import math
import unittest

import generate_decimal_oracle_rows as generator


class GapRowsTest(unittest.TestCase):
    def test_issue_446_shapes(self) -> None:
        rows = generator.gap_rows()
        self.assertEqual(len(rows), len(generator.GAP_CASES))
        # 1E+900000 plus or minus a sticky digit is the operand padded to 34 digits
        self.assertEqual(rows[0][0], "1.000000000000000000000000000000000E+900000")
        # 12345E-10 - 6E+400000 is -6E+400000 at 34 digits

        self.assertEqual(rows[7][0], "6.000000000000000000000000000000000E+400000")


class BallRowsTest(unittest.TestCase):
    def test_one_tenth_at_53_bits(self) -> None:
        rows = {(r[0], r[1]): r for r in generator.ball_rows()}
        text, p, lo_c, lo_k, hi_c, hi_k = rows[("0.1", 53)]
        self.assertEqual((lo_c, lo_k), (7205759403792793, -56))
        self.assertEqual((hi_c, hi_k), (7205759403792794, -56))

    def test_bounds_enclose_the_value(self) -> None:
        for text, p, lo_c, lo_k, hi_c, hi_k in generator.ball_rows():
            negative, numerator, denominator = generator.exact_parts(text)
            for c, k in ((lo_c, lo_k), (hi_c, hi_k)):
                self.assertLess(abs(c), 1 << p)
            # |lo| <= |value| <= |hi| for positive, reversed for negative; compare as fractions
            from fractions import Fraction

            value = Fraction(numerator, denominator) * (-1 if negative else 1)
            lo = Fraction(lo_c) * Fraction(2) ** lo_k
            hi = Fraction(hi_c) * Fraction(2) ** hi_k
            self.assertLessEqual(lo, value)
            self.assertLessEqual(value, hi)
            self.assertLessEqual(hi - lo, abs(Fraction(hi_c, 1) * Fraction(2) ** hi_k) / (1 << (p - 1)))


class WordRowsTest(unittest.TestCase):
    def test_prime_to_ten(self) -> None:
        self.assertEqual(generator.prime_to_ten(2000), 1)
        self.assertEqual(generator.prime_to_ten(2 * 3 * 5 * 7), 21)

    def test_terminates(self) -> None:
        self.assertTrue(generator.terminates(1, 8))
        self.assertFalse(generator.terminates(1, 3))
        self.assertTrue(generator.terminates(3, 12))
        self.assertTrue(generator.terminates(21, 42))
        self.assertFalse(generator.terminates(1, 14))

    def test_rows_agree_with_definitions(self) -> None:
        rows = generator.word_rows()
        self.assertEqual(len(rows), generator.DIVISOR_LIMIT - 1 + len(generator.LIMB_BOUND_DIVISORS))
        for numerator, divisor, ends, remainder in rows:
            n = int(numerator)
            self.assertEqual(remainder, n % divisor)
            self.assertEqual(ends, generator.terminates(n, divisor))
            # independent check of the decision: the reduced denominator has only the primes 2 and 5
            reduced = divisor // math.gcd(n, divisor)
            for prime in (2, 5):
                while reduced % prime == 0:
                    reduced //= prime
            self.assertEqual(ends, reduced == 1)

    def test_both_answers_occur(self) -> None:
        rows = generator.word_rows()
        self.assertGreater(sum(1 for r in rows if r[2]), 1000)
        self.assertGreater(sum(1 for r in rows if not r[2]), 1000)


if __name__ == "__main__":
    unittest.main()
