import tempfile
import unittest
from pathlib import Path
from unittest import mock

import itl_refinements
import run_itl_interpreter


class ItlGeneratedPhaseTest(unittest.TestCase):
    def test_a_phase_with_a_directory_runs_files_of_the_repository(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            corpus = root / "corpus"
            corpus.mkdir()
            (corpus / "sets.itl").touch()
            generated = root / "generated"
            generated.mkdir()
            (generated / "extra.itl").touch()
            config = {
                "phases": [
                    {"name": "sets", "include": ["sets.itl"]},
                    {
                        "name": "extra",
                        "directory": "generated",
                        "include": ["extra.itl"],
                        "operations": ["op"],
                    },
                ]
            }
            with mock.patch.object(run_itl_interpreter, "CONFIG", root / "stages.json"):
                phases = run_itl_interpreter.planned_phases(config, corpus, set())
        self.assertEqual([phase["name"] for phase in phases], ["sets", "extra"])
        self.assertEqual([path.name for path in phases[1]["files"]], ["extra.itl"])

    def test_the_official_aggregate_ignores_a_generated_phase(self) -> None:
        aggregate = {"phases": ["sets"], "expectedCases": 3}
        reports = [
            {"phase": "sets", "totalCases": 3},
            {"phase": "extra", "totalCases": 10},
        ]
        self.assertEqual(
            run_itl_interpreter.validate_official_aggregate(aggregate, reports), 3
        )


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


class RefinedPhaseTest(unittest.TestCase):
    SOURCE = (
        "testcase t {\n"
        "    sinRevBin [0.0,0.0] [3.0,3.5] = [0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1];\n"
        "    add [1.0,2.0] [3.0,4.0] = [4.0,6.0];\n"
        "}\n"
    )

    def refinement(self) -> itl_refinements.Refinement:
        return itl_refinements.Refinement(
            file="rev.itl",
            id="t:1",
            operation="sinRevBin",
            corpus="[0x1.921fb54442d18p+1,0x1.921fb54442d1ap+1]",
            refined="[0x1.921fb54442d18p+1,0x1.921fb54442d19p+1]",
            reason="test",
        )

    def test_a_refined_file_is_a_patched_copy_and_the_corpus_is_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / "corpus"
            corpus.mkdir()
            path = corpus / "rev.itl"
            path.write_text(self.SOURCE, encoding="utf-8")
            scratch = Path(directory) / "scratch"
            scratch.mkdir()
            phase = {"name": "trig", "files": [path], "operations": ["sinRevBin"]}
            files, applied = run_itl_interpreter.refined_files(phase, [self.refinement()], scratch)
            self.assertEqual(len(applied), 1)
            self.assertNotEqual(files[0], path)
            self.assertIn("0x1.921fb54442d19p+1", files[0].read_text(encoding="utf-8"))
            self.assertEqual(path.read_text(encoding="utf-8"), self.SOURCE)

    def test_a_phase_that_does_not_select_the_operation_keeps_the_corpus_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rev.itl"
            path.write_text(self.SOURCE, encoding="utf-8")
            phase = {"name": "other", "files": [path], "operations": ["add"]}
            files, applied = run_itl_interpreter.refined_files(phase, [self.refinement()], Path(directory))
            self.assertEqual((files, applied), ([path], []))

    def test_only_refined_cases_that_run_are_counted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rev.itl"
            path.write_text(self.SOURCE, encoding="utf-8")
            phase = {"name": "trig", "files": [path], "operations": ["sinRevBin"]}
            with mock.patch("run_itl_interpreter.subprocess.run") as run:
                run.return_value.returncode = 0
                run.return_value.stdout = '{"unsupportedIds": [], "diagnosticIds": []}'
                ran = run_itl_interpreter.run_phase(Path("itl"), phase, True, [self.refinement()])
                run.return_value.stdout = '{"unsupportedIds": ["t:1"], "diagnosticIds": []}'
                skipped = run_itl_interpreter.run_phase(Path("itl"), phase, False, [self.refinement()])
        self.assertEqual(ran["refinedCases"], 1)
        self.assertEqual(skipped["refinedCases"], 0)


if __name__ == "__main__":
    unittest.main()
