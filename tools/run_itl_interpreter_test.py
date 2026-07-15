import tempfile
import unittest
from pathlib import Path
from unittest import mock

import run_itl_interpreter


class ItlInterpreterPlanTest(unittest.TestCase):
    def make_corpus(self, root: Path, names: list[str]) -> Path:
        corpus = root / "corpus"
        corpus.mkdir()
        for name in names:
            (corpus / name).touch()
        return corpus

    def test_shared_file_operations_are_partitioned(self) -> None:
        config = {
            "phases": [
                {"name": "add", "include": ["elementary.itl"], "operations": ["add"]},
                {"name": "sub", "include": ["elementary.itl"], "operations": ["sub"]},
                {"name": "sets", "include": ["sets.itl"]},
            ]
        }
        with tempfile.TemporaryDirectory() as directory:
            phases = run_itl_interpreter.planned_phases(
                config,
                self.make_corpus(Path(directory), ["elementary.itl", "sets.itl"]),
                set(),
            )
        self.assertEqual([phase["name"] for phase in phases], ["add", "sub", "sets"])

    def test_unfiltered_shared_file_is_rejected(self) -> None:
        config = {
            "phases": [
                {"name": "all", "include": ["elementary.itl"]},
                {"name": "add", "include": ["elementary.itl"], "operations": ["add"]},
            ]
        }
        with tempfile.TemporaryDirectory() as directory:
            corpus = self.make_corpus(Path(directory), ["elementary.itl"])
            with self.assertRaisesRegex(ValueError, "re-runs every case"):
                run_itl_interpreter.planned_phases(config, corpus, set())

    def test_overlapping_shared_file_operation_is_rejected(self) -> None:
        config = {
            "phases": [
                {"name": "first", "include": ["elementary.itl"], "operations": ["add"]},
                {"name": "second", "include": ["elementary.itl"], "operations": ["add"]},
            ]
        }
        with tempfile.TemporaryDirectory() as directory:
            corpus = self.make_corpus(Path(directory), ["elementary.itl"])
            with self.assertRaisesRegex(ValueError, "re-runs operations"):
                run_itl_interpreter.planned_phases(config, corpus, set())

    def test_unknown_phase_is_rejected(self) -> None:
        config = {"phases": [{"name": "sets", "include": ["sets.itl"]}]}
        with tempfile.TemporaryDirectory() as directory:
            corpus = self.make_corpus(Path(directory), ["sets.itl"])
            with self.assertRaisesRegex(ValueError, "unknown phase: missing"):
                run_itl_interpreter.planned_phases(config, corpus, {"missing"})

    def test_phase_report_keeps_the_interpreter_exit_code(self) -> None:
        with mock.patch("run_itl_interpreter.subprocess.run") as run:
            run.return_value.returncode = 1
            run.return_value.stdout = '{"failedCases": 0}'
            payload = run_itl_interpreter.run_phase(
                Path("itl"),
                {"name": "unsupported", "files": [Path("unsupported.itl")], "operations": []},
                True,
            )
        self.assertEqual(payload["exitCode"], 1)

    def test_official_aggregate_requires_exact_case_count(self) -> None:
        aggregate = {"phases": ["sets", "elementary"], "expectedCases": 3}
        reports = [
            {"phase": "sets", "totalCases": 1},
            {"phase": "elementary", "totalCases": 2},
        ]
        self.assertEqual(
            run_itl_interpreter.validate_official_aggregate(aggregate, reports),
            3,
        )
        reports[1]["totalCases"] = 3
        with self.assertRaisesRegex(ValueError, "expected 3, got 4"):
            run_itl_interpreter.validate_official_aggregate(aggregate, reports)

    def test_official_aggregate_ignores_partial_phase_selection(self) -> None:
        aggregate = {"phases": ["sets", "elementary"], "expectedCases": 3}
        self.assertIsNone(
            run_itl_interpreter.validate_official_aggregate(
                aggregate, [{"phase": "sets", "totalCases": 1}]
            )
        )


if __name__ == "__main__":
    unittest.main()
