import unittest
from fractions import Fraction

import range_boundary_rows as tool


class DyadicTests(unittest.TestCase):
    def test_hex_operand_syntax(self) -> None:
        self.assertEqual(tool.hexfmt(Fraction(3, 2)), "0x3p-1")
        self.assertEqual(tool.hexfmt(Fraction(-8)), "-0x1p3")
        self.assertEqual(tool.hexfmt(Fraction(0)), "0x0p0")
        with self.assertRaises(ValueError):
            tool.hexfmt(Fraction(1, 3))

    def test_to_dyadic_keeps_the_significant_bits(self) -> None:
        value = tool.to_dyadic(Fraction(1, 3), 10)
        self.assertEqual(value, Fraction(683, 2048))
        self.assertEqual(tool.to_dyadic(Fraction(-1, 3), 10), -value)

    def test_around_is_centred_and_dyadic(self) -> None:
        values = list(tool.around(Fraction(-1073741823, 1)))
        self.assertEqual(len(values), 1 + 2 * len(tool.RELATIVE_OFFSETS))
        self.assertEqual(values[0], -1073741823)
        for value in values:
            tool.hexfmt(value)
        self.assertEqual(values[1] - values[0], values[0] / 2**20)


class RowTests(unittest.TestCase):
    def test_rows_are_oracle_inputs_with_unique_ids(self) -> None:
        lines = list(tool.rows(2, 3, tool.OPERATIONS))
        self.assertGreater(len(lines), 8000)
        ids = [line.split()[0] for line in lines]
        self.assertEqual(len(set(ids)), len(ids))
        for line in lines:
            fields = line.split()
            self.assertEqual(len(fields), 13, line)
            self.assertEqual(fields[-2:], ["?", "?"])
            self.assertIn(fields[2], tool.MODES)
        self.assertTrue(any(" - - - " in line for line in lines))
        self.assertTrue(any(" -1022 1023 " in line for line in lines))

    def test_thresholds_of_exp2_are_the_integers_around_q(self) -> None:
        lines = [line for line in tool.rows(2, 2, ("exp2",)) if " - - - " in line]
        # p = 2 unbounded: q = e_min - 1 = -1073741824, so q - 1 and q are rows.
        operands = {line.split()[7] for line in lines}
        self.assertIn(tool.hexfmt(Fraction(-1073741825)), operands)
        self.assertIn(tool.hexfmt(Fraction(-1073741824)), operands)

    def test_pown_exponents_stay_in_int32(self) -> None:
        for line in tool.rows(2, 2, ("pown",)):
            n = int(line.split()[10])
            self.assertTrue(n != 0 and abs(n) < 2**31)


if __name__ == "__main__":
    unittest.main()
