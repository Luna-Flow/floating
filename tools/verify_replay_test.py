import unittest

import code_fingerprint as cf
import incremental_test as fx
import verify_replay as vr
import incremental as inc


def snap(commit: str, result: dict[str, str], pre: dict[str, str] | None = None, startup: str = "s", frames: dict[str, str] | None = None) -> vr.Snapshot:
    return vr.Snapshot(commit, "subject " + commit, pre or {u: "p" for u in result}, result, startup, frames or {"testfloat": "f", "mpfr": "f"}, False, False)


class ClassifyTests(unittest.TestCase):
    def test_kinds_of_change(self) -> None:
        base = snap("a", {"u1": "k1", "u2": "k2"})
        self.assertEqual(vr.classify(base, snap("b", {"u1": "k1", "u2": "k2"})), "none")
        self.assertEqual(vr.classify(base, snap("b", {"u1": "k1", "u2": "x"})), "arm")
        self.assertEqual(vr.classify(base, snap("b", {"u1": "x", "u2": "k2"}, frames={"testfloat": "g", "mpfr": "f"})), "frame")
        self.assertEqual(vr.classify(base, snap("b", {"u1": "x", "u2": "k2"}, frames={"testfloat": "f", "mpfr": "g"})), "mpfr")
        # the MPFR frame changed and the start-up closure too: every unit reruns, the cause is the start-up code
        self.assertEqual(vr.classify(base, snap("b", {"u1": "x", "u2": "y"}, startup="t", frames={"testfloat": "f", "mpfr": "g"})), "start-up")
        self.assertEqual(vr.classify(base, snap("b", {"u1": "x", "u2": "y"}, startup="t")), "start-up")
        # a change in the frame wins over one in the start-up code: it reruns the units whatever the attribution
        self.assertEqual(vr.classify(base, snap("b", {"u1": "x", "u2": "y"}, startup="t", frames={"testfloat": "g", "mpfr": "f"})), "frame")

    def test_changed_units_and_new_units(self) -> None:
        self.assertEqual(vr.changed_units({"a": "1", "b": "2"}, {"a": "1", "b": "3", "c": "4"}), ["b", "c"])

    def test_time_estimate_sums_the_changed_units(self) -> None:
        self.assertEqual(vr.estimate_seconds(["a", "b", "z"], {"a": 1.5, "b": 2.0}), 3.5)

    def test_a_row_counts_testfloat_and_mpfr_units_apart(self) -> None:
        row = vr.make_row(snap("a", {"t": "1", "m.json": "1"}), snap("b", {"t": "2", "m.json": "2"}), {"t": 10.0, "m.json": 1.0})
        self.assertEqual((row.units, row.testfloat, row.mpfr, row.seconds), (2, 1, 1, 11.0))

    def test_the_table_has_a_row_per_commit_and_a_summary_per_kind(self) -> None:
        rows = [vr.make_row(snap("a", {"t": "1"}), snap("b", {"t": "1"}), {"t": 5.0}), vr.make_row(snap("b", {"t": "1"}), snap("c", {"t": "2"}), {"t": 5.0})]
        text = vr.format_table(rows, 1, 5.0)
        self.assertEqual(text.count("\n| none |") + text.count("\n| arm |"), 2)
        self.assertIn("100.0 %", text)
        self.assertIn("| frame | 0 |", text)


class SnapshotTests(unittest.TestCase):
    def units(self) -> dict[str, tuple[inc.UnitSpec, list[str]]]:
        return {
            "add_unit": (inc.UnitSpec("add_unit", "testfloat", "in", "a"), ["add"]),
            "sub_unit": (inc.UnitSpec("sub_unit", "testfloat", "in2", "a"), ["sub"]),
            "m.json": (inc.UnitSpec("m.json", "mpfr", "in3", "a"), []),
        }

    def test_an_arm_change_is_an_arm_change_for_its_units_only(self) -> None:
        a = vr.snapshot_keys(cf.parse_program(fx.program_text()), self.units(), "a", "s", False)
        b = vr.snapshot_keys(cf.parse_program(fx.program_text(add_body="return a + b + 0;")), self.units(), "b", "s", False)
        self.assertEqual(vr.changed_units(a.result, b.result), ["add_unit"])
        self.assertEqual(vr.classify(a, b), "arm")

    def test_an_initialiser_change_is_a_start_up_change_of_every_unit(self) -> None:
        a = vr.snapshot_keys(cf.parse_program(fx.program_text(init_value=1)), self.units(), "a", "s", False)
        b = vr.snapshot_keys(cf.parse_program(fx.program_text(init_value=2)), self.units(), "b", "s", False)
        self.assertEqual(len(vr.changed_units(a.result, b.result)), 3)
        self.assertEqual(vr.classify(a, b), "start-up")

    def test_a_build_without_arms_is_replayed_coarsely(self) -> None:
        text = fx.program_text().replace("arm__add", "plain__add").replace("arm__sub", "plain__sub")
        snapshot = vr.snapshot_keys(cf.parse_program(text), self.units(), "a", "s", False)
        self.assertTrue(snapshot.coarse)
        changed = vr.snapshot_keys(cf.parse_program(text.replace("return a + b;", "return a + b + 0;")), self.units(), "b", "s", False)
        self.assertEqual(set(vr.changed_units(snapshot.result, changed.result)), {"add_unit", "sub_unit"})


if __name__ == "__main__":
    unittest.main()
