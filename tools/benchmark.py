#!/usr/bin/env python3
"""Run the unified Maremark benchmark packages and persist their JSONL events."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
EVENT_MARKER = "MAREMARK_JSONL="
ANALYSIS_MARKERS = (
    "MAREMARK_HOTSPOT=",
    "MAREMARK_TUNE=",
    "MAREMARK_CROSSOVER=",
    "MAREMARK_POLICY=",
)


@dataclass(frozen=True)
class BenchmarkCommand:
    package: str
    test_filter: str | None = None


BENCHMARKS: dict[str, tuple[BenchmarkCommand, ...]] = {
    "bin-float": (BenchmarkCommand("src/bench/bin_float"),),
    "decimal": (BenchmarkCommand("src/bench/decimal"),),
    "decimal-gda": (BenchmarkCommand("src/bench/decimal_gda"),),
    "ball-float": (BenchmarkCommand("src/bench/ball_float"),),
    "auto-tune": (
        BenchmarkCommand(
            "src/bench/bin_float",
            "auto tune binary square crossover",
        ),
    ),
    "elementary": (
        BenchmarkCommand(
            "src/bench/bin_float",
            "binary elementary core and full paths",
        ),
    ),
}
BENCHMARKS["all"] = tuple(
    command
    for suite in ("bin-float", "decimal", "decimal-gda", "ball-float")
    for command in BENCHMARKS[suite]
)


def benchmark_command(spec: BenchmarkCommand, target: str) -> list[str]:
    command = [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "test",
        spec.package,
        "--release",
        "--include-skipped",
        "--no-parallelize",
        "--target",
        target,
    ]
    if spec.test_filter is not None:
        command.extend(("--filter", spec.test_filter))
    return command


def extract_maremark_events(output: str) -> list[dict[str, object]]:
    events: list[dict[str, object]] = []
    for line in output.splitlines():
        marker_index = line.find(EVENT_MARKER)
        if marker_index < 0:
            continue
        encoded = line[marker_index + len(EVENT_MARKER) :]
        try:
            event = json.loads(encoded)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid Maremark JSONL event: {error.msg}") from error
        if not isinstance(event, dict):
            raise ValueError("Maremark JSONL event must be an object")
        if event.get("artifact_version") != "mmka_1":
            raise ValueError("unsupported Maremark artifact version")
        events.append(event)
    return events


def extract_analysis_lines(output: str) -> list[str]:
    return [
        line
        for line in output.splitlines()
        if any(marker in line for marker in ANALYSIS_MARKERS)
    ]


def run_benchmark_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def write_events(path: Path, events: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(event, sort_keys=True) + "\n" for event in events),
        encoding="utf-8",
    )


def write_analysis(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=sorted(BENCHMARKS))
    parser.add_argument("--target", choices=("native",), default="native")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    commands = [
        benchmark_command(spec, args.target) for spec in BENCHMARKS[args.suite]
    ]
    if args.dry_run:
        for command in commands:
            print(" ".join(command))
        return 0

    events: list[dict[str, object]] = []
    analysis_lines: list[str] = []
    for command in commands:
        completed = run_benchmark_command(command)
        if completed.stdout:
            print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
        if completed.returncode != 0:
            return completed.returncode
        try:
            events.extend(extract_maremark_events(completed.stdout))
            analysis_lines.extend(extract_analysis_lines(completed.stdout))
        except ValueError as error:
            print(f"benchmark artifact error: {error}", file=sys.stderr)
            return 1

    output = args.output or REPO_ROOT / ".tmp" / "bench" / f"{args.suite}.jsonl"
    analysis_output = output.with_suffix(".analysis.txt")
    write_events(output, events)
    write_analysis(analysis_output, analysis_lines)
    print(f"Maremark artifact: {output}")
    print(f"Maremark analysis: {analysis_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
