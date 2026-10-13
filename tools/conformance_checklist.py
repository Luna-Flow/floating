#!/usr/bin/env python3
"""Generate the conformance checklist of doc/manual/verification.md.

The clause traceability tables of doc/manual/conformance/*.md are the source of
truth. This script condenses them into per-standard counts and a task list, and
rewrites the block between the checklist markers of verification.md.

    python3 tools/conformance_checklist.py          # check; exit 1 if stale
    python3 tools/conformance_checklist.py --write  # rewrite the block
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANUAL = REPO_ROOT / "doc" / "manual"
TARGET = MANUAL / "verification.md"
START = "<!-- conformance-checklist-start -->"
END = "<!-- conformance-checklist-end -->"

STANDARDS = (
    ("IEEE 754-2019: bin_float", "bin_float.md"),
    ("IEEE 754-2019: decimal", "decimal.md"),
    ("General Decimal Arithmetic 1.70: decimal_gda", "decimal_gda.md"),
    ("IEEE 1788-2015: ball_float", "ball_float.md"),
)
STATES = ("conforming", "partial", "not implemented", "not applicable")


def classify(status: str) -> str:
    text = status.strip().lower()
    for state in ("conforming", "partial", "not implemented", "not applicable"):
        if text.startswith(state):
            return state
    if text.startswith("valid"):
        return "partial"
    raise ValueError(f"unknown status: {status!r}")


def split_row(line: str) -> list[str]:
    return [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def clause_rows(page: Path) -> list[tuple[str, str, str]]:
    lines = page.read_text(encoding="utf-8").split("\n")
    rows: list[tuple[str, str, str]] = []
    in_section = False
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("## "):
            in_section = line[3:].strip() == "Clause traceability"
        if in_section and line.startswith("|") and index + 1 < len(lines):
            if set(lines[index + 1]) <= set("| -"):
                has_level = split_row(line)[1] == "Level"
                index += 2
                while index < len(lines) and lines[index].startswith("|"):
                    cells = split_row(lines[index])
                    level = cells[1].split()[0] if has_level else "required"
                    rows.append((cells[0], level, cells[-1]))
                    index += 1
                continue
        index += 1
    return rows


def build() -> str:
    counts = []
    blocks = []
    for title, name in STANDARDS:
        rows = clause_rows(MANUAL / "conformance" / name)
        if not rows:
            raise SystemExit(f"no clause traceability table in {name}")
        tally = {state: 0 for state in STATES}
        tally["missing required"] = 0
        tally["missing other"] = 0
        items = []
        for clause, level, status in rows:
            state = classify(status)
            tally[state] += 1
            if state in ("partial", "not implemented"):
                tally["missing required" if level == "required" else "missing other"] += 1
            mark = "x" if state == "conforming" else " "
            suffix = "" if state == "conforming" else f" ({state})"
            items.append(f"- [{mark}] {clause} [{level}]{suffix}")
        counts.append((title, len(rows), tally))
        blocks.append((title, items))
    out = [
        "| Standard | Rows | Conforming | Partial | Not implemented | Not applicable | Required gaps | Recommended or optional gaps |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for title, total, tally in counts:
        out.append(
            f"| {title} | {total} | {tally['conforming']} | {tally['partial']} | "
            f"{tally['not implemented']} | {tally['not applicable']} | "
            f"{tally['missing required']} | {tally['missing other']} |"
        )
    for title, items in blocks:
        out += ["", f"**{title}**", ""] + items
    return "\n".join(out)


def main(argv: list[str]) -> int:
    text = TARGET.read_text(encoding="utf-8")
    if START not in text or END not in text:
        print(f"{TARGET}: checklist markers are missing", file=sys.stderr)
        return 2
    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    fresh = f"{head}{START}\n{build()}\n{END}{tail}"
    if "--write" in argv:
        TARGET.write_text(fresh, encoding="utf-8")
        return 0
    if fresh != text:
        print(
            "doc/manual/verification.md: conformance checklist is stale; "
            "run python3 tools/conformance_checklist.py --write",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
