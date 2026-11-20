#!/usr/bin/env python3
"""Run the Python tooling tests and fail if one of them writes into the real repository.

A test that writes into `library/`, `tooling/`, `doc/` or `testdata/` of the checkout
it runs in races with the other stages of the quick gate: its `python` lane runs
concurrently with the `moon` lane, and a `moon` command that scans a source tree
while a test creates and deletes a file there fails with "input ... missing"
(#417). Tests must use a temporary directory (every tool function that writes takes
its root as a parameter).

This runner executes `unittest discover -s tools -p "*_test.py"` and records every
write that goes through `pathlib`, `open`, `os` or `shutil` to a path below a
protected directory, however briefly the file exists; it also compares
`git status --porcelain --ignored` of `library/src` and `tooling/src` before and after
the suite, which catches writes made by a subprocess.

The tree cannot say which process wrote a file, and another stage of the quick gate
writes throwaway sources into the same trees concurrently (the manual examples, the
IEEE smoke; #431). The paths of `tools/generated_paths.py`, the one list of those
files, are therefore left out of the comparison; the in-process recorder does not
leave them out, so a test that writes one itself is still reported. A subprocess of a
test that writes a file with one of those names is the one case that goes unseen.
The cost is a patched write call (microseconds) and two `git status` runs of about
0.05 s.

    run_python_tests.py [unittest arguments]
"""

from __future__ import annotations

import builtins
import os
import shutil
import subprocess
import sys
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from generated_paths import is_generated_path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROTECTED = ("library", "tooling", "doc", "testdata")
GIT_STATUS_PATHS = ("library/src", "tooling/src")


def protected_relative(path: object, root: Path = REPO_ROOT) -> str | None:
    """The path relative to `root` when it lies below a protected directory, else None."""
    try:
        resolved = Path(os.fspath(path)).resolve()  # type: ignore[arg-type]
        relative = resolved.relative_to(root.resolve())
    except (TypeError, ValueError, OSError):
        return None
    return str(relative) if relative.parts and relative.parts[0] in PROTECTED else None


def write_mode(mode: str) -> bool:
    return any(flag in mode for flag in "wax+")


@contextmanager
def record_protected_writes(
    root: Path = REPO_ROOT, protected: tuple[str, ...] = PROTECTED
) -> Iterator[list[str]]:
    """Record the writes below `root/<protected>` made while the context is active."""
    hits: list[str] = []

    def note(path: object, kind: str) -> None:
        relative = protected_relative(path, root)
        if relative is not None and relative.split(os.sep)[0] in protected:
            hits.append(f"{kind} {relative}")

    originals: list[tuple[object, str, object]] = []

    def patch(owner: object, name: str, make) -> None:
        original = getattr(owner, name)
        originals.append((owner, name, original))
        setattr(owner, name, make(original))

    def path_method(kind: str, index: int = 0):
        def make(original):
            def wrapper(self, *args, **kwargs):
                note(self, kind)
                return original(self, *args, **kwargs)

            return wrapper

        return make

    def function(kind: str, positions: tuple[int, ...] = (0,)):
        def make(original):
            def wrapper(*args, **kwargs):
                # A name relative to a directory descriptor (what `shutil.rmtree`
                # does internally) is not a path of the checkout.
                if kwargs.get("dir_fd") is not None:
                    return original(*args, **kwargs)
                for position in positions:
                    if position < len(args):
                        note(args[position], kind)
                return original(*args, **kwargs)

            return wrapper

        return make

    for name in ("write_text", "write_bytes", "touch", "mkdir", "unlink", "rmdir", "rename", "replace"):
        patch(Path, name, path_method(f"Path.{name}"))
    for name, positions in (
        ("mkdir", (0,)),
        ("makedirs", (0,)),
        ("remove", (0,)),
        ("unlink", (0,)),
        ("rename", (0, 1)),
        ("replace", (0, 1)),
        ("rmdir", (0,)),
    ):
        patch(os, name, function(f"os.{name}", positions))
    for name, positions in (
        ("copy", (1,)),
        ("copy2", (1,)),
        ("copyfile", (1,)),
        ("copytree", (1,)),
        ("move", (0, 1)),
        ("rmtree", (0,)),
    ):
        patch(shutil, name, function(f"shutil.{name}", positions))

    real_open = builtins.open

    def recording_open(file, mode="r", *args, **kwargs):  # noqa: ANN001
        if isinstance(file, (str, os.PathLike)) and write_mode(mode):
            note(file, "open")
        return real_open(file, mode, *args, **kwargs)

    originals.append((builtins, "open", real_open))
    builtins.open = recording_open  # type: ignore[assignment]
    try:
        yield hits
    finally:
        for owner, name, original in reversed(originals):
            setattr(owner, name, original)


def status_difference(before: str, after: str) -> list[str]:
    """Entries of `git status --porcelain` that differ, without the generated sources."""

    def entries(status: str) -> set[str]:
        return {
            line
            for line in status.splitlines()
            if line.strip() and not is_generated_path(line[3:])
        }

    first, second = entries(before), entries(after)
    return sorted(f"- {line}" for line in first - second) + sorted(f"+ {line}" for line in second - first)


def git_status(root: Path = REPO_ROOT, paths: tuple[str, ...] = GIT_STATUS_PATHS) -> str:
    result = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all", "--ignored", "--", *paths],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout if result.returncode == 0 else ""


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    tools = REPO_ROOT / "tools"
    sys.path.insert(0, str(tools))
    before = git_status()
    with record_protected_writes() as hits:
        suite = unittest.defaultTestLoader.discover(
            arguments[0] if arguments else str(tools), pattern="*_test.py", top_level_dir=str(tools)
        )
        result = unittest.TextTestRunner(stream=sys.stderr, verbosity=0).run(suite)
    after = git_status()
    status = 0 if result.wasSuccessful() else 1
    if hits:
        print("run_python_tests: tests wrote into the real repository (use a temporary directory):", file=sys.stderr)
        for line in sorted(set(hits)):
            print(f"  {line}", file=sys.stderr)
        status = 1
    difference = status_difference(before, after)
    if difference:
        print("run_python_tests: the content of library/src or tooling/src changed during the tests:", file=sys.stderr)
        for line in difference:
            print(f"  {line}", file=sys.stderr)
        status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
