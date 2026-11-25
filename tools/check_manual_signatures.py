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

PUB = re.compile(
    r"^(?:pub(?:\([a-z]+\))?\s+)?(fn|let|struct|enum|trait|suberror|type|typealias|impl|const)\b"
)


@dataclass(frozen=True)
class Item:
    """One declaration of a block or an interface: attribute lines, then the item itself.

    `lines` are the original lines; `canon` is their whitespace-normalised text. A page
    that writes `} derive(Eq)` where the interface has `#derive(Eq)` before the item differs.
    """

    first: int
    lines: tuple[str, ...]
    key: str
    canon: str


@dataclass(frozen=True)
class Difference:
    """One item of a page: `new` is None when the interface has no counterpart."""

    page: str
    line: int
    old: tuple[str, ...]
    new: tuple[str, ...] | None


def normalise(line: str) -> str:
    return " ".join(line.split())


def line_key(line: str) -> str | None:
    """The identity of a declaration line: its kind and name, up to the parameters or the body."""
    text = normalise(line)
    match = PUB.match(text)
    if match is None or line[:1].isspace():
        return None
    kind = match.group(1)
    if kind in ("fn", "impl"):
        end = text.find("(")
        return text if end < 0 else text[:end].strip()
    if kind in ("let", "const"):
        return text.split(" : ")[0].split(" = ")[0].strip()
    head, rest = text[: match.end()], text[match.end() :]
    return head + re.split(r" \{|\(| derive\(", rest)[0].rstrip()


def canonical(lines: list[str]) -> str:
    """The lines of an item, each whitespace normalised (an attribute line stays a line)."""
    return "\n".join(normalise(line) for line in lines)


def parse_items(lines: list[tuple[int, str]]) -> list[Item]:
    """Split numbered lines into items; lines outside an item (comments, blanks) are skipped."""
    items: list[Item] = []
    pending: list[tuple[int, str]] = []
    index = 0
    while index < len(lines):
        number, line = lines[index]
        index += 1
        if line.startswith("#"):
            pending.append((number, line))
            continue
        key = line_key(line)
        if key is None:
            pending = []
            continue
        taken = pending + [(number, line)]
        if normalise(line).endswith("{"):
            while index < len(lines):
                number, line = lines[index]
                index += 1
                taken.append((number, line))
                if line.startswith("}"):
                    break
        pending = []
        texts = [text for _, text in taken]
        items.append(Item(taken[0][0], tuple(texts), key, canonical(texts)))
    return items


def mbti_blocks(text: str) -> list[list[tuple[int, str]]]:
    """The numbered lines of every `mbti` fence, one list per block."""
    found: list[list[tuple[int, str]]] = []
    inside = False
    for number, line in enumerate(text.splitlines(), start=1):
        if inside:
            if line.startswith("```"):
                inside = False
            else:
                found[-1].append((number, line))
        elif re.match(r"^```mbti\b", line):
            inside = True
            found.append([])
    return found


def interface_items(text: str) -> dict[str, list[Item]]:
    """The items of an interface file, by key (a key may repeat)."""
    index: dict[str, list[Item]] = {}
    for item in parse_items(list(enumerate(text.splitlines(), start=1))):
        index.setdefault(item.key, []).append(item)
        if " trait " in item.key:
            # a page may show one method of a trait on its own line
            for inner in item.lines:
                method = inner.strip()
                key = line_key(method) if inner[:1].isspace() else None
                if key is not None:
                    index.setdefault(key, []).append(Item(item.first, (method,), key, normalise(method)))
    return index


def compare(page: str, items: list[Item], interface: dict[str, list[Item]]) -> list[Difference]:
    """The items of one page that differ from the interface."""
    used: dict[str, int] = {}
    result: list[Difference] = []
    for item in items:
        candidates = interface.get(item.key, [])
        if any(c.canon == item.canon for c in candidates):
            continue
        taken = used.get(item.key, 0)
        if taken < len(candidates):
            used[item.key] = taken + 1
            result.append(Difference(page, item.first, item.lines, candidates[taken].lines))
        else:
            result.append(Difference(page, item.first, item.lines, None))
    return result


def apply_fixes(text: str, differences: list[Difference]) -> str:
    """The page text with each paired item replaced by its interface lines."""
    lines = text.split("\n")
    for diff in sorted(differences, key=lambda d: d.line, reverse=True):
        if diff.new is not None:
            start = diff.line - 1
            lines[start : start + len(diff.old)] = list(diff.new)
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
        return [Difference(name, 0, (), None)], ""
    text = page.read_text()
    interface = interface_items(path.read_text())
    items = [item for block in mbti_blocks(text) for item in parse_items(block)]
    diffs = compare(name, items, interface)
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
                print(f"{diff.page}:{diff.line}: no counterpart")
                print("\n".join("  old: " + normalise(t) for t in diff.old))
            else:
                print(f"{diff.page}:{diff.line}")
                print("\n".join("  old: " + normalise(t) for t in diff.old))
                print("\n".join("  new: " + t for t in diff.new))
        if args.fix and any(d.new is not None for d in diffs):
            page.write_text(apply_fixes(text, diffs))
            fixed += sum(d.new is not None for d in diffs)
    print(f"differences: {total}, without counterpart: {orphans}, rewritten: {fixed}")
    return 1 if args.check and total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
