#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run_dectest_interpreter.py")
SPEC = importlib.util.spec_from_file_location("dectest_runner", MODULE_PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class DecTestInterpreterRunnerTests(unittest.TestCase):
    def test_phase_selection_preserves_prior_file_claims(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["add.decTest", "ddAdd.decTest", "base.decTest"]:
                (root / name).write_text("", encoding="utf-8")
            config = {
                "phases": [
                    {"name": "arithmetic", "include": ["*Add.decTest"]},
                    {"name": "remaining", "include": ["*.decTest"]},
                ]
            }
            phases = RUNNER.plan_phases(config, root, {"remaining"})
            self.assertEqual([path.name for path in phases[0]["files"]], ["base.decTest"])

    def test_worker_command_uses_interpreter_shards(self):
        command = RUNNER.worker_command(
            Path("gda-expr"),
            [Path("one.decTest")],
            4,
            2,
            "a1..a9",
            True,
        )
        self.assertIn("--shard-count", command)
        self.assertIn("4", command)
        self.assertIn("--shard-index", command)
        self.assertIn("2", command)
        self.assertIn("--strict-supported", command)

    def test_unknown_phase_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "add.decTest").write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unknown phase"):
                RUNNER.plan_phases(
                    {"phases": [{"name": "core", "include": ["*.decTest"]}]},
                    root,
                    {"missing"},
                )

    def test_aggregate_sums_shards_without_multiplying_total(self):
        first = {
            "totalCases": 8,
            "diagnosticCases": 1,
            "legacyConditionCases": 0,
            "unsupportedCases": 0,
            "execution": {
                "executableCases": 3,
                "passedCases": 3,
                "failedCases": 0,
                "skippedCases": 1,
                "failedIds": [],
            },
            "worker": {"elapsedSeconds": 0.2},
        }
        second = {
            "totalCases": 8,
            "diagnosticCases": 0,
            "legacyConditionCases": 0,
            "unsupportedCases": 0,
            "execution": {
                "executableCases": 4,
                "passedCases": 3,
                "failedCases": 1,
                "skippedCases": 0,
                "failedIds": ["x7"],
            },
            "worker": {"elapsedSeconds": 0.3},
        }
        summary = RUNNER.aggregate_phase("core", [Path("a")], [first, second])
        self.assertEqual(summary["totalCases"], 8)
        self.assertEqual(summary["executableCases"], 7)
        self.assertEqual(summary["passedCases"], 6)
        self.assertEqual(summary["failedIds"], ["x7"])


if __name__ == "__main__":
    unittest.main()
