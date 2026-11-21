from __future__ import annotations

import random
import unittest
from fractions import Fraction

import generate_hex_ctx_rows as reference
import generate_round_rows as gen


class RoundRowsTest(unittest.TestCase):
    def test_against_the_fraction_reference_on_small_ranges(self) -> None:
        rng = random.Random(7)
        for _ in range(4000):
            p = rng.randint(1, 12)
            emax = rng.randint(2, 30)
            m = rng.getrandbits(rng.randint(1, 40)) | 1
            e = rng.randint(-60, 60)
            negative = rng.random() < 0.5
            mode = rng.choice(gen.MODES)
            tininess = rng.choice(gen.TININESS)
            value = Fraction(m) * Fraction(2) ** e
            expected = reference.convert(value, negative, p, 1 - emax, emax, mode, tininess)
            self.assertEqual(gen.round_dyadic(negative, m, e, p, emax, mode, tininess), expected, (negative, m, e, p, emax, mode, tininess))

    def test_known_values(self) -> None:
        # 3 at p = 1 is a tie between 2 and 4: to even gives 4, toward zero 2
        self.assertEqual(gen.round_dyadic(False, 3, 0, 1, 100, "RNE", "before"), ("1p2", "I--"))
        self.assertEqual(gen.round_dyadic(False, 3, 0, 1, 100, "RTZ", "before"), ("1p1", "I--"))
        # 2^emax is exact, 2^(emax+1) overflows
        self.assertEqual(gen.round_dyadic(False, 1, 15, 11, 15, "RNE", "before"), ("1p15", "---"))
        self.assertEqual(gen.round_dyadic(False, 1, 16, 11, 15, "RNE", "before"), ("inf", "I-O"))

    def test_extreme_exponents_need_no_rational(self) -> None:
        text, flags = gen.round_dyadic(False, 3, gen.IMPL_EMIN - 1, 2, gen.IMPL_EMAX, "RTP", "after")
        self.assertEqual(flags, "---")
        self.assertEqual(text, "3p" + str(gen.IMPL_EMIN - 1))

    def test_sqrt_brackets_the_root_by_squaring(self) -> None:
        # in the normal range the result r (a multiple of the quantum u) satisfies, by squaring only:
        # toward zero r^2 <= x < (r + u)^2; toward plus infinity (r - u)^2 < x <= r^2;
        # to nearest (r - u/2)^2 <= x <= (r + u/2)^2, equality only where the tie rule allows it
        rng = random.Random(11)
        checked = 0
        for _ in range(4000):
            p = rng.randint(1, 10)
            emax = 1000
            m = rng.getrandbits(rng.randint(1, 30)) | 1
            e = rng.randint(-40, 40)
            mode = rng.choice(["RNE", "RNA", "RTZ", "RTP", "RTN"])
            text, flags = gen.sqrt_round(m, e, p, emax, mode, "before")
            mantissa, _, exponent = text.partition("p")
            r = Fraction(int(mantissa)) * Fraction(2) ** int(exponent)
            x = Fraction(m) * Fraction(2) ** e
            u = Fraction(2) ** (reference.binade(r) - p + 1)
            if mode in ("RTZ", "RTN"):
                self.assertTrue(r * r <= x < (r + u) ** 2 or r * r == x)
            elif mode == "RTP":
                self.assertTrue((r - u) ** 2 < x <= r * r)
            else:
                self.assertTrue((r - u / 2) ** 2 <= x <= (r + u / 2) ** 2)
            self.assertEqual(flags == "---", r * r == x)
            checked += 1
        self.assertEqual(checked, 4000)

    def test_sqrt_known_values(self) -> None:
        self.assertEqual(gen.sqrt_round(2, 0, 3, 100, "RNE", "before"), ("3p-1", "I--"))
        self.assertEqual(gen.sqrt_round(2, 0, 3, 100, "RTZ", "before"), ("5p-2", "I--"))
        self.assertEqual(gen.sqrt_round(4, 0, 53, 1023, "RNE", "before"), ("1p1", "---"))
        self.assertEqual(gen.sqrt_round(1, 2 * 2000, 53, 1023, "RNE", "before"), ("inf", "I-O"))

    def test_rows_are_well_formed(self) -> None:
        rows = gen.build()
        self.assertGreater(len(rows), 2000)
        for operation, negative, m, e, p, emax, mode, tininess, _expected, _flags in rows:
            self.assertIn(operation, ('round', 'sqrt'))
            self.assertIn(negative, (0, 1))
            self.assertGreater(int(m, 16), 0)
            self.assertIn(mode, gen.MODES)
            self.assertLess(abs(e), 2**31)


if __name__ == "__main__":
    unittest.main()
