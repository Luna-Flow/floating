#!/usr/bin/env python3
"""`just verify <scope> [jobs]`: the gate of a scope with incremental verification.

The stages are those of `run_ci.stages_for(scope, jobs)`. A conformance stage of a supported
backend gets `--incremental` (units whose code, input and toolchain are unchanged since a recorded
run are reused and reported as reused, 2 % of them are really rerun); every other stage runs as
in the gate. A scope that has no incremental stage is refused: use `just gate <scope>`.

Exit status: 0 all stages passed; the status of the first failing stage otherwise (70: a sampled
rerun differed from the ledger, a defect of the system).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from collections.abc import Sequence
from pathlib import Path

import run_ci

REPO_ROOT = Path(__file__).resolve().parent.parent
# Scopes with a conformance stage that supports `--incremental`: scope -> backend of that stage.
INCREMENTAL_BACKENDS: dict[str, str] = {"binary": "binary"}


def is_incremental_stage(command: Sequence[str], backend: str) -> bool:
    """Whether a stage command is `tools/conformance.py run --backend <backend>`."""
    text = " ".join(command)
    return "conformance.py run" in text and f"--backend {backend}" in text


def incremental_command(command: Sequence[str], backend: str) -> tuple[str, ...]:
    """The stage command with `--incremental` added when it is the conformance run of `backend`."""
    if is_incremental_stage(command, backend) and "--incremental" not in command:
        return (*command, "--incremental")
    return tuple(command)


def plan(scope: str, jobs: int) -> list[tuple[str, tuple[str, ...], bool]]:
    """(stage name, command, incremental) for every stage of the scope."""
    backend = INCREMENTAL_BACKENDS[scope]
    out = []
    for stage in run_ci.stages_for(scope, jobs):
        command = incremental_command(stage.command, backend)
        out.append((stage.name, command, command != tuple(stage.command)))
    return out


def run(scope: str, jobs: int, dry_run: bool = False) -> int:
    if scope not in INCREMENTAL_BACKENDS:
        print(
            f"verify: scope '{scope}' has no incremental stage in this version "
            f"(covered: {', '.join(sorted(INCREMENTAL_BACKENDS))}); run `just gate {scope}`",
            file=sys.stderr,
        )
        return 2
    stages = plan(scope, jobs)
    started = time.monotonic()
    print(f"VERIFY scope={scope} workers={jobs} (incremental stages: {sum(1 for s in stages if s[2])} of {len(stages)})")
    for name, command, incremental in stages:
        tag = "incremental" if incremental else "full"
        if dry_run:
            print(f"{name} [{tag}]: " + " ".join(command))
            continue
        stage_started = time.monotonic()
        result = subprocess.run(command, cwd=REPO_ROOT)
        seconds = time.monotonic() - stage_started
        if result.returncode != 0:
            print(f"FAIL  {name} [{tag}] exit {result.returncode}, {seconds:.1f}s")
            return result.returncode
        print(f"PASS  {name} [{tag}], {seconds:.1f}s")
    print(f"PASS  verify {scope}, {time.monotonic() - started:.1f}s (reused units are listed above, never counted as run)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a gate with incremental verification")
    parser.add_argument("scope")
    parser.add_argument("jobs", nargs="?", type=int, default=run_ci.DEFAULT_JOBS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    return run(args.scope, args.jobs, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
