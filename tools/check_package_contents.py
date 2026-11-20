#!/usr/bin/env python3
"""Check what `moon package` packs for a module of the workspace.

The repository is a `moon.work` workspace of two modules, each in its own
directory (#22): the library `Luna-Flow/floating` in `library/` and the tools
module `Luna-Flow/floating-tools` in `tooling/`. A package is exactly its
directory, so no ignore file is needed. This tool builds the zip with
`moon -C <module> package --frozen` (never publishes) and checks the shape expected
of the module:

- `library` (default): only `moon.mod`, `README.md`, `LICENSE`, `CHANGELOG.md` and
  paths under `src/`; the packed `moon.mod` imports exactly
  `Luna-Flow/arithmetic` and `Luna-Flow/luna-generic`;
- `tools`: only `moon.mod`, `LICENSE`, `README.md`, `CHANGELOG.md` (the last two
  optional) and paths under `src/`; the packed `moon.mod` has the version of
  `library/moon.mod` and imports `Luna-Flow/floating@<that version>`.

    check_package_contents.py [--module library|tools|all] [--root DIR]

`moon package` runs `moon check` first, so the dependencies must be fetched (the
repository gate's dependency stage, or `moon check`, does that). In the workspace
the tools module resolves the library as the member, so no registry is involved
here; the registry is only consulted by the publish dry run.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

from generated_paths import GENERATED_MARKERS, is_generated_path  # noqa: F401

REPO_ROOT = Path(__file__).resolve().parent.parent
ALLOWED_DEPENDENCIES = frozenset({"Luna-Flow/arithmetic", "Luna-Flow/luna-generic"})
LIBRARY = "Luna-Flow/floating"
LIBRARY_TOP_LEVEL_FILES = frozenset({"moon.mod", "README.md", "LICENSE", "CHANGELOG.md"})
LIBRARY_REQUIRED_FILES = LIBRARY_TOP_LEVEL_FILES
TOOLS_TOP_LEVEL_FILES = frozenset({"moon.mod", "LICENSE", "README.md", "CHANGELOG.md"})
TOOLS_REQUIRED_FILES = frozenset({"moon.mod", "LICENSE"})
PACKAGE_LINE = re.compile(r"^Package to (.+\.zip)\s*$", re.MULTILINE)
IMPORT_BLOCK = re.compile(r"\bimport\s*\{(.*?)\}", re.DOTALL)
IMPORT_PATH = re.compile(r'"([^"\s]+)"')
VERSION_LINE = re.compile(r'^version\s*=\s*"([^"]+)"', re.MULTILINE)


# Throwaway sources that gates write into the source trees: the list is shared with
# tools/run_python_tests.py (tools/generated_paths.py). A zip must never hold them even
# if an interrupted gate left them behind.


def generated_paths(names: list[str]) -> list[str]:
    """Packed paths that are throwaway generated sources."""
    return [name for name in names if is_generated_path(name)]


def unexpected_paths(names: list[str], top_level_files: frozenset[str]) -> list[str]:
    """Packed paths outside the shape of a module: its top-level files and `src/`."""
    return [name for name in names if name not in top_level_files and not name.startswith("src/")]


def packed_dependencies(moon_mod: str) -> list[str]:
    """Import paths (with versions) of the `import { ... }` block of a `moon.mod`."""
    found: list[str] = []
    for block in IMPORT_BLOCK.finditer(moon_mod):
        body = "\n".join(line.split("//", 1)[0] for line in block.group(1).splitlines())
        found.extend(IMPORT_PATH.findall(body))
    return found


def summarize(message: str, paths: list[str]) -> str:
    return f"{len(paths)} {message}, for example: {', '.join(paths[:3])}"


def shape_violations(
    names: list[str], top_level_files: frozenset[str], required: frozenset[str], module: str
) -> list[str]:
    found: list[str] = []
    generated = generated_paths(names)
    if generated:
        found.append(
            summarize(
                "packed paths are generated sources of a gate (an interrupted run left them; "
                "remove them and rerun)",
                generated,
            )
        )
    unexpected = [name for name in unexpected_paths(names, top_level_files) if name not in generated]
    if unexpected:
        found.append(
            summarize(
                f"packed paths do not belong in the zip of the {module} module "
                f"(only {', '.join(sorted(top_level_files))} and src/)",
                unexpected,
            )
        )
    found.extend(f"the zip of the {module} module has no {name}" for name in sorted(required - set(names)))
    return found


def library_violations(names: list[str], moon_mod: str | None) -> list[str]:
    found = shape_violations(names, LIBRARY_TOP_LEVEL_FILES, LIBRARY_REQUIRED_FILES, "library")
    if moon_mod is None:
        return found
    modules = [path.split("@", 1)[0] for path in packed_dependencies(moon_mod)]
    for dependency in modules:
        if dependency not in ALLOWED_DEPENDENCIES:
            found.append(f"packed moon.mod must not import {dependency}")
    found.extend(
        f"packed moon.mod does not import {dependency}"
        for dependency in sorted(ALLOWED_DEPENDENCIES - set(modules))
    )
    return found


def tools_violations(names: list[str], moon_mod: str | None, library_version: str) -> list[str]:
    found = shape_violations(names, TOOLS_TOP_LEVEL_FILES, TOOLS_REQUIRED_FILES, "tools")
    if moon_mod is None:
        return found
    version = VERSION_LINE.search(moon_mod)
    if version is None or version.group(1) != library_version:
        found.append(
            f"packed moon.mod has version {version.group(1) if version else 'none'}, "
            f"but the library version is {library_version}"
        )
    pinned = [
        path.split("@", 1)[1] if "@" in path else ""
        for path in packed_dependencies(moon_mod)
        if path.split("@", 1)[0] == LIBRARY
    ]
    if not pinned:
        found.append(f"packed moon.mod must import {LIBRARY}@{library_version}")
    found.extend(
        f"packed moon.mod imports {LIBRARY}@{pinned_version}, but the library version is {library_version}"
        for pinned_version in pinned
        if pinned_version != library_version
    )
    return found


def violations(
    module: str, names: list[str], moon_mod: str | None, library_version: str = ""
) -> list[str]:
    if module == "tools":
        return tools_violations(names, moon_mod, library_version)
    return library_violations(names, moon_mod)


def library_version(root: Path) -> str:
    match = VERSION_LINE.search((root / "library" / "moon.mod").read_text(encoding="utf-8"))
    if match is None:
        raise RuntimeError("library/moon.mod declares no version")
    return match.group(1)


def inspect_zip(path: Path, module: str = "library", version: str = "") -> list[str]:
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if not name.endswith("/")]
        moon_mod = archive.read("moon.mod").decode("utf-8") if "moon.mod" in names else None
    return violations(module, names, moon_mod, version)


def module_directory(module: str) -> str:
    return "tooling" if module == "tools" else "library"


def package_command(module: str) -> list[str]:
    """`moon -C <module directory> package --frozen`: never `moon publish`."""
    return ["sh", "tools/run_moon_clean_exec.sh", "-C", module_directory(module), "package", "--frozen"]


def build_zip(root: Path, module: str = "library") -> Path:
    """Package the module (not published) and return the zip path."""
    environment = dict(os.environ)
    # `-C` makes a relative target directory relative to the module directory: keep
    # the one `_build` of the workspace root.
    environment["CODEX_MOON_TARGET_DIR"] = str(root / "_build")
    result = subprocess.run(
        package_command(module),
        cwd=root,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    match = PACKAGE_LINE.search(result.stdout)
    if result.returncode != 0 or match is None:
        raise RuntimeError(f"moon package --frozen failed:\n{result.stdout}")
    return Path(match.group(1))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--module", choices=("library", "tools", "all"), default="library")
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repository root")
    args = parser.parse_args(argv)
    modules = ("library", "tools") if args.module == "all" else (args.module,)
    status = 0
    for module in modules:
        try:
            version = library_version(args.root)
            found = inspect_zip(build_zip(args.root, module), module, version)
        except (RuntimeError, OSError, zipfile.BadZipFile) as error:
            print(f"check_package_contents: {error}", file=sys.stderr)
            return 1
        for line in found:
            print(f"check_package_contents ({module}): {line}", file=sys.stderr)
        if not found:
            print(f"check_package_contents ({module}): ok")
        status = max(status, 1 if found else 0)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
