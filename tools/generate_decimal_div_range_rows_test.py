"""Tests of `generate_decimal_div_range_rows.py`."""

from __future__ import annotations

import decimal
import unittest

import generate_decimal_div_range_rows as generator


class GeneratorTest(unittest.TestCase):
    def test_row_count(self) -> None:
        expected = len(generator.ISSUE_ROWS) + 4 * generator.ROWS_PER_OPERATOR
        self.assertEqual(len(generator.rows()), expected)

    def test_operands_stay_in_the_stored_range(self) -> None:
        for row in generator.rows():
            for text in (row.left, row.right):
                value = decimal.Decimal(text)
                exponent = value.as_tuple().exponent
                adjusted = value.adjusted()
                self.assertGreaterEqual(exponent, generator.TINY)
                self.assertLessEqual(adjusted, generator.EMAX)

    def test_issue_row_expected_values(self) -> None:
        context = generator.plain_context()
        first = generator.rows()[0]
        self.assertEqual(
            generator.expected(first, context), "4.9382715604938E-2147483632"
        )
        last = generator.rows()[7]
        self.assertEqual(generator.expected(last, context), "0E-2147483645")

    def test_special_values_are_spelled_as_the_library_does(self) -> None:
        self.assertEqual(generator.library_text(decimal.Decimal("Infinity")), "inf")
        self.assertEqual(generator.library_text(decimal.Decimal("-Infinity")), "-inf")


if __name__ == "__main__":
    unittest.main()
