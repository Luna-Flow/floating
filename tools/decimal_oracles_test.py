import unittest
from decimal import Decimal

import decimal_oracles
import run_ieee_decimal


class DecimalOracleTests(unittest.TestCase):
    def test_manifest_routes_cover_requested_families(self) -> None:
        self.assertEqual(decimal_oracles.validate_manifest(), 10)

    def test_probe_reports_libmpdec_and_exact_rational(self) -> None:
        capabilities = decimal_oracles.probe()
        self.assertTrue(capabilities["libmpdec-allcr1"]["available"])
        self.assertTrue(capabilities["exact-gmp-rational"]["available"])

    def test_special_case_flags_are_not_taken_from_value_oracle(self) -> None:
        self.assertEqual(
            decimal_oracles.special_case_flags("divide", [Decimal("1"), Decimal("0")]),
            frozenset({"DivisionByZero"}),
        )
        self.assertEqual(
            decimal_oracles.special_case_flags("sqrt", [Decimal("-1")]),
            frozenset({"InvalidOperation"}),
        )

    def test_libmpdec_exp_uses_nearest_even_context(self) -> None:
        result = decimal_oracles.libmpdec_unary(
            "exp", "0", "decimal64", run_ieee_decimal.decimal_context
        )
        self.assertEqual(result.value, "1")
        self.assertEqual(result.flags, frozenset())
        self.assertIn("libmpdec", result.source)

    def test_static_examples_validate_value_and_flags_separately(self) -> None:
        self.assertEqual(
            decimal_oracles.validate_static_examples(run_ieee_decimal.decimal_context),
            19,
        )


if __name__ == "__main__":
    unittest.main()
