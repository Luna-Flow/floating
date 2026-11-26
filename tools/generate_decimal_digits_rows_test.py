"""Tests of the pure functions of `generate_decimal_digits_rows.py`."""

import unittest

import generate_decimal_digits_rows as generator

ONE_LINE = '  (1UL, -1073741822, 7, "9.530260e-323228497"),'
WRAPPED = '  (\n    1UL,\n    -1073741822,\n    7,\n    "9.530260e-323228497",\n  ),'


class RenderBlockTest(unittest.TestCase):
    def test_the_table_type_uses_int32(self) -> None:
        block = generator.render_block([(1, -5, 1, "1e-1")], "3.13", "4.0")
        self.assertIn("Array[(UInt64, Int32, Int32, String)]", block)
        self.assertNotIn("(UInt64, Int, Int, String)", block)

    def test_a_row_is_one_line_with_the_ul_suffix(self) -> None:
        block = generator.render_block([(1, -5, 7, "9.530260e-9")], "3.13", "4.0")
        self.assertIn('  (1UL, -5, 7, "9.530260e-9"),', block.splitlines())

    def test_the_block_is_delimited_and_counts_its_rows(self) -> None:
        block = generator.render_block([(1, 0, 1, "1e+0"), (2, 0, 1, "2e+0")], "3.13", "4.0")
        self.assertTrue(block.startswith(generator.BEGIN))
        self.assertTrue(block.endswith(generator.END))
        self.assertIn(": 2 rows,", block)


class NormalizedRowsTest(unittest.TestCase):
    def block(self, row: str, version: str = "3.13") -> str:
        return "\n".join([generator.BEGIN, f"// Python {version}, libmpdec 4.0.0", "let t : Array[X] = [", row, "]", generator.END])

    def test_a_wrapped_row_equals_the_one_line_row(self) -> None:
        self.assertEqual(generator.normalized_rows(self.block(ONE_LINE)), generator.normalized_rows(self.block(WRAPPED)))

    def test_the_version_comments_are_ignored(self) -> None:
        self.assertEqual(generator.normalized_rows(self.block(ONE_LINE, "3.12")), generator.normalized_rows(self.block(ONE_LINE, "3.14")))

    def test_a_different_value_is_a_difference(self) -> None:
        other = ONE_LINE.replace("9.530260", "9.530261")
        self.assertNotEqual(generator.normalized_rows(self.block(ONE_LINE)), generator.normalized_rows(self.block(other)))

    def test_a_different_exponent_is_a_difference(self) -> None:
        other = ONE_LINE.replace("-1073741822", "-1073741821")
        self.assertNotEqual(generator.normalized_rows(self.block(ONE_LINE)), generator.normalized_rows(self.block(other)))

    def test_a_missing_row_is_a_difference(self) -> None:
        both = self.block(ONE_LINE + "\n" + ONE_LINE)
        self.assertNotEqual(generator.normalized_rows(both), generator.normalized_rows(self.block(ONE_LINE)))

    def test_the_type_name_is_part_of_the_comparison(self) -> None:
        old = self.block(ONE_LINE).replace("Array[X]", "Array[(UInt64, Int, Int, String)]")
        new = self.block(ONE_LINE).replace("Array[X]", "Array[(UInt64, Int32, Int32, String)]")
        self.assertNotEqual(generator.normalized_rows(old), generator.normalized_rows(new))


class DecimalTextTest(unittest.TestCase):
    def test_rounding_to_digits(self) -> None:
        self.assertEqual(generator.decimal_text(1, 0, 1), "1e+0")
        self.assertEqual(generator.decimal_text(3, -1, 3), "1.50e+0")
        self.assertEqual(generator.decimal_text(7, -3, 1), "9e-1")  # 0.875 to one digit


if __name__ == "__main__":
    unittest.main()
