import json
import math
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

import itl_refinements as refs

SOURCE = """/* header
comment */
testcase first {
    add [1.0,2.0] [3.0,4.0] = [4.0,6.0];
    // a comment line
    sinRevBin [0.0,0.0] [3.0,3.5]
        = [0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1]; // trailing
    sqr [1.0,2.0] = [1.0,4.0];
}

testcase second {
    mulRevToPair [1.0,2.0] [3.0,4.0] = [1.5,4.0] [empty];
}
"""


def refinement(**overrides: str) -> refs.Refinement:
    values = {
        "file": "f.itl",
        "id": "first:2",
        "operation": "sinRevBin",
        "corpus": "[0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1]",
        "refined": "[0x1.921fb54442d18p+1,0x1.921fb54442d19p+1]",
        "reason": "test",
    }
    values.update(overrides)
    return refs.Refinement(**values)


class ParseTest(unittest.TestCase):
    def test_statement_ids_follow_the_interpreter(self) -> None:
        statements = refs.parse_statements(SOURCE)
        self.assertEqual(
            [s.id for s in statements],
            ["first:1", "first:2", "first:3", "second:1"],
        )
        self.assertEqual(statements[1].operation, "sinRevBin")
        self.assertEqual(
            statements[1].expected, "[0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1]"
        )

    def test_words_keep_a_bracketed_interval_with_its_suffix(self) -> None:
        self.assertEqual(
            refs.split_words("[1.0, 2.0]_com [empty]"), ["[1.0, 2.0]_com", "[empty]"]
        )

    def test_interval_words(self) -> None:
        interval = refs.parse_interval("[-0x1p+0, 0x1.8p+1]_trv")
        self.assertEqual((interval.lo, interval.hi, interval.decoration), (-1, 3, "trv"))
        self.assertTrue(refs.parse_interval("[empty]").empty)
        entire = refs.parse_interval("[entire]")
        self.assertEqual((entire.lo, entire.hi), (-math.inf, math.inf))
        self.assertEqual(refs.parse_interval("[ -infinity, 1.0]").lo, -math.inf)

    def test_decimal_bounds_are_the_nearest_binary64(self) -> None:
        # 0.1 is read as the nearest double, as the interpreter reads a bound
        self.assertEqual(refs.parse_bound("0.1"), Fraction(0.1))
        self.assertEqual(refs.parse_bound("1.57"), Fraction(1.57))

    def test_directed_rounding_to_binary64(self) -> None:
        third = Fraction(1, 3)
        down = refs.round_binary64(third, up=False)
        up = refs.round_binary64(third, up=True)
        self.assertLess(down, third)
        self.assertGreater(up, third)
        self.assertEqual(up - down, refs.binary64_ulp(third))
        self.assertEqual(refs.round_binary64(Fraction(3, 8), up=True), Fraction(3, 8))
        self.assertEqual(refs.round_binary64(-third, up=True), -down)

    def test_containment(self) -> None:
        outer = refs.parse_interval("[0.0, 4.0]")
        self.assertTrue(refs.contains(outer, refs.parse_interval("[1.0, 4.0]")))
        self.assertTrue(refs.contains(outer, refs.parse_interval("[empty]")))
        self.assertFalse(refs.contains(outer, refs.parse_interval("[-1.0, 4.0]")))
        self.assertFalse(refs.contains(refs.parse_interval("[empty]"), outer))


class ValidateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.statements = {"f.itl": refs.parse_statements(SOURCE)}

    def test_a_correct_entry_is_accepted(self) -> None:
        refs.validate([refinement()], self.statements)

    def test_a_missing_case_or_file_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing case"):
            refs.validate([refinement(id="first:9")], self.statements)
        with self.assertRaisesRegex(ValueError, "missing file"):
            refs.validate([refinement(file="g.itl")], self.statements)

    def test_a_wrong_operation_or_recorded_corpus_value_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "operation"):
            refs.validate([refinement(operation="cosRevBin")], self.statements)
        with self.assertRaisesRegex(ValueError, "corpus value"):
            refs.validate([refinement(corpus="[1.0,2.0]")], self.statements)

    def test_a_refined_value_outside_the_corpus_value_is_rejected(self) -> None:
        wider = "[0x1.921fb54442d18p+1,0x1.921fb54442d1bp+1]"
        with self.assertRaisesRegex(ValueError, "not inside"):
            refs.validate([refinement(refined=wider)], self.statements)

    def test_an_equal_or_differently_decorated_value_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "equals"):
            refs.validate(
                [refinement(refined="[0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1]")],
                self.statements,
            )
        with self.assertRaisesRegex(ValueError, "decoration"):
            refs.validate(
                [refinement(refined="[0x1.921fb54442d18p+1,0x1.921fb54442d19p+1]_trv")],
                self.statements,
            )

    def test_the_number_of_results_must_agree(self) -> None:
        with self.assertRaisesRegex(ValueError, "number of results"):
            refs.validate(
                [
                    refinement(
                        id="second:1",
                        operation="mulRevToPair",
                        corpus="[1.5,4.0] [empty]",
                        refined="[2.0,4.0]",
                    )
                ],
                self.statements,
            )


class ApplyTest(unittest.TestCase):
    def test_only_the_refined_statement_changes(self) -> None:
        patched = refs.apply(SOURCE, [refinement()])
        before = {s.id: s for s in refs.parse_statements(SOURCE)}
        after = {s.id: s for s in refs.parse_statements(patched)}
        self.assertEqual(set(before), set(after))
        for case_id in before:
            if case_id == "first:2":
                self.assertEqual(
                    after[case_id].expected,
                    "[0x1.921fb54442d18p+1,0x1.921fb54442d19p+1]",
                )
                self.assertEqual(after[case_id].lhs, before[case_id].lhs)
            else:
                self.assertEqual(after[case_id].expected, before[case_id].expected)

    def test_a_multi_line_statement_becomes_one_line(self) -> None:
        patched = refs.apply(SOURCE, [refinement()])
        self.assertNotIn("\n        = [0x1.921fb54442d18p+1", patched)


class LoadTest(unittest.TestCase):
    def write(self, document: object) -> Path:
        directory = Path(tempfile.mkdtemp())
        path = directory / "r.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_a_well_formed_file_is_read(self) -> None:
        entry = {
            "file": "f.itl",
            "id": "first:2",
            "operation": "sinRevBin",
            "corpus": "[1.0,2.0]",
            "refined": "[1.0,1.5]",
            "reason": "r",
        }
        loaded = refs.load(self.write({"schemaVersion": 1, "refinements": [entry]}))
        self.assertEqual(loaded[0].id, "first:2")

    def test_malformed_files_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            refs.load(self.write({"schemaVersion": 2, "refinements": []}))
        with self.assertRaises(ValueError):
            refs.load(self.write({"schemaVersion": 1, "refinements": [{"id": "x"}]}))
        entry = {
            "file": "f.itl",
            "id": "a:1",
            "operation": "o",
            "corpus": "[1.0,2.0]",
            "refined": "[1.0,1.5]",
            "reason": "r",
        }
        with self.assertRaisesRegex(ValueError, "twice"):
            refs.load(self.write({"schemaVersion": 1, "refinements": [entry, entry]}))


if __name__ == "__main__":
    unittest.main()
