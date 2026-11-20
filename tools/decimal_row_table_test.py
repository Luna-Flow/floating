import json
import unittest

import decimal_row_table as table


def row(**overrides: object) -> table.TableRow:
    fields: dict[str, object] = dict(
        op="exp2m1", rounding="half_even", precision=1, emin=-999999, emax=999999,
        clamp=False, tininess="b", a="1", b=None, n=0, expected="1", flags="-",
    )
    fields.update(overrides)
    return table.TableRow(**fields)  # type: ignore[arg-type]


def cli_output(total: int, failed: list[str]) -> str:
    return json.dumps({"totalCases": total, "failedIds": failed})


class RowFormatTests(unittest.TestCase):
    def test_row_line_has_the_thirteen_fields_of_the_cli_format(self) -> None:
        line = table.format_row("pm1-00000", row())
        self.assertEqual(
            line, "pm1-00000 exp2m1 half_even 1 -999999 999999 0 b 1 - 0 1 -"
        )
        self.assertEqual(len(line.split()), 13)

    def test_clamp_and_second_operand_are_written(self) -> None:
        tokens = table.format_row("t-1", row(clamp=True, b="2.5", n=-3)).split()
        self.assertEqual((tokens[6], tokens[9], tokens[10]), ("1", "2.5", "-3"))

    def test_unwritable_tokens_are_rejected(self) -> None:
        for bad in ("a b", ""):
            with self.assertRaises(ValueError):
                table.format_row("t-1", row(a=bad))

    def test_render_numbers_rows_and_counts_only_data_lines(self) -> None:
        text = table.render_table("pm1", "gen.py", [row(), row(a="2", expected="3")])
        self.assertIn("mpfr-decimal-random-v1", text.split("\n")[0])
        self.assertEqual(table.count_rows(text), 2)
        self.assertIn("\npm1-00001 ", text)

    def test_check_table_compares_bytes(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "t.txt"
            self.assertFalse(table.check_table(path, "x\n"))
            path.write_text("x\n", encoding="utf-8")
            self.assertTrue(table.check_table(path, "x\n"))
            self.assertFalse(table.check_table(path, "x \n"))


class EvaluateRunTests(unittest.TestCase):
    def test_all_rows_passed(self) -> None:
        result = table.evaluate_run("pm1", 10, 0, cli_output(10, []))
        self.assertEqual((result["totalCases"], result["passedCases"], result["failedCases"]), (10, 10, 0))

    def test_failed_rows_fail_the_table(self) -> None:
        result = table.evaluate_run("pm1", 10, 1, cli_output(10, ["pm1-00003"]))
        self.assertEqual((result["passedCases"], result["failedCases"]), (9, 1))
        self.assertEqual(result["failedIds"], ["pm1-00003"])

    def test_nonzero_exit_without_failed_ids_still_fails(self) -> None:
        result = table.evaluate_run("pm1", 10, 1, cli_output(10, []))
        self.assertEqual(result["failedCases"], 1)

    def test_executed_count_must_equal_the_data_rows(self) -> None:
        for executed in (9, 11, 0):
            result = table.evaluate_run("pm1", 10, 0, cli_output(executed, []))
            self.assertEqual(result["failedCases"], 10)
            self.assertIn("expected 10", str(result["error"]))

    def test_crash_and_garbage_fail(self) -> None:
        self.assertEqual(table.evaluate_run("pm1", 10, 2, "", "parse error")["failedCases"], 10)
        self.assertEqual(table.evaluate_run("pm1", 10, 0, "not json")["failedCases"], 10)
        self.assertEqual(table.evaluate_run("pm1", 10, 0, "{}")["failedCases"], 10)


class SamplingTests(unittest.TestCase):
    def test_positions_are_equidistant_and_never_empty(self) -> None:
        self.assertEqual(table.sample_positions(20, 8), [4, 12])
        self.assertEqual(table.sample_positions(3, 8), [1])
        self.assertEqual(table.sample_positions(0, 8), [])
        self.assertEqual(table.sample_positions(5, 1), [0, 1, 2, 3, 4])
        with self.assertRaises(ValueError):
            table.sample_positions(5, 0)

    def test_sample_keeps_exact_rows_and_strata(self) -> None:
        rows = (
            [row(a=str(i)) for i in range(4)]  # exact rows: all kept
            + [row(a=str(i), rounding="down") for i in range(20)]
            + [row(a=str(i), rounding="up") for i in range(3)]
            + [row(op="exp", a=str(i), rounding="up") for i in range(3)]
        )
        certified = [False] * 4 + [True] * (len(rows) - 4)
        kept = table.stratified_sample(rows, certified, 8)
        self.assertEqual(kept[:4], [0, 1, 2, 3])
        self.assertEqual([rows[i].a for i in kept if rows[i].rounding == "down" and rows[i].b is None], ["4", "12"])
        self.assertEqual(sum(1 for i in kept if rows[i].op == "exp"), 1)  # short stratum keeps its middle
        self.assertEqual(kept, sorted(set(kept)))
        self.assertEqual(kept, table.stratified_sample(rows, certified, 8))  # deterministic

    def test_stratum_counts_report_full_and_sampled(self) -> None:
        rows = [row(a=str(i), rounding="down") for i in range(20)]
        certified = [True] * 20
        kept = table.stratified_sample(rows, certified, 8)
        self.assertEqual(table.stratum_counts(rows, certified, kept), [("exp2m1", "down", 20, 2)])

    def test_length_mismatch_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            table.stratified_sample([row()], [], 8)


class CheckedInTableTests(unittest.TestCase):
    def test_tables_are_well_formed_cli_rows(self) -> None:
        for name in (*table.TABLES, *table.OPT_IN_TABLES):
            text = table.table_path(name).read_text(encoding="utf-8")
            self.assertIn("mpfr-decimal-random-v1", text.split("\n")[0])
            lines = table.data_lines(text)
            if name == "pi_inverse":
                self.assertGreater(len(lines), 5000, name)
                self.assertEqual(len(lines), 19134)
            else:
                self.assertGreater(len(lines), 10, name)
            ids = [line.split()[0] for line in lines]
            self.assertEqual(len(set(ids)), len(ids), name)
            self.assertTrue(all(len(line.split()) == 13 for line in lines), name)


if __name__ == "__main__":
    unittest.main()
