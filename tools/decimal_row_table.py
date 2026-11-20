"""Run-time data tables for the IEEE decimal elementary functions.

The tables used to be MoonBit source (`library/src/decimal/elementary_*_rows_wbtest.mbt`,
about 5 MB) compiled into the debug test build of the `decimal` package. They
are now plain `mpfr-decimal-random-v2` rows (see
`tooling/src/frontend/mpfr_expr/decimal_random.mbt`) that the release-built
`floating-conformance --backend mpfr` executable reads at run time and checks
with `total_order_compare` (value, sign, cohort and exponent) and exact flag letters.

Row: `id op rounding precision emax a b n expected flags` (the context is the
IEEE 754-2019 format of `precision` and `emax`: `emin = 1 - emax`, tininess
before rounding; flags are a subset of `xouvz`).
"""

from __future__ import annotations

import json
from decimal import Decimal, InvalidOperation
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

FORMAT = "mpfr-decimal-random-v2"
TABLE_ROOT = Path(__file__).resolve().parent.parent / "testdata/decimal/ieee/rows"
ABSENT = "-"


@dataclass(frozen=True)
class TableRow:
    op: str
    rounding: str
    precision: int
    emin: int
    emax: int
    clamp: bool
    tininess: str
    a: str
    b: str | None
    n: int
    expected: str
    flags: str


def format_row(identifier: str, row: TableRow) -> str:
    if row.emin != 1 - row.emax or not row.clamp or row.tininess != "b":
        raise ValueError(f"row context is not an IEEE format: {row!r}")
    fields = [
        identifier,
        row.op,
        row.rounding,
        str(row.precision),
        str(row.emax),
        row.a,
        ABSENT if row.b is None else row.b,
        str(row.n),
        row.expected,
        row.flags,
    ]
    for field in fields:
        if not field or any(character.isspace() for character in field):
            raise ValueError(f"row field cannot be written as a token: {field!r}")
    return " ".join(fields)


def render_table(name: str, generator: str, rows: Iterable[TableRow]) -> str:
    lines = [
        f"# {FORMAT} table={name} generator={generator}",
        "# Generated from exact rational arithmetic and certified MPFR 4.2.2 enclosures",
        "# rounded by libmpdec; do not edit.",
        "# id op rounding precision emax a b n expected flags",
    ]
    lines.extend(format_row(f"{name}-{index:05d}", row) for index, row in enumerate(rows))
    return "\n".join(lines) + "\n"


def data_lines(text: str) -> list[str]:
    return [
        line
        for line in (item.strip() for item in text.split("\n"))
        if line and not line.startswith("#")
    ]


def count_rows(text: str) -> int:
    return len(data_lines(text))


def table_path(name: str) -> Path:
    return TABLE_ROOT / f"{name}.txt"


def check_table(path: Path, rendered: str) -> bool:
    return path.is_file() and path.read_text(encoding="utf-8") == rendered


TABLES = ("pi_inverse", "huge_trig")
# Rows that cost 20 to 60 seconds each (`1E+999999`): not in the gate; run them
# with `python3 tools/run_huge_trig_extreme.py`.
OPT_IN_TABLES = ("huge_trig_extreme",)


def evaluate_run(
    table: str, expected_rows: int, returncode: int, stdout: str, stderr: str = ""
) -> dict[str, object]:
    """Pure: turn one CLI run (`--backend mpfr --json <table>`) into a gate row.

    The run passes only if the process exited 0 or 1 with parsable JSON, the
    CLI executed exactly `expected_rows` rows (the data lines of the file, which
    `generate_decimal_*_rows.py --check` ties to the generator), and none failed.
    A table whose executed count differs fails even if every executed row
    passed, so a truncated read cannot shrink the evidence.
    """
    failure = {"table": table, "totalCases": expected_rows, "passedCases": 0, "failedCases": expected_rows, "failedIds": []}
    if returncode not in (0, 1):
        return {**failure, "error": f"runner exited {returncode}: {(stderr or stdout).strip()[:300]}"}
    try:
        payload = json.loads(stdout)
        total = int(payload["totalCases"])
        failed_ids = [str(item) for item in payload["failedIds"]]
    except (ValueError, KeyError, TypeError):
        return {**failure, "error": f"unparsable runner output: {stdout.strip()[:300]}"}
    if total != expected_rows:
        return {**failure, "error": f"executed {total} rows, expected {expected_rows}"}
    failed = max(len(failed_ids), 1 if returncode != 0 else 0)
    return {
        "table": table,
        "totalCases": total,
        "passedCases": total - failed,
        "failedCases": failed,
        "failedIds": failed_ids[:20],
    }


def sample_positions(count: int, step: int) -> list[int]:
    """Deterministic equidistant positions inside one stratum of `count` rows.

    Every `step`-th row starting at `step // 2`; a stratum shorter than that
    still keeps its middle row, so no stratum disappears from the sample.
    """
    if step < 1:
        raise ValueError("sampling step must be positive")
    if count <= 0:
        return []
    positions = list(range(step // 2, count, step))
    return positions or [count // 2]


def stratum_key(row: TableRow) -> tuple[str, str]:
    """(operation, rounding)."""
    return (row.op, row.rounding)


def stratified_sample(
    rows: Sequence[TableRow], certified: Sequence[bool], step: int
) -> list[int]:
    """Indices (ascending) of the sampled rows.

    Rows that do not come from an MPFR enclosure (`certified` false: exact
    values, special values, rows computed by exact rational arithmetic) are all
    kept. MPFR rows are stratified by (operation, rounding mode) and sampled
    equidistantly inside each stratum in generation order, every `step`-th row.
    """
    if len(rows) != len(certified):
        raise ValueError("rows and certified flags differ in length")
    kept = {index for index, flag in enumerate(certified) if not flag}
    strata: dict[tuple[str, str], list[int]] = {}
    for index, row in enumerate(rows):
        if certified[index]:
            strata.setdefault(stratum_key(row), []).append(index)
    for members in strata.values():
        kept.update(members[position] for position in sample_positions(len(members), step))
    return sorted(kept)


def stratum_counts(
    rows: Sequence[TableRow], certified: Sequence[bool], kept: Sequence[int]
) -> list[tuple[str, str, int, int]]:
    """(operation, rounding, full rows, sampled rows) of the MPFR strata."""
    chosen = set(kept)
    totals: dict[tuple[str, str], list[int]] = {}
    for index, row in enumerate(rows):
        if certified[index]:
            entry = totals.setdefault(stratum_key(row), [0, 0])
            entry[0] += 1
            entry[1] += index in chosen
    return [(op, rounding, full, sampled) for (op, rounding), (full, sampled) in sorted(totals.items())]
