#!/usr/bin/env python3

import argparse
import fnmatch
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import fetch_interval_corpora
import itl_refinements
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
        # a phase with a "directory" runs files of this repository (testdata/interval/<directory>),
        # not of the pinned corpus: generated cases of our own, counted apart from the corpus
        directory = phase.get("directory")
        candidates = (
            sorted((CONFIG.parent / directory).glob("*.itl")) if directory else files
        )
        matched = [
            path
            for path in candidates
            if any(fnmatch.fnmatch(path.name, pattern) for pattern in phase["include"])
        ]
        if directory:
            if not matched:
                raise ValueError(f"phase {phase['name']} matches no file in {directory}")
        else:
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


def refined_files(
    phase: dict,
    refinements: list[itl_refinements.Refinement],
    directory: Path,
) -> tuple[list[Path], list[itl_refinements.Refinement]]:
    """The files of a phase, those with refined cases replaced by patched copies
    in `directory`, and the refinements applied to them.

    A refined case is run against the refined value, not against the corpus
    value; the planner has already checked that the refined value lies inside
    the corpus value. A refinement counts for the phase that selects its
    operation."""
    operations = set(phase["operations"])
    files: list[Path] = []
    applied: list[itl_refinements.Refinement] = []
    for path in phase["files"]:
        applicable = [
            refinement
            for refinement in refinements
            if refinement.file == path.name
            and (not operations or refinement.operation in operations)
        ]
        if not applicable:
            files.append(path)
            continue
        patched = directory / path.name
        patched.write_text(
            itl_refinements.apply(path.read_text(encoding="utf-8"), applicable),
            encoding="utf-8",
        )
        files.append(patched)
        applied.extend(applicable)
    return files, applied


def run_phase(
    executable: Path,
    phase: dict,
    strict_supported: bool,
    refinements: list[itl_refinements.Refinement] | None = None,
) -> dict:
    command = [str(executable), "--backend", "itl"]
    if strict_supported:
        command.append("--strict-supported")
    for operation in phase["operations"]:
        command.extend(("--operation", operation))
    with tempfile.TemporaryDirectory() as directory:
        files, applied = refined_files(phase, refinements or [], Path(directory))
        command.extend(str(path) for path in files)
        result = subprocess.run(command, cwd=REPO_ROOT, text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr or result.stdout)
    payload = json.loads(result.stdout)
    payload["phase"] = phase["name"]
    payload["files"] = len(phase["files"])
    payload["exitCode"] = result.returncode
    # only a refined case that runs counts: an unsupported one is not run
    not_run = set(payload.get("unsupportedIds", [])) | set(payload.get("diagnosticIds", []))
    payload["refinedCases"] = sum(1 for r in applied if r.id not in not_run)
    return payload


def validate_official_aggregate(
    aggregate: dict | None, reports: list[dict]
) -> int | None:
    if aggregate is None:
        return None
    phases = aggregate.get("phases")
    expected_cases = aggregate.get("expectedCases")
    if (
        not isinstance(phases, list)
        or not phases
        or not all(isinstance(name, str) and name for name in phases)
        or len(set(phases)) != len(phases)
        or isinstance(expected_cases, bool)
        or not isinstance(expected_cases, int)
        or expected_cases <= 0
    ):
        raise ValueError("invalid officialAggregate configuration")
    # the generated phases (with a directory of their own) are not part of the aggregate
    official = [report for report in reports if report["phase"] in set(phases)]
    selected = {report["phase"] for report in official}
    if selected != set(phases):
        return None
    actual_cases = sum(report["totalCases"] for report in official)
    if actual_cases != expected_cases:
        raise ValueError(
            "official ITF1788 aggregate mismatch: "
            f"expected {expected_cases}, got {actual_cases}"
        )
    return expected_cases


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
        refinements: list[itl_refinements.Refinement] = []
        if args.smoke:
            phases = [
                {
                    "name": "smoke",
                    "files": [REPO_ROOT / "testdata/interval/smoke.itl"],
                    "operations": [],
                }
            ]
            revision = "committed-smoke"
            official_aggregate = None
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
            official_aggregate = config.get("officialAggregate")
            refinement_file = config.get("refinements")
            if refinement_file is not None:
                refinements = itl_refinements.load(CONFIG.parent / refinement_file)
                itl_refinements.validate(
                    refinements, itl_refinements.corpus_statements(corpus)
                )
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
            lambda phase: run_phase(
                executable, phase, args.strict_supported, refinements
            ),
            phase_progress,
            lambda phase: phase["name"],
        )
        expected_official_cases = validate_official_aggregate(
            official_aggregate, reports
        )
        exit_code = 1 if any(report["exitCode"] != 0 for report in reports) else 0
        phase_progress.finish(exit_code == 0)
        report = {
            "schemaVersion": 1,
            "runner": "staged-itf1788",
            "revision": revision,
            "expectedOfficialCases": expected_official_cases,
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
                    "refinedCases",
                )
            },
        }
        if getattr(args, "json", False):
            print(json.dumps(report, indent=2))
        else:
            summary = report["summary"]
            print_summary(
                "INTERVAL: IEEE 1788",
                f"ITF1788 revision={revision}",
                [
                    SummaryRow(
                        phase["phase"],
                        phase["passedCases"],
                        phase["executableCases"],
                        phase["failedCases"]
                        + (phase["unsupportedCases"] + phase["diagnosticCases"] if args.strict_supported else 0),
                        f"{phase['unsupportedCases']} unsupported"
                        + (
                            f", {phase['refinedCases']} refined"
                            if phase["refinedCases"]
                            else ""
                        ),
                    )
                    for phase in reports
                ],
                summary["passedCases"],
                summary["executableCases"],
                0 if exit_code == 0 else 1,
                time.monotonic() - started,
            )
            if summary["refinedCases"]:
                print(
                    f"refined: {summary['refinedCases']:,} of {summary['executableCases']:,} "
                    "executed cases run against a value inside the corpus value "
                    "(testdata/interval/interpreter_refinements.json)"
                )
        return exit_code
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ITL interpreter runner failed: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
