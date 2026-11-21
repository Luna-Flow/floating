from __future__ import annotations

import tempfile
import textwrap
import unittest
from pathlib import Path

import check_test_oracles as check


class OracleCheckTest(unittest.TestCase):
    def make_root(self, files: dict[str, str], debt: str = "") -> Path:
        root = Path(tempfile.mkdtemp(prefix="oracle-check-"))
        self.addCleanup(lambda: __import__("shutil").rmtree(root, True))
        for name, text in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(textwrap.dedent(text))
        (root / "tools").mkdir(exist_ok=True)
        (root / "tools" / "oracle_debt.txt").write_text(debt)
        return root

    def run_check(self, files: dict[str, str], debt: str = "", limit: int | None = None):
        root = self.make_root(files, debt)
        entries = len([line for line in debt.splitlines() if line and not line.startswith("#")])
        return check.check(root, debt_limit=entries if limit is None else limit)

    def one(self, block: str, debt: str = ""):
        return self.run_check({"library/src/p/a_wbtest.mbt": block}, debt)

    def test_a_valid_declaration_passes(self) -> None:
        problems, declared, _ = self.one(
            '''\
            ///|
            // oracle: A
            // source: written out from IEEE 754-2019 7.2 for the ten operand classes
            // shares: nothing
            test "x" { }
            '''
        )
        self.assertEqual(problems, [])
        self.assertEqual(declared["A"], 1)

    def test_a_continued_value_is_joined(self) -> None:
        problems, _, _ = self.one(
            '''\
            ///|
            // oracle: A, S
            // source: Python 3 decimal at 50 digits,
            //   rounded by hand
            // shares: nothing
            test "x" { }
            '''
        )
        self.assertEqual(problems, [])

    def test_a_block_without_declaration_must_declare(self) -> None:
        problems, _, _ = self.one('///|\ntest "x" { }\n')
        self.assertEqual(len(problems), 1)
        self.assertIn("no `// oracle:` line", problems[0])

    def test_a_block_in_the_debt_list_may_stay_undeclared(self) -> None:
        problems, _, debt = self.one('///|\ntest "x" { }\n', "library/src/p/a_wbtest.mbt::x\tC\n")
        self.assertEqual(problems, [])
        self.assertEqual(debt["C"], 1)

    def test_level_c_is_refused(self) -> None:
        problems, _, _ = self.one(
            "///|\n// oracle: C\n// source: the plain tier\n// shares: add\ntest \"x\" { }\n"
        )
        self.assertTrue(any("level C is refused" in problem for problem in problems))

    def test_level_b_needs_primitives_and_level_e_needs_underneath(self) -> None:
        problems, _, _ = self.one(
            '///|\n// oracle: B\n// source: another algorithm on exact sums\n// shares: add\ntest "x" { }\n'
        )
        self.assertTrue(any("needs `primitives:`" in problem for problem in problems))
        problems, _, _ = self.one(
            '///|\n// oracle: E\n// source: the old implementation\n// shares: add\ntest "x" { }\n'
        )
        self.assertTrue(any("needs `underneath:`" in problem for problem in problems))
        problems, _, _ = self.one(
            "///|\n// oracle: E\n// source: the old implementation\n// shares: add\n"
            "// underneath: A: TestFloat level 1 rows for add\ntest \"x\" { }\n"
        )
        self.assertEqual(problems, [])

    def test_placeholders_are_refused(self) -> None:
        problems, _, _ = self.one('///|\n// oracle: A\n// source: see above\n// shares: nothing\ntest "x" { }\n')
        self.assertTrue(any("`source:`" in problem for problem in problems))
        problems, _, _ = self.one('///|\n// oracle: A\n// source: written out from the standard\n// shares:\ntest "x" { }\n')
        self.assertTrue(any("`shares:`" in problem for problem in problems))

    def test_an_unknown_level_is_refused(self) -> None:
        problems, _, _ = self.one('///|\n// oracle: Z\n// source: written out from the standard\n// shares: nothing\ntest "x" { }\n')
        self.assertTrue(any("not one of A, B, E, S" in problem for problem in problems))

    def test_a_declared_block_must_leave_the_debt_list(self) -> None:
        problems, _, _ = self.one(
            '///|\n// oracle: A\n// source: written out from the standard\n// shares: nothing\ntest "x" { }\n',
            "library/src/p/a_wbtest.mbt::x\tC\n",
        )
        self.assertTrue(any("remove it from tools/oracle_debt.txt" in problem for problem in problems))

    def test_a_missing_block_must_leave_the_debt_list(self) -> None:
        problems, _, _ = self.one('///|\ntest "y" { }\n', "library/src/p/a_wbtest.mbt::x\tC\nlibrary/src/p/a_wbtest.mbt::y\t?\n")
        self.assertTrue(any("does not exist" in problem for problem in problems))

    def test_the_debt_limit_must_equal_the_list(self) -> None:
        problems, _, _ = self.run_check(
            {"library/src/p/a_wbtest.mbt": '///|\ntest "x" { }\n'}, "library/src/p/a_wbtest.mbt::x\tC\n", limit=2
        )
        self.assertTrue(any("DEBT_LIMIT is 2" in problem for problem in problems))

    def test_duplicate_names_are_refused(self) -> None:
        problems, _, _ = self.one('///|\ntest "x" { }\n\n///|\ntest "x" { }\n', "library/src/p/a_wbtest.mbt::x\tC\n")
        self.assertTrue(any("duplicate test name" in problem for problem in problems))

    def test_a_generated_table_takes_a_file_declaration(self) -> None:
        files = {
            "tools/gen.py": "",
            "library/src/p/t_wbtest.mbt": (
                "// oracle-file: A\n// producer: tools/gen.py\n// input: 110 strings and Random(1788)\n"
                '// library-ran: no\n\n///|\ntest "table" { }\n'
            ),
        }
        problems, declared, _ = self.run_check(files)
        self.assertEqual(problems, [])
        self.assertEqual(declared["A"], 1)

    def test_a_file_declaration_needs_an_existing_producer_and_no_library_run(self) -> None:
        text = (
            "// oracle-file: A\n// producer: tools/missing.py\n// input: x\n// library-ran: no\n\n///|\ntest \"table\" { }\n"
        )
        problems, _, _ = self.run_check({"library/src/p/t_wbtest.mbt": text})
        self.assertTrue(any("does not exist" in problem for problem in problems))
        text = text.replace("tools/missing.py", "tools/gen.py").replace("library-ran: no", "library-ran: yes")
        problems, _, _ = self.run_check({"library/src/p/t_wbtest.mbt": text, "tools/gen.py": ""})
        self.assertTrue(any("library-ran: yes" in problem for problem in problems))

    def test_a_plain_words_statement_is_accepted_and_counted(self) -> None:
        problems, declared, _ = self.one(
            '///|\n// Oracle (level A): expected values written out from the standard\ntest "x" { }\n'
        )
        self.assertEqual(problems, [])
        self.assertEqual(declared["prose A"], 1)

    def test_a_file_head_statement_covers_the_blocks_of_the_file(self) -> None:
        problems, declared, _ = self.one(
            '// ORACLE level A: every expected bound is worked out by hand\n\n///|\ntest "x" { }\n\n///|\ntest "y" { }\n'
        )
        self.assertEqual(problems, [])
        self.assertEqual(declared["prose A"], 2)

    def test_a_plain_words_statement_of_level_c_is_refused_but_history_is_not(self) -> None:
        problems, _, _ = self.one('///|\n// Oracle (level C): the plain tier\ntest "x" { }\n')
        self.assertTrue(any("level C, which is refused" in problem for problem in problems))
        problems, _, _ = self.one(
            '///|\n// Oracle: level A. Before, the test was level C (a copy of the code).\ntest "x" { }\n'
        )
        self.assertEqual(problems, [])

    def test_a_comment_without_a_level_is_not_a_declaration(self) -> None:
        problems, _, _ = self.one('///|\n// the oracle is the standard\ntest "x" { }\n')
        self.assertEqual(len(problems), 1)

    def test_the_repository_passes(self) -> None:
        problems, declared, debt = check.check()
        self.assertEqual(problems, [])
        self.assertEqual(sum(debt.values()), check.DEBT_LIMIT)


if __name__ == "__main__":
    unittest.main()
