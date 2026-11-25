#!/usr/bin/env python3
"""Mutation test of the native test units (`tools/native_units.py`).

For each edit of a scratch worktree the program asks `native_units.make_plan` which keyed units
would run (a baseline ledger holds every unit as passed, the sample rate is 0), and compares the
set with the one an independent account gives: the units whose own `moon test ... --dry-run`
names the edited file as a source of their build (or, for a file the dry run does not list, any
file of its package directory). The dry run is moon's own list of what the unit compiles; it
does not come from the import closure that the key is computed from, so a key that is too coarse
(a unit reruns that does not compile the file) or too fine (a unit that compiles it is reused)
makes the row fail.

One row is behavioural: a one-line edit of `internal/binary_kernel` that a test must see. The
stage is then run for real on the mutated tree (baseline ledger, no sampling) and must fail: an
oracle that does not see the edit would make the key check vacuous.

Usage: python3 tools/native_mutation.py [--worktree DIR] [--no-run]
`--no-run` skips the run of the behavioural row (the plan checks are cheap: one `moon --dry-run`
per unit, about 20 s per plan). The scratch worktree defaults to `native-mutation` beside the
other worktrees; an existing one must be clean and on the HEAD of this checkout.
Exit status: 0 all rows held; 1 a row failed; 2 the scratch worktree is unusable.
"""

from __future__ import annotations

import argparse
import dataclasses
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Mapping, Sequence
from pathlib import Path

import incremental as inc
import kernel_units as ku
import native_units as nu
import verify_mutation as vm

REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclasses.dataclass(frozen=True)
class Edit:
    name: str
    path: str
    kind: str  # "behavioural", "source", "test file", "package file" or "outside"
    mutation: vm.Mutation


def comment(name: str, path: str, text: str = "\n// native-mutation edit\n") -> vm.Mutation:
    return vm.Mutation(name, path, "(a comment appended)", "", "", text, "comment")


KERNEL = next(m for m in vm.MUTATIONS if m.name == "kernel-compare")
EDITS: list[Edit] = [
    Edit("source of the kernel (behavioural)", KERNEL.path, "behavioural", dataclasses.replace(KERNEL, name="native-kernel-source")),
    Edit("source of a package imported by every unit", "library/src/def/types.mbt", "source", comment("def-source", "library/src/def/types.mbt")),
    Edit("white-box test of interval", "library/src/interval/atan2_wbtest.mbt", "test file", comment("interval-wbtest", "library/src/interval/atan2_wbtest.mbt")),
    Edit("doc test file of interval", "library/src/interval/README.mbt.md", "test file", comment("interval-readme", "library/src/interval/README.mbt.md", "\n<!-- native-mutation edit -->\n")),
    Edit("white-box test of an imported package (binary)", "library/src/binary/arith_rows_wbtest.mbt", "test file", comment("binary-wbtest", "library/src/binary/arith_rows_wbtest.mbt")),
    Edit("moon.pkg of an imported package (binary)", "library/src/binary/moon.pkg", "package file", comment("binary-pkg", "library/src/binary/moon.pkg")),
    Edit("a file outside every package (the manual)", "doc/manual/verification.md", "outside", comment("manual", "doc/manual/verification.md", "\nnative-mutation edit\n")),
]


# ---------------------------------------------------------------------------------------
# Pure parts
# ---------------------------------------------------------------------------------------


def lists_file(dry_run: str, path: str) -> bool:
    """Whether a dry run names `path` (a repository-relative path) as a file of some command."""
    return re.search(r"(?<![\w/.])\./" + re.escape(path) + r"(?=[\s'])", dry_run) is not None


def lists_directory(dry_run: str, path: str) -> bool:
    """Whether a dry run names any file directly inside the directory of `path`."""
    directory = path.rsplit("/", 1)[0] if "/" in path else ""
    return bool(directory) and re.search(r"(?<![\w/.])\./" + re.escape(directory) + r"/[^/\s']+(?=[\s'])", dry_run) is not None


def expected_run(path: str, dry_runs: Mapping[str, str]) -> set[str]:
    """The keyed units that must run when `path` is edited, from their dry runs. A source file
    (`.mbt`, `.mbt.md`) is named by the commands that compile it; any other file of a package
    (`moon.pkg`, a stub, a data file) is not, so the units that compile some file of its
    directory count."""
    source = path.endswith((".mbt", ".mbt.md"))
    return {u for u, text in dry_runs.items() if (lists_file(text, path) if source else lists_directory(text, path))}


def judge(edited: str, ran: set[str], expected: set[str], status: int | None, must_fail: bool) -> list[str]:
    """The problems of one row (empty when it held)."""
    problems: list[str] = []
    if ran - expected:
        problems.append(f"too coarse: {sorted(ran - expected)} ran but their build does not compile {edited}")
    if expected - ran:
        problems.append(f"too fine: {sorted(expected - ran)} compile {edited} and would be reused")
    if must_fail and not status:
        problems.append("the stage passed on the mutated tree: no test sees the edit")
    return problems


def format_table(rows: Sequence[Mapping[str, object]]) -> str:
    head = "| edit | kind | units that ran | expected | stage on the mutated tree | verdict |\n| --- | --- | ---: | ---: | --- | --- |"
    return "\n".join([head] + [f"| {r['name']} | {r['kind']} | {r['ran']} | {r['expected']} | {r['stage']} | {r['verdict']} |" for r in rows])


# ---------------------------------------------------------------------------------------
# Files and processes
# ---------------------------------------------------------------------------------------


def scratch_problem(scratch: Path) -> str | None:
    """Why an existing scratch worktree cannot be used, or None: it must be on the HEAD of this
    checkout and clean (tracked files)."""
    head = inc.git_output(REPO_ROOT, "rev-parse", "HEAD")
    there = inc.git_output(scratch, "rev-parse", "HEAD")
    if there != head:
        return f"{scratch} is on {there[:10] or 'no commit'}, this checkout on {head[:10]}: remove it or check it out"
    if inc.git_output(scratch, "status", "--porcelain", "--untracked-files=no"):
        return f"{scratch} has uncommitted changes: clean it"
    return None


def keyed_plan(scratch: Path, ledger: inc.Ledger) -> nu.Plan:
    plan = nu.make_plan(scratch, ledger, seed=0, rate=0.0)
    if plan.disabled:
        raise RuntimeError(f"the plan is disabled: {plan.disabled}")
    return plan


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--worktree", type=Path, default=None)
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args(argv)
    scratch = args.worktree or inc.main_checkout(REPO_ROOT) / ".claude" / "worktrees" / "native-mutation"
    created = not scratch.exists()
    if created:
        subprocess.run(["git", "worktree", "add", "--detach", str(scratch), "HEAD"], cwd=REPO_ROOT, check=True)
    if not (scratch / ".mooncakes").exists() and (REPO_ROOT / ".mooncakes").is_dir():
        # the stage runs with --frozen: the dependencies must be there already
        shutil.copytree(REPO_ROOT / ".mooncakes", scratch / ".mooncakes")
    problem = scratch_problem(scratch)
    if problem:
        print(f"native_mutation: {problem}", file=sys.stderr)
        return 2
    work = Path(tempfile.mkdtemp(prefix="native-mutation-"))
    ledger = inc.Ledger(work / "baseline.jsonl")
    base = keyed_plan(scratch, ledger)
    keyed = [u for u in base.units if u.keyed]
    for unit in keyed:
        if not nu.record_pass(base, unit, 0.0, len(keyed)):
            print(f"native_mutation: cannot record the baseline of {unit.name}", file=sys.stderr)
            return 2
    dry_runs = {u.name: ku.dry_run_commands(nu.test_command(nu.NATIVE_ARGUMENTS, u.members), scratch) for u in keyed}
    rows: list[dict[str, object]] = []
    failed = False
    for edit in EDITS:
        path = scratch / edit.path
        original = path.read_text(encoding="utf-8")
        try:
            path.write_text(vm.apply_mutation(original, edit.mutation), encoding="utf-8")
            plan = keyed_plan(scratch, inc.Ledger(work / "baseline.jsonl"))
            ran = {u.name for u in plan.units if u.keyed and plan.actions[u.name] == "run"}
            expected = expected_run(edit.path, dry_runs)
            status: int | None = None
            if edit.kind == "behavioural" and not args.no_run:
                command = [sys.executable, "tools/native_units.py", "--sample-rate", "0", "--ledger", str(work / "behavioural.jsonl")]
                (work / "behavioural.jsonl").write_text((work / "baseline.jsonl").read_text(encoding="utf-8"), encoding="utf-8")
                status = subprocess.run(command, cwd=scratch).returncode
        finally:
            path.write_text(original, encoding="utf-8")
        problems = judge(edit.path, ran, expected, status, edit.kind == "behavioural" and not args.no_run)
        failed |= bool(problems)
        rows.append(
            {
                "name": edit.name, "kind": edit.kind, "ran": len(ran), "expected": len(expected),
                "stage": "not run" if status is None else ("failed" if status else "PASSED"),
                "verdict": "held" if not problems else "FAILED: " + "; ".join(problems),
            }
        )
        print(format_table(rows[-1:]).split("\n")[-1], flush=True)
    print()
    print(format_table(rows))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
