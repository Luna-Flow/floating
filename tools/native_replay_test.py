import unittest

import native_replay as nr

D = nr.UnitDigest


class CompareTest(unittest.TestCase):
    prev = {"a": D("o1", "n1", 10.0), "b": D("o2", "n2", 5.0)}

    def test_nothing_changed(self) -> None:
        self.assertEqual(nr.compare(self.prev, self.prev), ([], []))

    def test_a_test_file_edit_changes_only_the_old_digest_of_a_dependent(self) -> None:
        cur = {"a": D("o1", "n1", 10.0), "b": D("o2x", "n2", 5.0)}
        self.assertEqual(nr.compare(self.prev, cur), (["b"], []))

    def test_a_source_edit_changes_both(self) -> None:
        cur = {"a": D("o1x", "n1x", 10.0), "b": D("o2", "n2", 5.0)}
        self.assertEqual(nr.compare(self.prev, cur), (["a"], ["a"]))

    def test_a_new_unit_reruns(self) -> None:
        cur = {**self.prev, "c": D("o3", "n3", 1.0)}
        self.assertEqual(nr.compare(self.prev, cur), (["c"], ["c"]))

    def test_row_seconds_sum_the_units_that_rerun(self) -> None:
        cur = {"a": D("o1x", "n1", 10.0), "b": D("o2x", "n2x", 5.0)}
        row = nr.make_row("abcdef012345", "s", self.prev, cur)
        self.assertEqual((row.old_units, row.new_units, row.old_seconds, row.new_seconds), (2, 1, 15.0, 5.0))

    def test_table_has_a_total_line(self) -> None:
        rows = [nr.Row("abcdef012345", "s", 2, 1, 15.0, 5.0), nr.Row("123456abcdef", "t", 0, 0, 0.0, 0.0)]
        text = nr.format_table(rows)
        self.assertIn("| abcdef01 | s | 2 | 1 | 15.0 | 5.0 |", text)
        self.assertIn("| total, 2 changes | | 2 | 1 | 15.0 | 5.0 |", text)


if __name__ == "__main__":
    unittest.main()
