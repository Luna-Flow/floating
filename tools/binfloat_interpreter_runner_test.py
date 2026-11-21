#!/usr/bin/env python3

import importlib.util
import hashlib
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


MODULE_PATH = Path(__file__).with_name("run_binfloat_interpreter.py")
SPEC = importlib.util.spec_from_file_location("binfloat_runner", MODULE_PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class BinFloatInterpreterRunnerTests(unittest.TestCase):
    def test_task_matrix_keeps_both_tininess_modes_distinct(self):
        arguments = SimpleNamespace(
            formats=["f16"],
            operations=["mul"],
            roundings=["rnear_even"],
            tininess_modes=["after", "before"],
            level=1,
            seed=1,
        )
        tasks = RUNNER.task_matrix(arguments)
        self.assertEqual(len(tasks), 2)
        self.assertEqual(
            [task["tininess"] for task in tasks], ["after", "before"]
        )

    def test_task_matrix_skips_irrelevant_rounding_tininess_and_exact_axes(self):
        arguments = SimpleNamespace(
            formats=["f64"],
            operations=["mulAdd", "rem", "roundToInt", "to_i32", "le_quiet"],
            roundings=["rnear_even", "rmin"],
            tininess_modes=["after", "before"],
            level=1,
            seed=1,
        )
        counts = {}
        for task in RUNNER.task_matrix(arguments):
            counts[task["operation"]] = counts.get(task["operation"], 0) + 1
        # mulAdd: 2 roundings x 2 tininess; rem/le_quiet: one task;
        # roundToInt/to_i32: 2 roundings x {notexact, exact}.
        self.assertEqual(
            counts,
            {"mulAdd": 4, "rem": 1, "roundToInt": 4, "to_i32": 4, "le_quiet": 1},
        )

    def test_conversion_tasks_skip_the_source_format_and_the_rounding_of_exact_ones(self):
        arguments = SimpleNamespace(
            formats=["f16", "f64"],
            operations=["to_f16", "to_f32", "to_f128"],
            roundings=["rnear_even", "rmin"],
            tininess_modes=["after", "before"],
            level=1,
            seed=1,
        )
        tasks = RUNNER.task_matrix(arguments)
        functions = {}
        for task in tasks:
            functions[task["function"]] = functions.get(task["function"], 0) + 1
        # f16_to_f16 and f64_to_f16 exist only as f64_to_f16 (no identical pair);
        # a widening conversion is exact: one task; a narrowing one: 2 roundings x 2 tininess.
        self.assertEqual(
            functions,
            {
                "f16_to_f32": 1,
                "f16_to_f128": 1,
                "f64_to_f16": 4,
                "f64_to_f32": 4,
                "f64_to_f128": 1,
            },
        )

    def test_exact_tasks_pass_exact_to_generator_and_interpreter(self):
        task = {
            "function": "f32_to_i64",
            "operation": "to_i64",
            "rounding": "rminMag",
            "tininess": "after",
            "exact": True,
            "level": 1,
            "seed": 1,
        }
        self.assertIn("-exact", RUNNER.testfloat_generator_command(task))
        self.assertIn(
            "--exact", RUNNER.testfloat_interpreter_command(task, Path("v"))
        )
        self.assertIn("-exact-", RUNNER.task_name(task))
        task["exact"] = False
        self.assertIn("-notexact", RUNNER.testfloat_generator_command(task))
        self.assertNotIn(
            "--exact", RUNNER.testfloat_interpreter_command(task, Path("v"))
        )

    def test_chunk_merge_preserves_global_failure_line_numbers(self):
        task = {"function": "f16_mul"}
        aggregate = {
            "totalCases": 0,
            "selectedCases": 0,
            "passedCases": 0,
            "failedCases": 0,
            "failedIds": [],
            "chunks": 0,
        }
        payload = {
            "totalCases": 3,
            "selectedCases": 3,
            "passedCases": 2,
            "failedCases": 1,
            "failedIds": ["f16_mul:2"],
        }
        RUNNER.merge_testfloat_chunk(aggregate, payload, task, 100, 3)
        self.assertEqual(aggregate["totalCases"], 3)
        self.assertEqual(aggregate["selectedCases"], 3)
        self.assertEqual(aggregate["passedCases"], 2)
        self.assertEqual(aggregate["failedIds"], ["f16_mul:102"])
        self.assertEqual(aggregate["chunks"], 1)

    def test_chunk_merge_rejects_partial_interpreter_execution(self):
        aggregate = {
            "totalCases": 0,
            "selectedCases": 0,
            "passedCases": 0,
            "failedCases": 0,
            "failedIds": [],
            "chunks": 0,
        }
        payload = {
            "totalCases": 2,
            "selectedCases": 1,
            "passedCases": 1,
            "failedCases": 0,
            "failedIds": [],
        }
        with self.assertRaisesRegex(RuntimeError, "did not execute every"):
            RUNNER.merge_testfloat_chunk(
                aggregate,
                payload,
                {
                    "function": "f16_add",
                    "rounding": "rnear_even",
                    "tininess": "after",
                    "level": 1,
                },
                0,
                2,
            )

    def test_fetch_artifacts_uses_binary_fetcher_directly(self):
        with mock.patch.object(RUNNER, "artifacts_ready", side_effect=[False, True]):
            with mock.patch.object(
                RUNNER.fetch_binfloat_corpora, "main", return_value=0
            ) as fetch:
                RUNNER.fetch_artifacts({}, False)
        fetch.assert_called_once_with([])

    def test_smoke_manifest_entry_becomes_a_concrete_task(self):
        task = RUNNER.smoke_task(
            {
                "function": "f16_sqrt",
                "rounding": "rnear_even",
                "tininess": "after",
                "expectedCases": 12,
            }
        )
        self.assertEqual(task["function"], "f16_sqrt")
        self.assertEqual(task["rounding"], "rnear_even")
        self.assertEqual(task["tininess"], "after")
        self.assertEqual(task["level"], 1)
        self.assertEqual(task["seed"], 1)

    def test_elementary_mpfr_corpus_is_hash_pinned(self):
        manifest = RUNNER.load_json(RUNNER.DEFAULT_MANIFEST)
        spec = manifest["mpfrCorpora"]["mpfr-4.2.2-elementary"]
        path = RUNNER.repo_path(spec["path"])
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertEqual(digest, spec["sha256"])
        self.assertEqual(spec["expectedCases"], 1740)

    def test_wide_logarithm_mpfr_corpus_is_hash_pinned(self):
        manifest = RUNNER.load_json(RUNNER.DEFAULT_MANIFEST)
        spec = manifest["mpfrCorpora"]["mpfr-4.2.2-ln-wide"]
        path = RUNNER.repo_path(spec["path"])
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), spec["sha256"])
        self.assertEqual(spec["expectedCases"], 3040)
        rows = [
            line.split()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")
        ]
        self.assertEqual(len(rows), 3040)
        precisions = {int(row[1]) for row in rows}
        # both sides of the ln kernel thresholds at 768 and 1152 working bits
        # (result precision + 64): 704 and 1088
        for precision in (320, 640, 688, 700, 704, 720, 768, 1072, 1088, 1104, 1152):
            self.assertIn(precision, precisions)
        self.assertEqual({row[0] for row in rows}, {"ln", "log2", "log10", "log1p"})

    def test_decimal_string_mpfr_corpora_are_hash_pinned(self):
        manifest = RUNNER.load_json(RUNNER.DEFAULT_MANIFEST)
        expected = {
            "mpfr-4.2.2-strtofr": 3699,
            "mpfr-4.2.2-decimal-output": 2688,
        }
        for name, cases in expected.items():
            spec = manifest["mpfrCorpora"][name]
            path = RUNNER.repo_path(spec["path"])
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(digest, spec["sha256"], name)
            self.assertEqual(spec["expectedCases"], cases, name)
            rows = [
                line
                for line in path.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("#")
            ]
            self.assertEqual(len(rows), cases, name)
        smoke = RUNNER.load_json(RUNNER.DEFAULT_SMOKE_MANIFEST)
        smoke_paths = {entry["path"]: entry["expectedCases"] for entry in smoke["mpfr"]}
        for name, cases in expected.items():
            spec = manifest["mpfrCorpora"][name]
            self.assertEqual(smoke_paths[spec["path"]], cases, name)

    def test_chunk_merge_collects_the_arms_of_every_chunk_once(self):
        task = {"function": "f16_mul"}
        aggregate = {
            "totalCases": 0, "selectedCases": 0, "passedCases": 0, "failedCases": 0,
            "failedIds": [], "chunks": 0, "arms": [],
        }
        payload = {"totalCases": 1, "selectedCases": 1, "passedCases": 1, "failedCases": 0, "failedIds": [], "arms": ["mul"]}
        RUNNER.merge_testfloat_chunk(aggregate, payload, task, 0, 1)
        RUNNER.merge_testfloat_chunk(aggregate, payload, task, 1, 1)
        self.assertEqual(aggregate["arms"], ["mul"])

    def test_testfloat_unit_names_the_generator_and_the_interpreter_arguments(self):
        task = {
            "function": "f16_add", "operation": "add", "rounding": "rnear_even",
            "tininess": "after", "exact": False, "level": 1, "seed": 1,
        }
        unit = RUNNER.testfloat_unit(task, "abc")
        self.assertEqual(unit.frontend, "testfloat")
        self.assertIn("testfloat_gen:abc:", unit.input_id)
        self.assertIn("-level 1 -seed 1", unit.input_id)
        self.assertIn("--function f16_add", unit.args)
        self.assertNotIn(str(RUNNER.TESTFLOAT_INTERPRETER), unit.args)
        other = RUNNER.testfloat_unit({**task, "rounding": "rmax"}, "abc")
        self.assertNotEqual((unit.input_id, unit.args), (other.input_id, other.args))

    def test_the_incremental_report_separates_executed_from_reused_units(self):
        import contextlib
        import io

        passed = {"passedCases": 10, "totalCases": 10, "failedCases": 0}
        outcomes = [
            RUNNER.incremental.Outcome("a", "ran", dict(passed)),
            RUNNER.incremental.Outcome("b", "reused", dict(passed), "c0ffee"),
            RUNNER.incremental.Outcome("c", "sampled", dict(passed), "c0ffee"),
        ]
        report = {
            "testfloat": {"tasks": [], "passedCases": 30, "totalCases": 30, "failedCases": 0},
            "mpfr": [],
            "summary": {"passedCases": 30, "totalCases": 30, "failedCases": 0, "failedIds": [], "elapsedSeconds": 1.0},
        }
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            RUNNER.print_text(report, outcomes)
        text = buffer.getvalue()
        self.assertIn("reused, not executed", text)
        self.assertIn("20/20 passed", text)  # the total counts what was executed (ran + sampled)
        self.assertIn("TOTAL executed (reused units not included)", text)
        self.assertNotIn("30/30", text)

    def test_an_interpreter_crash_is_a_failure_of_its_unit_in_an_incremental_run(self):
        error = RuntimeError("MPFR interpreter failed (-6)")
        payload = RUNNER.crash_payload(error, "mpfr")
        self.assertEqual(payload["failedCases"], 1)
        self.assertEqual(payload["frontend"], "mpfr")
        with mock.patch.object(RUNNER, "run_mpfr_path", side_effect=error):
            self.assertEqual(RUNNER.guarded_mpfr_path(Path("x"), 1, Path("o"), "n.json")["failedCases"], 1)
        with mock.patch.object(RUNNER, "run_testfloat_task", side_effect=error):
            self.assertEqual(RUNNER.guarded_testfloat_task({"function": "f"}, Path("o"), 1)["failedCases"], 1)

    def test_a_commit_is_shortened_with_its_dirty_mark(self):
        self.assertEqual(RUNNER.short_commit("0123456789abcdef"), "0123456789")
        self.assertEqual(RUNNER.short_commit("0123456789abcdef+dirty"), "0123456789+dirty")


if __name__ == "__main__":
    unittest.main()
