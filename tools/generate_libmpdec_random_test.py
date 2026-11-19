import decimal
import unittest
from decimal import Decimal

import generate_libmpdec_random as generator


class RngTests(unittest.TestCase):
    def test_splitmix64_matches_the_reference_stream(self) -> None:
        # First outputs of SplitMix64 seeded with 0 (Vigna's reference code).
        state = 0
        outputs = []
        for _ in range(3):
            state, value = generator.splitmix(state)
            outputs.append(value)
        self.assertEqual(
            outputs,
            [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F],
        )

    def test_streams_depend_on_seed_family_and_index(self) -> None:
        first = generator.Rng(1, "add", 0).next()
        self.assertEqual(first, generator.Rng(1, "add", 0).next())
        self.assertNotEqual(first, generator.Rng(2, "add", 0).next())
        self.assertNotEqual(first, generator.Rng(1, "multiply", 0).next())
        self.assertNotEqual(first, generator.Rng(1, "add", 1).next())

    def test_ranges_are_inclusive_and_log_uniform_is_bounded(self) -> None:
        rng = generator.Rng(3, "add", 0)
        values = {rng.range(2, 5) for _ in range(200)}
        self.assertEqual(values, {2, 3, 4, 5})
        for _ in range(200):
            self.assertTrue(1 <= rng.log(1, 5000) <= 5000)


class CaseTests(unittest.TestCase):
    def test_a_case_is_a_pure_function_of_seed_family_and_index(self) -> None:
        for family in generator.FAMILIES:
            first = generator.generate_case(family, 9, 17)
            again = generator.generate_case(family, 9, 17)
            self.assertEqual(first, again, family)
            self.assertEqual(first.case_id, f"d9.{family}.17")

    def test_a_single_row_equals_the_row_of_a_longer_run(self) -> None:
        full = list(generator.generate("add", 4, 0, 6))
        single = list(generator.generate("add", 4, 5, 1))
        self.assertEqual(full[-6:], single[-6:])

    def test_rows_carry_a_context_block_and_the_oracle_result(self) -> None:
        for family in generator.FAMILIES:
            lines = list(generator.generate(family, 2, 0, 4))
            directives = [line for line in lines if line.startswith("precision:")]
            self.assertEqual(len(directives), 4, family)
            rows = [line for line in lines if line.startswith("d2.")]
            self.assertEqual(len(rows), 4, family)
            for row in rows:
                self.assertIn(" -> ", row)

    def test_wide_families_write_the_plain_operation_name(self) -> None:
        row = next(
            line for line in generator.generate("expwide", 1, 0, 3) if line.startswith("d1.")
        )
        self.assertEqual(row.split()[1], "exp")

    def test_every_generated_context_is_a_legal_gda_context(self) -> None:
        for family in generator.FAMILIES:
            for index in range(60):
                context = generator.generate_case(family, 5, index).context
                self.assertGreaterEqual(context.precision, 1)
                self.assertLessEqual(context.precision, 999_999_999)
                self.assertLessEqual(context.emin, 0)
                self.assertGreaterEqual(context.emax, 0)
                self.assertIn(context.clamp, (0, 1))

    def test_plain_elementary_families_stay_inside_the_certified_range(self) -> None:
        for family in ("exp", "ln", "log10", "power"):
            for index in range(200):
                context = generator.generate_case(family, 5, index).context
                self.assertLess(context.emax, 1_000_000)
                self.assertGreater(context.emin, -1_000_000)
                if family == "power" and self.in_power_of_ten_class(generator.generate_case(family, 5, index)):
                    # The only rows in a mode other than nearest-even: the class
                    # of issue 351, whose expected result is this library's own
                    # (checked against libmpdec within one unit in the last place).
                    continue
                self.assertEqual(context.rounding, "half_even")

    @staticmethod
    def in_power_of_ten_class(case: generator.Case) -> bool:
        try:
            base, exponent = (Decimal(text) for text in case.operands)
        except decimal.InvalidOperation:
            return False
        return generator.power_of_ten_exponent(base, exponent) is not None

    def test_the_power_of_ten_class_is_drawn_in_every_rounding_mode(self) -> None:
        modes = set()
        for index in range(3000):
            case = generator.generate_case("power", 5, index)
            if self.in_power_of_ten_class(case):
                modes.add(case.context.rounding)
        self.assertEqual(modes, {name for name, _ in generator.ROUNDINGS})


class OperandTests(unittest.TestCase):
    def test_operands_beyond_emax_are_moved_to_emax(self) -> None:
        self.assertEqual(generator.fit_operand("9.75E+10003", 10002), "9.75E+10002")
        self.assertEqual(generator.fit_operand("-1E+10004", 10002), "-1E+10002")

    def test_operands_in_range_and_specials_are_unchanged(self) -> None:
        for text in ("9.75E+10002", "0E+99999", "-0", "NaN", "Infinity", "12"):
            self.assertEqual(generator.fit_operand(text, 10002), text)

    def test_generated_arithmetic_operands_never_exceed_emax(self) -> None:
        for family in ("add", "fma", "power", "divide"):
            for index in range(300):
                case = generator.generate_case(family, 11, index)
                for text in case.operands:
                    value = Decimal(text)
                    if value.is_finite() and value != 0:
                        self.assertLessEqual(value.adjusted(), case.context.emax, (family, index, text))


class OracleTests(unittest.TestCase):
    def context(self, precision: int, rounding: str = "half_even", emin: int = -99, emax: int = 99, clamp: int = 0) -> generator.Ctx:
        return generator.Ctx(precision, rounding, emin, emax, clamp)

    def row(self, op: str, operands: tuple[str, ...], context: generator.Ctx) -> generator.Row:
        return generator.evaluate(generator.Case("t", op, context, operands))

    def test_exact_and_inexact_results(self) -> None:
        context = self.context(3)
        self.assertEqual(self.row("add", ("1.20", "3.40"), context).result, "4.60")
        inexact = self.row("multiply", ("9.99", "9.99"), context)
        self.assertEqual(inexact.result, "99.8")
        self.assertEqual(inexact.conditions, ("Inexact", "Rounded"))

    def test_zero_divided_by_zero_is_division_undefined(self) -> None:
        row = self.row("divide", ("0", "0"), self.context(5))
        self.assertEqual(row.result, "NaN")
        self.assertEqual(row.conditions, ("Invalid_operation", "Division_undefined"))
        self.assertEqual(self.row("divide", ("1", "0"), self.context(5)).conditions, ("Division_by_zero",))

    def test_overflow_after_rounding_is_the_gda_rule(self) -> None:
        # GDA 1.70 "Overflow": the adjusted exponent after rounding exceeds Emax.
        context = self.context(2, "half_down", emin=0, emax=0, clamp=1)
        row = self.row("add", ("-9.999", "0.05650600"), context)
        self.assertEqual(row.result, "-9.9")
        self.assertEqual(row.conditions, ("Inexact", "Rounded"))

    def test_string_operations_apply_the_context(self) -> None:
        context = self.context(4)
        self.assertEqual(self.row("tosci", ("12345.6",), context).result, "1.235E+4")
        self.assertEqual(self.row("toeng", ("12345.6",), context).result, "12.35E+3")
        self.assertEqual(self.row("apply", ("0.0001234567",), context).conditions, ("Inexact", "Rounded"))

    def test_tie_construction_makes_an_exact_halfway_case(self) -> None:
        ties = 0
        wide = decimal.Context(prec=30000, Emin=decimal.MIN_EMIN, Emax=decimal.MAX_EMAX, traps=[])
        for index in range(400):
            case = generator.generate_case("add", 3, index)
            exact = wide.add(Decimal(case.operands[0]), Decimal(case.operands[1]))
            if not exact.is_finite() or exact == 0:
                continue
            digits = list(exact.as_tuple().digits)
            while len(digits) > 1 and digits[-1] == 0:
                digits.pop()
            if len(digits) - 1 == case.context.precision and digits[-1] == 5:
                ties += 1
        self.assertGreater(ties, 10)

    def test_row_format_matches_dectest(self) -> None:
        case = generator.Case("d1.add.0", "add", self.context(3), ("1.20", "3.40"))
        lines = generator.format_row(generator.evaluate(case))
        self.assertEqual(
            lines,
            [
                "precision: 3",
                "rounding: half_even",
                "maxexponent: 99",
                "minexponent: -99",
                "clamp: 0",
                "d1.add.0 add 1.20 3.40 -> 4.60",
            ],
        )


class PowerOfTenDifferenceTests(unittest.TestCase):
    """Issue 351: `power(10^k, y)` with a non-integral `y` and an integral `k*y`
    is the exact value in every rounding mode; libmpdec differs by 1 ulp in some
    modes. The class is checked, and the row expects this library's result."""

    @staticmethod
    def case(rounding: str, base: str, exponent: str, precision: int = 16, emin: int = -383, emax: int = 384) -> object:
        context = generator.Ctx(precision, rounding, emin, emax, 1)
        return generator.Case("d1.power.0", "power", context, (base, exponent))

    def test_the_class_is_recognised_in_every_cohort(self) -> None:
        find = generator.power_of_ten_exponent
        self.assertEqual(find(Decimal("1E-5"), Decimal("1.2")), -6)
        self.assertEqual(find(Decimal("100"), Decimal("1.5")), 3)
        self.assertEqual(find(Decimal("1.0E+2"), Decimal("-1.5")), -3)
        self.assertEqual(find(Decimal("1E+5"), Decimal("-1.2")), -6)
        # k*y not an integer, y integral, k = 0, not a power of ten, negative.
        self.assertIsNone(find(Decimal("1E-5"), Decimal("1.5")))
        self.assertIsNone(find(Decimal("1E-5"), Decimal("2")))
        self.assertIsNone(find(Decimal("1"), Decimal("1.5")))
        self.assertIsNone(find(Decimal("2E+5"), Decimal("1.2")))
        self.assertIsNone(find(Decimal("-1E+5"), Decimal("1.2")))
        self.assertIsNone(find(Decimal("Infinity"), Decimal("1.5")))

    def test_the_result_is_the_exact_value_padded_in_every_mode(self) -> None:
        for rounding, _ in generator.ROUNDINGS:
            case = self.case(rounding, "1E-5", "1.2")
            value, conditions = generator.power_of_ten_result(case.context, -6)
            self.assertEqual(str(value), "0.000001000000000000000", rounding)
            self.assertEqual(conditions, ("Inexact", "Rounded"), rounding)

    def test_the_directed_modes_differ_from_libmpdec_and_are_registered(self) -> None:
        for rounding in ("ceiling", "up"):
            case = self.case(rounding, "1E-5", "1.2")
            row = generator.evaluate(case)
            self.assertEqual(row.result, "0.000001000000000000000")
            self.assertEqual(row.libmpdec, "0.000001000000000000001 Inexact Rounded")
            self.assertTrue(any(generator.POWER_OF_TEN_MARKER in line for line in generator.format_row(row)))
        for rounding in ("half_even", "floor", "down"):
            row = generator.evaluate(self.case(rounding, "1E-5", "1.2"))
            self.assertEqual(row.libmpdec, "", rounding)

    def test_a_result_beyond_one_ulp_is_refused(self) -> None:
        case = self.case("half_even", "1E-5", "1.2")
        with self.assertRaises(ValueError):
            generator.power_of_ten_difference(case, Decimal("0.000001000000000000003"))

    def test_overflow_and_underflow_follow_the_rounding_of_the_exact_value(self) -> None:
        context = generator.Ctx(16, "ceiling", -383, 384, 0)
        value, conditions = generator.power_of_ten_result(context, 385)
        self.assertTrue(value.is_infinite())
        self.assertEqual(conditions, ("Inexact", "Overflow", "Rounded"))
        context = generator.Ctx(16, "half_even", -383, 384, 0)
        value, conditions = generator.power_of_ten_result(context, -385)
        self.assertEqual(str(value), "1.0000000000000E-385")
        self.assertEqual(conditions, ("Inexact", "Rounded", "Subnormal", "Underflow"))
        value, conditions = generator.power_of_ten_result(context, -399)
        self.assertEqual(str(value), "0E-398")

    def test_wide_contexts_are_not_in_the_class(self) -> None:
        case = self.case("ceiling", "1E-5", "1.2", emin=-999999999, emax=999999999)
        self.assertIsNone(generator.power_of_ten_difference(case, Decimal("0.000001000000000000001")))


if __name__ == "__main__":
    unittest.main()
