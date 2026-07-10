#!/usr/bin/env python3

import argparse
import concurrent.futures
import fnmatch
import json
import os
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = REPO_ROOT / "testdata/decimal/interpreter_stages.json"
DEFAULT_MANIFEST = REPO_ROOT / "testdata/decimal/corpora.json"
DEFAULT_OUTPUT = REPO_ROOT / ".tmp/dectest-interpreter"
DEFAULT_EXECUTABLE = (
    REPO_ROOT / "_build/native/release/build/gda_expr_cli/gda_expr_cli.exe"
)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_path(value: str) -> Path:
    path = (REPO_ROOT / value).resolve()
    if path != REPO_ROOT and REPO_ROOT not in path.parents:
        raise ValueError(f"path escapes repository: {value}")
    return path


def resolve_corpus(config: dict, manifest: dict, override: str) -> tuple[str, Path]:
    name = override or config.get("corpus", "official")
    try:
        return name, repo_path(manifest["corpora"][name]["destination"])
    except KeyError as error:
        raise ValueError(f"unknown configured corpus: {name}") from error


def installed_corpus_ready(corpus: Path, spec: dict) -> bool:
    stamp_path = corpus / ".corpus.json"
    if not corpus.is_dir() or not stamp_path.is_file():
        return False
    try:
        stamp = load_json(stamp_path)
    except (OSError, ValueError, json.JSONDecodeError):
        return False
    files = list(corpus.glob("*.decTest"))
    return (
        stamp.get("url") == spec["url"]
        and stamp.get("sha256") == spec["sha256"]
        and stamp.get("decTestFiles") == spec["expectedDecTestFiles"]
        and len(files) == spec["expectedDecTestFiles"]
    )


def plan_phases(config: dict, corpus: Path, selected: set[str]) -> list[dict]:
    files = sorted(corpus.glob("*.decTest"), key=lambda path: path.name.lower())
    remaining = set(files)
    planned = []
    configured_names = {phase["name"] for phase in config.get("phases", [])}
    unknown = selected - configured_names
    if unknown:
        raise ValueError("unknown phase: " + ", ".join(sorted(unknown)))
    for phase in config.get("phases", []):
        name = phase["name"]
        patterns = phase.get("include", ["*.decTest"])
        matched = [
            path
            for path in files
            if path in remaining
            and any(fnmatch.fnmatch(path.name.lower(), pattern.lower()) for pattern in patterns)
        ]
        for path in matched:
            remaining.remove(path)
        if not selected or name in selected:
            planned.append({"name": name, "files": matched})
    if remaining:
        names = ", ".join(path.name for path in sorted(remaining))
        raise ValueError(f"stage configuration leaves files unassigned: {names}")
    return planned


def build_interpreter(executable: Path) -> None:
    command = [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "run",
        "--release",
        "--target",
        "native",
        "--build-only",
        "src/gda_expr_cli",
    ]
    result = subprocess.run(command, cwd=REPO_ROOT)
    if result.returncode != 0:
        raise RuntimeError("failed to build GDA interpreter")
    if not executable.is_file():
        raise RuntimeError(f"interpreter executable was not produced: {executable}")


def worker_command(
    executable: Path,
    files: list[Path],
    shard_count: int,
    shard_index: int,
    cases: str,
    strict_supported: bool,
) -> list[str]:
    command = [
        str(executable),
        "--json",
        "--shard-count",
        str(shard_count),
        "--shard-index",
        str(shard_index),
    ]
    if cases:
        command.extend(["--cases", cases])
    if strict_supported:
        command.append("--strict-supported")
    command.extend(str(path) for path in files)
    return command


def run_worker(
    phase: str,
    executable: Path,
    files: list[Path],
    shard_count: int,
    shard_index: int,
    cases: str,
    strict_supported: bool,
    output_dir: Path,
) -> dict:
    command = worker_command(
        executable, files, shard_count, shard_index, cases, strict_supported
    )
    started = time.monotonic()
    result = subprocess.run(command, cwd=REPO_ROOT, text=True, capture_output=True)
    elapsed = time.monotonic() - started
    shard_path = output_dir / phase / f"shard-{shard_index:03d}.json"
    shard_path.parent.mkdir(parents=True, exist_ok=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(
            f"{phase} shard {shard_index} failed to run ({result.returncode}):\n{result.stderr}{result.stdout}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"{phase} shard {shard_index} returned invalid JSON:\n{result.stdout}\n{result.stderr}"
        ) from error
    payload["worker"] = {
        "phase": phase,
        "shardIndex": shard_index,
        "elapsedSeconds": round(elapsed, 3),
        "exitCode": result.returncode,
    }
    shard_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def aggregate_phase(name: str, files: list[Path], shards: list[dict]) -> dict:
    executions = [payload["execution"] for payload in shards]
    failed_ids = []
    for execution in executions:
        failed_ids.extend(execution.get("failedIds", []))
    return {
        "name": name,
        "files": len(files),
        "shards": len(shards),
        "totalCases": max((payload.get("totalCases", 0) for payload in shards), default=0),
        "selectedCases": sum(execution.get("executableCases", 0) + execution.get("skippedCases", 0) for execution in executions),
        "executableCases": sum(execution.get("executableCases", 0) for execution in executions),
        "passedCases": sum(execution.get("passedCases", 0) for execution in executions),
        "failedCases": sum(execution.get("failedCases", 0) for execution in executions),
        "skippedCases": sum(execution.get("skippedCases", 0) for execution in executions),
        "diagnosticCases": sum(payload.get("diagnosticCases", 0) for payload in shards),
        "legacyConditionCases": sum(payload.get("legacyConditionCases", 0) for payload in shards),
        "unsupportedCases": sum(payload.get("unsupportedCases", 0) for payload in shards),
        "failedIds": failed_ids,
        "elapsedSeconds": round(max((payload["worker"]["elapsedSeconds"] for payload in shards), default=0), 3),
    }


def aggregate_run(
    phases: list[dict],
    elapsed: float,
    corpus_name: str,
    corpus_spec: dict,
    jobs: int,
) -> dict:
    failed_ids = []
    for phase in phases:
        failed_ids.extend(phase["failedIds"])
    return {
        "schemaVersion": 1,
        "runner": "gda-expression-interpreter",
        "corpus": {
            "name": corpus_name,
            "sha256": corpus_spec["sha256"],
            "expectedDecTestFiles": corpus_spec["expectedDecTestFiles"],
        },
        "jobs": jobs,
        "phases": phases,
        "summary": {
            "files": sum(phase["files"] for phase in phases),
            "selectedCases": sum(phase["selectedCases"] for phase in phases),
            "executableCases": sum(phase["executableCases"] for phase in phases),
            "passedCases": sum(phase["passedCases"] for phase in phases),
            "failedCases": sum(phase["failedCases"] for phase in phases),
            "skippedCases": sum(phase["skippedCases"] for phase in phases),
            "diagnosticCases": sum(phase["diagnosticCases"] for phase in phases),
            "legacyConditionCases": sum(phase["legacyConditionCases"] for phase in phases),
            "unsupportedCases": sum(phase["unsupportedCases"] for phase in phases),
            "failedIds": failed_ids,
            "elapsedSeconds": round(elapsed, 3),
        },
    }


def print_text(report: dict) -> None:
    print("GDA interpreter staged execution")
    for phase in report["phases"]:
        print(
            f"phase {phase['name']}: files {phase['files']}, "
            f"passed {phase['passedCases']}/{phase['executableCases']}, "
            f"failed {phase['failedCases']}, skipped {phase['skippedCases']}, "
            f"shards {phase['shards']}, elapsed {phase['elapsedSeconds']:.1f}s"
        )
    summary = report["summary"]
    print(
        f"total: files {summary['files']}, passed {summary['passedCases']}/"
        f"{summary['executableCases']}, failed {summary['failedCases']}, "
        f"skipped {summary['skippedCases']}, elapsed {summary['elapsedSeconds']:.1f}s"
    )
    if summary["failedIds"]:
        print("failed ids: " + ", ".join(summary["failedIds"]))


def main() -> int:
    normalized_args = []
    for argument in sys.argv[1:]:
        if argument.startswith("jobs="):
            normalized_args.extend(["--jobs", argument.removeprefix("jobs=")])
        elif argument.startswith("corpus="):
            normalized_args.extend(["--corpus", argument.removeprefix("corpus=")])
        elif argument.startswith("phase="):
            normalized_args.extend(["--phase", argument.removeprefix("phase=")])
        else:
            normalized_args.append(argument)
    parser = argparse.ArgumentParser(
        description="Run GDA .decTest files through staged interpreter processes"
    )
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--corpus", default="")
    parser.add_argument("--jobs", type=int, default=max(1, min(8, os.cpu_count() or 1)))
    parser.add_argument("--phase", action="append", default=[])
    parser.add_argument("--cases", default="")
    parser.add_argument("--strict-supported", action="store_true")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--interpreter", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args(normalized_args)
    try:
        if args.jobs <= 0:
            raise ValueError("--jobs must be positive")
        config = load_json(args.config.resolve())
        manifest = load_json(args.manifest.resolve())
        corpus_name, corpus = resolve_corpus(config, manifest, args.corpus)
        corpus_spec = manifest["corpora"][corpus_name]
        if args.fetch or not installed_corpus_ready(corpus, corpus_spec):
            result = subprocess.run(
                [sys.executable, "tools/fetch_decimal_corpora.py", corpus_name],
                cwd=REPO_ROOT,
            )
            if result.returncode != 0:
                return result.returncode
        if not installed_corpus_ready(corpus, corpus_spec):
            raise FileNotFoundError(
                f"corpus installation is incomplete: {corpus}"
            )
        phases = plan_phases(config, corpus, set(args.phase))
        if args.plan:
            payload = {
                "corpus": str(corpus.relative_to(REPO_ROOT)),
                "jobs": args.jobs,
                "phases": [
                    {"name": phase["name"], "files": [path.name for path in phase["files"]]}
                    for phase in phases
                ],
            }
            print(json.dumps(payload, indent=2))
            return 0
        executable = args.interpreter.resolve()
        if not args.no_build:
            build_interpreter(executable)
        elif not executable.is_file():
            raise FileNotFoundError(f"interpreter executable is missing: {executable}")
        output_dir = args.output.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        phase_reports = []
        for phase in phases:
            files = phase["files"]
            if not files:
                continue
            shard_count = args.jobs
            print(
                f"running phase {phase['name']}: {len(files)} files across {shard_count} processes",
                file=sys.stderr,
            )
            with concurrent.futures.ThreadPoolExecutor(max_workers=shard_count) as pool:
                futures = [
                    pool.submit(
                        run_worker,
                        phase["name"],
                        executable,
                        files,
                        shard_count,
                        shard_index,
                        args.cases,
                        args.strict_supported,
                        output_dir,
                    )
                    for shard_index in range(shard_count)
                ]
                shards = [future.result() for future in futures]
            phase_report = aggregate_phase(phase["name"], files, shards)
            phase_reports.append(phase_report)
            print(
                f"finished phase {phase['name']}: {phase_report['passedCases']}/"
                f"{phase_report['executableCases']} passed",
                file=sys.stderr,
            )
        report = aggregate_run(
            phase_reports,
            time.monotonic() - started,
            corpus_name,
            corpus_spec,
            args.jobs,
        )
        report_path = output_dir / "summary.json"
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print_text(report)
            print(f"summary: {report_path.relative_to(REPO_ROOT)}")
        summary = report["summary"]
        if summary["failedCases"] > 0:
            return 1
        if args.strict_supported and (
            summary["legacyConditionCases"] > 0 or summary["unsupportedCases"] > 0
        ):
            return 1
        return 0
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"dectest interpreter runner failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
