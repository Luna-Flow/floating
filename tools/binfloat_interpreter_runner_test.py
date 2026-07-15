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
        self.assertEqual(spec["expectedCases"], 2088)


if __name__ == "__main__":
    unittest.main()
