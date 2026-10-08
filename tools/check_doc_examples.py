#!/usr/bin/env python3
"""Compile and run the manual's MoonBit examples against the current branch.

The English manual lives in `doc/manual` as plain Markdown, outside the module's
`src` tree, so `moon` never sees its fenced examples. This tool generates one
throwaway package per manual page under `src/<GENERATED_ROOT>`, re-fences the
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
GENERATED_ROOT = REPO_ROOT / "src" / "_generated_doc_examples"
FENCE_RE = re.compile(r"^```moonbit(?P<attributes>[a-z ]*)$")

FLOATING_PACKAGES = (
    "ball_float",
    "ball_float_checked",
    "bench",
    "bin_float",
    "bin_float_checked",
    "consistency",
    "decimal",
    "decimal_checked",
    "decimal_gda",
    "decimal_gda_checked",
    "def",
    "internal",
    "numeric_expr",
    "semantic",
)
FRONTEND_PACKAGES = ("gda_expr", "itl_expr", "mpfr_expr", "testfloat_expr")
CLI_PACKAGES = ("gda_expr_cli", "itl_expr_cli", "mpfr_expr_cli", "testfloat_expr_cli")


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
    for name in FRONTEND_PACKAGES:
        aliases[name] = f"Luna-Flow/floating/frontend/{name}"
    for name in CLI_PACKAGES:
        aliases[name] = f"Luna-Flow/floating/cli/{name}"
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
    directory = GENERATED_ROOT / page.slug
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


def run_page(page: Page, directory: Path, target: str) -> tuple[bool, str]:
    completed = subprocess.run(
        (
            "sh",
            "tools/run_moon_clean_exec.sh",
            "test",
            str(directory.relative_to(REPO_ROOT)),
            "--target",
            target,
        ),
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    return completed.returncode == 0, completed.stdout + completed.stderr


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

    shutil.rmtree(GENERATED_ROOT, ignore_errors=True)
    pages = collect_pages()
    if not pages:
        print("no manual examples found", file=sys.stderr)
        return 1

    failures: list[str] = []
    examples = 0
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
            directory = write_package(page)
            passed, output = run_page(page, directory, arguments.target)
            if not passed:
                failures.append(f"{relative}: examples failed\n{output.rstrip()}")
            if not arguments.keep:
                shutil.rmtree(directory, ignore_errors=True)
    finally:
        if not arguments.keep:
            shutil.rmtree(GENERATED_ROOT, ignore_errors=True)

    if failures:
        for failure in failures:
            print(failure)
        print(
            f"manual examples: {len(failures)} of {len(pages)} pages failed",
            file=sys.stderr,
        )
        return 1
    print(f"manual examples: {examples} across {len(pages)} pages compile and pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
