import math
import unittest
from fractions import Fraction

import itl_refinements as refs
import itl_trig_reverse_oracle as oracle

PI_DIGITS = "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899"


def decimal_prefix(value: Fraction, digits: int) -> str:
    scaled = value * 10**digits
    return str(scaled.numerator // scaled.denominator)


class ConstantsTest(unittest.TestCase):
    def test_pi_has_the_known_digits_and_a_tiny_enclosure(self) -> None:
        enc = oracle.pi()
        known = PI_DIGITS.replace(".", "")[:61]
        self.assertEqual(decimal_prefix(enc.lo, 60), known)
        self.assertEqual(decimal_prefix(enc.hi, 60), known)
        self.assertLess(enc.hi - enc.lo, Fraction(1, 10**200))

    def test_atan_asin_acos_at_known_points(self) -> None:
        pi = oracle.pi()
        quarter = oracle.atan(Fraction(1))
        self.assertLess(abs(quarter.lo * 4 - pi.lo), Fraction(1, 10**200))
        sixth = oracle.asin(Fraction(1, 2))
        self.assertLess(abs(sixth.lo * 6 - pi.lo), Fraction(1, 10**200))
        third = oracle.acos(Fraction(1, 2))
        self.assertLess(abs(third.lo * 3 - pi.lo), Fraction(1, 10**200))
        self.assertEqual(oracle.acos(Fraction(1)), oracle.exact(Fraction(0)))
        self.assertLess(abs(oracle.acos(Fraction(-1)).lo - pi.lo), Fraction(1, 10**200))
        self.assertLess(abs(oracle.atan(Fraction(-3)).lo + oracle.atan(Fraction(3)).lo), Fraction(1, 10**200))
        # atan(1/2) + atan(1/3) = pi/4
        total = oracle.atan(Fraction(1, 2)) + oracle.atan(Fraction(1, 3))
        self.assertLess(abs(total.lo - quarter.lo), Fraction(1, 10**200))

    def test_the_directed_rounding_of_pi_is_the_known_pair(self) -> None:
        pi = oracle.pi()
        down = oracle.rounded_end(pi, upper=False)
        up = oracle.rounded_end(pi, upper=True)
        self.assertEqual(float(down).hex(), "0x1.921fb54442d18p+1")
        self.assertEqual(float(up).hex(), "0x1.921fb54442d19p+1")

    def test_an_enclosure_that_holds_a_float_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            oracle.rounded_end(oracle.Enc(Fraction(1, 2), Fraction(1, 2) + Fraction(1, 10**100)), upper=True)


class HullTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rd_pi = Fraction(float.fromhex("0x1.921fb54442d18p+1"))
        self.ru_pi = Fraction(float.fromhex("0x1.921fb54442d19p+1"))

    def test_the_multiples_of_pi_in_a_prior(self) -> None:
        zero = (Fraction(0), Fraction(0))
        self.assertEqual(
            oracle.reverse_hull("sin", zero, (Fraction(3), Fraction(7, 2))),
            (self.rd_pi, self.ru_pi),
        )
        # RU(pi) is above pi: the next multiple is 2 pi
        result = oracle.reverse_hull("sin", zero, (self.ru_pi, Fraction(7)))
        assert result is not None
        self.assertEqual(result[0], 2 * self.rd_pi)
        self.assertEqual(result[1], 2 * self.ru_pi)
        self.assertIsNone(oracle.reverse_hull("sin", zero, (self.ru_pi, Fraction(6))))

    def test_cos_and_tan_at_their_special_points(self) -> None:
        minus_one = (Fraction(-1), Fraction(-1))
        self.assertEqual(
            oracle.reverse_hull("cos", minus_one, (Fraction(3), Fraction(4))),
            (self.rd_pi, self.ru_pi),
        )
        zero = (Fraction(0), Fraction(0))
        self.assertEqual(
            oracle.reverse_hull("tan", zero, (Fraction(-1), Fraction(1))),
            (Fraction(0), Fraction(0)),
        )
        # tan x >= 1 below the pole pi/2: the prior [1.2, RD(pi/2)] lies inside
        lower = Fraction(1.2)
        pole_down = Fraction(float.fromhex("0x1.921fb54442d18p+0"))
        self.assertEqual(
            oracle.reverse_hull("tan", (Fraction(1), math.inf), (lower, pole_down)),
            (lower, pole_down),
        )
        # the prior holds the pole: the hull of the part below it ends at RU(pi/2)
        pole_up = Fraction(float.fromhex("0x1.921fb54442d19p+0"))
        self.assertEqual(
            oracle.reverse_hull("tan", (Fraction(1), math.inf), (pole_down, pole_up)),
            (pole_down, pole_up),
        )

    def test_an_infinite_prior_end_gives_an_infinite_result_end(self) -> None:
        result = oracle.reverse_hull("sin", (Fraction(0), Fraction(0)), (Fraction(1), math.inf))
        assert result is not None
        self.assertEqual(result[1], math.inf)
        self.assertEqual(result[0], self.rd_pi)

    def test_sin_and_cos_are_empty_outside_their_range(self) -> None:
        outside = (Fraction(3, 2), Fraction(2))
        self.assertIsNone(oracle.reverse_hull("sin", outside, (Fraction(0), Fraction(1))))
        self.assertIsNone(oracle.reverse_hull("cos", outside, (Fraction(0), Fraction(1))))


class CorpusTest(unittest.TestCase):
    def test_the_committed_refinements_agree_with_the_oracle(self) -> None:
        if not (oracle.CORPUS / oracle.FILE).exists():
            self.skipTest("the ITF1788 corpus is not installed")
        self.assertEqual(oracle.main(["--check"]), 0)

    def test_every_corpus_statement_is_equal_or_a_proper_subset(self) -> None:
        path = oracle.CORPUS / oracle.FILE
        if not path.exists():
            self.skipTest("the ITF1788 corpus is not installed")
        verdicts = {"equal": 0, "refined": 0, "wrong": 0}
        for statement in refs.parse_statements(path.read_text(encoding="utf-8")):
            if statement.operation in oracle.OPERATIONS:
                verdict, _ = oracle.classify(statement)
                verdicts[verdict] += 1
        self.assertEqual(verdicts["wrong"], 0)
        self.assertEqual(sum(verdicts.values()), 136)
        self.assertEqual(verdicts["refined"], 12)


if __name__ == "__main__":
    unittest.main()
