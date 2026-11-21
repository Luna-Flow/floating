from __future__ import annotations

import unittest

import generate_div_long_rows as gen


class DivLongRowsTest(unittest.TestCase):
    def test_random_matches_the_moonbit_generator_first_values(self) -> None:
        # state after one step: s = s * 6364136223846793005 + 1442695040888963407 mod 2^64, then rotated by 47
        random = gen.Random(0)
        state = 1442695040888963407
        expected = ((state >> 17) | (state << 47)) & gen.MASK
        self.assertEqual(random.next(), expected)

    def test_coeff_has_exact_width(self) -> None:
        random = gen.Random(12345)
        for bits in (1, 31, 32, 33, 700, 51200):
            self.assertEqual(gen.coeff(random, bits).bit_length(), bits)

    def test_outcomes(self) -> None:
        # q = 3 (round bit 1, kept 1 odd), r = 0: a tie to an odd value goes up to even in RNE, RNA goes up,
        # RTZ never, RTP up for the positive sign only, RTN for the negative only
        self.assertEqual(gen.outcomes(3, 0), "UU" "UU" "DD" "UD" "DU")
        # q = 5 (round bit 1, kept 2 even), r = 0: a tie to an even value stays down in RNE
        self.assertEqual(gen.outcomes(5, 0), "DD" "UU" "DD" "UD" "DU")
        # q = 4 (round bit 0), r = 1 (sticky): RNE and RNA down, directed up in their direction
        self.assertEqual(gen.outcomes(4, 1), "DD" "DD" "DD" "UD" "DU")
        # q = 4, r = 0: exact, all down
        self.assertEqual(gen.outcomes(4, 0), "DD" * 5)

    def test_rounded_quotient(self) -> None:
        self.assertEqual(gen.rounded_quotient(1, 0, 3, 0, 4), (11, -5))  # 1/3 = 0.0101..: 1.0101 * 2^-2, 4 bits: 1011 * 2^-5
        self.assertEqual(gen.rounded_quotient(6, 0, 3, 0, 4), (1, 1))  # exactly 2

    def test_weighted(self) -> None:
        self.assertEqual(gen.weighted((5 << 64) | 7), 1 * 7 + 2 * 5)

    def test_row_shapes(self) -> None:
        self.assertEqual(len(gen.constructed_rows()), 4 * 3 * 6)
        self.assertEqual(len(gen.quotient_rows()), 3)


if __name__ == "__main__":
    unittest.main()
