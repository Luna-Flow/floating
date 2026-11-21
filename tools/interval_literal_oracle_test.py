import unittest
from fractions import Fraction

import interval_literal_oracle as oracle


def value(result, which):
    return oracle.flt_to_fraction(result[which])


class EvaluateTest(unittest.TestCase):
    def test_the_uncertain_forms_of_table_9_4(self) -> None:
        for text, lo, hi in (
            ("3.56?1", Fraction("3.55"), Fraction("3.57")),
            ("3.56?1e2", Fraction(355), Fraction(357)),
            ("3.560?2", Fraction("3.558"), Fraction("3.562")),
            ("3.56?", Fraction("3.555"), Fraction("3.565")),
            ("3.560?2u", Fraction("3.560"), Fraction("3.562")),
            ("-10?", Fraction("-10.5"), Fraction("-9.5")),
            ("-10?u", Fraction(-10), Fraction("-9.5")),
            ("-10?12", Fraction(-22), Fraction(2)),
        ):
            result = oracle.evaluate(text, 113, False)
            self.assertEqual(result[0], "ok", text)
            # a binary bound is the rounded decimal bound: it brackets the exact value closely
            self.assertLessEqual(value(result, 1), lo, text)
            self.assertGreaterEqual(value(result, 2), hi, text)
            self.assertLess(lo - value(result, 1), Fraction(1, 2**100), text)
            self.assertLess(value(result, 2) - hi, Fraction(1, 2**100), text)

    def test_special_and_decorated_forms(self) -> None:
        self.assertEqual(oracle.evaluate("[]", 53, False), ("empty", None))
        self.assertEqual(oracle.evaluate("[ Empty ]", 53, True), ("empty", "trv"))
        self.assertEqual(oracle.evaluate("[nai]", 53, True), ("nai",))
        self.assertEqual(oracle.evaluate("[1,2]_COM", 53, True)[3], "com")
        self.assertEqual(oracle.evaluate("[1,]", 53, True)[3], "dac")
        self.assertEqual(oracle.evaluate("[,]_com", 53, True), ("err", "com-unbounded"))
        self.assertEqual(oracle.evaluate("[]_com", 53, True), ("err", "empty-decoration"))

    def test_rejected_strings_have_a_named_category(self) -> None:
        for text, category in (
            ("[2,1]", "order"),
            ("[1 000 000]", "number"),
            ("[1/0]", "rational-denominator"),
            ("[1.5/2]", "rational-numerator"),
            ("[inf]", "lower-inf"),
            ("[-inf]", "upper-inf"),
            ("[]_ill", "decoration-literal"),
            ("[nai]_com", "nai-decoration"),
            ("[1,2] ", "trailing"),
            ("?1", "uncertain-base"),
            ("[1,2]_com", "bare-decorated"),
        ):
            decorated = text != "[1,2]_com"
            self.assertEqual(oracle.evaluate(text, 53, decorated), ("err", category), text)

    def test_huge_exponents_are_classified_without_forming_the_value(self) -> None:
        result = oracle.evaluate("[1e400000000, 1e400000001]", 53, False)
        self.assertEqual(result[1], oracle.flt(2**53 - 1, oracle.EMAX - 53 + 1))
        self.assertEqual(result[2], float("inf"))
        tiny = oracle.evaluate("[1e-400000000]", 53, False)
        self.assertEqual(tiny[1], (0, 0))
        self.assertEqual(tiny[2], oracle.flt(1, oracle.EMIN - 53 + 1))


class SecondWayTest(unittest.TestCase):
    def test_every_rational_literal_is_bracketed_by_cross_multiplication(self) -> None:
        self.assertEqual(oracle.check_rational_cross_multiplication(1500), 1500)


class TableTest(unittest.TestCase):
    def test_the_committed_table_is_the_oracles_output(self) -> None:
        if not oracle.TABLE.exists():
            self.skipTest("the table is not written")
        self.assertEqual(oracle.TABLE.read_text(encoding="utf-8"), oracle.build())


if __name__ == "__main__":
    unittest.main()


class SameRadixOrderTest(unittest.TestCase):
    def test_hex_pairs_are_ordered_at_any_exponent(self) -> None:
        self.assertEqual(oracle.evaluate("[0x1p-1073741829, 0x1p-1073741830]", 8, False), ("err", "order"))
        self.assertEqual(oracle.evaluate("[0x1p-1073741885, 0x1p-1073741886]", 64, False), ("err", "order"))
        self.assertEqual(oracle.evaluate("[0x1p-1073741886, 0x1p-1073741885]", 64, False)[0], "ok")

    def test_long_exponent_fields_of_uncertain_forms(self) -> None:
        result = oracle.evaluate("1?1e1234567890123456789012345678901234567890", 53, False)
        self.assertEqual(result[0], "ok")
        self.assertEqual(oracle.flt_to_fraction(result[1]), 0)
        self.assertEqual(result[2], float("inf"))
