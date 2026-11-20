import unittest
from pathlib import Path

import native_test_timing as timing


class NativeTestTimingTests(unittest.TestCase):
    def test_only_test_files_are_selected(self) -> None:
        self.assertTrue(timing.is_test_file(Path("library/src/decimal/a_wbtest.mbt")))
        self.assertTrue(timing.is_test_file(Path("library/src/decimal/a_test.mbt")))
        self.assertFalse(timing.is_test_file(Path("library/src/decimal/a.mbt")))

    def test_repository_test_files_are_found(self) -> None:
        files = timing.test_files(timing.REPO_ROOT)
        self.assertTrue(files)
        self.assertTrue(all(timing.is_test_file(path) for path in files))
        scoped = timing.test_files(timing.REPO_ROOT, "library/src/decimal")
        self.assertTrue(scoped and set(scoped) < set(files))
        # Both modules are timed: the cross-package tests are in `tooling/src/consistency`.
        self.assertTrue(any("tooling/src/consistency" in str(path) for path in files))

    def test_command_builds_then_runs_one_file(self) -> None:
        path = timing.REPO_ROOT / "library/src/decimal/a_wbtest.mbt"
        build = timing.moon_command(path, build_only=True)
        run = timing.moon_command(path, build_only=False)
        self.assertEqual(build[-1], "--build-only")
        self.assertEqual(build[:-1], run)
        self.assertIn("library/src/decimal/a_wbtest.mbt", run)

    def test_total_line_is_parsed_from_the_last_match(self) -> None:
        text = "Total tests: 3, passed: 3, failed: 0.\nTotal tests: 9, passed: 8, failed: 1.\n"
        self.assertEqual(timing.parse_total(text), (9, 8, 1))
        self.assertIsNone(timing.parse_total("nothing"))

    def test_table_lists_the_slowest_first_with_shares(self) -> None:
        rows = [
            {"file": "a", "tests": 1, "seconds": 1.0},
            {"file": "b", "tests": 2, "seconds": 3.0},
            {"file": "c", "tests": 3, "seconds": 2.0},
        ]
        self.assertEqual([row["file"] for row in timing.slowest(rows, 2)], ["b", "c"])
        table = timing.format_table(rows, 2)
        self.assertIn("slowest 2 of 3 test files", table)
        self.assertLess(table.index("| b "), table.index("| c "))
        self.assertIn("50.0%", table)
        self.assertNotIn("| a ", table)
        self.assertNotIn(chr(0xB7), table)


if __name__ == "__main__":
    unittest.main()
