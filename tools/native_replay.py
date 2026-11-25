#!/usr/bin/env python3
"""Replay the key of the native test units over consecutive commits of a branch.

For each commit the program checks it out in a scratch worktree (no build, no test run), forms the
content digest of every keyed unit of `tools/native_units.py` under the old rule (every file of the
import closure) and the new one (test files and nested packages of imported packages left out), and
reports how many units would rerun against the previous commit and how many seconds of tests they
hold. The seconds are per package (`--seconds`, default `tools/fixtures/native_package_seconds.json`:
every test block run alone, a proxy and an upper bound, not a gate time); a unit's seconds are the
sum over its members.

The table of pull request 819 (30 changes, 139e339b to 526b2a3e):

    git worktree add --detach .claude/worktrees/native-replay 526b2a3e
    python3 tools/native_replay.py --worktree .claude/worktrees/native-replay \\
        $(git log --first-parent --format=%H -31 526b2a3e | tail -r)

(`tail -r` reverses the list on macOS; `tac` elsewhere.) Commits are given oldest first; the first is
only the base. The scratch worktree is left on the last commit. Module files (`moon.mod`, `moon.work`)
are part of every digest, as in the key.
Exit status 0; 2 when the worktree is missing.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

import code_fingerprint as cf
import native_units as nu

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SECONDS = REPO_ROOT / "tools" / "fixtures" / "native_package_seconds.json"


@dataclasses.dataclass(frozen=True)
class UnitDigest:
    old: str  # every file of the closure
    new: str  # imported test files and nested packages left out
    seconds: float


@dataclasses.dataclass(frozen=True)
class Row:
    commit: str
    subject: str
    old_units: int
    new_units: int
    old_seconds: float
    new_seconds: float


def compare(prev: Mapping[str, UnitDigest], cur: Mapping[str, UnitDigest]) -> tuple[list[str], list[str]]:
    """(units that rerun under the old rule, under the new rule): a unit reruns when its digest
    differs from the previous commit's or it is new."""
    old = [u for u, d in cur.items() if u not in prev or prev[u].old != d.old]
    new = [u for u, d in cur.items() if u not in prev or prev[u].new != d.new]
    return old, new


def make_row(commit: str, subject: str, prev: Mapping[str, UnitDigest], cur: Mapping[str, UnitDigest]) -> Row:
    old, new = compare(prev, cur)
    return Row(commit, subject, len(old), len(new), sum(cur[u].seconds for u in old), sum(cur[u].seconds for u in new))


def format_table(rows: Sequence[Row]) -> str:
    lines = [
        "| commit | subject | units rerun, all files | units rerun, imported test files out | seconds, all files | seconds, new |",
        "| --- | --- | ---: | ---: | ---: | ---: |",
    ]
    for r in rows:
        lines.append(f"| {r.commit[:8]} | {r.subject[:70]} | {r.old_units} | {r.new_units} | {r.old_seconds:.1f} | {r.new_seconds:.1f} |")
    lines.append(
        f"| total, {len(rows)} changes | | {sum(r.old_units for r in rows)} | {sum(r.new_units for r in rows)} "
        f"| {sum(r.old_seconds for r in rows):.1f} | {sum(r.new_seconds for r in rows):.1f} |"
    )
    return "\n".join(lines)


def unit_digests(worktree: Path, seconds: Mapping[str, float]) -> dict[str, UnitDigest]:
    """The digests of the keyed units of the tree in `worktree` (reads files)."""
    packages = nu.discover_packages(worktree)
    modules = cf.hash_tree(nu.module_files(worktree), worktree)
    return {
        u.name: UnitDigest(
            nu.digest_unit(worktree, u, packages, False) + modules,
            nu.digest_unit(worktree, u, packages, True) + modules,
            sum(seconds.get(m, 0.0) for m in u.members),
        )
        for u in nu.make_units(packages)
        if u.keyed
    }


def git(worktree: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(worktree), *args], check=True, capture_output=True, text=True).stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--worktree", type=Path, required=True)
    parser.add_argument("--seconds", type=Path, default=DEFAULT_SECONDS)
    parser.add_argument("commits", nargs="+")
    args = parser.parse_args(argv)
    if not args.worktree.is_dir():
        print(f"native_replay: {args.worktree} is not a directory", file=sys.stderr)
        return 2
    seconds = {k: float(v) for k, v in json.loads(args.seconds.read_text(encoding="utf-8"))["packages"].items()}
    git(args.worktree, "checkout", "-q", "--detach", args.commits[0])
    prev = unit_digests(args.worktree, seconds)
    rows: list[Row] = []
    for commit in args.commits[1:]:
        git(args.worktree, "checkout", "-q", "--detach", commit)
        cur = unit_digests(args.worktree, seconds)
        rows.append(make_row(commit, git(args.worktree, "log", "-1", "--format=%s", commit), prev, cur))
        prev = cur
    print(format_table(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
