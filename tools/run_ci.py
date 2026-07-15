#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from conformance_ui import Console, Progress, format_duration
from conformance_runtime import BackendName


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_JOBS = max(1, min(8, os.cpu_count() or 1))
INTERVAL_PHASES = (
    "sets",
    "relations",
    "observations",
    "cancellation",
    "arithmetic",
    "elementary-core",
    "exponential-logarithmic",
    "general-power",
    "trigonometric",
    "hyperbolic",
    "inverse-trigonometric",
    "atan2",
    "fma",
    "integer-power",
    "extrema",
)
SUPPORTED_TARGETS = ("native", "wasm", "wasm-gc", "js")


@dataclass(frozen=True)
class Stage:
    name: str
    command: tuple[str, ...]


def conformance_command(backend: BackendName, jobs: int) -> tuple[str, ...]:
    base = [
        sys.executable,
        "tools/conformance.py",
        "run",
        "--backend",
        backend.value,
    ]
    if backend != BackendName.DECIMAL:
        base.extend(("--jobs", str(jobs)))
    if backend == BackendName.BINARY:
        base.extend(("--level", "1", "--tininess", "after", "--tininess", "before"))
    if backend == BackendName.INTERVAL:
        phases = tuple(item for phase in INTERVAL_PHASES for item in ("--phase", phase))
        base.extend((*phases, "--strict-supported"))
    if backend == BackendName.DECIMAL:
        base.extend(
            (
                "--run-target",
                "native",
                "--run-target",
                "wasm",
                "--run-target",
                "wasm-gc",
                "--run-target",
                "js",
            )
        )
    return tuple(base)


def stages_for(scope: str, jobs: int) -> list[Stage]:
    suites = {
        "decimal": Stage(
            "DECIMAL · IEEE 754",
            conformance_command(BackendName.DECIMAL, 1),
        ),
        "decimal_gda": [
            Stage(
                "DECIMAL_GDA · package tests",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating/decimal_gda",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "DECIMAL_GDA · frontend tests",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating/frontend/gda_expr",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "DECIMAL_GDA · official decTest",
                conformance_command(BackendName.DECIMAL_GDA, jobs),
            ),
            Stage(
                "DECIMAL_GDA · official0 decTest",
                (*conformance_command(BackendName.DECIMAL_GDA, jobs), "--corpus", "official0"),
            ),
        ],
        "binary": Stage(
            "BINARY · TestFloat + MPFR",
            conformance_command(BackendName.BINARY, jobs),
        ),
        "interval": Stage(
            "INTERVAL · IEEE 1788",
            conformance_command(BackendName.INTERVAL, jobs),
        ),
        "elementary": [
            Stage(
                "ELEMENTARY · correctness and candidate workload",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating/bench/bin_float",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "ELEMENTARY · immutable baseline mare_mark gate",
                (sys.executable, "tools/run_elementary_performance_gate.py"),
            ),
            Stage(
                "ELEMENTARY · candidate mare_mark workload",
                (sys.executable, "tools/benchmark.py", "elementary"),
            ),
        ],
    }
    if scope not in {"all", "quick"}:
        selected = suites[scope]
        return selected if isinstance(selected, list) else [selected]
    common_repository_stages = [
        Stage(
            "FORMAT · MoonBit sources",
            ("sh", "tools/run_moon_clean_exec.sh", "fmt", "--check"),
        ),
        Stage(
            "DOCS · localized examples",
            (sys.executable, "tools/run_docs.py"),
        ),
    ]
    if scope == "quick":
        repository_stages = [
            *common_repository_stages,
            Stage(
                "CHECK · native",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "check",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                ),
            ),
        ]
        return [
            *repository_stages,
            Stage(
                "TEST · native",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--jobs",
                    str(jobs),
                ),
            ),
            Stage(
                "SMOKE · IEEE 754",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "decimal",
                ),
            ),
            Stage(
                "TEST · Python tooling",
                (
                    sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    "tools",
                    "-p",
                    "*_test.py",
                ),
            ),
            Stage(
                "SMOKE · DecimalGDA",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "decimal_gda",
                ),
            ),
            Stage(
                "SMOKE · Binary",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "binary",
                ),
            ),
            Stage(
                "SMOKE · Interval",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "interval",
                    "--strict-supported",
                ),
            ),
        ]
    repository_stages = [
        *common_repository_stages,
        *[
            Stage(
                f"CHECK · {target}",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "check",
                    "--target",
                    target,
                    "--deny-warn",
                    "--frozen",
                ),
            )
            for target in SUPPORTED_TARGETS
        ],
    ]
    return [
        *repository_stages,
        Stage("INFO · generated interfaces", ("sh", "tools/run_moon_clean_exec.sh", "info")),
        *[
            Stage(
                f"TEST · {target}",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "--target",
                    target,
                    "--deny-warn",
                    "--frozen",
                    "--jobs",
                    str(jobs),
                ),
            )
            for target in SUPPORTED_TARGETS
        ],
        suites["decimal"],
        *suites["decimal_gda"],
        suites["binary"],
        suites["interval"],
    ]


def run(scope: str, jobs: int, dry_run: bool = False) -> int:
    stages = stages_for(scope, jobs)
    console = Console()
    console.heading("LUNAFLOW CI", f"scope={scope} · workers={jobs}")
    if dry_run:
        for stage in stages:
            print(stage.name + ": " + " ".join(stage.command))
        return 0
    progress = Progress("repository gate", len(stages), console)
    started = time.monotonic()
    completed = 0
    for stage in stages:
        progress.update(completed, stage.name)
        progress.pause()
        stage_started = time.monotonic()
        result = subprocess.run(stage.command, cwd=REPO_ROOT)
        elapsed = format_duration(time.monotonic() - stage_started)
        if result.returncode != 0:
            progress.finish(False, f"{stage.name} · {elapsed}")
            return result.returncode
        console.status(True, stage.name, elapsed)
        completed += 1
        progress.update(completed, stage.name)
    progress.finish(True, format_duration(time.monotonic() - started))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run LunaFlow repository CI gates")
    parser.add_argument(
        "scope",
        choices=(
            "all",
            "quick",
            "decimal",
            "decimal_gda",
            "binary",
            "interval",
            "elementary",
        ),
    )
    parser.add_argument("jobs", nargs="?", type=int, default=DEFAULT_JOBS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    return run(args.scope, args.jobs, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
