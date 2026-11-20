#!/usr/bin/env python3
"""Compile and run the manual's MoonBit examples against the current branch.

The English manual lives in `doc/manual` as plain Markdown, outside the module's
`src` tree, so `moon` never sees its fenced examples. This tool generates one
throwaway package per manual page under `_generated_doc_examples` of a module, re-fences the
examples as `moonbit check` so `moon` compiles them, runs the resulting
black-box tests, and removes the tree again.

Each page becomes its own package because pages pick their own import aliases
and may define helpers with the same name.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANUAL_ROOT = REPO_ROOT / "doc" / "manual"
# A page whose examples use a tools package (`TOOLS_ALIASES`) is compiled in the
# tools module, which imports the library and the tools packages alike. Every
# other page is compiled in the library module, so that the examples of the
# library-internal `@internal` package keep working: a package of the tools
# module cannot import it.
LIBRARY_GENERATED_ROOT = REPO_ROOT / "library" / "src" / "_generated_doc_examples"
TOOLS_GENERATED_ROOT = REPO_ROOT / "tooling" / "src" / "_generated_doc_examples"
GENERATED_ROOTS = (LIBRARY_GENERATED_ROOT, TOOLS_GENERATED_ROOT)
GENERATED_NAME = LIBRARY_GENERATED_ROOT.name
FENCE_RE = re.compile(r"^```moonbit(?P<attributes>[a-z ]*)$")

FLOATING_PACKAGES = (
    "ball_float",
    "ball_float_checked",
    "bin_float",
    "bin_float_checked",
    "decimal",
    "decimal_checked",
    "decimal_gda",
    "decimal_gda_checked",
    "def",
    "internal",
)
TOOLS_PACKAGES = ("bench", "numeric_expr", "consistency", "semantic")
# Packages whose alias is not the last component of a path directly below the module.
TOOLS_PATH_ALIASES = {
    "conformance": "internal/conformance",
    "runner_cli": "internal/runner_cli",
    "dispatch": "cli/dispatch",
}
FRONTEND_PACKAGES = ("gda_expr", "itl_expr", "mpfr_expr", "testfloat_expr")
CLI_PACKAGES = ("gda_expr_cli", "itl_expr_cli", "mpfr_expr_cli", "testfloat_expr_cli")
TOOLS_ALIASES = frozenset((*TOOLS_PACKAGES, *FRONTEND_PACKAGES, *CLI_PACKAGES, *TOOLS_PATH_ALIASES))


def generated_root(page: "Page") -> Path:
    """The generated-package root of the module that compiles the page."""
    if set(page.aliases) & TOOLS_ALIASES:
        return TOOLS_GENERATED_ROOT
    return LIBRARY_GENERATED_ROOT


def alias_map() -> dict[str, str]:
    aliases = {
        "lf_arith": "Luna-Flow/arithmetic",
        "arithmetic": "Luna-Flow/arithmetic",
        "luna": "Luna-Flow/luna-generic",
        "lf_alg": "Luna-Flow/luna-generic",
        "bigint": "moonbitlang/core/bigint",
        "debug": "moonbitlang/core/debug",
        "env": "moonbitlang/core/env",
        "string": "moonbitlang/core/string",
    }
    for name in FLOATING_PACKAGES:
        aliases[name] = f"Luna-Flow/floating/{name}"
    for name in TOOLS_PACKAGES:
        aliases[name] = f"Luna-Flow/floating-tools/{name}"
    for name, path in TOOLS_PATH_ALIASES.items():
        aliases[name] = f"Luna-Flow/floating-tools/{path}"
    for name in FRONTEND_PACKAGES:
        aliases[name] = f"Luna-Flow/floating-tools/frontend/{name}"
    for name in CLI_PACKAGES:
        aliases[name] = f"Luna-Flow/floating-tools/cli/{name}"
    return aliases


@dataclass(frozen=True)
class Page:
    path: Path
    slug: str
    blocks: tuple[str, ...]
    aliases: tuple[str, ...]
    unknown_aliases: tuple[str, ...]


def checkable_blocks(text: str) -> list[str]:
    """Return every fenced `moonbit` block that is not marked `nocheck`."""
    blocks: list[str] = []
    lines = text.split("\n")
    index = 0
    while index < len(lines):
        match = FENCE_RE.match(lines[index])
        if match is None:
            index += 1
            continue
        body: list[str] = []
        index += 1
        while index < len(lines) and lines[index] != "```":
            body.append(lines[index])
            index += 1
        if match.group("attributes").strip() != "nocheck":
            blocks.append("\n".join(body))
        index += 1
    return blocks


def page_slug(path: Path) -> str:
    relative = path.relative_to(MANUAL_ROOT).with_suffix("")
    return re.sub(r"[^a-z0-9]+", "_", str(relative).lower())


def collect_pages() -> list[Page]:
    known = alias_map()
    pages: list[Page] = []
    for path in sorted(MANUAL_ROOT.rglob("*.md")):
        blocks = checkable_blocks(path.read_text(encoding="utf-8"))
        if not blocks:
            continue
        referenced = set(re.findall(r"@([a-z_][a-z_0-9]*)", "\n".join(blocks)))
        pages.append(
            Page(
                path=path,
                slug=page_slug(path),
                blocks=tuple(blocks),
                aliases=tuple(sorted(referenced & known.keys())),
                unknown_aliases=tuple(sorted(referenced - known.keys())),
            )
        )
    return pages


def write_package(page: Page) -> Path:
    known = alias_map()
    directory = generated_root(page) / page.slug
    directory.mkdir(parents=True, exist_ok=True)
    imports = "".join(f'  "{known[alias]}" @{alias},\n' for alias in page.aliases)
    # A package with no imports still needs a well-formed manifest.
    directory.joinpath("moon.pkg").write_text(
        f'import {{\n{imports}}} for "test"\n', encoding="utf-8"
    )
    body = "\n".join(f"```moonbit check\n{block}\n```\n" for block in page.blocks)
    directory.joinpath("README.mbt.md").write_text(
        f"# Generated from {page.path.relative_to(REPO_ROOT)}\n\n"
        "Do not edit: `tools/check_doc_examples.py` regenerates and removes this\n"
        f"package on every run.\n\n{body}",
        encoding="utf-8",
    )
    return directory


TOTAL_RE = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")


def moon_test_command(directories: list[Path], target: str) -> tuple[str, ...]:
    """One `moon test` call over every generated page package.

    `moon test` takes several package paths, so the workspace is resolved and
    the test executables are linked in one invocation instead of one per page
    (about 50).

    `--deny-warn` makes a warning of an example (a deprecated call, an unused
    value) a failure of its page: the compiler names the page and the line, so no
    output has to be searched for warnings, and the library packages that the pages
    import are not affected (they are checked with `--deny-warn` by the other stages).
    """
    return (
        "sh",
        "tools/run_moon_clean_exec.sh",
        "test",
        *(str(directory.relative_to(REPO_ROOT)) for directory in directories),
        "--target",
        target,
        "--deny-warn",
    )


def parse_totals(output: str) -> tuple[int, int, int] | None:
    """(total, passed, failed) of the last `Total tests:` line, if any."""
    found = list(TOTAL_RE.finditer(output))
    if not found:
        return None
    total, passed, failed = (int(value) for value in found[-1].groups())
    return total, passed, failed


def failing_pages(output: str, pages: list[Page]) -> list[Page]:
    """The pages whose generated package directory the output mentions."""
    return [page for page in pages if f"{GENERATED_NAME}/{page.slug}/" in output]


def run_pages(
    pages: list[Page], directories: list[Path], target: str
) -> tuple[bool, str, tuple[int, int, int] | None]:
    completed = subprocess.run(
        moon_test_command(directories, target),
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    output = completed.stdout + completed.stderr
    return completed.returncode == 0, output, parse_totals(output)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compile and run the manual's MoonBit examples"
    )
    parser.add_argument("--target", default="native")
    parser.add_argument(
        "--keep",
        action="store_true",
        help="keep the generated packages for inspection after the run",
    )
    arguments = parser.parse_args(argv)

    for root in GENERATED_ROOTS:
        shutil.rmtree(root, ignore_errors=True)
    pages = collect_pages()
    if not pages:
        print("no manual examples found", file=sys.stderr)
        return 1

    failures: list[str] = []
    examples = 0
    tests = 0
    runnable: list[Page] = []
    directories: list[Path] = []
    try:
        for page in pages:
            relative = page.path.relative_to(REPO_ROOT)
            if page.unknown_aliases:
                failures.append(
                    f"{relative}: unknown package aliases "
                    f"{', '.join('@' + alias for alias in page.unknown_aliases)}; "
                    "add them to alias_map() in tools/check_doc_examples.py"
                )
                continue
            examples += len(page.blocks)
            directories.append(write_package(page))
            runnable.append(page)
        if runnable:
            passed, output, totals = run_pages(runnable, directories, arguments.target)
            if totals is not None:
                tests = totals[0]
            if not passed or totals is None or totals[2] != 0:
                blamed = failing_pages(output, runnable)
                names = ", ".join(str(page.path.relative_to(REPO_ROOT)) for page in blamed)
                failures.append(
                    f"manual examples failed{f' (output names {names})' if names else ''}\n{output.rstrip()}"
                )
    finally:
        if not arguments.keep:
            for root in GENERATED_ROOTS:
                shutil.rmtree(root, ignore_errors=True)

    if failures:
        for failure in failures:
            print(failure)
        print(
            f"manual examples: {len(failures)} of {len(pages)} pages failed",
            file=sys.stderr,
        )
        return 1
    print(
        f"manual examples: {examples} blocks across {len(pages)} pages compile, "
        f"{tests} tests pass"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
