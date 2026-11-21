import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_random_rna_rows as rna  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


def row(operation: str, operands: str, expected: str, flags: str, precision: int = 11, emin: int = -14, emax: int = 15, tininess: str = "a") -> str:
    # binary16 context by default: the weight of the last place of a subnormal is 2^-24
    return f"t.{operation} {operation} na {precision} {emin} {emax} {tininess} {operands} 0 {expected} {flags}"


class RoundAwayTests(unittest.TestCase):
    def test_a_tie_on_the_subnormal_grid_goes_away_from_zero(self) -> None:
        # 2^-25 is half the weight of the last place: nearest-away gives 2^-24, nearest-even would give 0
        report = rna.check_text(row("add", "0x1p-26 0x1p-26 -", "0x1p-24", "xu"))
        self.assertEqual((report.checked, report.tiny, report.failures), (1, 1, []))
        wrong = rna.check_text(row("add", "0x1p-26 0x1p-26 -", "0x0p0", "xu"))
        self.assertEqual(wrong.failures, ["t.add: value"])

    def test_a_tie_between_two_and_three_units_goes_to_three(self) -> None:
        # 2.5 units of 2^-24: nearest-even gives 2 units, nearest-away 3
        self.assertEqual(rna.check_text(row("add", "0x5p-25 0x0p0 -", "0x3p-24", "xu")).failures, [])
        self.assertEqual(rna.check_text(row("add", "0x5p-25 0x0p0 -", "0x1p-23", "xu")).failures, ["t.add: value"])

    def test_the_flags_are_checked(self) -> None:
        # exact subnormal result: no inexact, no underflow
        self.assertEqual(rna.check_text(row("add", "0x1p-24 0x1p-24 -", "0x1p-23", "-")).failures, [])
        self.assertEqual(rna.check_text(row("add", "0x1p-24 0x1p-24 -", "0x1p-23", "xu")).failures, ["t.add: inexact flag"])
        # inexact and tiny: underflow under both tininess rules
        self.assertEqual(rna.check_text(row("add", "0x1p-26 0x1p-26 -", "0x1p-24", "x")).failures, ["t.add: underflow flag"])

    def test_tininess_after_rounding_depends_on_the_rounding_to_p_bits(self) -> None:
        # exact 2^-14 - 2^-26: rounded to 11 bits with an unbounded exponent it is 2^-14, so not tiny after rounding,
        # and tiny before rounding; the subnormal grid result is 2^-14 (a tie goes up)
        operands = "0x3fffffp-36 0x0p0 -"  # (2^22 - 1) * 2^-36 = 2^-14 - 2^-36: far from a tie
        result = "0x1p-14"
        self.assertEqual(rna.check_text(row("add", operands, result, "x", tininess="a")).failures, [])
        self.assertEqual(rna.check_text(row("add", operands, result, "xu", tininess="a")).failures, ["t.add: underflow flag"])
        self.assertEqual(rna.check_text(row("add", operands, result, "xu", tininess="b")).failures, [])

    def test_the_other_operations(self) -> None:
        self.assertEqual(rna.check_text(row("mul", "0x1p-13 0x1p-12 -", "0x1p-24", "xu")).failures, [])
        self.assertEqual(rna.check_text(row("div", "0x1p-24 0x2p0 -", "0x1p-24", "xu")).failures, [])  # 2^-25 ties away
        self.assertEqual(rna.check_text("t.fma fma na 11 -14 15 a 0x1p-13 0x1p-12 0x1p-26 0 0x1p-24 xu").failures, [])

    def test_rows_that_are_not_checked_are_skipped_or_ignored(self) -> None:
        self.assertEqual(rna.check_text("t.x sqrt na 11 -14 15 a 0x1p0 - - 0 0x1p0 -").checked, 0)  # not a checked operation
        self.assertEqual(rna.check_text("t.x add n 11 -14 15 a 0x1p0 0x1p0 - 0 0x1p1 -").checked, 0)  # not nearest-away
        report = rna.check_text("t.x add na 11 -14 15 a 0x1p0 inf - 0 inf -")  # a special operand
        self.assertEqual((report.checked, report.skipped), (0, 1))
        self.assertEqual(rna.check_text("t.x div na 11 -14 15 a 0x1p0 0x0p0 - 0 inf z").checked, 0)

    def test_the_committed_rows_are_right(self) -> None:
        for name in ("testdata/bin_float/mpfr-4.2.2-random.txt", "testdata/bin_float/random-regressions.txt"):
            report = rna.check_text((REPO / name).read_text(encoding="utf-8"))
            self.assertEqual(report.failures, [], name)
            self.assertGreater(report.checked, 0, name)
            self.assertGreater(report.tiny, 0, name)  # the class the generator used to rewrite


if __name__ == "__main__":
    unittest.main()
