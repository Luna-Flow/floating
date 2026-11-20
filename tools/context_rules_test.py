import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import context_rules as cr  # noqa: E402
import corpus_common  # noqa: E402

VECTORS = Path(__file__).resolve().parent.parent / "testdata" / "context_vectors.txt"


class VectorTests(unittest.TestCase):
    """The rules against the vectors file, which the library constructors are tested against too."""

    def test_every_vector_has_the_verdict_of_the_rules(self) -> None:
        vectors = cr.parse_vectors(VECTORS.read_text(encoding="utf-8"))
        self.assertGreater(len(vectors), 60)
        wrong = [v.line for v in vectors if v.is_legal() != v.legal]
        self.assertEqual(wrong, [])

    def test_the_file_covers_every_standard_and_both_verdicts(self) -> None:
        vectors = cr.parse_vectors(VECTORS.read_text(encoding="utf-8"))
        self.assertEqual({(v.standard, v.legal) for v in vectors}, {(s, ok) for s in ("binary", "decimal", "gda") for ok in (True, False)})

    def test_the_parser(self) -> None:
        (vector,) = cr.parse_vectors("binary 53 - - n - a legal   # a precision alone\n\n# a comment\n")
        self.assertEqual((vector.standard, vector.precision, vector.e_min, vector.e_max, vector.rounding, vector.clamp, vector.tininess, vector.legal),
                         ("binary", 53, None, None, "n", None, "a", True))  # fmt: skip
        for bad in ("binary 53 - - n a legal", "binary 53 - - n - a maybe", "x 1 0 1 n - a legal"):
            with self.assertRaises(ValueError):
                for v in cr.parse_vectors(bad):
                    v.check()


class RuleTests(unittest.TestCase):
    def test_binary_boundaries(self) -> None:
        cr.check_binary_context(1, 1)
        cr.check_binary_context(cr.BINARY_PRECISION_MAX, cr.BINARY_E_MAX_LIMIT, 1 - cr.BINARY_E_MAX_LIMIT)
        cr.check_binary_context(53)
        for bad in ((0, None), (cr.BINARY_PRECISION_MAX + 1, None), (53, 0), (53, cr.BINARY_E_MAX_LIMIT + 1), (53, 1023, -1023), (53, None, -1022)):
            with self.assertRaises(ValueError):
                cr.check_binary_context(*bad)  # type: ignore[arg-type]
        with self.assertRaises(ValueError):
            cr.check_binary_context(53, 1023, None, "a")  # round away from zero is not a rounding direction

    def test_decimal_boundaries(self) -> None:
        cr.check_ieee_decimal_context(1, "half_even", 0, 1, 1, "b")
        cr.check_ieee_decimal_context(cr.DECIMAL_PRECISION_MAX, "floor", 1 - cr.DECIMAL_E_MAX_LIMIT, cr.DECIMAL_E_MAX_LIMIT, 1, "b")
        for bad in (
            (0, "half_even", 0, 1, 1, "b"),
            (34, "half_even", 1, 0, 1, "b"),
            (34, "half_even", -6143, 6143, 1, "b"),
            (34, "half_even", -6142, 6143, 0, "b"),
            (34, "half_even", -6142, 6143, 1, "a"),
            (34, "half_down", -6142, 6143, 1, "b"),
        ):
            with self.assertRaises(ValueError):
                cr.check_ieee_decimal_context(*bad)

    def test_gda_boundaries(self) -> None:
        for e_min in (-100, -99, -98):
            cr.check_gda_context(34, e_min, 99)
        for bad in ((34, -97, 99), (34, 0, -1), (34, 1, 0), (0, -10, 10), (34, -10, 10, "away")):
            with self.assertRaises(ValueError):
                cr.check_gda_context(*bad)  # type: ignore[arg-type]
        self.assertTrue(cr.gda_exponent_range_is_legal(-1, 0))
        self.assertFalse(cr.gda_exponent_range_is_legal(1, 0))


class DataclassTests(unittest.TestCase):
    def test_a_generator_builds_a_context_only_through_the_dataclasses(self) -> None:
        self.assertEqual(cr.BinaryFormat(24, 127).e_min, -126)
        self.assertIsNone(cr.BinaryFormat(53).e_min)
        self.assertEqual((cr.DecimalFormat(16, 384).e_min, cr.DecimalFormat(16, 384).clamp, cr.DecimalFormat(16, 384).tininess), (-383, 1, "b"))
        self.assertEqual(cr.GdaContextSpec(9, -99, 99).rounding, "half_even")
        for bad in (
            lambda: cr.BinaryFormat(53, 0),
            lambda: cr.BinaryFormat(0),
            lambda: cr.DecimalFormat(34, 0),
            lambda: cr.DecimalFormat(34, 6144, "half_down"),
            lambda: cr.GdaContextSpec(34, -50, 60),
        ):
            with self.assertRaises(ValueError):
                bad()

    def test_the_old_names_still_work_and_are_the_same_rule(self) -> None:
        self.assertIs(corpus_common.check_ieee_decimal_context, cr.check_ieee_decimal_context)
        self.assertEqual(corpus_common.IEEE_DECIMAL_ROUNDINGS, cr.DECIMAL_ROUNDINGS)
        import generate_libmpdec_random as gen

        self.assertTrue(gen.legal_exponent_range(-98, 99))
        self.assertFalse(gen.legal_exponent_range(-50, 60))


if __name__ == "__main__":
    unittest.main()
