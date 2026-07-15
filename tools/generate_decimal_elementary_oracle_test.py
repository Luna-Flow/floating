import decimal
import unittest

import generate_decimal_elementary_oracle as oracle


class DecimalElementaryOracleTests(unittest.TestCase):
    def test_dyadic_conversion_is_exact(self) -> None:
        self.assertEqual(oracle.parse_dyadic("0x3p-2"), decimal.Decimal("0.75"))
        self.assertEqual(oracle.parse_dyadic("-0x5p1"), decimal.Decimal("-10"))

    def test_committed_intervals_regenerate_every_row(self) -> None:
        intervals = oracle.parse_intervals(
            oracle.ROOT
            / "testdata/decimal/ieee/mpfr-4.2.2-elementary-interval.txt"
        )
        rows = oracle.generate_rows(intervals)
        self.assertEqual(len(intervals), 116)
        self.assertEqual(len(rows), 2784)

    def test_non_unique_interval_is_rejected(self) -> None:
        interval = {
            "operation": "exp",
            "left": decimal.Decimal("1"),
            "right": None,
            "integer": 0,
            "lower": decimal.Decimal("1.0"),
            "upper": decimal.Decimal("2.0"),
            "exact": False,
            "line": 1,
        }
        with self.assertRaisesRegex(ValueError, "does not uniquely round"):
            oracle.generate_rows([interval])


if __name__ == "__main__":
    unittest.main()
