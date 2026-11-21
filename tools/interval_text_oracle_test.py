import unittest

import interval_text_oracle as oracle


class IntervalTextOracleTest(unittest.TestCase):
    def test_table_is_current(self) -> None:
        self.assertEqual(oracle.TABLE.read_text(encoding="utf-8"), oracle.build())

    def test_known_texts(self) -> None:
        from fractions import Fraction

        self.assertEqual(oracle.interval_texts(Fraction(1), Fraction(1), 53), ("[1, 1]", "[0x1p0, 0x1p0]"))
        self.assertEqual(oracle.interval_texts("-inf", "inf", 53), ("[entire]", "[entire]"))
        self.assertEqual(
            oracle.interval_texts(Fraction(1, 2), Fraction(3), 53),
            ("[5e-1, 3]", "[0x1p-1, 0x3p0]"),
        )
        self.assertEqual(oracle.interval_texts(Fraction(0), Fraction(-0), 53)[0], "[0, 0]")


if __name__ == "__main__":
    unittest.main()
