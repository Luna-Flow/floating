#!/usr/bin/env python3
"""Every test block states where its expected value comes from.

The maintainer's rule (2026-11-21): an oracle that is not independent of the code
under test is a serious problem. After issue 624 (a copy of a reader tested against
its original) every test block of `library/src` and `tooling/src` carries an oracle
declaration, a comment block directly above `test "..."`:

    ///|
    // oracle: A
    // source: expected endpoints written out from the standard, computed with Python math.isqrt
    // shares: nothing
    test "..." {

Keys (a value may continue on the following comment lines):

    oracle:      the levels, comma separated, the weakest last: A, B, E, S.
                 A external (written out, a corpus or program of another implementation),
                 B independent inside the repository (another algorithm; needs `primitives:`),
                 E equivalence with the previous implementation (needs `underneath:`),
                 S self-consistency (round trips, identities, is_ok only). Level C (the oracle
                 is the code under test, a sibling, a copy, or a wrapper against what it wraps)
                 is refused: a block whose only oracle is C is repaired, not declared.
    source:      what produces the expected value.
    shares:      the functions the oracle and the code under test both use ("nothing" if none).
    primitives:  B: the shared primitives, each of which has a level A oracle on the inputs used.
    underneath:  E: the level A or B oracle of the previous implementation on the same input
                 class (a file, corpus or test), naming the level.

A block (or the first 60 lines of its file) that states its level in plain words is accepted as
well and counted as `prose`: the word "oracle" and `level A|B|E|S` (`Oracle (level A): ...`,
`ORACLE level A`, `Oracle, level A`); a statement whose first level is C is refused. Convert such blocks to the
key form when you touch them.

A file made of generated tables takes one block in its first 60 lines instead:

    // oracle-file: A
    // producer: tools/generate_hex_ctx_rows.py
    // input: ...
    // library-ran: no

The blocks that existed when the rule started are in `tools/oracle_debt.txt` (path::name and
the level the audit of 2026-11-21 gave them). The list can only shrink: an entry leaves it
with a valid declaration (or when its block is deleted, with a line in the PR body saying what
replaces it); a block that is not in the list must declare; a renamed block is a new block;
`DEBT_LIMIT` below is the length of the list and is lowered with it.

What this tool checks is the form. What it cannot check, and the reviewer does: that the
level is true, that `source` is really independent of the code under test and was not
produced by running this library, that `shares` is complete, and that the underneath oracle
covers the same input class. The reviewer checks the statement of the oracle, not only that
the test passes (RULES.md).

    check_test_oracles.py            check the repository, print the counts
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEBT_FILE = REPO / "tools" / "oracle_debt.txt"
# The length of tools/oracle_debt.txt. Lowering the list lowers this number in the same commit;
# raising it is visible in review and is a decision, not a side effect.
DEBT_LIMIT = 787
ROOTS = ("library/src", "tooling/src")
LEVELS = ("A", "B", "E", "S")
KEYS = ("oracle", "source", "shares", "primitives", "underneath")
FILE_KEYS = ("oracle-file", "producer", "input", "library-ran")
TEST_RE = re.compile(r'^(?:async\s+)?test\s+"((?:[^"\\]|\\.)*)"')
PLACEHOLDER_RE = re.compile(r"^(see\b|same\b|as above|n/?a\b|todo|tbd|-+$|none$|\.\.\.)", re.IGNORECASE)
KEY_RE = re.compile(r"^//+\s*(oracle-file|oracle|source|shares|primitives|underneath|producer|input|library-ran)\s*:\s*(.*)$")


class Block:
    def __init__(self, path: str, name: str, line: int, comment: list[str]) -> None:
        self.path = path
        self.name = name
        self.line = line
        self.comment = comment

    @property
    def key(self) -> str:
        return f"{self.path}::{self.name}"


def test_files(root: Path = REPO) -> list[Path]:
    files: list[Path] = []
    for top in ROOTS:
        files.extend(sorted((root / top).rglob("*.mbt")))
    return [path for path in files if path.name.endswith(("_test.mbt", "_wbtest.mbt"))]


def parse_blocks(path: Path, root: Path = REPO) -> list[Block]:
    lines = path.read_text(encoding="utf-8").splitlines()
    relative = path.relative_to(root).as_posix()
    blocks: list[Block] = []
    for index, line in enumerate(lines):
        match = TEST_RE.match(line)
        if match is None:
            continue
        comment: list[str] = []
        cursor = index - 1
        while cursor >= 0 and lines[cursor].lstrip().startswith("#"):  # attributes such as #skip(...)
            cursor -= 1
        while cursor >= 0 and lines[cursor].lstrip().startswith("//"):
            text = lines[cursor].strip()
            if text != "///|":
                comment.append(text)
            cursor -= 1
        comment.reverse()
        blocks.append(Block(relative, match.group(1), index + 1, comment))
    return blocks


def parse_keys(comment: list[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    current: str | None = None
    for text in comment:
        match = KEY_RE.match(text)
        if match is not None:
            current = match.group(1)
            values[current] = match.group(2).strip()
        elif current is not None:
            values[current] = (values[current] + " " + text.lstrip("/ ").strip()).strip()
    return values


def head_comment(head: list[str]) -> list[str]:
    """The comment lines of the first 60 lines of a file, without the `///|` markers."""
    comment: list[str] = []
    for line in head:
        text = line.strip()
        if text.startswith("//") and text != "///|":
            comment.append(text)
    return comment


PROSE_LEVEL_RE = re.compile(r"\blevels?\s+([A-Z])\b")
PROSE_ORACLE_RE = re.compile(r"\boracles?\b", re.IGNORECASE)


def prose_levels(comment: list[str]) -> list[str]:
    """The levels a comment states in plain words (`Oracle (level A): ...`, `ORACLE level A`,
    `(oracle level A)`, `Oracle, level A`): the word oracle and at least one `level X`. Several
    authors wrote the declaration this way before the key form existed; a clear statement is
    accepted (counted as `prose`), a statement whose first level is C is refused like the key form (a later mention of C, such as "the old test was level C", is history)."""
    text = " ".join(line.lstrip("/ ").strip() for line in comment)
    if not PROSE_ORACLE_RE.search(text):
        return []
    found: list[str] = []
    for match in PROSE_LEVEL_RE.finditer(text):
        if match.group(1) not in found:
            found.append(match.group(1))
    return found


def file_declaration(path: Path, root: Path = REPO) -> dict[str, str] | None:
    head = path.read_text(encoding="utf-8").splitlines()[:60]
    values = parse_keys(head_comment(head))
    return values if "oracle-file" in values else None


def levels_of(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]


def check_file_declaration(path: str, values: dict[str, str], root: Path) -> list[str]:
    problems: list[str] = []
    for level in levels_of(values["oracle-file"]):
        if level not in LEVELS:
            problems.append(f"{path}: oracle-file level {level!r} is not one of A, B, E, S (level C is refused)")
    producer = values.get("producer", "")
    if not producer:
        problems.append(f"{path}: oracle-file without `producer:`")
    else:
        first = producer.split()[0].strip("`")
        if not (root / first).exists():
            problems.append(f"{path}: producer {first!r} does not exist")
    if not values.get("input"):
        problems.append(f"{path}: oracle-file without `input:`")
    if values.get("library-ran", "").lower() not in ("no", "yes"):
        problems.append(f"{path}: oracle-file needs `library-ran: no` or `library-ran: yes`")
    elif values["library-ran"].lower() == "yes":
        problems.append(f"{path}: a table produced by running this library is not an oracle (library-ran: yes)")
    return problems


def check_declaration(block: Block, values: dict[str, str]) -> list[str]:
    where = f"{block.path}:{block.line}: test {block.name!r}"
    problems: list[str] = []
    oracle = values.get("oracle")
    if oracle is None:
        return [f"{where}: no `// oracle:` line"]
    levels = levels_of(oracle)
    if not levels:
        return [f"{where}: empty `oracle:`"]
    for level in levels:
        if level == "C":
            problems.append(f"{where}: level C is refused (the oracle is not independent of the code under test): repair the test")
        elif level not in LEVELS:
            problems.append(f"{where}: oracle level {level!r} is not one of A, B, E, S")
    source = values.get("source", "")
    if len(source) < 8 or PLACEHOLDER_RE.match(source):
        problems.append(f"{where}: `source:` must say what produces the expected value (got {source!r})")
    shares = values.get("shares", "")
    if not shares or PLACEHOLDER_RE.match(shares) and shares.lower() != "nothing":
        problems.append(f"{where}: `shares:` must name the shared functions or say `nothing` (got {shares!r})")
    if "B" in levels:
        primitives = values.get("primitives", "")
        if len(primitives) < 3 or primitives.lower() == "nothing" or PLACEHOLDER_RE.match(primitives):
            problems.append(f"{where}: level B needs `primitives:` naming the shared primitives that have a level A oracle")
    if "E" in levels:
        underneath = values.get("underneath", "")
        if not re.search(r"\b[AB]\b", underneath) or len(underneath) < 8:
            problems.append(f"{where}: level E needs `underneath:` naming the level A or B oracle under the old implementation on the same input class")
    return problems


def read_debt(path: Path = DEBT_FILE) -> dict[str, str]:
    debt: dict[str, str] = {}
    if not path.exists():
        return debt
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        key, _, level = line.partition("\t")
        debt[key] = level or "?"
    return debt


def check(root: Path = REPO, debt_file: Path | None = None, debt_limit: int | None = None) -> tuple[list[str], Counter, Counter]:
    debt = read_debt(debt_file if debt_file is not None else root / "tools" / "oracle_debt.txt")
    limit = DEBT_LIMIT if debt_limit is None else debt_limit
    problems: list[str] = []
    declared: Counter = Counter()
    seen: set[str] = set()
    for path in test_files(root):
        relative = path.relative_to(root).as_posix()
        file_values = file_declaration(path, root)
        if file_values is not None:
            problems.extend(check_file_declaration(relative, file_values, root))
        file_prose = prose_levels(head_comment(path.read_text(encoding="utf-8").splitlines()[:60]))
        names: Counter = Counter()
        for block in parse_blocks(path, root):
            names[block.name] += 1
            if names[block.name] > 1:
                problems.append(f"{block.path}:{block.line}: duplicate test name {block.name!r}")
            seen.add(block.key)
            values = parse_keys(block.comment)
            has_declaration = "oracle" in values
            if file_values is not None and not has_declaration:
                for level in levels_of(file_values["oracle-file"]):
                    declared[level] += 1
                if block.key in debt:
                    problems.append(f"{block.key}: covered by `oracle-file`, remove it from tools/oracle_debt.txt")
                continue
            if block.key in debt:
                if has_declaration and not check_declaration(block, values):
                    problems.append(f"{block.key}: has a valid declaration, remove it from tools/oracle_debt.txt")
                continue
            if not has_declaration:
                stated = prose_levels(block.comment) or file_prose
                if stated:
                    if stated[0] == "C":
                        problems.append(f"{block.path}:{block.line}: test {block.name!r}: the comment states level C, which is refused: repair the test")
                    else:
                        declared["prose " + stated[0]] += 1
                    continue
            block_problems = check_declaration(block, values)
            problems.extend(block_problems)
            if not block_problems:
                declared[levels_of(values["oracle"])[0]] += 1
    for key in sorted(debt):
        if key not in seen:
            problems.append(f"{key}: listed in tools/oracle_debt.txt but the block does not exist (deleted or renamed: remove the entry; a renamed block must declare)")
    if len(debt) != limit:
        problems.append(f"tools/oracle_debt.txt has {len(debt)} entries, DEBT_LIMIT is {limit}: the list can only shrink and the limit is lowered with it")
    return problems, declared, Counter(debt.values())


def main() -> int:
    problems, declared, debt = check()
    for problem in problems:
        sys.stderr.write(problem + "\n")
    total = sum(debt.values())
    print(f"check_test_oracles: declared blocks by level: " + (", ".join(f"{level} {declared[level]}" for level in LEVELS) or "none"))
    prose = {level: count for level, count in declared.items() if level.startswith("prose ")}
    print(f"check_test_oracles: blocks that state their level in plain words (accepted, to convert to the key form): " + (", ".join(f"{level[6:]} {count}" for level, count in sorted(prose.items())) or "none"))
    print(f"check_test_oracles: debt list {total} blocks by audit level: " + ", ".join(f"{level} {count}" for level, count in sorted(debt.items())))
    print(f"check_test_oracles: level C in the debt list: {debt.get('C', 0)}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
