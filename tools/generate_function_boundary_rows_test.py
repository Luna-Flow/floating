from __future__ import annotations

import unittest
from fractions import Fraction

import generate_function_boundary_rows as gen


class FunctionBoundaryRowsTest(unittest.TestCase):
    def test_sample_group_keeps_order_and_count(self) -> None:
        items = [str(i) for i in range(20)]
        self.assertEqual(gen.sample_group(items, 5), ["0", "4", "8", "12", "16"])
        self.assertEqual(gen.sample_group(items[:3], 5), ["0", "1", "2"])

    def test_around_is_exact_and_ordered(self) -> None:
        values = gen.around(1.0)
        self.assertEqual(len(values), 7)
        self.assertEqual(values[0], Fraction(1))
        self.assertEqual(values[1], 1 + Fraction(1, 1024))
        self.assertEqual(values[2], 1 - Fraction(1, 1024))

    def test_threshold_args_drop_integers_when_asked(self) -> None:
        with_integers = gen.threshold_args(1.0, 2, -6, 7, True)
        without = gen.threshold_args(1.0, 2, -6, 7, False)
        self.assertTrue(any(x.denominator == 1 for x in with_integers))
        self.assertTrue(all(x.denominator != 1 for x in without))

    def test_builder_cycles_every_mode_and_tininess(self) -> None:
        builder = gen.Builder("g")
        for _ in range(10):
            builder.add("exp", 2, "0x1p0")
        combos = {(row.split()[2], row.split()[6]) for row in builder.rows}
        self.assertEqual(len(combos), 10)

    def test_operand_range_filter(self) -> None:
        self.assertTrue(gen.operand_in_range("0x1p-1073741822"))
        self.assertFalse(gen.operand_in_range("0x1p-1073741900"))
        self.assertTrue(gen.operand_in_range("-"))

    def test_parse_evaluated_maps_modes_and_unbounded_rows(self) -> None:
        row = gen.parse_evaluated("rsqrt.1 rsqrt u 2 - - - 0x3p0 - - 0 0x1p-1 x")
        self.assertEqual(row, ("rsqrt", "rsqrt", 2, "0", "0", "RTP", "-", "0x3p0", "", 0, "0x1p-1", "x"))

    def test_groups_are_not_empty(self) -> None:
        for group in gen.GROUPS:
            self.assertTrue(group())


if __name__ == "__main__":
    unittest.main()
