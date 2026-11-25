"""Tests of `generate_decimal_plain_ctx_rows.py`."""

from __future__ import annotations

import decimal
import unittest

import generate_decimal_plain_ctx_rows as generator

SPEC = generator.Spec(3, -30, 40, "half_even", False)


class ContextTableTest(unittest.TestCase):
    def test_size_and_ends(self) -> None:
        specs = generator.context_table()
        self.assertEqual(len(specs), 3 + 7 * 8 * 4)
        self.assertEqual(specs[0], generator.Spec(7, -95, 96, "half_even", True))
        self.assertEqual(specs[3], generator.Spec(1, generator.E_TINY, generator.E_MAX, "half_even", False))

    def test_all_roundings_present(self) -> None:
        names = {spec.rounding for spec in generator.context_table()}
        self.assertEqual(names, set(generator.ROUNDINGS))


class EvaluateTest(unittest.TestCase):
    def test_inexact_sum(self) -> None:
        self.assertEqual(generator.evaluate(SPEC, "add", decimal.Decimal("1"), decimal.Decimal("1E-5")), "1.00 x..")

    def test_exact_product(self) -> None:
        self.assertEqual(generator.evaluate(SPEC, "mul", decimal.Decimal("25"), decimal.Decimal("-4")), "-100 ...")

    def test_overflow_is_an_infinity_with_the_flag(self) -> None:
        text = generator.evaluate(SPEC, "mul", decimal.Decimal("9E39"), decimal.Decimal("9E39"))
        self.assertEqual(text, "inf x.o")

    def test_underflow(self) -> None:
        text = generator.evaluate(SPEC, "mul", decimal.Decimal("1E-20"), decimal.Decimal("1E-20"))
        self.assertEqual(text, "0E-32 xu.")

    def test_exact_tie_to_even(self) -> None:
        # 1230 + 15 = 1245 at three digits rounds half-even to 1.24E+3
        self.assertEqual(generator.evaluate(SPEC, "add", decimal.Decimal("123E1"), decimal.Decimal("15")), "1.24E+3 x..")


class RowsTest(unittest.TestCase):
    def test_storage_filter(self) -> None:
        self.assertTrue(generator.in_storage("1E2147483646"))
        self.assertFalse(generator.in_storage("1E2147483647"))
        self.assertFalse(generator.in_storage("1E-2147483646"))

    def test_zero_operands_are_skipped(self) -> None:
        self.assertIsNone(generator.row(0, SPEC, "0", "1"))

    def test_counts(self) -> None:
        self.assertEqual(len(generator.random_rows(20, 40, 1)), 20)
        carry, top = generator.carry_rows()
        self.assertGreater(len(carry), 1000)
        self.assertGreater(len(top), 0)
        for index, lhs, rhs, *_ in top:
            self.assertEqual(generator.all_specs()[index].e_max, generator.E_MAX)

    def test_random_rows_are_seeded(self) -> None:
        self.assertEqual(generator.random_rows(10, 40, 7), generator.random_rows(10, 40, 7))


if __name__ == "__main__":
    unittest.main()
