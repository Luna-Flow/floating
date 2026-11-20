import math
import unittest
from fractions import Fraction

import itl_atan2_reverse_oracle as oracle

ENTIRE = (-math.inf, math.inf)


def iv(lo, hi):
    def bound(x):
        return x if isinstance(x, float) and math.isinf(x) else Fraction(x)

    return (bound(lo), bound(hi))


class AngleCompareTest(unittest.TestCase):
    def test_floats_next_to_the_multiples_of_pi_over_two(self) -> None:
        def below_or_above(text: str, k: int) -> int:
            return oracle.cmp_bound_enc(Fraction(float.fromhex(text)), oracle.bp_enc(k))

        self.assertEqual(below_or_above("0x1.921fb54442d18p+1", 2), -1)
        self.assertEqual(below_or_above("0x1.921fb54442d19p+1", 2), 1)
        self.assertEqual(below_or_above("0x1.921fb54442d18p+0", 1), -1)
        self.assertEqual(below_or_above("0x1.921fb54442d19p+0", 1), 1)
        self.assertEqual(oracle.cmp_bound_enc(Fraction(0), oracle.bp_enc(0)), 0)
        self.assertEqual(oracle.cmp_bound_enc(-math.inf, oracle.bp_enc(-2)), -1)


class HullTest(unittest.TestCase):
    def test_axis_angles_and_the_origin(self) -> None:
        zero = iv(0, 0)
        up = oracle.hull(1, zero, iv(1, 2), ENTIRE)
        self.assertEqual((up.lo, up.hi), (Fraction(0), math.inf))
        self.assertIsNone(oracle.hull(1, zero, iv(0, 0), ENTIRE))
        self.assertIsNone(oracle.hull(1, zero, iv(1, 1.5), ENTIRE))
        point = oracle.hull(1, ENTIRE, iv(0, 0), ENTIRE)
        self.assertEqual((point.lo, point.hi), (Fraction(0), Fraction(0)))
        self.assertIsNone(oracle.hull(2, zero, iv(1, 1.5), ENTIRE))
        right = oracle.hull(2, zero, iv(0, 0), ENTIRE)
        self.assertEqual((right.lo, right.hi), (Fraction(0), math.inf))
        self.assertIsNone(oracle.hull(2, zero, iv(0, 0), iv(-1, 0)))

    def test_the_branch_cut(self) -> None:
        # pi is attained (y = 0, x < 0), -pi never
        cut = oracle.hull(1, iv(-1, -1), iv(3.1, 4.0), iv(-1, 0))
        self.assertEqual((cut.lo, cut.hi), (Fraction(0), Fraction(0)))
        below = oracle.hull(1, iv(-1, -1), iv(-4.0, -3.1), iv(-1, 0))
        self.assertEqual(below.hi, Fraction(0))
        self.assertIsNone(oracle.hull(1, iv(-1, -1), iv(-4.0, -3.1), iv(0, 0)))
        left = oracle.hull(2, iv(0, 0), iv(3.1, 4.0), ENTIRE)
        self.assertEqual((left.lo, left.hi), (-math.inf, Fraction(0)))
        self.assertIsNone(oracle.hull(2, iv(0, 0), iv(-4.0, -3.1), ENTIRE))

    def test_c_above_pi_or_below_minus_pi_is_empty(self) -> None:
        self.assertIsNone(oracle.hull(1, ENTIRE, iv(4, 5), ENTIRE))
        self.assertIsNone(oracle.hull(2, ENTIRE, iv(-5, -4), ENTIRE))


class ForwardDefinitionTest(unittest.TestCase):
    def test_members(self) -> None:
        # atan2(y, b0) with b0 in [1, 2] and y = 1: angles in [atan(1/2), atan(1)]
        self.assertTrue(oracle.member1(Fraction(1), iv(1, 2), iv(0.5, 0.6)))
        self.assertFalse(oracle.member1(Fraction(1), iv(1, 2), iv(1.0, 1.2)))
        # y = 0: the angle is 0 for b0 > 0 and pi for b0 < 0
        self.assertTrue(oracle.member1(Fraction(0), iv(-1, 1), iv(3.1, 4.0)))
        self.assertTrue(oracle.member1(Fraction(0), iv(-1, 1), iv(-0.5, 0.0)))
        self.assertFalse(oracle.member1(Fraction(0), iv(0, 0), iv(-4, 4)))
        self.assertFalse(oracle.member1(Fraction(0), iv(1, 2), iv(3.1, 4.0)))
        # Rev2: x0 = -1 with a0 in [-1, 1]: the angle pi is attained at a0 = 0
        self.assertTrue(oracle.member2(Fraction(-1), iv(-1, 1), iv(3.1, 4.0)))
        self.assertFalse(oracle.member2(Fraction(-1), iv(1, 2), iv(3.1, 4.0)))
        self.assertFalse(oracle.member2(Fraction(0), iv(0, 0), iv(-4, 4)))

    def test_the_hull_is_validated_by_the_forward_definition(self) -> None:
        stats = {"cases": 0, "passed": 0, "points": 0, "empty": 0}
        for rev, factor, c, prior in (
            (1, iv(-1, 1), iv(1, 2), ENTIRE),
            (1, iv(0.5, 2), iv(-0.5, 0.5), iv(-1, 1)),
            (1, iv(-2, -1), iv(2, 4), ENTIRE),
            (2, iv(-1, 1), iv(1, 2), ENTIRE),
            (2, iv(0.5, 2), iv(-3.0, -2.0), iv(-4, 4)),
            (2, iv(-2, -1), iv(3.1, 4.0), ENTIRE),
        ):
            result = oracle.hull(rev, factor, c, prior)
            self.assertEqual(oracle.validate(rev, factor, c, prior, result, stats), [])


class GridTest(unittest.TestCase):
    def test_the_generated_grid_size(self) -> None:
        cases = oracle.cases()
        self.assertGreater(len(cases), 15000)
        self.assertEqual(len([item for item in cases if item[0] == 1]), len(cases) // 2)


if __name__ == "__main__":
    unittest.main()
