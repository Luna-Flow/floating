#!/usr/bin/env python3
"""Refinements of expected ITL values: parsing, validation and application.

A refinement is the claim that, for one corpus statement, the pinned corpus
expects a value that is valid but wider than the exact result, and that the
exact value is the one the implementation must return. The corpus itself is not
modified: the runner runs a patched copy of the file in which the expected value
of each refined statement is replaced by the refined value.

Everything here is a pure function of its arguments, apart from `load` and
`corpus_statements`, which read files.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

Bound = Fraction | float


@dataclass(frozen=True)
class Statement:
    """One `operation operands = expected;` statement of an ITL file."""

    id: str
    operation: str
    lhs: str
    expected: str
    first_line: int
    last_line: int
    indent: str


@dataclass(frozen=True)
class Interval:
    """A parsed interval word: `empty`, or bounds, and the decoration suffix."""

    empty: bool
    lo: Bound
    hi: Bound
    decoration: str | None


@dataclass(frozen=True)
class Refinement:
    file: str
    id: str
    operation: str
    corpus: str
    refined: str
    reason: str


def _strip_line_comment(line: str) -> str:
    position = line.find("//")
    return line if position < 0 else line[:position].strip()


def parse_statements(source: str) -> list[Statement]:
    """The statements of an ITL source, with the ids the interpreter gives them.

    The id is `<testcase>:<index>`, the index counting the statements of the
    test case from 1, exactly as the MoonBit parser numbers them.
    """
    statements: list[Statement] = []
    testcase = "anonymous"
    index = 0
    in_comment = False
    pending: list[str] = []
    pending_first = 0
    pending_indent = ""
    for number, raw in enumerate(source.split("\n")):
        line = raw.strip()
        if in_comment:
            if "*/" in line:
                in_comment = False
            continue
        if line.startswith("/*"):
            if "*/" not in line:
                in_comment = True
            continue
        line = _strip_line_comment(line)
        if not line:
            continue
        if line.startswith("testcase "):
            suffix = line[len("testcase ") :].strip()
            testcase = suffix.split(" ", 1)[0]
            index = 0
            continue
        if line == "}":
            continue
        if not pending:
            pending_first = number
            pending_indent = raw[: len(raw) - len(raw.lstrip())]
        pending.append(line)
        if line.endswith(";"):
            text = " ".join(pending)[:-1]
            pending = []
            index += 1
            if "=" not in text:
                continue
            lhs, expected = text.split("=", 1)
            words = lhs.split()
            if not words:
                continue
            statements.append(
                Statement(
                    id=f"{testcase}:{index}",
                    operation=words[0],
                    lhs=lhs.strip(),
                    expected=expected.strip(),
                    first_line=pending_first,
                    last_line=number,
                    indent=pending_indent,
                )
            )
    return statements


def split_words(text: str) -> list[str]:
    """Whitespace separated words, a bracketed interval and its suffix being one."""
    words: list[str] = []
    current = ""
    depth = 0
    for char in text.strip():
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
        if char.isspace() and depth == 0:
            if current:
                words.append(current)
            current = ""
        else:
            current += char
    if current:
        words.append(current)
    return words


def binary64_ulp(q: Fraction) -> Fraction:
    """The spacing of binary64 values at the magnitude of q (normal range, q != 0)."""
    magnitude = abs(q)
    exponent = magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    if Fraction(2) ** exponent > magnitude:
        exponent -= 1
    return Fraction(2) ** (exponent - 52)


def round_binary64(q: Fraction, up: bool) -> Fraction:
    """The least binary64 value >= q (up) or the greatest <= q (normal range)."""
    if q == 0:
        return Fraction(0)
    negative = q < 0
    magnitude = -q if negative else q
    ulp = binary64_ulp(q)
    steps = magnitude / ulp
    lower_steps = steps.numerator // steps.denominator
    if steps.denominator == 1:
        chosen = lower_steps
    else:
        # taking the magnitude of a negative value flips the direction
        chosen = lower_steps + 1 if up != negative else lower_steps
    value = chosen * ulp
    return -value if negative else value


def round_nearest_even_binary64(q: Fraction) -> Fraction:
    """The binary64 value nearest to q, ties to even (normal range)."""
    if q == 0:
        return Fraction(0)
    negative = q < 0
    magnitude = -q if negative else q
    ulp = binary64_ulp(q)
    steps = magnitude / ulp
    lower_steps = steps.numerator // steps.denominator
    remainder = steps - lower_steps
    if remainder > Fraction(1, 2) or (remainder == Fraction(1, 2) and lower_steps % 2 == 1):
        lower_steps += 1
    value = lower_steps * ulp
    return -value if negative else value


def parse_bound(text: str) -> Bound:
    """A bound as the interpreter reads it at binary64: ITF1788 writes `[l,u]`
    as an inf-sup constructor over two floating constants, so each bound is the
    nearest binary64 number (hexadecimal text is exact)."""
    text = text.strip()
    lowered = text.lower()
    if lowered in ("inf", "+inf", "infinity", "+infinity"):
        return math.inf
    if lowered in ("-inf", "-infinity"):
        return -math.inf
    if lowered.lstrip("+-").startswith("0x"):
        return Fraction(float.fromhex(text))
    return round_nearest_even_binary64(Fraction(text))


def parse_interval(word: str) -> Interval:
    match = re.fullmatch(r"\[([^\]]*)\](?:_(\w+))?", word.strip())
    if match is None:
        raise ValueError(f"not an interval word: {word!r}")
    body, decoration = match.group(1).strip(), match.group(2)
    lowered = body.lower()
    if lowered == "empty":
        return Interval(True, math.inf, -math.inf, decoration)
    if lowered == "entire":
        return Interval(False, -math.inf, math.inf, decoration)
    parts = [part for part in body.split(",")]
    if len(parts) == 1:
        bound = parse_bound(parts[0])
        return Interval(False, bound, bound, decoration)
    if len(parts) != 2:
        raise ValueError(f"not an interval word: {word!r}")
    return Interval(False, parse_bound(parts[0]), parse_bound(parts[1]), decoration)


def contains(outer: Interval, inner: Interval) -> bool:
    """Whether the set `inner` is a subset of the set `outer`."""
    if inner.empty:
        return True
    if outer.empty:
        return False
    return outer.lo <= inner.lo and inner.hi <= outer.hi


def same_set(left: Interval, right: Interval) -> bool:
    if left.empty or right.empty:
        return left.empty and right.empty
    return left.lo == right.lo and left.hi == right.hi


def load(path: Path) -> list[Refinement]:
    """Reads and type-checks a refinements file."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or not isinstance(data.get("refinements"), list):
        raise ValueError(f"invalid refinements file: {path}")
    refinements: list[Refinement] = []
    for entry in data["refinements"]:
        keys = {"file", "id", "operation", "corpus", "refined", "reason"}
        if not isinstance(entry, dict) or set(entry) != keys:
            raise ValueError(f"invalid refinement entry: {entry!r}")
        if not all(isinstance(entry[key], str) and entry[key] for key in keys):
            raise ValueError(f"invalid refinement entry: {entry!r}")
        refinements.append(Refinement(**entry))
    ids = [(refinement.file, refinement.id) for refinement in refinements]
    if len(set(ids)) != len(ids):
        raise ValueError("a refinement names the same case twice")
    return refinements


def validate(
    refinements: list[Refinement], statements: dict[str, list[Statement]]
) -> None:
    """Checks every entry against the corpus statements; raises ValueError.

    An entry must name a case that exists, with the operation and the corpus
    value the entry records; its refined value must have the same number of
    results and the same decorations, differ from the corpus value, and lie
    inside it word by word.
    """
    for refinement in refinements:
        if refinement.file not in statements:
            raise ValueError(f"refinement names a missing file: {refinement.file}")
        found = [s for s in statements[refinement.file] if s.id == refinement.id]
        if not found:
            raise ValueError(f"refinement names a missing case: {refinement.id}")
        statement = found[0]
        if statement.operation != refinement.operation:
            raise ValueError(f"{refinement.id}: operation is {statement.operation}")
        if statement.expected != refinement.corpus:
            raise ValueError(f"{refinement.id}: the corpus value is not the recorded one")
        corpus_words = split_words(refinement.corpus)
        refined_words = split_words(refinement.refined)
        if len(corpus_words) != len(refined_words):
            raise ValueError(f"{refinement.id}: the number of results differs")
        if refinement.refined == refinement.corpus:
            raise ValueError(f"{refinement.id}: the refined value equals the corpus value")
        for corpus_word, refined_word in zip(corpus_words, refined_words):
            outer = parse_interval(corpus_word)
            inner = parse_interval(refined_word)
            if outer.decoration != inner.decoration:
                raise ValueError(f"{refinement.id}: the decoration differs")
            if not contains(outer, inner):
                raise ValueError(f"{refinement.id}: the refined value is not inside the corpus value")


def apply(source: str, refinements: list[Refinement]) -> str:
    """The source with the expected value of every refined statement replaced."""
    by_id = {refinement.id: refinement for refinement in refinements}
    lines = source.split("\n")
    for statement in reversed(parse_statements(source)):
        refinement = by_id.get(statement.id)
        if refinement is None:
            continue
        replacement = f"{statement.indent}{statement.lhs} = {refinement.refined};"
        lines[statement.first_line : statement.last_line + 1] = [replacement]
    return "\n".join(lines)


def corpus_statements(corpus: Path) -> dict[str, list[Statement]]:
    return {
        path.name: parse_statements(path.read_text(encoding="utf-8"))
        for path in sorted(corpus.glob("*.itl"))
    }
