#!/usr/bin/env python3
"""Check that every `moon add Luna-Flow/floating@<x>` line names the library version.

The version is the `version` of `library/moon.mod`. The install lines of
`README.md`, `library/README.md`, `tooling/README.md`, `CONTRIBUTING.md` and
`doc/manual/**/*.md` must name exactly that version, so that a version bump cannot
leave an old install line behind. `moon add Luna-Flow/floating-tools@<x>` is another
module and is not checked.

A fenced block whose info string has the word `history` (```` ```bash history ````)
quotes an older release on purpose and is skipped; the changelogs are not scanned.

    check_install_lines.py [--root DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
INSTALL = re.compile(r"moon add Luna-Flow/floating@([^\s`'\")]+)")
VERSION = re.compile(r'^version\s*=\s*"([^"]+)"', re.MULTILINE)
FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")


def library_version(mod_text: str) -> str | None:
    match = VERSION.search(mod_text)
    return match.group(1) if match else None


def stale_lines(text: str, version: str) -> list[tuple[int, str]]:
    """Return (line number, found version) of each install line that differs."""
    found: list[tuple[int, str]] = []
    fence: str | None = None
    skipping = False
    for number, line in enumerate(text.splitlines(), start=1):
        opening = FENCE.match(line)
        if opening:
            marker = opening.group(1)
            if fence is None:
                fence = marker[0]
                skipping = "history" in opening.group(2).split()
            elif marker[0] == fence and not opening.group(2).strip():
                fence = None
                skipping = False
            continue
        if skipping:
            continue
        for match in INSTALL.finditer(line):
            if match.group(1) != version:
                found.append((number, match.group(1)))
    return found


def checked_files(root: Path) -> list[Path]:
    files = [root / "README.md", root / "library/README.md", root / "tooling/README.md", root / "CONTRIBUTING.md"]
    files += sorted((root / "doc/manual").glob("**/*.md"))
    return [path for path in files if path.is_file()]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    args = parser.parse_args(argv)
    mod = args.root / "library/moon.mod"
    version = library_version(mod.read_text()) if mod.is_file() else None
    if version is None:
        print("check_install_lines: no version in library/moon.mod")
        return 1
    errors = 0
    for path in checked_files(args.root):
        for number, found in stale_lines(path.read_text(), version):
            rel = path.relative_to(args.root)
            print(f"{rel}:{number}: moon add names floating@{found}, the library version is {version}")
            errors += 1
    if errors:
        return 1
    print(f"install lines: all name floating@{version}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
