import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_corpus_contexts as cc  # noqa: E402

DECIMAL_V2 = """# mpfr-decimal-random-v2 table=x
# id op rounding precision emax a b n expected flags
r0 exp half_even 34 6144 1 - 0 2 -
r1 exp half_up 16 384 1 - 0 2 -
"""
DECIMAL_V1 = """# id op rounding precision emin emax clamp tininess a b n expected flags
r0 exp half_even 34 -6142 6143 1 b 1 - 0 2 -
r1 exp half_even 34 -6143 6143 1 b 1 - 0 2 -
r2 exp half_even 34 -6142 6143 0 b 1 - 0 2 -
r3 exp half_even 34 -6142 6143 1 a 1 - 0 2 -
"""
BINARY = """# id op rounding precision emin emax tininess a b c n expected flags
b0 add n 53 -1022 1023 a 1 1 - 0 2 -
b1 add na 53 - - - 1 1 - 0 2 -
b2 add n 53 -1023 1023 a 1 1 - 0 2 -
b3 add a 53 -1022 1023 a 1 1 - 0 2 -
b4 add n 53 -1022 1023 - 1 1 - 0 2 -
"""
DECTEST = """version: 2.62
precision: 9
rounding: half_up
maxexponent: 99
minexponent: -99
clamp: 0
a add 1 1 -> 2
-- an illegal range follows
maxexponent: 60
minexponent: -50
b add 1 1 -> 2
"""
TABLE = '''fn rows() -> Array[Unit] {
  [
    ("exp", "half_even", 51, -10, 11, true, "1", "", "2", "x"),
    ("exp", "half_even", 51, -11, 11, true, "1", "", "2", "x"),
    ("pm1", "floor", 7, -95, 96, true, "b", "1", "2", "-"),
    ("ops", 34, 6144, "half_even", "1"),
    ("ops", 34, 0, "half_even", "1"),
  ]
}
'''


class ScanTests(unittest.TestCase):
    def test_decimal_v2_rows_are_legal_by_representation_unless_the_range_or_rounding_is_wrong(self) -> None:
        report = cc.scan_decimal_text(DECIMAL_V2)
        self.assertEqual((report.rows, len(report.contexts), report.illegal), (2, 2, {}))
        bad = cc.scan_decimal_text(DECIMAL_V2.replace("half_up", "half_down").replace("6144", "0"))
        self.assertEqual(len(bad.illegal), 2)

    def test_decimal_v1_rows_name_each_illegal_column(self) -> None:
        report = cc.scan_decimal_text(DECIMAL_V1)
        self.assertEqual(report.rows, 4)
        reasons = sorted(problem.split()[0] for problem in report.illegal.values())
        self.assertEqual(reasons, ["clamp", "emin", "tininess"])

    def test_binary_rows(self) -> None:
        report = cc.scan_binary_text(BINARY)
        self.assertEqual(report.rows, 5)
        reasons = " | ".join(report.illegal.values())
        self.assertEqual(len(report.illegal), 3)  # e_min off, rounding a, tininess missing next to a range
        self.assertIn("not 1 - emax", reasons)
        self.assertIn("rounding a", reasons)
        self.assertIn("tininess", reasons)

    def test_dectest_directives_in_force(self) -> None:
        report = cc.scan_dectest(DECTEST)
        self.assertEqual((report.rows, len(report.contexts), len(report.illegal)), (2, 2, 1))
        self.assertIn("not a GDA 1.70 exponent range", next(iter(report.illegal.values())))

    def test_mbt_tables_of_both_shapes(self) -> None:
        report = cc.scan_mbt_tables(TABLE)
        self.assertEqual(report.rows, 5)
        self.assertEqual(len(report.illegal), 2)  # e_min -11 for e_max 11; e_max 0


class RepositoryTests(unittest.TestCase):
    def test_the_repository_is_clean(self) -> None:
        reports, missing = cc.scan_repository()
        self.assertEqual(missing, [])
        self.assertEqual([report.path for report in reports if report.illegal], [])
        self.assertGreater(sum(report.rows for report in reports), 50_000)

    def test_a_glob_that_matches_nothing_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reports, missing = cc.scan_repository(Path(directory))
            self.assertEqual(reports, [])
            self.assertIn("testdata/bin_float/random-regressions.txt", missing)
            self.assertEqual(cc.main(["--root", directory]), 1)

    def test_an_illegal_row_fails_the_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "testdata/decimal/random").mkdir(parents=True)
            (root / "testdata/decimal/random/x.txt").write_text(DECIMAL_V1, encoding="utf-8")
            self.assertEqual(cc.main(["--root", directory]), 1)


if __name__ == "__main__":
    unittest.main()
