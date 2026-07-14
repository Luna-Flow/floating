#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import fetch_binfloat_corpora
from conformance_cli import build_backend, executable_path
from conformance_runtime import ensure_available, ordered_parallel_map
from conformance_ui import Console, Progress, SummaryRow, print_summary


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "testdata/bin_float/corpora.json"
DEFAULT_SMOKE_MANIFEST = REPO_ROOT / "testdata/bin_float/smoke/manifest.json"
DEFAULT_OUTPUT = REPO_ROOT / ".tmp/binfloat-conformance/results"
TESTFLOAT_EXECUTABLE = (
    REPO_ROOT
    / ".tmp/binfloat-conformance/vendor/TestFloat-3e"
    / "build/Linux-x86_64-GCC/testfloat_gen"
)
TESTFLOAT_INTERPRETER = executable_path("testfloat")
MPFR_INTERPRETER = executable_path("mpfr")
DEFAULT_CHUNK_CASES = 100_000
FORMATS = ("f16", "f32", "f64", "f128")
OPERATIONS = ("add", "sub", "mul", "div", "sqrt")
ROUNDINGS = ("rnear_even", "rnear_maxMag", "rminMag", "rmin", "rmax")
TININESS_MODES = ("after", "before")


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_path(value: str) -> Path:
    path = (REPO_ROOT / value).resolve()
    if path != REPO_ROOT and REPO_ROOT not in path.parents:
        raise ValueError(f"path escapes repository: {value}")
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifacts_ready(manifest: dict) -> bool:
    artifacts = manifest["artifacts"]
    softfloat = repo_path(artifacts["softfloat-3e"]["destination"])
    testfloat = repo_path(artifacts["testfloat-3e"]["destination"])
    mpfr = repo_path(artifacts["mpfr-4.2.2-sqrt"]["destination"])
    return (
        (softfloat / "source/include/softfloat.h").is_file()
        and (testfloat / "source/testfloat_gen.c").is_file()
        and mpfr.is_file()
        and sha256(mpfr) == artifacts["mpfr-4.2.2-sqrt"]["sha256"]
    )


def fetch_artifacts(manifest: dict, force: bool) -> None:
    return_code = ensure_available(
        is_ready=lambda: artifacts_ready(manifest),
        fetcher=fetch_binfloat_corpora.main,
        fetch_args=["--force"] if force else [],
        force=force,
        missing_message="binary conformance artifact installation is incomplete",
    )
    if return_code != 0:
        raise RuntimeError("failed to fetch binary conformance artifacts")


def build_reference_tools(manifest: dict, jobs: int) -> None:
    artifacts = manifest["artifacts"]
    softfloat = repo_path(artifacts["softfloat-3e"]["destination"])
    testfloat = repo_path(artifacts["testfloat-3e"]["destination"])
    platform = "Linux-x86_64-GCC"
    softfloat_build = softfloat / "build" / platform
    testfloat_build = testfloat / "build" / platform
    softfloat_result = subprocess.run(
        ["make", f"-j{jobs}"],
        cwd=softfloat_build,
        text=True,
        capture_output=True,
    )
    if softfloat_result.returncode != 0:
        raise RuntimeError(
            "failed to build Berkeley SoftFloat:\n"
            + softfloat_result.stdout
            + softfloat_result.stderr
        )
    testfloat_result = subprocess.run(
        [
            "make",
            f"-j{jobs}",
            f"SOFTFLOAT_DIR={softfloat}",
            f"PLATFORM={platform}",
            "testfloat_gen",
        ],
        cwd=testfloat_build,
        text=True,
        capture_output=True,
    )
    if testfloat_result.returncode != 0 or not TESTFLOAT_EXECUTABLE.is_file():
        raise RuntimeError(
            "failed to build Berkeley TestFloat generator:\n"
            + testfloat_result.stdout
            + testfloat_result.stderr
        )


def build_interpreters() -> None:
    build_backend("testfloat")
    build_backend("mpfr")


def task_matrix(args: argparse.Namespace) -> list[dict]:
    formats = args.formats or list(FORMATS)
    operations = args.operations or list(OPERATIONS)
    roundings = args.roundings or list(ROUNDINGS)
    tininess_modes = args.tininess_modes or ["after"]
    return [
        {
            "format": format_name,
            "operation": operation,
            "function": f"{format_name}_{operation}",
            "rounding": rounding,
            "tininess": tininess,
            "level": args.level,
            "seed": args.seed,
        }
        for format_name in formats
        for operation in operations
        for rounding in roundings
        for tininess in tininess_modes
    ]


def task_name(task: dict) -> str:
    return (
        f"{task['function']}-{task['rounding']}-"
        f"tininess-{task['tininess']}-level-{task['level']}"
    )


def testfloat_generator_command(task: dict) -> list[str]:
    return [
        str(TESTFLOAT_EXECUTABLE),
        "-level",
        str(task["level"]),
        "-seed",
        str(task["seed"]),
        f"-{task['rounding']}",
        f"-tininess{task['tininess']}",
        task["function"],
    ]


def testfloat_interpreter_command(task: dict, vector_path: Path) -> list[str]:
    return [
        str(TESTFLOAT_INTERPRETER),
        "--backend",
        "testfloat",
        "--function",
        task["function"],
        "--rounding",
        task["rounding"],
        "--tininess",
        task["tininess"],
        "--json",
        str(vector_path),
    ]


def remap_failed_ids(
    task: dict, failed_ids: list[str], case_offset: int
) -> list[str]:
    prefix = task["function"] + ":"
    remapped = []
    for identifier in failed_ids:
        if identifier.startswith(prefix):
            line_number = identifier.removeprefix(prefix)
            if line_number.isdigit():
                remapped.append(prefix + str(case_offset + int(line_number)))
                continue
        remapped.append(identifier)
    return remapped


def merge_testfloat_chunk(
    aggregate: dict, payload: dict, task: dict, case_offset: int, line_count: int
) -> None:
    total_cases = payload.get("totalCases")
    selected_cases = payload.get("selectedCases")
    if total_cases != line_count or selected_cases != line_count:
        raise RuntimeError(
            f"interpreter did not execute every generated case for "
            f"{task_name(task)} chunk at case {case_offset + 1}: "
            f"expected {line_count}, got total={total_cases}, "
            f"selected={selected_cases}"
        )
    aggregate["totalCases"] += total_cases
    aggregate["selectedCases"] += selected_cases
    aggregate["passedCases"] += payload["passedCases"]
    aggregate["failedCases"] += payload["failedCases"]
    aggregate["failedIds"].extend(
        remap_failed_ids(task, payload["failedIds"], case_offset)
    )
    aggregate["chunks"] += 1


def run_testfloat_chunk(task: dict, vector_path: Path) -> dict:
    result = subprocess.run(
        testfloat_interpreter_command(task, vector_path),
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(
            f"interpreter failed for {task_name(task)} "
            f"({result.returncode}):\n{result.stderr}{result.stdout}"
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"interpreter returned invalid JSON for {task_name(task)}:\n"
            f"{result.stdout}\n{result.stderr}"
        ) from error


def run_testfloat_task(task: dict, output: Path, chunk_cases: int) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    temporary_dir = REPO_ROOT / ".tmp/binfloat-conformance/vectors"
    temporary_dir.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    aggregate = {
        "function": task["function"],
        "rounding": task["rounding"],
        "tininess": task["tininess"],
        "totalCases": 0,
        "selectedCases": 0,
        "passedCases": 0,
        "failedCases": 0,
        "failedIds": [],
        "chunks": 0,
    }
    generator = subprocess.Popen(
        testfloat_generator_command(task),
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        if generator.stdout is None or generator.stderr is None:
            raise RuntimeError("failed to open TestFloat generator streams")
        case_offset = 0
        with tempfile.TemporaryDirectory(
            prefix=task_name(task) + "-",
            dir=temporary_dir,
        ) as task_directory:
            task_directory = Path(task_directory)
            chunk_index = 0
            while True:
                vector_path = task_directory / f"{chunk_index:08d}.testfloat"
                line_count = 0
                with vector_path.open("wb") as vector:
                    while line_count < chunk_cases:
                        line = generator.stdout.readline()
                        if not line:
                            break
                        vector.write(line)
                        line_count += 1
                if line_count == 0:
                    vector_path.unlink(missing_ok=True)
                    break
                payload = run_testfloat_chunk(task, vector_path)
                merge_testfloat_chunk(
                    aggregate, payload, task, case_offset, line_count
                )
                case_offset += line_count
                chunk_index += 1
                vector_path.unlink(missing_ok=True)
        generator_error = generator.stderr.read().decode(errors="replace")
        generator_returncode = generator.wait()
        if generator_returncode != 0:
            raise RuntimeError(
                f"TestFloat generation failed for {task_name(task)}:\n"
                + generator_error
            )
        if aggregate["totalCases"] == 0:
            raise RuntimeError(f"TestFloat generated no cases for {task_name(task)}")
        aggregate["level"] = task["level"]
        aggregate["seed"] = task["seed"]
        aggregate["elapsedSeconds"] = round(time.monotonic() - started, 3)
        (output / f"{task_name(task)}.json").write_text(
            json.dumps(aggregate, indent=2) + "\n", encoding="utf-8"
        )
        return aggregate
    finally:
        if generator.poll() is None:
            generator.kill()
            generator.wait()


def run_mpfr_path(
    path: Path, expected_cases: int, output: Path, output_name: str
) -> dict:
    started = time.monotonic()
    result = subprocess.run(
        [
            str(MPFR_INTERPRETER),
            "--backend",
            "mpfr",
            "--json",
            str(path),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(
            f"MPFR interpreter failed ({result.returncode}):\n"
            f"{result.stderr}{result.stdout}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"MPFR interpreter returned invalid JSON:\n{result.stdout}"
        ) from error
    if payload["totalCases"] != expected_cases:
        raise RuntimeError(
            "MPFR executable row count changed: "
            f"expected {expected_cases}, got {payload['totalCases']}"
        )
    payload["elapsedSeconds"] = round(time.monotonic() - started, 3)
    (output / output_name).write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    return payload


def run_mpfr(manifest: dict, output: Path) -> dict:
    spec = manifest["artifacts"]["mpfr-4.2.2-sqrt"]
    return run_mpfr_path(
        repo_path(spec["destination"]),
        spec["expectedExecutableRows"],
        output,
        "mpfr-4.2.2-sqrt.json",
    )


def smoke_task(spec: dict) -> dict:
    return {
        "function": spec["function"],
        "rounding": spec["rounding"],
        "tininess": spec["tininess"],
        "level": 1,
        "seed": 1,
    }


def run_smoke(
    manifest: dict, output: Path, skip_mpfr: bool
) -> tuple[list[dict], list[dict]]:
    tasks = []
    for index, spec in enumerate(manifest["testfloat"]):
        task = smoke_task(spec)
        path = repo_path(spec["path"])
        started = time.monotonic()
        payload = run_testfloat_chunk(task, path)
        if payload["totalCases"] != spec["expectedCases"]:
            raise RuntimeError(
                f"smoke row count changed for {path.relative_to(REPO_ROOT)}: "
                f"expected {spec['expectedCases']}, got {payload['totalCases']}"
            )
        payload["corpus"] = "smoke"
        payload["elapsedSeconds"] = round(time.monotonic() - started, 3)
        (output / f"smoke-{index:02d}-{task_name(task)}.json").write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )
        tasks.append(payload)
    mpfr_results = []
    if not skip_mpfr:
        for spec in manifest["mpfr"]:
            payload = run_mpfr_path(
                repo_path(spec["path"]),
                spec["expectedCases"],
                output,
                f"smoke-{spec['name']}.json",
            )
            payload["corpus"] = "smoke"
            mpfr_results.append(payload)
    return tasks, mpfr_results


def aggregate(tasks: list[dict], mpfr: list[dict], elapsed: float) -> dict:
    failed_ids = []
    for task in tasks:
        failed_ids.extend(task.get("failedIds", []))
    for result in mpfr:
        failed_ids.extend(result.get("failedIds", []))
    testfloat_total = sum(task["totalCases"] for task in tasks)
    testfloat_passed = sum(task["passedCases"] for task in tasks)
    testfloat_failed = sum(task["failedCases"] for task in tasks)
    mpfr_total = sum(result["totalCases"] for result in mpfr)
    mpfr_passed = sum(result["passedCases"] for result in mpfr)
    mpfr_failed = sum(result["failedCases"] for result in mpfr)
    return {
        "schemaVersion": 1,
        "runner": "binfloat-conformance-interpreters",
        "testfloat": {
            "tasks": tasks,
            "totalCases": testfloat_total,
            "passedCases": testfloat_passed,
            "failedCases": testfloat_failed,
        },
        "mpfr": mpfr,
        "summary": {
            "totalCases": testfloat_total + mpfr_total,
            "passedCases": testfloat_passed + mpfr_passed,
            "failedCases": testfloat_failed + mpfr_failed,
            "failedIds": failed_ids,
            "elapsedSeconds": round(elapsed, 3),
        },
    }


def print_text(report: dict) -> None:
    testfloat = report["testfloat"]
    rows = [
        SummaryRow(
            "TestFloat 3e",
            testfloat["passedCases"],
            testfloat["totalCases"],
            testfloat["failedCases"],
            f"{len(testfloat['tasks'])} tasks",
        )
    ]
    rows.extend(
        SummaryRow(
            mpfr["corpus"],
            mpfr["passedCases"],
            mpfr["totalCases"],
            mpfr["failedCases"],
        )
        for mpfr in report["mpfr"]
    )
    summary = report["summary"]
    print_summary(
        "BINARY · TestFloat + MPFR",
        "Berkeley TestFloat 3e · GNU MPFR 4.2.2",
        rows,
        summary["passedCases"],
        summary["totalCases"],
        summary["failedCases"],
        summary["elapsedSeconds"],
        summary["failedIds"],
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run BinFloat through Berkeley TestFloat and GNU MPFR data"
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--smoke-manifest", type=Path, default=DEFAULT_SMOKE_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--jobs", type=int, default=max(1, min(8, os.cpu_count() or 1)))
    parser.add_argument("--chunk-cases", type=int, default=DEFAULT_CHUNK_CASES)
    parser.add_argument("--level", type=int, choices=(1, 2), default=1)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--format", dest="formats", action="append", choices=FORMATS)
    parser.add_argument(
        "--operation", dest="operations", action="append", choices=OPERATIONS
    )
    parser.add_argument(
        "--rounding", dest="roundings", action="append", choices=ROUNDINGS
    )
    parser.add_argument(
        "--tininess",
        dest="tininess_modes",
        action="append",
        choices=TININESS_MODES,
    )
    parser.add_argument("--skip-mpfr", action="store_true")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--no-reference-build", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.jobs <= 0:
            raise ValueError("--jobs must be positive")
        if args.chunk_cases <= 0:
            raise ValueError("--chunk-cases must be positive")
        if args.seed < 0:
            raise ValueError("--seed must be non-negative")
        if args.smoke:
            if args.fetch:
                raise ValueError("--fetch cannot be combined with --smoke")
            smoke_manifest = load_json(args.smoke_manifest.resolve())
            smoke_tasks = [smoke_task(spec) for spec in smoke_manifest["testfloat"]]
            if args.plan:
                print(
                    json.dumps(
                        {
                            "tasks": smoke_tasks,
                            "mpfr": not args.skip_mpfr,
                            "estimatedTaskCount": len(smoke_tasks),
                            "corpus": "smoke",
                        },
                        indent=2,
                    )
                )
                return 0
            if not args.no_build:
                build_interpreters()
            elif not TESTFLOAT_INTERPRETER.is_file() or (
                not args.skip_mpfr and not MPFR_INTERPRETER.is_file()
            ):
                raise FileNotFoundError("one or more BinFloat interpreters are missing")
            output = args.output.resolve()
            output.mkdir(parents=True, exist_ok=True)
            started = time.monotonic()
            task_results, mpfr_result = run_smoke(
                smoke_manifest, output, args.skip_mpfr
            )
            report = aggregate(
                task_results, mpfr_result, time.monotonic() - started
            )
            report["corpus"] = "smoke"
            report_path = output / "summary.json"
            report_path.write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )
            if args.json:
                print(json.dumps(report, indent=2))
            else:
                print_text(report)
                print(f"summary: {report_path.relative_to(REPO_ROOT)}")
            return 0 if report["summary"]["failedCases"] == 0 else 1

        manifest = load_json(args.manifest.resolve())
        tasks = task_matrix(args)
        if args.plan:
            print(
                json.dumps(
                    {
                        "tasks": tasks,
                        "mpfr": not args.skip_mpfr,
                        "estimatedTaskCount": len(tasks),
                    },
                    indent=2,
                )
            )
            return 0
        fetch_artifacts(manifest, args.fetch)
        if not args.no_reference_build:
            build_reference_tools(manifest, args.jobs)
        elif not TESTFLOAT_EXECUTABLE.is_file():
            raise FileNotFoundError(
                f"TestFloat generator is missing: {TESTFLOAT_EXECUTABLE}"
            )
        if not args.no_build:
            build_interpreters()
        elif not TESTFLOAT_INTERPRETER.is_file() or (
            not args.skip_mpfr and not MPFR_INTERPRETER.is_file()
        ):
            raise FileNotFoundError("one or more BinFloat interpreters are missing")
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        task_progress = Progress(f"binary/TestFloat level {args.level}", len(tasks), Console())
        task_results = ordered_parallel_map(
            tasks,
            args.jobs,
            lambda task: run_testfloat_task(task, output, args.chunk_cases),
            task_progress,
            lambda task: task["function"],
        )
        task_progress.finish(
            not any(task["failedCases"] != 0 for task in task_results),
        )
        mpfr_results = [] if args.skip_mpfr else [run_mpfr(manifest, output)]
        report = aggregate(task_results, mpfr_results, time.monotonic() - started)
        report_path = output / "summary.json"
        report_path.write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print_text(report)
            print(f"summary: {report_path.relative_to(REPO_ROOT)}")
        return 0 if report["summary"]["failedCases"] == 0 else 1
    except (OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"binfloat interpreter runner failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
