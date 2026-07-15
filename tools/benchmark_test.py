from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import benchmark


class BenchmarkDispatcherTests(unittest.TestCase):
    def test_command_targets_unified_bench_package(self) -> None:
        command = benchmark.benchmark_command(
            benchmark.BenchmarkCommand("src/bench/bin_float", "auto tune"),
            "native",
        )
        self.assertEqual(command[:4], ["sh", "tools/run_moon_clean_exec.sh", "test", "src/bench/bin_float"])
        self.assertIn("--release", command)
        self.assertEqual(command[-2:], ["--filter", "auto tune"])

    def test_extracts_versioned_maremark_events(self) -> None:
        event = {"artifact_version": "mmka_1", "type": "observation"}
        output = "noise\nMAREMARK_JSONL=" + json.dumps(event) + "\n"
        self.assertEqual(benchmark.extract_maremark_events(output), [event])

    def test_extracts_tuning_and_hotspot_analysis(self) -> None:
        output = "\n".join(
            (
                "noise",
                "MAREMARK_HOTSPOT=decimal/add/0 core_pct=12",
                "MAREMARK_POLICY=lookup case=square lookup=4:mul,8:square",
            )
        )
        self.assertEqual(
            benchmark.extract_analysis_lines(output),
            [
                "MAREMARK_HOTSPOT=decimal/add/0 core_pct=12",
                "MAREMARK_POLICY=lookup case=square lookup=4:mul,8:square",
            ],
        )

    def test_rejects_unknown_artifact_version(self) -> None:
        output = 'MAREMARK_JSONL={"artifact_version":"future"}'
        with self.assertRaisesRegex(ValueError, "artifact version"):
            benchmark.extract_maremark_events(output)

    def test_main_runs_suite_and_writes_jsonl(self) -> None:
        event = {"artifact_version": "mmka_1", "type": "summary"}
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "MAREMARK_JSONL="
                + json.dumps(event)
                + "\nMAREMARK_TUNE=square/8 candidate=square\n"
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.jsonl"
            with patch.object(benchmark, "run_benchmark_command", return_value=completed):
                self.assertEqual(
                    benchmark.main(["ball-float", "--output", str(output)]),
                    0,
                )
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), event)
            self.assertEqual(
                output.with_suffix(".analysis.txt").read_text(encoding="utf-8"),
                "MAREMARK_TUNE=square/8 candidate=square\n",
            )

    def test_dry_run_does_not_execute(self) -> None:
        with patch.object(benchmark, "run_benchmark_command") as run:
            self.assertEqual(benchmark.main(["decimal", "--dry-run"]), 0)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
