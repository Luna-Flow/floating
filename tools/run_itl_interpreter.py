#!/usr/bin/env python3

import argparse
import fnmatch
import json
import subprocess
import sys
import time
from pathlib import Path

import fetch_interval_corpora
from conformance_cli import build_backend, executable_path
from conformance_runtime import ensure_available, ordered_parallel_map
from conformance_ui import Console, Progress, SummaryRow, print_summary


REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG = REPO_ROOT / "testdata/interval/interpreter_stages.json"
MANIFEST = REPO_ROOT / "testdata/interval/corpora.json"
ITL_INTERPRETER = executable_path("itl")


def build() -> Path:
    return build_backend("itl")


def phase_operations(phase: dict) -> set[str]:
    operations = phase.get("operations", [])
    unique = set(operations)
    if len(unique) != len(operations):
        raise ValueError(f"phase repeats an operation: {phase['name']}")
    return unique


def validate_phase_routes(routes: dict[Path, list[tuple[str, set[str]]]]) -> None:
    for path, phases in routes.items():
        for index, (left_name, left_operations) in enumerate(phases):
            for right_name, right_operations in phases[index + 1 :]:
                if not left_operations or not right_operations:
                    raise ValueError(
                        "phase configuration re-runs every case in "
                        f"{path.name}: {left_name}, {right_name}"
                    )
                overlap = left_operations.intersection(right_operations)
                if overlap:
                    raise ValueError(
                        "phase configuration re-runs operations in "
                        f"{path.name}: {', '.join(sorted(overlap))}"
                    )


def planned_phases(config: dict, corpus: Path, selected: set[str]) -> list[dict]:
    files = sorted(corpus.glob("*.itl"))
    assigned = set()
    configured = config["phases"]
    configured_names = {phase["name"] for phase in configured}
    unknown = selected.difference(configured_names)
    if unknown:
        raise ValueError("unknown phase: " + ", ".join(sorted(unknown)))
    routes: dict[Path, list[tuple[str, set[str]]]] = {}
    planned = []
    for phase in configured:
        matched = [
            path
            for path in files
            if any(fnmatch.fnmatch(path.name, pattern) for pattern in phase["include"])
        ]
        assigned.update(matched)
        operations = phase_operations(phase)
        for path in matched:
            routes.setdefault(path, []).append((phase["name"], operations))
        if not selected or phase["name"] in selected:
            planned.append(
                {
                    "name": phase["name"],
                    "files": matched,
                    "operations": sorted(operations),
                }
            )
    remaining = set(files).difference(assigned)
    if remaining:
        raise ValueError("unassigned ITL files: " + ", ".join(path.name for path in remaining))
    validate_phase_routes(routes)
    return planned


def run_phase(executable: Path, phase: dict, strict_supported: bool) -> dict:
    command = [str(executable), "--backend", "itl"]
    if strict_supported:
        command.append("--strict-supported")
    for operation in phase["operations"]:
        command.extend(("--operation", operation))
    command.extend(str(path) for path in phase["files"])
    result = subprocess.run(command, cwd=REPO_ROOT, text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr or result.stdout)
    payload = json.loads(result.stdout)
    payload["phase"] = phase["name"]
    payload["files"] = len(phase["files"])
    payload["exitCode"] = result.returncode
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run staged ITF1788 conformance tests")
    parser.add_argument("--phase", action="append", default=[])
    parser.add_argument("--strict-supported", action="store_true")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.jobs <= 0:
            raise ValueError("--jobs must be positive")
        if args.smoke:
            phases = [
                {
                    "name": "smoke",
                    "files": [REPO_ROOT / "testdata/interval/smoke.itl"],
                    "operations": [],
                }
            ]
            revision = "committed-smoke"
        else:
            config = json.loads(CONFIG.read_text(encoding="utf-8"))
            manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
            spec = manifest["corpora"][config["corpus"]]
            corpus = REPO_ROOT / spec["destination"]
            fetch_result = ensure_available(
                is_ready=corpus.is_dir,
                fetcher=fetch_interval_corpora.main,
                fetch_args=[config["corpus"]],
                force=False,
                missing_message="ITF1788 corpus installation failed",
            )
            if fetch_result != 0:
                raise FileNotFoundError("ITF1788 corpus installation failed")
            phases = planned_phases(config, corpus, set(args.phase))
            revision = spec["revision"]
        if args.plan:
            for phase in phases:
                print(f"{phase['name']}: {len(phase['files'])} files")
            return 0
        executable = build()
        started = time.monotonic()
        phase_progress = Progress("interval/ITF1788 phases", len(phases), Console())
        reports = ordered_parallel_map(
            phases,
            args.jobs,
            lambda phase: run_phase(executable, phase, args.strict_supported),
            phase_progress,
            lambda phase: phase["name"],
        )
        exit_code = 1 if any(report["exitCode"] != 0 for report in reports) else 0
        phase_progress.finish(exit_code == 0)
        report = {
            "schemaVersion": 1,
            "runner": "staged-itf1788",
            "revision": revision,
            "phases": reports,
            "summary": {
                key: sum(phase[key] for phase in reports)
                for key in (
                    "totalCases",
                    "executableCases",
                    "passedCases",
                    "failedCases",
                    "unsupportedCases",
                    "diagnosticCases",
                )
            },
        }
        if getattr(args, "json", False):
            print(json.dumps(report, indent=2))
        else:
            summary = report["summary"]
            print_summary(
                "INTERVAL · IEEE 1788",
                f"ITF1788 revision={revision}",
                [
                    SummaryRow(
                        phase["phase"],
                        phase["passedCases"],
                        phase["executableCases"],
                        phase["failedCases"]
                        + (phase["unsupportedCases"] + phase["diagnosticCases"] if args.strict_supported else 0),
                        f"{phase['unsupportedCases']} unsupported",
                    )
                    for phase in reports
                ],
                summary["passedCases"],
                summary["executableCases"],
                0 if exit_code == 0 else 1,
                time.monotonic() - started,
            )
        return exit_code
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ITL interpreter runner failed: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
