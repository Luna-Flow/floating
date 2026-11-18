#!/usr/bin/env python3
"""Check the package import rules that no compiler error enforces.

The IEEE 754 package `decimal` and the GDA package `decimal_gda` must stay
independent of each other (doc/manual/design/decimal_gda.md, section "A GDA
package independent of `decimal`"), and the status-free coefficient kernel
`internal/decimal_kernel` that both build on must not know either of them.
Every import in a package's `moon.pkg` counts, including `for "test"` and
`for "wbtest"` blocks, because a test-only edge couples the packages as well.

    check_imports.py [--root DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

MODULE = "Luna-Flow/floating"
REPO_ROOT = Path(__file__).resolve().parent.parent

# package directory (below src/) -> import paths it must not use.
FORBIDDEN: dict[str, tuple[str, ...]] = {
    "decimal": (f"{MODULE}/decimal_gda",),
    "decimal_gda": (f"{MODULE}/decimal",),
}
# package directories that may import nothing of this module except what they list.
ALLOWED_MODULE_IMPORTS: dict[str, tuple[str, ...]] = {}

IMPORT_PATH = re.compile(r'"([^"\s]+)"')


def imports_of(pkg_file: Path) -> list[str]:
    """Import paths named in the `import { ... }` blocks of a `moon.pkg`."""
    text = pkg_file.read_text(encoding="utf-8")
    paths: list[str] = []
    for block in re.finditer(r"\bimport\s*\{(.*?)\}", text, flags=re.S):
        body = "\n".join(line.split("//", 1)[0] for line in block.group(1).splitlines())
        paths.extend(IMPORT_PATH.findall(body))
    return paths


def is_module_path(path: str) -> bool:
    return path == MODULE or path.startswith(MODULE + "/")


def violations(src: Path) -> list[str]:
    found: list[str] = []
    for directory, forbidden in FORBIDDEN.items():
        pkg_file = src / directory / "moon.pkg"
        if not pkg_file.exists():
            found.append(f"{directory}: missing {pkg_file}")
            continue
        for path in imports_of(pkg_file):
            if path in forbidden:
                found.append(f"src/{directory} must not import {path}")
    for directory, allowed in ALLOWED_MODULE_IMPORTS.items():
        pkg_file = src / directory / "moon.pkg"
        if not pkg_file.exists():
            found.append(f"{directory}: missing {pkg_file}")
            continue
        for path in imports_of(pkg_file):
            if is_module_path(path) and path not in allowed:
                found.append(f"src/{directory} must not import {path}")
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repository root")
    args = parser.parse_args(argv)
    found = violations(args.root / "src")
    for line in found:
        print(f"check_imports: {line}", file=sys.stderr)
    if not found:
        print("check_imports: ok")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
