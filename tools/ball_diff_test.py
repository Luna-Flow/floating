import random
import unittest

import ball_diff as bd


class ValueTests(unittest.TestCase):
    """Oracle: level A (orders and texts written out)."""

    def test_text(self) -> None:
        self.assertEqual(bd.value(0x1F, -3).text(), "0x1fp-3")
        self.assertEqual(bd.value(0x1F, -3, negative=True).text(), "-0x1fp-3")
        self.assertEqual(bd.ZERO.text(), "0x0p0")
        self.assertEqual(bd.value(0, 5, negative=True).text(), "0x0p0")  # no negative zero in the rows

    def test_compare_is_exact_with_huge_exponents(self) -> None:
        big = bd.value(3, bd.EMAX - 10)
        bigger = bd.value(3, bd.EMAX - 9)
        tiny = bd.value(1, bd.EMIN - 50)
        self.assertEqual(bd.compare(big, bigger), -1)
        self.assertEqual(bd.compare(bigger, big), 1)
        self.assertEqual(bd.compare(big, big), 0)
        self.assertEqual(bd.compare(tiny, big), -1)
        self.assertEqual(bd.compare(big.neg(), tiny), -1)
        self.assertEqual(bd.compare(bd.ZERO, tiny), -1)
        self.assertEqual(bd.compare(tiny.neg(), bd.ZERO), -1)
        self.assertEqual(bd.compare(bd.ZERO, bd.ZERO), 0)
        # the same leading bit: the mantissas decide (0x3p0 = 3, 0x7p-1 = 3.5)
        self.assertEqual(bd.compare(bd.value(3, 0), bd.value(7, -1)), -1)
        self.assertEqual(bd.compare(bd.value(3, 0, negative=True), bd.value(7, -1, negative=True)), 1)

    def test_one_ulp_up(self) -> None:
        self.assertEqual(bd.one_ulp_up(bd.value(0b1011, 0), 4), bd.value(0b1100, 0))
        self.assertEqual(bd.one_ulp_up(bd.value(0b1111, 0), 4), bd.value(0b1000, 1))  # a carry into a new binade
        self.assertEqual(bd.one_ulp_up(bd.value(0b11, 0), 4), bd.value(0b100, 0))  # fewer bits than p: one unit of its last bit

    def test_max_finite_and_quantum(self) -> None:
        self.assertEqual(bd.max_finite(4), bd.value(15, bd.EMAX + 1 - 4))
        self.assertEqual(bd.quantum(53), bd.EMIN - 52)

    def test_round_shift_ties_to_even(self) -> None:
        self.assertEqual([bd.round_shift(x, 2) for x in (4, 5, 6, 7, 10, 14)], [1, 1, 2, 2, 2, 4])


class PartnerTests(unittest.TestCase):
    """Oracle: level B (exact integer arithmetic against the construction; the construction is only a source of operands)."""

    def test_product_partner_lands_within_one_unit_of_the_target(self) -> None:
        rng = random.Random(1)
        for p in (8, 53, 128):
            for n, e in ((1 << p, bd.EMAX + 1 - p), (3, bd.EMIN - p + 1), ((1 << (p - 1)) + 1, bd.EMIN - p + 1)):
                a = bd.with_lead(rng, p, bd.EMAX // 2 if e > 0 else bd.EMIN // 2)
                b = bd.product_partner(a, n, e, p)
                # a*b = ma*mb * 2^(ea+eb) against n * 2^e: relative error below 2^-(p-1)
                shift = a.exponent + b.exponent - e
                left, right = a.mantissa * b.mantissa, n
                if shift >= 0:
                    left <<= shift
                else:
                    right <<= -shift
                self.assertLess(abs(left - right) * (1 << (p - 1)), right, (p, n))

    def test_square_root_of_brackets_the_target(self) -> None:
        for p in (8, 53, 128):
            for n, e in ((1 << p, bd.EMAX + 1 - p), (5, bd.EMIN - p + 1), (1 << (p - 1), bd.EMIN - p + 1)):
                a = bd.square_root_of(n, e, p)
                shift = 2 * a.exponent - e
                left, right = a.mantissa**2, n
                if shift >= 0:
                    left <<= shift
                else:
                    right <<= -shift
                self.assertLess(abs(left - right) * (1 << (p - 2)), right, (p, n))
                self.assertLessEqual(a.mantissa.bit_length(), p + 1)


class IntegerOracleTests(unittest.TestCase):
    """Oracle: level A (every expected value is worked out by hand in the comment)."""

    def test_directed_rounding_to_p_bits(self) -> None:
        # 0b10111 = 23 at 4 bits: 22 (0b1011 * 2) below, 24 (0b1100 * 2) above
        down = bd.round_directed(0b10111, 0, False, False, False, 4)
        up = bd.round_directed(0b10111, 0, False, False, True, 4)
        self.assertEqual((down, up), (bd.value(0b1011, 1), bd.value(0b1100, 1)))
        # a negative value rounds the other way: -23 down is -24, up is -22
        self.assertEqual(bd.round_directed(0b10111, 0, False, True, False, 4), bd.value(0b1100, 1, negative=True))
        self.assertEqual(bd.round_directed(0b10111, 0, False, True, True, 4), bd.value(0b1011, 1, negative=True))
        # exact values stay; a carry into a new binade: 0b11111 up at 4 bits is 32
        self.assertEqual(bd.round_directed(0b1111, 0, False, False, True, 4), bd.value(0b1111, 0))
        self.assertEqual(bd.round_directed(0b11111, 0, False, False, True, 4), bd.value(0b1000, 2))
        # a quotient with a remainder (sticky) is above its integer part
        self.assertEqual(bd.round_directed(0b1000, 0, True, False, True, 4), bd.value(0b1001, 0))
        self.assertEqual(bd.round_directed(0b1000, 0, True, False, False, 4), bd.value(0b1000, 0))

    def test_the_range_ends(self) -> None:
        p = 4
        largest = bd.max_finite(p)
        # one unit above the largest finite value: up is infinity, down is the largest
        over = bd.round_directed((1 << p) + 1, bd.EMAX + 1 - p, False, False, False, p)
        self.assertEqual(over, largest)
        self.assertEqual(bd.round_directed((1 << p) + 1, bd.EMAX + 1 - p, False, False, True, p), bd.INF)
        self.assertEqual(bd.round_directed((1 << p) + 1, bd.EMAX + 1 - p, False, True, False, p), bd.NEG_INF)
        # the smallest positive number is 2^(EMIN - p + 1): half of it rounds to zero down and to it up
        half_quantum = bd.round_directed(1, bd.quantum(p) - 1, False, False, False, p)
        self.assertEqual(half_quantum, bd.ZERO)
        self.assertEqual(bd.round_directed(1, bd.quantum(p) - 1, False, False, True, p), bd.value(1, bd.quantum(p)))
        # the smallest normal number is 2^EMIN: (1 + 1/16) 2^EMIN = 17 * 2^(EMIN-4) has 5 bits, at 4 bits up it is 18 * 2^(EMIN-4) = 9 * 2^(EMIN-3)
        self.assertEqual(bd.round_directed(0b10001, bd.EMIN - 4, False, False, True, p), bd.value(0b1001, bd.EMIN - 3))
        # in the subnormal band (leading bit below EMIN) the grid is 2^quantum: 3 quanta + a bit rounds to 4 quanta up
        tiny = bd.round_directed(0b111, bd.quantum(p) - 1, False, False, True, p)  # 3.5 quanta
        self.assertEqual(tiny, bd.value(0b100, bd.quantum(p)))

    def test_rows_by_the_integer_oracle(self) -> None:
        def row(op: str, size: int, *operands: tuple[bd.Value, bd.Value]) -> bd.Row:
            return bd.Row("t", op, size, "R", tuple(operands))

        v = bd.value
        # [1, 2] + [3, 5] = [4, 7]
        self.assertEqual(bd.py_oracle(row("add", 8, (v(1, 0), v(2, 0)), (v(3, 0), v(5, 0)))), ("0b1p2", "0b111p0"))
        # [1, 2] - [3, 5] = [-4, -1]
        self.assertEqual(bd.py_oracle(row("sub", 8, (v(1, 0), v(2, 0)), (v(3, 0), v(5, 0)))), ("-0b1p2", "-0b1p0"))
        # [-3, 2] * [5, 7] = [-21, 14]
        self.assertEqual(bd.py_oracle(row("mul", 8, (v(3, 0, True), v(2, 0)), (v(5, 0), v(7, 0)))), ("-0b10101p0", "0b111p1"))
        # [-3, 2] squared = [0, 9]
        self.assertEqual(bd.py_oracle(row("sqr", 8, (v(3, 0, True), v(2, 0)))), ("0", "0b1001p0"))
        # 1 / 3 at 4 bits: 0.0101 0101... : down 0b1010 * 2^-5 = 5/16... (0b1010 p-5 = 10/32 = 0.3125), up 0b1011 p-5 = 0.34375
        self.assertEqual(bd.py_oracle(row("div", 4, (v(1, 0), v(1, 0)), (v(3, 0), v(3, 0)))), ("0b101p-4", "0b1011p-5"))
        # sqrt [2, 2] at 4 bits: 1.4142: down 0b1011 * 2^-3 = 1.375, up 0b1100 p-3 = 1.5
        self.assertEqual(bd.py_oracle(row("sqrt", 4, (v(2, 0), v(2, 0)))), ("0b1011p-3", "0b11p-1"))
        # fma [1, 1] * [2, 2] + [-3, -3] = -1
        self.assertEqual(bd.py_oracle(row("fma", 8, (v(1, 0), v(1, 0)), (v(2, 0), v(2, 0)), (v(3, 0, True), v(3, 0, True)))), ("-0b1p0", "-0b1p0"))

    def test_an_exponent_gap_is_skipped(self) -> None:
        row = bd.Row("t", "add", 8, "R", ((bd.value(1, 0), bd.value(1, 0)), (bd.value(1, -bd.MAX_GAP - 50), bd.value(1, -bd.MAX_GAP - 50))))
        with self.assertRaises(bd.Skipped):
            bd.py_oracle(row)


class RowTests(unittest.TestCase):
    def test_illegal_rows_are_refused(self) -> None:
        one, two = bd.value(1, 0), bd.value(1, 1)
        with self.assertRaises(ValueError):
            bd.Row("x", "add", 8, "R", ((two, one), (one, one)))  # lower above upper
        with self.assertRaises(ValueError):
            bd.Row("x", "sqrt", 8, "R", ((one.neg(), one),))
        with self.assertRaises(ValueError):
            bd.Row("x", "div", 8, "R", ((one, one), (one.neg(), one)))  # the divisor contains zero
        with self.assertRaises(ValueError):
            bd.Row("x", "div", 8, "R", ((one, one), (bd.ZERO, one)))
        bd.Row("x", "div", 8, "R", ((one, one), (one, two)))

    def test_rows_are_deterministic_and_all_legal(self) -> None:
        first = bd.generate_rows(per_cell=6)
        second = bd.generate_rows(per_cell=6)
        self.assertEqual([r.line() for r in first], [r.line() for r in second])
        self.assertEqual(len({r.id for r in first}), len(first))
        applicable = sum(len(ops) * len(bd.PRECISIONS) * 6 for ops, _ in bd.CLASSES.values())
        self.assertEqual(len(first), applicable)
        for row in first:
            self.assertEqual(len(row.operands), bd.ARITY[row.op])

    def test_a_cell_keeps_its_stream_when_other_cells_are_selected(self) -> None:
        everything = {r.id: r.line() for r in bd.generate_rows(per_cell=4)}
        only = bd.generate_rows(per_cell=4, classes=["SUB"], ops=["mul"], precisions=[128])
        self.assertEqual(len(only), 4)
        for row in only:
            self.assertEqual(everything[row.id], row.line())

    def test_the_text_of_a_row(self) -> None:
        row = bd.Row("1.add.R.8.0", "add", 8, "R", ((bd.value(0xA5, 0), bd.value(0xA6, 0)), (bd.value(3, -1, negative=True), bd.value(3, -1, negative=True))))
        self.assertEqual(row.line(), "1.add.R.8.0 add 8 R 0xa5p0:0xa6p0 -0x3p-1:-0x3p-1")


class ReductionTests(unittest.TestCase):
    """Oracle: level A (lines and verdicts written out)."""

    ORACLE = "# header\nr1 0b1p0 0b11p0 o 0b1p0:0b1p0\nr2 0 0b1p1 - 0b1p0:0b1p0\nr3 0 0 su -0:0\n"

    def rows(self) -> list[bd.Row]:
        one = bd.value(1, 0)
        return [bd.Row(f"r{i}", "sqr", 8, "OV" if i < 3 else "SUB", ((one, one),)) for i in (1, 2, 3)]

    def test_parse_oracle_and_coverage(self) -> None:
        oracle = bd.parse_oracle(self.ORACLE)
        self.assertEqual(oracle["r1"], ("0b1p0", "0b11p0", "o", "0b1p0:0b1p0"))
        table = bd.coverage(self.rows(), oracle)
        self.assertEqual(table[("OV", "sqr", 8)]["o"], 1)
        self.assertEqual(table[("OV", "sqr", 8)]["rows"], 2)
        self.assertEqual(table[("SUB", "sqr", 8)]["s"], 1)
        self.assertEqual(table[("SUB", "sqr", 8)]["u"], 1)
        self.assertEqual(bd.check_coverage(table), [])

    def test_a_class_that_misses_its_band_is_an_error(self) -> None:
        oracle = bd.parse_oracle("r1 0 0 - x\nr2 0 0 - x\nr3 0 0 - x\n")
        errors = bd.check_coverage(bd.coverage(self.rows(), oracle))
        self.assertEqual(len(errors), 2)
        self.assertIn("class OV sqr 8", errors[0])
        self.assertIn("class SUB sqr 8", errors[1])
        # the subnormal band is reached by an operand (flag i) as well as by a result (flag s)
        oracle = bd.parse_oracle("r1 0 0 o x\nr2 0 0 - x\nr3 0 0 i x\n")
        self.assertEqual(bd.check_coverage(bd.coverage(self.rows(), oracle)), [])

    def test_known_rows(self) -> None:
        known = bd.parse_known("# comment\n\nr1 #657\nr9 #12\n")
        self.assertEqual(known, {"r1": "#657", "r9": "#12"})
        with self.assertRaises(ValueError):
            bd.parse_known("r1\n")
        failures = ["BALLDIFF_FAIL r1 add 8 R expected a b got c d", "BALLDIFF_FAIL r2 add 8 R expected a b got c d"]
        unknown, still, stale = bd.split_failures(failures, known, ["r1", "r2", "r3"])
        self.assertEqual([line.split()[1] for line in unknown], ["r2"])
        self.assertEqual(still, ["r1"])
        self.assertEqual(stale, [])  # r9 did not run in this selection
        unknown, still, stale = bd.split_failures([], known, ["r1", "r2"])
        self.assertEqual((unknown, still, stale), ([], [], ["r1"]))  # r1 agrees now: stale

    def test_the_test_output(self) -> None:
        text = "BALLDIFF_FAIL r1 x\nnoise\nBALLDIFF_SUMMARY rows=10 failed=1 undecided=2\n"
        self.assertEqual(bd.parse_test_output(text), (10, 1, 2, ["BALLDIFF_FAIL r1 x"]))
        with self.assertRaises(RuntimeError):
            bd.parse_test_output("Segmentation fault\n")


if __name__ == "__main__":
    unittest.main()
