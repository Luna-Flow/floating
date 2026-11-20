import math
import unittest
from fractions import Fraction

import itl_pow_reverse_oracle as oracle
import itl_refinements as refs


def end(c: float, beta: float) -> oracle.End:
    return oracle.End("pow", Fraction(c), Fraction(beta))


class ExactnessTest(unittest.TestCase):
    def test_dyadic_values_are_found_exactly(self) -> None:
        self.assertEqual(oracle._rational_value(end(0.25, -2.0)), Fraction(2))
        self.assertEqual(oracle._rational_value(end(8.0, 3.0)), Fraction(2))
        self.assertEqual(oracle._rational_value(end(8.0, 0.5)), Fraction(64))
        self.assertEqual(oracle._rational_value(end(81.0, 4.0)), Fraction(3))
        self.assertEqual(oracle._rational_value(end(2.25, 2.0)), Fraction(3, 2))
        self.assertEqual(oracle._rational_value(end(1.0, 7.5)), Fraction(1))

    def test_a_rational_that_is_not_dyadic(self) -> None:
        self.assertEqual(oracle._rational_value(end(9.0, -2.0)), Fraction(1, 3))

    def test_irrational_values_are_not_rational(self) -> None:
        self.assertIsNone(oracle._rational_value(end(2.0, 2.0)))
        self.assertIsNone(oracle._rational_value(end(10.0, 3.0)))
        self.assertIsNone(oracle._rational_value(end(1.1, 0.1)))

    def test_comparison_and_rounding_of_an_irrational_end(self) -> None:
        sqrt2 = end(2.0, 2.0)
        self.assertEqual(oracle.compare_end(sqrt2, Fraction(1)), 1)
        self.assertEqual(oracle.compare_end(sqrt2, Fraction(2)), -1)
        down = oracle.rounded(sqrt2, upper=False)
        up = oracle.rounded(sqrt2, upper=True)
        self.assertEqual(float(down).hex(), "0x1.6a09e667f3bccp+0")
        self.assertEqual(float(up).hex(), "0x1.6a09e667f3bcdp+0")

    def test_a_tiny_exponent_is_decided_by_the_side_of_one(self) -> None:
        # 2^(1/2^100): above 1 by about 2^-100 ln 2: RD = 1, RU = 1 + ulp
        tiny = end(2.0, 2.0**100)
        self.assertEqual(oracle.rounded(tiny, upper=False), Fraction(1))
        self.assertEqual(oracle.rounded(tiny, upper=True), Fraction(1) + Fraction(1, 2**52))


class HullTest(unittest.TestCase):
    def test_the_examples_that_fix_the_definition(self) -> None:
        entire = (-math.inf, math.inf)
        two = (Fraction(2), Fraction(2))
        four = (Fraction(4), Fraction(4))
        self.assertEqual(oracle.hull(two, four, entire), (Fraction(2), Fraction(2)))
        zero = (Fraction(0), Fraction(0))
        # beta in [1, 2], c = {0}: only x = 0
        self.assertEqual(oracle.hull((Fraction(1), Fraction(2)), zero, entire), (Fraction(0), Fraction(0)))
        # x^0 = 1: every x > 0, 0^0 undefined, the hull is [0, inf)
        one = (Fraction(1), Fraction(1))
        self.assertEqual(oracle.hull(zero, one, entire), (Fraction(0), math.inf))
        self.assertIsNone(oracle.hull(zero, (Fraction(2), Fraction(3)), entire))

    def test_open_ends_against_a_touching_prior(self) -> None:
        # S = (1, +inf) for beta in [1, inf), c = [2, inf)
        b = (Fraction(1), math.inf)
        c = (Fraction(2), math.inf)
        self.assertIsNone(oracle.hull(b, c, (Fraction(1), Fraction(1))))
        self.assertIsNone(oracle.hull(b, c, (Fraction(0), Fraction(1))))
        self.assertEqual(oracle.hull(b, c, (Fraction(1), Fraction(2))), (Fraction(1), Fraction(2)))


class CorpusTest(unittest.TestCase):
    def test_every_powrev1_statement_equals_the_exact_hull(self) -> None:
        path = oracle.CORPUS / oracle.FILE
        if not path.exists():
            self.skipTest("the ITF1788 corpus is not installed")
        counts = {"equal": 0, "refined": 0, "wrong": 0}
        for statement in refs.parse_statements(path.read_text(encoding="utf-8")):
            if statement.operation == "powRev1":
                counts[oracle.classify(statement)[0]] += 1
        self.assertEqual(counts, {"equal": 429, "refined": 0, "wrong": 0})


if __name__ == "__main__":
    unittest.main()
