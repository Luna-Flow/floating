import math
import unittest
from fractions import Fraction

import itl_pow2_reverse_oracle as oracle
import itl_refinements as refs


def end(c: float, a: float) -> oracle.Q:
    return oracle.Q("val", Fraction(c), Fraction(a))


class ExactnessTest(unittest.TestCase):
    def test_rational_quotients_are_found_exactly(self) -> None:
        self.assertEqual(oracle._rational_value(end(16.0, 4.0)), Fraction(2))
        self.assertEqual(oracle._rational_value(end(0.5, 8.0)), Fraction(-1, 3))
        self.assertEqual(oracle._rational_value(end(9.0, 27.0)), Fraction(2, 3))
        self.assertEqual(oracle._rational_value(end(27.0, 9.0)), Fraction(3, 2))
        self.assertEqual(oracle._rational_value(end(1.0, 3.0)), Fraction(0))

    def test_independent_bases_are_irrational(self) -> None:
        self.assertIsNone(oracle._rational_value(end(3.0, 5.0)))
        self.assertIsNone(oracle._rational_value(end(3.0, 2.0)))
        self.assertIsNone(oracle._rational_value(end(15.0, 3.0)))

    def test_comparison_and_rounding(self) -> None:
        third = end(0.5, 8.0)
        self.assertEqual(oracle.compare_end(third, Fraction(0)), -1)
        self.assertEqual(oracle.compare_end(third, Fraction(-1, 2)), 1)
        down = oracle.rounded(third, upper=False)
        up = oracle.rounded(third, upper=True)
        self.assertLess(down, Fraction(-1, 3))
        self.assertGreater(up, Fraction(-1, 3))
        ln_ratio = end(3.0, 5.0)  # ln 3 / ln 5 = 0.6826...
        self.assertEqual(oracle.compare_end(ln_ratio, Fraction(2, 3)), 1)
        self.assertEqual(oracle.compare_end(ln_ratio, Fraction(7, 10)), -1)


class HullTest(unittest.TestCase):
    def test_the_examples_of_the_corpus(self) -> None:
        entire = (-math.inf, math.inf)
        quarter_half = (Fraction(1, 4), Fraction(1, 2))
        self.assertEqual(
            oracle.hull(quarter_half, (Fraction(1, 2), Fraction(1)), entire),
            (Fraction(0), Fraction(1)),
        )
        self.assertEqual(
            oracle.hull(quarter_half, (Fraction(2), Fraction(4)), entire),
            (Fraction(-2), Fraction(-1, 2)),
        )
        self.assertEqual(
            oracle.hull(quarter_half, (Fraction(2), math.inf), entire),
            (-math.inf, Fraction(-1, 2)),
        )

    def test_the_base_one_and_the_base_zero(self) -> None:
        entire = (-math.inf, math.inf)
        one = (Fraction(1), Fraction(1))
        self.assertIsNone(oracle.hull(one, (Fraction(2), Fraction(4)), entire))
        self.assertEqual(oracle.hull(one, (Fraction(1, 2), Fraction(2)), entire), entire)
        zero = (Fraction(0), Fraction(0))
        self.assertEqual(oracle.hull(zero, zero, entire), (Fraction(0), math.inf))
        self.assertIsNone(oracle.hull(zero, zero, (Fraction(-4), Fraction(0))))

    def test_open_ends_against_a_touching_prior(self) -> None:
        # a in [2, inf), c in [2, 4]: beta in (0, 2], 0 is not attained
        a = (Fraction(2), math.inf)
        c = (Fraction(2), Fraction(4))
        self.assertIsNone(oracle.hull(a, c, (Fraction(-3), Fraction(0))))
        self.assertEqual(oracle.hull(a, c, (Fraction(0), Fraction(5))), (Fraction(0), Fraction(2)))
        # with 1 in c the end 0 is attained
        one_four = (Fraction(1), Fraction(4))
        self.assertEqual(
            oracle.hull(a, one_four, (Fraction(-3), Fraction(0))),
            (Fraction(0), Fraction(0)),
        )


class CorpusTest(unittest.TestCase):
    """The corpus statements and the committed refinements against the exact hull.

    Oracle: this program's exact hull (Python `decimal` and `fractions`, no code of the
    library; level A). The two `powRev2` entries of `interpreter_refinements.json` were
    added by hand; `main` recomputes them from the corpus and fails if they differ.
    """

    def corpus(self):
        path = oracle.CORPUS / oracle.FILE
        if not path.exists():
            self.skipTest("the ITF1788 corpus is not installed")
        return refs.parse_statements(path.read_text(encoding="utf-8"))

    def test_every_powrev2_statement_contains_the_exact_hull(self) -> None:
        counts = {"equal": 0, "refined": 0, "wrong": 0}
        for statement in self.corpus():
            if statement.operation == "powRev2":
                counts[oracle.classify(statement)[0]] += 1
        self.assertEqual(counts, {"equal": 373, "refined": 2, "wrong": 0})

    def test_the_committed_refinements_are_recomputed(self) -> None:
        self.corpus()
        self.assertEqual(oracle.main([]), 0)


if __name__ == "__main__":
    unittest.main()
