#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from conformance_ui import Console, Progress, format_duration


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
    "fma",
    "integer-power",
    "extrema",
)


@dataclass(frozen=True)
class Stage:
    name: str
    command: tuple[str, ...]


def conformance_command(backend: str, jobs: int) -> tuple[str, ...]:
    runner_backend = "binary" if backend == "bin" else backend
    base = (
        sys.executable,
        "tools/conformance.py",
        "run",
        "--backend",
        runner_backend,
        "--jobs",
        str(jobs),
    )
    if backend == "binary":
        return (*base, "--level", "1", "--tininess", "after", "--tininess", "before")
    if backend == "interval":
        phases = tuple(item for phase in INTERVAL_PHASES for item in ("--phase", phase))
        return (*base, *phases, "--strict-supported")
    return base


def stages_for(scope: str, jobs: int) -> list[Stage]:
    suites = {
        "decimal": Stage("DECIMAL · GDA decTest", conformance_command("decimal", jobs)),
        "bin": Stage("BINARY · TestFloat + MPFR", conformance_command("binary", jobs)),
        "interval": Stage("INTERVAL · IEEE 1788", conformance_command("interval", jobs)),
    }
    if scope not in {"all", "quick"}:
        return [suites[scope]]
    repository_stages = [
        Stage(
            "FORMAT · MoonBit sources",
            ("sh", "tools/run_moon_clean_exec.sh", "fmt", "--check"),
        ),
        Stage(
            "DOCS · localized examples",
            ("just", "docs"),
        ),
        Stage(
            "CHECK · all targets",
            (
                "sh",
                "tools/run_moon_clean_exec.sh",
                "check",
                "--target",
                "all",
                "--deny-warn",
                "--frozen",
            ),
        ),
    ]
    if scope == "quick":
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
                "SMOKE · Decimal",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "decimal",
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
    return [
        *repository_stages,
        Stage("INFO · generated interfaces", ("sh", "tools/run_moon_clean_exec.sh", "info")),
        Stage(
            "TEST · all targets",
            (
                "sh",
                "tools/run_moon_clean_exec.sh",
                "test",
                "--target",
                "all",
                "--deny-warn",
                "--frozen",
                "--jobs",
                str(jobs),
            ),
        ),
        suites["decimal"],
        suites["bin"],
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
        choices=("all", "quick", "decimal", "bin", "interval"),
    )
    parser.add_argument("jobs", nargs="?", type=int, default=DEFAULT_JOBS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    return run(args.scope, args.jobs, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
