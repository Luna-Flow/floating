#!/usr/bin/env python3
"""Check the package import rules that no compiler error enforces.

The IEEE 754 package `decimal` and the GDA package `decimal_gda` must stay
independent of each other (doc/manual/design/decimal_gda.md, section "A GDA
package independent of `decimal`"), and the status-free coefficient kernel
`internal/decimal_kernel` that both build on must not know either of them.
The library module (`library/moon.mod`) may depend on `Luna-Flow/arithmetic` and
`Luna-Flow/luna-generic` only, and none of its packages may import the tools
module `Luna-Flow/floating-tools` (`tooling/`): benchmarks, command-line
frontends and the differential harness live there (#22).
The three LICENSE files (repository root, `library/`, `tooling/`) must be
byte-identical: each published package carries its own copy.
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

# package directory (below library/src/) -> import paths it must not use.
FORBIDDEN: dict[str, tuple[str, ...]] = {
    "decimal": (f"{MODULE}/decimal_gda",),
    "decimal_gda": (f"{MODULE}/decimal",),
}
# package directories that may import nothing of this module except what they list.
ALLOWED_MODULE_IMPORTS: dict[str, tuple[str, ...]] = {
    # `internal` holds BigInt helpers that the white-box tests use as oracles.
    "internal/decimal_kernel": (f"{MODULE}/internal",),
}

# The only external modules the library module may import (names without version).
LIBRARY_DEPENDENCIES = frozenset({"Luna-Flow/arithmetic", "Luna-Flow/luna-generic"})
TOOLS_MODULE = "Luna-Flow/floating-tools"

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
                found.append(f"library/src/{directory} must not import {path}")
    for directory, allowed in ALLOWED_MODULE_IMPORTS.items():
        pkg_file = src / directory / "moon.pkg"
        if not pkg_file.exists():
            found.append(f"{directory}: missing {pkg_file}")
            continue
        for path in imports_of(pkg_file):
            if is_module_path(path) and path not in allowed:
                found.append(f"library/src/{directory} must not import {path}")
    return found


def manifest_dependencies(manifest: Path) -> list[str]:
    """Module names (versions stripped) of the `import { ... }` block of a `moon.mod`."""
    return [path.split("@", 1)[0] for path in imports_of(manifest)]


def module_violations(root: Path) -> list[str]:
    """Violations of the two-module split: the library's dependencies and imports."""
    found: list[str] = []
    manifest = root / "library" / "moon.mod"
    for dependency in manifest_dependencies(manifest):
        if dependency not in LIBRARY_DEPENDENCIES:
            found.append(f"library/moon.mod must not depend on {dependency}")
    for pkg_file in sorted((root / "library" / "src").rglob("moon.pkg")):
        for path in imports_of(pkg_file):
            if path == TOOLS_MODULE or path.startswith(TOOLS_MODULE + "/"):
                found.append(f"{pkg_file.relative_to(root)} must not import {path}")
            elif not is_module_path(path) and "/" in path:
                module = "/".join(path.split("/")[:2])
                if module not in LIBRARY_DEPENDENCIES and not path.startswith("moonbitlang/core"):
                    found.append(f"{pkg_file.relative_to(root)} must not import {path}")
    return found


LICENSE_FILES = ("LICENSE", "library/LICENSE", "tooling/LICENSE")


def license_violations(root: Path) -> list[str]:
    """The LICENSE of the repository and of both modules must be the same bytes."""
    contents: dict[str, bytes | None] = {}
    for name in LICENSE_FILES:
        path = root / name
        contents[name] = path.read_bytes() if path.is_file() else None
    found = [f"{name} is missing" for name, data in contents.items() if data is None]
    reference = contents[LICENSE_FILES[0]]
    found.extend(
        f"{name} differs from {LICENSE_FILES[0]}"
        for name, data in contents.items()
        if data is not None and reference is not None and data != reference
    )
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repository root")
    args = parser.parse_args(argv)
    found = violations(args.root / "library" / "src") + module_violations(args.root) + license_violations(args.root)
    for line in found:
        print(f"check_imports: {line}", file=sys.stderr)
    if not found:
        print("check_imports: ok")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
