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
import os
import subprocess
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import gate_lock
import incremental
import kernel_units
import native_units
import run_ci
import stage_units

REPO_ROOT = Path(__file__).resolve().parent.parent
# Scopes with a conformance stage that supports `--incremental`: scope -> backend of that stage.
INCREMENTAL_BACKENDS: dict[str, str] = {"binary": "binary"}
# Scopes whose stages include whole-stage units (`tools/stage_units.py`): the keys are in `SPECS`.
UNIT_SCOPES = tuple(stage_units.SPECS)
COVERED_SCOPES = tuple(sorted({*INCREMENTAL_BACKENDS, *UNIT_SCOPES}))


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
    backend = INCREMENTAL_BACKENDS.get(scope, "")
    out = []
    for stage in run_ci.stages_for(scope, jobs):
        command = incremental_command(stage.command, backend) if backend else tuple(stage.command)
        out.append((stage.name, command, command != tuple(stage.command)))
    return out


def run_stages(
    stages: Sequence[tuple[str, tuple[str, ...], bool]],
    kernel: kernel_units.Plan | None,
    execute: Callable[[tuple[str, ...]], int],
    out: Callable[[str], None] = print,
    stage: stage_units.Plan | None = None,
    stage_tally: stage_units.Tally | None = None,
    stage_commits: dict[str, int] | None = None,
    execute_tee: stage_units.Execute | None = None,
) -> tuple[int, kernel_units.KernelTally, dict[str, int]]:
    """Run the stages in order. A kernel stage whose key is in the ledger is reported as reused and
    not executed; one that is sampled is executed and must pass (a failure is a defect of the
    system, status 70); a passing kernel stage that ran is recorded. Returns (exit status, tally of
    the kernel units, commits the reused stages ran on)."""
    tally = kernel_units.KernelTally(disabled=kernel.disabled if kernel else "")
    commits: dict[str, int] = {}
    units = {u.name: u for u in kernel.units} if kernel else {}
    whole = {u.name: u for u in stage.units} if stage else {}
    for name, command, is_incremental in stages:
        if stage and name in whole and execute_tee is not None and stage_tally is not None and stage_commits is not None:
            status = stage_units.run_stage(stage, whole[name], execute_tee, stage_tally, stage_commits, out)
            if status != 0:
                return status, tally, commits
            continue
        unit = units.get(name)
        action = kernel.actions[name] if (kernel and unit and not kernel.disabled) else "run"
        if unit and kernel and action == "reuse":
            commit = kernel_units.recorded_commit(kernel, unit)
            tally.reused += 1
            commits[commit] = commits.get(commit, 0) + 1
            out(f"REUSED  {name} [kernel unit, recorded on {commit[:10]}{'+dirty' if commit.endswith('+dirty') else ''}], not executed")
            continue
        tag = "incremental" if is_incremental else ("kernel unit, sampled rerun" if action == "sample" else "full")
        started = time.monotonic()
        status = execute(command)
        seconds = time.monotonic() - started
        if status != 0:
            out(f"FAIL  {name} [{tag}] exit {status}, {seconds:.1f}s")
            if unit:
                tally.failed += 1
            if unit and action == "sample":
                out(f"DEFECT  {name}: its key is recorded as passing and the sampled rerun failed: a defect of the incremental system, not of the change")
                return incremental.EXIT_DEFECT, tally, commits
            return status, tally, commits
        out(f"PASS  {name} [{tag}], {seconds:.1f}s")
        if unit and kernel:
            if action == "sample":
                tally.sampled += 1
            else:
                tally.ran += 1
                if action == "run" and not kernel.disabled:
                    if not kernel_units.record_pass(kernel, unit, seconds):
                        tally.unrecorded += 1
                        why = kernel.unit_disabled.get(name) or "the files of its key changed during the run"
                        out(f"NOTE  {name} passed but was not recorded: {why}")
    return 0, tally, commits


def run(
    scope: str,
    jobs: int,
    dry_run: bool = False,
    kernel_incremental: bool = True,
    seed: int | None = None,
    rate: float = kernel_units.DEFAULT_RATE,
    ledger_path: Path | None = None,
    kernel_only: bool = False,
    plan_only: bool = False,
) -> int:
    """`verify` of a scope. One run per worktree (`tools/gate_lock.py`), except `--dry-run` and
    `--plan-only`, which run no stage."""
    arguments = (scope, jobs, dry_run, kernel_incremental, seed, rate, ledger_path, kernel_only, plan_only)
    if dry_run or plan_only:
        return run_unlocked(*arguments)
    return gate_lock.guarded(REPO_ROOT, f"verify.py {scope} {jobs}", lambda: run_unlocked(*arguments))


def run_unlocked(
    scope: str,
    jobs: int,
    dry_run: bool = False,
    kernel_incremental: bool = True,
    seed: int | None = None,
    rate: float = kernel_units.DEFAULT_RATE,
    ledger_path: Path | None = None,
    kernel_only: bool = False,
    plan_only: bool = False,
) -> int:
    if scope not in COVERED_SCOPES:
        print(
            f"verify: scope '{scope}' has no incremental stage in this version "
            f"(covered: {', '.join(COVERED_SCOPES)}); run `just gate {scope}`",
            file=sys.stderr,
        )
        return 2
    stages = plan(scope, jobs)
    if kernel_only:
        stages = [st for st in stages if st[0].startswith(("DEPENDENCIES", kernel_units.KERNEL_STAGE_PREFIX))]
    started = time.monotonic()
    kernel_count = len(kernel_units.kernel_units([(n, c) for n, c, _ in stages])) if kernel_incremental else 0
    whole_units = stage_units.units_for(scope, [(n, c) for n, c, _ in stages]) if kernel_incremental else []
    whole_names = {u.name for u in whole_units}
    print(
        f"VERIFY scope={scope} workers={jobs} (incremental stages: {sum(1 for s in stages if s[2])} of {len(stages)}, "
        f"kernel units: {kernel_count}, stage units: {len(whole_units)})"
    )
    if dry_run:
        for name, command, flag in stages:
            kind = "incremental" if flag else "kernel unit" if kernel_count and name.startswith(kernel_units.KERNEL_STAGE_PREFIX) else "stage unit" if name in whole_names else "full"
            print(f"{name} [{kind}]: " + " ".join(command))
        return 0
    if whole_units:
        full = [n for n, _, f in stages if n not in whole_names and not f and not n.startswith(("DEPENDENCIES", kernel_units.KERNEL_STAGE_PREFIX))]
        print(f"stages of this scope that stay full: {', '.join(full) if full else 'none'}")
    chosen_seed = seed if seed is not None else int.from_bytes(os.urandom(4), "big")
    kernel = None
    if kernel_incremental:
        ledger = incremental.Ledger(ledger_path or incremental.ledger_path(REPO_ROOT))
        kernel = kernel_units.make_plan([(n, c) for n, c, _ in stages], REPO_ROOT, ledger, chosen_seed, rate)
        if kernel.disabled and "could not print" in kernel.disabled:
            # a fresh checkout has not fetched its dependencies yet: moon cannot print the build
            # before the dependency stage ran; run it once and form the keys again
            fetch = next((st for st in stages if st[0].startswith("DEPENDENCIES")), None)
            if fetch is not None and subprocess.run(fetch[1], cwd=REPO_ROOT).returncode == 0:
                kernel = kernel_units.make_plan([(n, c) for n, c, _ in stages], REPO_ROOT, ledger, chosen_seed, rate)
        if kernel.disabled:
            print(f"kernel units disabled: {kernel.disabled}")
    stage_plan = None
    if kernel_incremental and whole_units:
        ledger = incremental.Ledger(ledger_path or incremental.ledger_path(REPO_ROOT))
        stage_plan = stage_units.make_plan(scope, [(n, c) for n, c, _ in stages], REPO_ROOT, ledger, chosen_seed, rate)
        if stage_plan.disabled and "could not print" in stage_plan.disabled:
            fetch = next((st for st in stages if st[0].startswith("DEPENDENCIES")), None)
            if fetch is not None and subprocess.run(fetch[1], cwd=REPO_ROOT).returncode == 0:
                stage_plan = stage_units.make_plan(scope, [(n, c) for n, c, _ in stages], REPO_ROOT, ledger, chosen_seed, rate)
        if stage_plan.disabled:
            print(f"stage units disabled: {stage_plan.disabled}")
    if plan_only:
        import json

        print("KERNEL-PLAN " + json.dumps({"disabled": kernel.disabled if kernel else "", "actions": kernel.actions if kernel else {}}, sort_keys=True))
        if stage_plan:
            print("STAGE-PLAN " + json.dumps({"disabled": stage_plan.disabled, "actions": stage_plan.actions, "not keyed": stage_plan.unit_disabled}, sort_keys=True))
        return 0

    def execute(command: tuple[str, ...]) -> int:
        return subprocess.run(command, cwd=REPO_ROOT).returncode

    def execute_tee(command: tuple[str, ...], env: "Mapping[str, str] | None") -> tuple[int, str]:
        return native_units.run_tee(command, REPO_ROOT, env)

    stage_tally = stage_units.Tally(disabled=stage_plan.disabled if stage_plan else "")
    stage_commits: dict[str, int] = {}
    status, tally, commits = run_stages(stages, kernel, execute, stage=stage_plan, stage_tally=stage_tally, stage_commits=stage_commits, execute_tee=execute_tee)
    if kernel and kernel.units:
        print(kernel_units.summary_line(tally, chosen_seed, rate, commits))
    if stage_plan and stage_plan.units:
        print(stage_units.summary_line(stage_tally, chosen_seed, rate, stage_commits))
    if status != 0:
        return status
    print(f"PASS  verify {scope}, {time.monotonic() - started:.1f}s (reused units are listed above, never counted as run)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a gate with incremental verification")
    parser.add_argument("scope")
    parser.add_argument("jobs", nargs="?", type=int, default=run_ci.DEFAULT_JOBS)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--full-kernel", action="store_true", help="run the kernel stages in full (no kernel units)")
    parser.add_argument("--sample-seed", type=int, default=None, help="seed of the draw of the sampled kernel stages")
    parser.add_argument("--sample-rate", type=float, default=kernel_units.DEFAULT_RATE, help="probability that a reusable kernel stage is rerun")
    parser.add_argument("--ledger", type=Path, default=None)
    parser.add_argument("--kernel-only", action="store_true", help="run only the kernel stages (the mutation test of the kernel units)")
    parser.add_argument("--plan-only", action="store_true", help="print what each kernel unit would do and exit")
    args = parser.parse_args(argv)
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    return run(args.scope, args.jobs, args.dry_run, not args.full_kernel, args.sample_seed, args.sample_rate, args.ledger, args.kernel_only, args.plan_only)


if __name__ == "__main__":
    raise SystemExit(main())
