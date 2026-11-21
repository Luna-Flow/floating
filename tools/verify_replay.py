#!/usr/bin/env python3
"""Replay incremental verification over the last merged commits of main.

For each of the last N first-parent commits of `origin/main` (a squash-merged PR each) the script
builds the conformance executable of the commit and of its parent, computes the key of every unit
of the binary gate (the 534 TestFloat tasks and the MPFR files of `just gate binary`) and reports
how many units would have run, which kind of change it was, and the estimated time, against the
full TestFloat and MPFR stage.

What it assumes, stated in the table caption by `format_table`:
* the arms of a unit (which operation it executes) and the time of a unit come from one
  measured full run (`--baseline summary.json`, written by `run_binary_interpreter.py
  --incremental`); the arms are checked present in every replayed build;
* toolchain and verifier digests are held constant (only the code part of the key is replayed);
* the frontend split of PR 685 is applied to a commit that predates it (`--patch`); a commit on
  which the patch does not apply is replayed coarsely (one key per frontend), and said so.

Usage: python3 tools/verify_replay.py --baseline summary.json [--count 30] [--worktree DIR]
       [--patch FILE] [--out table.md] [--ref origin/main]
Heavy: one build per commit. The scratch worktree defaults to `verify-replay` beside the other worktrees.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import subprocess
import sys
from typing import Any
from collections.abc import Mapping, Sequence
from pathlib import Path

import code_fingerprint as cf
import incremental as inc

REPO_ROOT = Path(__file__).resolve().parent.parent
C_FILE = "_build/conformance/cli/native/release/build/Luna-Flow/floating-tools/cli/cli.c"
CONSTANT_TOOLCHAIN = "replay-toolchain"
CONSTANT_VERIFIER = "replay-verifier"


@dataclasses.dataclass(frozen=True)
class Snapshot:
    """Everything the replay keeps of one build (the 18 MB C file is dropped)."""

    commit: str
    subject: str
    pre: Mapping[str, str]  # unit -> pre key (frame, input, args, toolchain, verifier)
    result: Mapping[str, str]  # unit -> result key
    startup: str  # fingerprint of the start-up closure alone
    frames: Mapping[str, str]  # frontend -> fingerprint of its frame WITHOUT the start-up code
    coarse: bool  # no arm functions in the build: one key per frontend
    patched: bool


# ---------------------------------------------------------------------------------------
# Pure parts
# ---------------------------------------------------------------------------------------


def changed_units(previous: Mapping[str, str], current: Mapping[str, str]) -> list[str]:
    """Units whose key differs (or that are new), in the order of `current`."""
    return [unit for unit, key in current.items() if previous.get(unit) != key]


def classify(previous: Snapshot, current: Snapshot) -> str:
    """The kind of change between two builds, from the keys alone, by cause.

    `none`: no key changed. `frame`: the frame of the TestFloat frontend (the code reachable from
    its entry, start-up code left out) changed: the 534 tasks rerun whatever else changed.
    `start-up`: that frame is unchanged and the start-up closure changed (an initialiser, or code
    that only the start-up reaches): every unit reruns, and it is the only kind of change that an
    attribution of the initialisers can narrow. `mpfr`: only the frame of the MPFR frontend
    changed (its files rerun). `arm`: only an arm's closure changed.
    """
    if not changed_units(previous.result, current.result):
        return "none"
    if previous.frames.get("testfloat") != current.frames.get("testfloat"):
        return "frame"
    if previous.startup != current.startup:
        return "start-up"
    if previous.frames.get("mpfr") != current.frames.get("mpfr"):
        return "mpfr"
    return "arm"


def estimate_seconds(units: Sequence[str], seconds: Mapping[str, float]) -> float:
    return sum(seconds.get(unit, 0.0) for unit in units)


@dataclasses.dataclass(frozen=True)
class Row:
    commit: str
    subject: str
    kind: str
    units: int
    testfloat: int
    mpfr: int
    seconds: float
    note: str


def make_row(previous: Snapshot, current: Snapshot, seconds: Mapping[str, float]) -> Row:
    units = changed_units(previous.result, current.result)
    mpfr = [u for u in units if u.endswith(".json")]
    notes = []
    if current.coarse:
        notes.append("coarse (no arms)")
    elif not current.patched and not previous.patched:
        notes.append("")
    if current.patched:
        notes.append("split patch applied")
    return Row(
        current.commit[:8], current.subject[:70], classify(previous, current), len(units),
        len(units) - len(mpfr), len(mpfr), estimate_seconds(units, seconds), ", ".join(n for n in notes if n),
    )


def format_table(rows: Sequence[Row], total_units: int, full_seconds: float) -> str:
    """The replay table and a summary per kind of change, as Markdown."""
    lines = [
        f"| commit | change | kind | units that would run (of {total_units}) | TestFloat | MPFR | estimated time | share of the full stage | note |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        share = f"{100 * row.seconds / full_seconds:.1f} %" if full_seconds else "n/a"
        lines.append(
            f"| {row.commit} | {row.subject} | {row.kind} | {row.units} | {row.testfloat} | {row.mpfr} | {row.seconds:.1f} s | {share} | {row.note} |"
        )
    lines.append("")
    lines.append("| kind of change | commits | mean units that would run | mean estimated time | mean share of the full stage |")
    lines.append("| --- | --- | --- | --- | --- |")
    for kind in ("none", "arm", "mpfr", "frame", "start-up"):
        chosen = [r for r in rows if r.kind == kind]
        if not chosen:
            lines.append(f"| {kind} | 0 | | | |")
            continue
        mean_units = sum(r.units for r in chosen) / len(chosen)
        mean_seconds = sum(r.seconds for r in chosen) / len(chosen)
        share = f"{100 * mean_seconds / full_seconds:.1f} %" if full_seconds else "n/a"
        lines.append(f"| {kind} | {len(chosen)} | {mean_units:.1f} | {mean_seconds:.1f} s | {share} |")
    return "\n".join(lines)


def snapshot_keys(
    program: cf.Program,
    units: Mapping[str, tuple[inc.UnitSpec, Sequence[str]]],
    commit: str,
    subject: str,
    patched: bool,
) -> Snapshot:
    """The keys of every unit for one build. `units[name] = (spec, arms the unit executes)`."""
    builder = inc.KeyBuilder(program, CONSTANT_TOOLCHAIN, CONSTANT_VERIFIER)
    spec = builder.frontends["testfloat"]
    has_arms = bool(spec.arm and inc.arm_definitions(program, spec.arm))
    pre: dict[str, str] = {}
    result: dict[str, str] = {}
    for name, (unit, arms) in units.items():
        pre[name] = builder.pre_key(unit.frontend, unit.input_id, unit.args)
        if unit.frontend == "testfloat" and not has_arms:
            result[name] = inc.digest("coarse", pre[name])
            continue
        key = builder.result_key(unit.frontend, pre[name], arms)
        if key is None:
            raise RuntimeError(f"{name}: an arm of {list(arms)} has no definition in {commit}")
        result[name] = key
    dispatcher = inc._one(program, spec.dispatcher, "dispatcher")
    startup = cf.fingerprint(program, [], cut={dispatcher}, exclude=(), startup=True)
    frames = {}
    for frontend in ("testfloat", "mpfr"):
        frontend_arms = builder.arms(frontend)
        frames[frontend] = cf.fingerprint(
            program,
            inc._one(program, builder.frontends[frontend].entry, "entry"),
            cut={dispatcher},
            exclude=set(frontend_arms.values()) if frontend_arms else (),
            startup=False,
        )
    return Snapshot(commit, subject, pre, result, startup, frames, not has_arms, patched)


# ---------------------------------------------------------------------------------------
# The driver
# ---------------------------------------------------------------------------------------


def git(repo: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(["git", *arguments], cwd=repo, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(arguments)} failed: {result.stderr}")
    return result.stdout


def load_units(baseline: dict[str, Any]) -> tuple[dict[str, tuple[inc.UnitSpec, list[str]]], dict[str, float]]:
    """The units of the gate with the arms and the time measured in the baseline run."""
    import importlib.util

    spec = importlib.util.spec_from_file_location("binary_runner", REPO_ROOT / "tools" / "run_binary_interpreter.py")
    assert spec is not None and spec.loader is not None
    runner = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(REPO_ROOT / "tools"))
    spec.loader.exec_module(runner)
    seconds: dict[str, float] = {}
    units: dict[str, tuple[inc.UnitSpec, list[str]]] = {}
    for task in baseline["testfloat"]["tasks"]:
        seconds[runner.task_name(task)] = float(task.get("elapsedSeconds", 0.0))
        unit = runner.testfloat_unit(task, "replay-generator")
        units[unit.name] = (unit, list(task.get("arms", [])))
    for mpfr in baseline["mpfr"]:
        name = mpfr["corpus"] + ".json"  # the output name of the corpus file
        units[name] = (inc.UnitSpec(name, "mpfr", f"replay-input:{name}", "--backend mpfr --json"), [])
        seconds[name] = float(mpfr.get("elapsedSeconds", 0.0))
    return units, seconds


def build_commit(worktree: Path, commit: str, patch: Path | None) -> bool:
    """Check out `commit` detached in the scratch worktree, apply the patch if it applies, build.
    Returns whether the patch was applied."""
    git(worktree, "checkout", "-q", "--detach", "--force", commit)
    git(worktree, "clean", "-fdq", "--", "tooling", "library")
    patched = False
    if patch is not None:
        probe = subprocess.run(["git", "apply", "--check", str(patch)], cwd=worktree, capture_output=True, text=True)
        has_arms = "fn arm_add" in (worktree / "tooling/src/frontend/testfloat_expr/testfloat_expr.mbt").read_text(encoding="utf-8")
        if not has_arms and probe.returncode == 0:
            subprocess.run(["git", "apply", str(patch)], cwd=worktree, check=True)
            patched = True
    code = "import sys; sys.path.insert(0, 'tools'); import conformance_cli as c; c.build_backend('testfloat')"
    built = subprocess.run([sys.executable, "-c", code], cwd=worktree, capture_output=True, text=True)
    if built.returncode != 0:
        raise RuntimeError(f"build of {commit} failed:\n{built.stdout[-1500:]}{built.stderr[-1500:]}")
    return patched


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", type=Path, required=True, help="summary.json of a full incremental run")
    parser.add_argument("--count", type=int, default=30)
    parser.add_argument("--ref", default="origin/main")
    parser.add_argument("--worktree", type=Path, default=inc.main_checkout(REPO_ROOT) / ".claude" / "worktrees" / "verify-replay")
    parser.add_argument("--patch", type=Path, default=None, help="the frontend split (git diff of tooling/src)")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    units, seconds = load_units(baseline)
    log = git(REPO_ROOT, "log", "--first-parent", f"-{args.count + 1}", "--format=%H\t%s", args.ref).strip().splitlines()
    commits = [tuple(line.split("\t", 1)) for line in reversed(log)]
    if not args.worktree.exists():
        git(REPO_ROOT, "worktree", "add", "--detach", str(args.worktree), commits[0][0])
        (args.worktree / ".tmp").mkdir(exist_ok=True)
    snapshots: list[Snapshot] = []
    for commit, subject in commits:
        patched = build_commit(args.worktree, commit, args.patch)
        program = cf.read_c_file(args.worktree / C_FILE)
        snapshots.append(snapshot_keys(program, units, commit, subject, patched))
        print(f"replayed {commit[:8]} {subject[:60]}", flush=True)
    rows = [make_row(a, b, seconds) for a, b in zip(snapshots, snapshots[1:])]
    table = format_table(rows, len(units), sum(seconds.get(u, 0.0) for u in units))
    print(table)
    if args.out:
        args.out.write_text(table + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
