#!/usr/bin/env python3
"""Per-file run time of the native debug tests.

`moon test` reports no per-test or per-file time, so this tool runs every test
file on its own: `moon test <file> --target native --frozen --build-only` links
that file's executable (not timed), then the same command without
`--build-only` runs it and is timed. The table lists the slowest files.

The numbers are run times of one file in isolation, debug build, one process
at a time, so their sum is about the native test stage minus its build time.

    python3 tools/native_test_timing.py [--top 20] [--package library/src/decimal] [--json out.json]

It is a heavy job: run it in a heavy slot.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEST_SUFFIXES = ("_test.mbt", "_wbtest.mbt")
TOTAL_RE = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")
DEFAULT_TOP = 20


class ToolError(Exception):
    pass


def is_test_file(path: Path) -> bool:
    return path.name.endswith(TEST_SUFFIXES)


def test_files(root: Path, package: str | None = None) -> list[Path]:
    """Test files under `library/src` and `tooling/src` (or one package directory), sorted."""
    bases = [root / package] if package else [root / "library/src", root / "tooling/src"]
    return sorted(path for base in bases for path in base.rglob("*.mbt") if is_test_file(path))


def moon_command(path: Path, build_only: bool) -> tuple[str, ...]:
    command = [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "test",
        str(path.relative_to(REPO_ROOT)),
        "--target",
        "native",
        "--frozen",
    ]
    if build_only:
        command.append("--build-only")
    return tuple(command)


def parse_total(output: str) -> tuple[int, int, int] | None:
    found = list(TOTAL_RE.finditer(output))
    if not found:
        return None
    return tuple(int(value) for value in found[-1].groups())  # type: ignore[return-value]


def slowest(rows: list[dict], top: int) -> list[dict]:
    return sorted(rows, key=lambda row: row["seconds"], reverse=True)[:top]


def format_table(rows: list[dict], top: int) -> str:
    chosen = slowest(rows, top)
    total = sum(row["seconds"] for row in rows)
    lines = [
        f"slowest {len(chosen)} of {len(rows)} test files, "
        f"native debug, {total:.1f}s in all",
        "",
        "| file | tests | seconds | share |",
        "| --- | ---: | ---: | ---: |",
    ]
    for row in chosen:
        share = 100.0 * row["seconds"] / total if total else 0.0
        lines.append(
            f"| {row['file']} | {row['tests']} | {row['seconds']:.2f} | {share:.1f}% |"
        )
    return "\n".join(lines)


def run(command: tuple[str, ...]) -> tuple[int, str, float]:
    start = time.monotonic()
    process = subprocess.run(
        command, cwd=REPO_ROOT, capture_output=True, text=True, check=False
    )
    return process.returncode, process.stdout + process.stderr, time.monotonic() - start


def time_file(path: Path) -> dict:
    code, output, _ = run(moon_command(path, build_only=True))
    if code != 0:
        raise ToolError(f"build of {path} failed:\n{output}")
    code, output, seconds = run(moon_command(path, build_only=False))
    if code != 0:
        raise ToolError(f"{path} failed:\n{output}")
    totals = parse_total(output)
    return {
        "file": str(path.relative_to(REPO_ROOT)),
        "tests": totals[0] if totals else 0,
        "seconds": seconds,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--top", type=int, default=DEFAULT_TOP)
    parser.add_argument("--package", help="restrict to one package directory, e.g. library/src/decimal")
    parser.add_argument("--json", type=Path, help="also write every row to this file")
    args = parser.parse_args(argv)
    files = test_files(REPO_ROOT, args.package)
    if not files:
        print("native_test_timing: no test files found", file=sys.stderr)
        return 1
    rows = []
    try:
        for index, path in enumerate(files, 1):
            rows.append(time_file(path))
            print(
                f"[{index}/{len(files)}] {rows[-1]['file']} {rows[-1]['seconds']:.2f}s",
                file=sys.stderr,
            )
    except ToolError as error:
        print(f"native_test_timing: {error}", file=sys.stderr)
        return 1
    if args.json:
        args.json.write_text(json.dumps(rows, indent=1) + "\n")
    print(format_table(rows, args.top))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
