#!/usr/bin/env python3
"""Compare the `pub` lines of the `mbti` blocks of the API pages with the generated interfaces.

Every fenced `mbti` block of `doc/manual/api/**` shows lines of the package's
`pkg.generated.mbti`. The package of a page follows from its path:
`api/<name>.md` and `api/<group>/<name>.md` name the folder `<name>` or
`<group>/<name>` under `library/src` or `tooling/src`. A `pub` line of a block is
paired with the interface line that has the same key (the declaration kind and
name, see `line_key`); the pair differs when the lines are not equal after
whitespace normalisation.

    check_manual_signatures.py --check   report every difference, exit 1 if any
    check_manual_signatures.py --fix     rewrite each differing line to the interface line

`--fix` changes one line at a time, never reorders and never touches a line that
has no counterpart in the interface: such a line is reported and left.
Lines that do not start with `pub` (attributes, private types, comments) are
not compared.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
API = Path("doc/manual/api")
ROOTS = (Path("library/src"), Path("tooling/src"))

PUB = re.compile(r"^pub(?:\([a-z]+\))?\s+(fn|let|struct|enum|trait|suberror|type|typealias|impl|const)\b")


@dataclass(frozen=True)
class Difference:
    """One `pub` line of a page: `new` is None when the interface has no counterpart."""

    page: str
    line: int
    old: str
    new: str | None


def normalise(line: str) -> str:
    return " ".join(line.split())


def line_key(line: str) -> str | None:
    """The identity of a `pub` line: its declaration up to the parameters or the body."""
    text = normalise(line)
    match = PUB.match(text)
    if match is None:
        return None
    kind = match.group(1)
    if kind in ("fn", "impl"):
        end = text.find("(")
        return text if end < 0 else text[:end].strip()
    if kind in ("let", "const"):
        return text.split(" : ")[0].split(" = ")[0].strip()
    head, rest = text[: match.end()], text[match.end() :]
    return head + re.split(r" \{|\(| derive\(", rest)[0].rstrip()


def mbti_blocks(text: str) -> list[tuple[int, str]]:
    """The (1-based line number, line) pairs of every line inside an `mbti` fence."""
    found: list[tuple[int, str]] = []
    inside = False
    for number, line in enumerate(text.splitlines(), start=1):
        if inside:
            if line.startswith("```"):
                inside = False
            else:
                found.append((number, line))
        elif re.match(r"^```mbti\b", line):
            inside = True
    return found


def interface_lines(text: str) -> dict[str, list[str]]:
    """The `pub` lines of an interface file, by key (a key may repeat)."""
    index: dict[str, list[str]] = {}
    for line in text.splitlines():
        key = line_key(line)
        if key is not None:
            index.setdefault(key, []).append(line)
    return index


def compare(page: str, lines: list[tuple[int, str]], interface: dict[str, list[str]]) -> list[Difference]:
    """The differences of the `pub` lines of one page against its interface."""
    used: dict[str, int] = {}
    result: list[Difference] = []
    for number, line in lines:
        key = line_key(line)
        if key is None:
            continue
        candidates = interface.get(key, [])
        # prefer an identical line, so that repeated keys do not pair wrongly
        same = [c for c in candidates if normalise(c) == normalise(line)]
        if same:
            continue
        taken = used.get(key, 0)
        if taken < len(candidates):
            used[key] = taken + 1
            result.append(Difference(page, number, line, candidates[taken]))
        else:
            result.append(Difference(page, number, line, None))
    return result


def apply_fixes(text: str, differences: list[Difference]) -> str:
    """The page text with each paired line replaced by its interface line."""
    lines = text.split("\n")
    for diff in differences:
        if diff.new is not None:
            lines[diff.line - 1] = diff.new
    return "\n".join(lines)


def interface_path(page: Path, root: Path) -> Path | None:
    relative = page.relative_to(root / API).with_suffix("")
    for base in ROOTS:
        candidate = root / base / relative / "pkg.generated.mbti"
        if candidate.is_file():
            return candidate
    return None


def check_page(page: Path, root: Path) -> tuple[list[Difference], str]:
    name = str(page.relative_to(root))
    path = interface_path(page, root)
    if path is None:
        return [Difference(name, 0, "", None)], ""
    text = page.read_text()
    diffs = compare(name, mbti_blocks(text), interface_lines(path.read_text()))
    return diffs, text


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--fix", action="store_true")
    parser.add_argument("--root", type=Path, default=REPO)
    args = parser.parse_args(argv)
    total = fixed = orphans = 0
    for page in sorted((args.root / API).rglob("*.md")):
        diffs, text = check_page(page, args.root)
        for diff in diffs:
            total += 1
            if diff.line == 0:
                print(f"{diff.page}: no interface file for this page")
                orphans += 1
                continue
            if diff.new is None:
                orphans += 1
                print(f"{diff.page}:{diff.line}: no counterpart\n  old: {normalise(diff.old)}")
            else:
                print(f"{diff.page}:{diff.line}\n  old: {normalise(diff.old)}\n  new: {diff.new}")
        if args.fix and any(d.new is not None for d in diffs):
            page.write_text(apply_fixes(text, diffs))
            fixed += sum(d.new is not None for d in diffs)
    print(f"differences: {total}, without counterpart: {orphans}, rewritten: {fixed}")
    return 1 if args.check and total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
