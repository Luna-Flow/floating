import unittest

import native_mutation as nm

DRY = {
    "interval": "moonc build-package ./library/src/def/a.mbt -pkg d\nmoonc build-package ./library/src/interval/b.mbt ./library/src/interval/b_wbtest.mbt -whitebox-test\n",
    "decimal": "moonc build-package ./library/src/def/a.mbt ./library/src/interval/b.mbt -pkg x\nmoonc build-package ./library/src/decimal/c_wbtest.mbt -whitebox-test\n",
}


class OracleTest(unittest.TestCase):
    def test_a_source_is_named_by_the_builds_that_compile_it(self) -> None:
        self.assertEqual(nm.expected_run("library/src/def/a.mbt", DRY), {"interval", "decimal"})
        self.assertEqual(nm.expected_run("library/src/interval/b.mbt", DRY), {"interval", "decimal"})

    def test_a_test_file_is_named_only_by_its_own_package_build(self) -> None:
        self.assertEqual(nm.expected_run("library/src/interval/b_wbtest.mbt", DRY), {"interval"})

    def test_a_file_that_is_not_a_source_counts_every_unit_that_compiles_its_directory(self) -> None:
        self.assertEqual(nm.expected_run("library/src/def/moon.pkg", DRY), {"interval", "decimal"})
        self.assertEqual(nm.expected_run("library/src/decimal/moon.pkg", DRY), {"decimal"})

    def test_a_file_outside_every_package_is_in_no_build(self) -> None:
        self.assertEqual(nm.expected_run("doc/manual/verification.md", DRY), set())

    def test_a_prefix_of_a_path_is_not_a_match(self) -> None:
        self.assertEqual(nm.expected_run("library/src/interval/b.mbt", {"u": "x ./library/src/interval/b.mbt.bak y"}), set())


class JudgeTest(unittest.TestCase):
    def test_equal_sets_hold(self) -> None:
        self.assertEqual(nm.judge("f", {"a"}, {"a"}, None, False), [])

    def test_too_coarse_and_too_fine_are_named(self) -> None:
        self.assertIn("too coarse", nm.judge("f", {"a", "b"}, {"a"}, None, False)[0])
        self.assertIn("too fine", nm.judge("f", {"a"}, {"a", "b"}, None, False)[0])

    def test_a_behavioural_row_needs_a_failing_stage(self) -> None:
        self.assertEqual(len(nm.judge("f", {"a"}, {"a"}, 0, True)), 1)
        self.assertEqual(nm.judge("f", {"a"}, {"a"}, 1, True), [])

    def test_table(self) -> None:
        row = {"name": "n", "kind": "k", "ran": 1, "expected": 1, "stage": "failed", "verdict": "held"}
        self.assertIn("| n | k | 1 | 1 | failed | held |", nm.format_table([row]))


if __name__ == "__main__":
    unittest.main()
