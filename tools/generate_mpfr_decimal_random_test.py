import shutil
import unittest
from fractions import Fraction

import generate_mpfr_decimal_random as tool


def exact(value) -> Fraction:
    return Fraction(value)


class DyadicBoundTests(unittest.TestCase):
    CONTEXT = tool.Context(34, "half_even", -6143, 6144, 1, "b")

    def test_bounds_bracket_the_dyadic_value(self) -> None:
        for mantissa, exponent in (
            (3, -1),
            (-3, -1),
            (1, 0),
            ((1 << 767) + 12345, -700),
            (-((1 << 767) + 12345), 300),
            (7, -1000),
            (-(2**200 + 1), -2000),
        ):
            value = Fraction(mantissa) * Fraction(2) ** exponent
            low = tool.dyadic_bound(mantissa, exponent, False, self.CONTEXT)
            high = tool.dyadic_bound(mantissa, exponent, True, self.CONTEXT)
            self.assertLessEqual(exact(low), value, (mantissa, exponent))
            self.assertGreaterEqual(exact(high), value, (mantissa, exponent))
            # The slack is far below a 768-bit enclosure.
            self.assertLess(abs(exact(high) - exact(low)), abs(value) * Fraction(1, 10**800))

    def test_endpoints_far_outside_the_range_are_representatives(self) -> None:
        huge = tool.dyadic_bound(1, 10**8, True, self.CONTEXT)
        self.assertEqual(huge, tool.decimal.Decimal("1E+6154"))
        tiny = tool.dyadic_bound(-1, -(10**8), False, self.CONTEXT)
        self.assertEqual(tiny, tool.decimal.Decimal("-1E-6186"))


class CandidateTests(unittest.TestCase):
    def test_candidates_are_a_function_of_seed_operation_index_and_attempt(self) -> None:
        first = tool.make_candidate("exp", 20261118, 17, 0)
        again = tool.make_candidate("exp", 20261118, 17, 0)
        other = tool.make_candidate("exp", 20261118, 17, 1)
        self.assertEqual(first, again)
        self.assertNotEqual(first, other)

    def test_operands_are_members_of_the_format(self) -> None:
        for operation in tool.OPERATIONS:
            for index in range(40):
                candidate = tool.make_candidate(operation, 1, index, 0)
                if candidate is None:
                    continue
                for operand in candidate.operands:
                    self.assertIsNotNone(tool.representable(operand, candidate.context), (operation, index))

    def test_domains_are_respected(self) -> None:
        for index in range(60):
            for operation, test in (
                ("ln", lambda x: x > 0),
                ("acosh", lambda x: x >= 1),
                ("log1p", lambda x: x > -1),
                ("asin", lambda x: abs(x) <= 1),
                ("atanh", lambda x: abs(x) <= 1),
            ):
                candidate = tool.make_candidate(operation, 5, index, 0)
                if candidate is not None:
                    self.assertTrue(test(candidate.operands[0]), (operation, candidate.operands[0]))

    def test_rootn_of_a_negative_uses_an_odd_degree(self) -> None:
        for index in range(200):
            candidate = tool.make_candidate("rootn", 3, index, 0)
            if candidate is not None and candidate.operands[0] < 0:
                self.assertEqual(candidate.integer % 2, 1)


class RowTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("cc"), "needs a C compiler")
    def test_rows_are_reproducible_and_well_formed(self) -> None:
        try:
            tool.build_enclosure()
        except RuntimeError as error:  # no MPFR on this machine
            self.skipTest(str(error))
        first = tool.generate("exp", 20261118, 0, 20)
        again = tool.generate("exp", 20261118, 0, 20)
        self.assertEqual(first, again)
        self.assertGreater(len(first), 15)
        for row in first:
            tokens = row.split()
            self.assertEqual(len(tokens), 10)
            self.assertTrue(tokens[0].startswith("m20261118.exp."))
            self.assertTrue(set(tokens[9]) <= set("xouvz-"))
            self.assertIn("x", tokens[9])  # every sampled result is inexact

    @unittest.skipUnless(shutil.which("cc"), "needs a C compiler")
    def test_a_start_offset_selects_the_same_rows(self) -> None:
        try:
            tool.build_enclosure()
        except RuntimeError as error:
            self.skipTest(str(error))
        whole = tool.generate("ln", 7, 0, 12)
        tail = tool.generate("ln", 7, 6, 6)
        self.assertEqual([row for row in whole if int(row.split()[0].split(".")[-1]) >= 6], tail)


if __name__ == "__main__":
    unittest.main()
