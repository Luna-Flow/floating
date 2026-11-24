#!/usr/bin/env python3
"""Check the log of the native tests of `internal/binary_kernel` for the tier of the row primitives.

The nightly job on an arm64 macOS runner runs the tests in three states
(`LUNA_FLOATING_PORTABLE=1`, `LUNA_FLOATING_LIMBS=c`, default) and passes each
log here. The differential test prints one line:

    luna_limbs: cc_id=... arch_id=... int128=... cpu_features=... tier=<portable|c|asm> (mode <0|1|2>) asm_compiled_in=<n> override=<0|1>

`tier=` is the tier the library chose (the mode in brackets), `asm_compiled_in` says whether
the build has the assembly rows, and `override=1` says that `LUNA_FLOATING_PORTABLE` or
`LUNA_FLOATING_LIMBS` was set in the environment of the test. Three things are checked:

* the runner is the architecture the job is for (`arch_id=2`, arm64): a job that
  silently ran on x86-64 would test nothing it is meant to test;
* the tier: the state `portable` reports `tier=portable`, the state `c` reports `tier=c`,
  and the default state reports the expected tier (`--expected`, set in one line of
  `.github/workflows/nightly.yml`). A log without `tier=` is the log of a build that has
  only the C tier, so its tier is `c`;
* the environment took: the states `portable` and `c` report `override=1`, the default
  state reports `override=0`. A line without `override=` is an error in every state.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ARM64 = 2
STATES = ("portable", "c", "default")


def parse_line(log: str) -> tuple[int | None, str | None, bool | None]:
    """`(arch_id, tier, override)` of the last `luna_limbs:` line of a log; `None` for what the line does not say."""
    lines = [line for line in log.splitlines() if "luna_limbs:" in line]
    if not lines:
        raise ValueError("the log has no `luna_limbs:` line: the differential test did not run")
    line = lines[-1]
    arch = re.search(r"\barch_id=(\d+)", line)
    tier = re.search(r"\btier=([A-Za-z0-9_-]+)", line)
    override = re.search(r"\boverride=([01])\b", line)
    return (int(arch.group(1)) if arch else None, tier.group(1) if tier else None, override.group(1) == "1" if override else None)


def check(log: str, state: str, expected_default: str) -> list[str]:
    """The problems found in the log of one state; empty when it is as expected."""
    if state not in STATES:
        raise ValueError(f"state {state!r}: one of {', '.join(STATES)}")
    arch, tier, override = parse_line(log)
    problems = []
    if arch != ARM64:
        problems.append(f"the runner is not arm64 (arch_id={arch}, expected {ARM64})")
    want_override = state != "default"
    if override is None:
        problems.append("the line has no `override=`")
    elif override != want_override:
        problems.append(f"state {state} reports override={int(override)}, expected override={int(want_override)}")
    reported = tier if tier is not None else "c"
    want_tier = {"portable": "portable", "c": "c", "default": expected_default}[state]
    if reported != want_tier:
        problems.append(f"state {state} reports the tier {reported!r}, expected {want_tier!r}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--state", choices=STATES, required=True)
    parser.add_argument("--expected", required=True, help="the tier the default state must report")
    args = parser.parse_args(argv)
    try:
        problems = check(args.log.read_text(encoding="utf-8", errors="replace"), args.state, args.expected)
    except ValueError as error:
        print(f"check_limbs_tier: {error}", file=sys.stderr)
        return 1
    for problem in problems:
        print(f"check_limbs_tier: {problem}", file=sys.stderr)
    if not problems:
        arch, tier, override = parse_line(args.log.read_text(encoding="utf-8", errors="replace"))
        print(f"check_limbs_tier: state {args.state}: arch_id={arch}, tier={tier or 'c (not reported)'}, override={int(bool(override))}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
