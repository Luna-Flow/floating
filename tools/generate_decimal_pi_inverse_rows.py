#!/usr/bin/env python3
"""White-box rows for decimal asinPi, acosPi, atanPi and atan2Pi (issue #236, PR 3).

Writes two tables (`x` is the operand, or the ordinate of atan2Pi, whose
abscissa is `y`): the full one, `testdata/decimal/ieee/rows/pi_inverse.txt`, as
`mpfr-decimal-random-v1` rows (`decimal_row_table`) that the release-built
conformance CLI executes at run time on every target in the full gate; and a
copy of it, `library/src/decimal/elementary_pi_inverse_rows_wbtest.mbt`,
compiled into the `decimal` test module for the quick gate (the full table by
default; `--sample-step N` keeps all exact rows and one certified MPFR row in N
per (operation, rounding) stratum). No row comes from the library under test:

* exact results are the Niven values (asinPi(+-1) = +-1/2, acosPi(+-1, 0) =
  0, 1, 1/2, atanPi(+-1) = +-1/4, atan2Pi(+-a, +-a) = +-1/4, +-3/4), computed
  with `fractions.Fraction`, written at the preferred exponent 0 of IEEE
  754-2019 9.2.2 and rounded once by libmpdec (Python `decimal`);
* every other row is the rounding of a certified MPFR 4.2.2 enclosure
  (`mpfr_asinpi`, `mpfr_acospi`, `mpfr_atanpi`, `mpfr_atan2pi` through
  `tools/mpfr_decimal_enclosure.c`), kept only when both endpoints round to one
  result with one flag set and the result lies outside the enclosure.

Flags use the letters of `generate_decimal_pm1_rows.py`.

    python3 tools/generate_decimal_pi_inverse_rows.py && moon fmt
    python3 tools/generate_decimal_pi_inverse_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

import decimal_row_table as table
import generate_decimal_pm1_rows as pm1
import generate_mpfr_decimal_random as decm

sys.set_int_max_str_digits(0)
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = table.table_path("pi_inverse")
ROUNDINGS = pm1.ROUNDINGS
DECIMAL32 = pm1.DECIMAL32
DECIMAL64 = pm1.DECIMAL64
DECIMAL128 = pm1.DECIMAL128


def ctx(spec, rounding, tininess="b"):
    return pm1.ctx(spec, rounding, tininess)


def exact_value(op: str, x: Decimal, y: Decimal | None) -> Fraction | tuple[str, Fraction] | None:
    """The exact value (a signed zero is `("-0", 0)`), or None when irrational."""
    one = Fraction(1)
    if op == "atan2pi":
        assert y is not None
        if x == 0 or y == 0 or abs(x) != abs(y):
            return None
        value = Fraction(1, 4) if y > 0 else Fraction(3, 4)
        return -value if x < 0 else value
    if op == "asinpi":
        return Fraction(1, 2) * (1 if x > 0 else -1) if abs(x) == 1 else None
    if op == "acospi":
        if abs(x) != 1:
            return None
        return Fraction(0) if x > 0 else one
    if op == "atanpi":
        return Fraction(1, 4) * (1 if x > 0 else -1) if abs(x) == 1 else None
    raise ValueError(op)


class Rows:
    def __init__(self) -> None:
        self.rows: list[tuple] = []
        # Parallel to `rows`: True for a row that is the rounding of a certified
        # MPFR enclosure, False for an exact (Niven / rational) row.
        self.certified: list[bool] = []
        self.pending: list[tuple] = []
        self.seen: set = set()
        self.dropped = 0

    def add(self, op: str, context: decm.Context, x, y=None) -> None:
        x = Decimal(x)
        y = None if y is None else Decimal(y)
        key = (op, context, str(x), str(y))
        if key in self.seen:
            return
        self.seen.add(key)
        if op in ("asinpi", "acospi") and abs(x) > 1:
            raise ValueError("asinpi and acospi rows need |x| <= 1")
        if x == 0 or (y is not None and y == 0):
            raise ValueError("zero operands are covered by the hand-written tests")
        exact = exact_value(op, x, y)
        if exact is not None:
            expected, flags = pm1.round_exact(pm1.fraction_decimal(exact), context)
            self.rows.append((op, context, str(x), "-" if y is None else str(y), expected, flags))
            self.certified.append(False)
            return
        self.pending.append((op, context, x, y))

    def certify_pending(self) -> None:
        binary = decm.build_enclosure()
        candidates = []
        for index, (op, context, x, y) in enumerate(self.pending):
            operands = (x,) if y is None else (x, y)
            candidates.append(decm.Candidate(index, op, context, operands, 0))
        for offset in range(0, len(candidates), decm.CHUNK):
            chunk = candidates[offset : offset + decm.CHUNK]
            for candidate, enclosure in zip(chunk, decm.enclose(chunk, binary)):
                row = None if enclosure is None else decm.certify(candidate, enclosure)
                if row is None:
                    self.dropped += 1
                    continue
                fields = row.split()
                self.rows.append((candidate.op, candidate.context, fields[8], fields[9], fields[11], fields[12]))
                self.certified.append(True)
        self.pending = []


def build() -> Rows:
    rows = Rows()
    # Exact (Niven) values in every mode at small precisions, several cohort
    # members of the operand (the result is always at exponent 0).
    units = ["1", "1.0", "1.000", "1E+0", "10E-1"]
    for precision in (1, 2, 3, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        modes = ROUNDINGS if precision in (1, 2, 16) else ("half_even", "floor", "up")
        for mode in modes:
            c = ctx(spec, mode)
            for u in units:
                for sign in ("", "-"):
                    x = sign + u
                    rows.add("asinpi", c, x)
                    rows.add("acospi", c, x)
                    rows.add("atanpi", c, x)
                    for v in units:
                        for ysign in ("", "-"):
                            rows.add("atan2pi", c, x, ysign + v)
            for pair in (("2.5", "2.50"), ("7E+100", "7000E+97"), ("3E-300", "30E-301"), ("9.99", "9.990")):
                for sa in ("", "-"):
                    for sb in ("", "-"):
                        rows.add("atan2pi", c, sa + pair[0], sb + pair[1])
    # Non-terminating rational values (never rounding breakpoints): +-1/6, 1/3,
    # 2/3 and the neighbours of the exact arguments.
    for precision in (1, 3, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        for mode in ROUNDINGS:
            c = ctx(spec, mode)
            for x in ("0.5", "-0.5", "0.50", "0.866025403784438646763723170752936183", "-0.7071067811865475244"):
                rows.add("asinpi", c, x)
                rows.add("acospi", c, x)
            for x in ("0.9999999999999999999", "-0.9999999999999999999", "1E-1", "0.99999", "-0.99999"):
                rows.add("asinpi", c, x)
                rows.add("acospi", c, x)
            for x in ("1.0000000000000000001", "0.9999999999999999999"):
                rows.add("atanpi", c, x)
            for y, x in (("1", "3"), ("3", "1"), ("-1", "2"), ("1", "-2"), ("-5", "-2"), ("1.7320508075688772", "1"),
                         ("0.5773502691896258", "1"), ("1", "1.0000000000000001"), ("1.0000000000000001", "1")):
                rows.add("atan2pi", c, y, x)
    # Anchors: atanPi for large |x| (1/2 - d), acosPi for tiny |x| (1/2 - asin/pi),
    # atan2Pi for extreme ratios; both sides, every mode, precisions around the
    # anchor threshold.
    for precision in (1, 3, 7, 16, 34):
        for mode in ROUNDINGS:
            for tininess in (("b", "a") if precision == 3 else ("b",)):
                c = ctx((precision, -999999, 999999, 0), mode, tininess)
                for k in (precision - 1, precision + 3, precision + 5, precision + 20, 400):
                    for m in ("1", "9.99"):
                        for s in ("", "-"):
                            x = Decimal(f"{s}{m}E+{k}")
                            rows.add("atanpi", c, x)
                            rows.add("acospi", c, Decimal(f"{s}{m}E-{k + 1}"))
                            rows.add("atan2pi", c, x, "1")
                            rows.add("atan2pi", c, x, "-1" if not s else "-3")
                            rows.add("atan2pi", c, "1", x)
                            rows.add("atan2pi", c, "-2", x)
                            rows.add("atan2pi", c, f"{s}{m}E+{k + 2}", "-3E+3")
                            rows.add("atan2pi", c, f"{m}E-{k}", f"-{m}E+7")
                            rows.add("atan2pi", c, f"-{m}E-{k}", "-1.5")
    # Tiny and extreme-exponent operands of asinPi/atanPi/atan2Pi (relative
    # accuracy near 0, the exponent range): decimal32/64/128, both tininess.
    for spec in (DECIMAL32, DECIMAL64, DECIMAL128):
        p, emin, emax = spec[0], spec[1], spec[2]
        etiny = emin - p + 1
        for mode in ROUNDINGS:
            for tininess in ("b", "a"):
                c = ctx(spec, mode, tininess)
                for k in (etiny - 2, etiny - 1, etiny, emin - 1, emin + p, -3 * p):
                    for m in ("1", "3", "9.99"):
                        for s in ("", "-"):
                            x = Decimal(f"{s}{m}E{k}")
                            rows.add("asinpi", c, x)
                            rows.add("atanpi", c, x)
                            rows.add("atan2pi", c, x, "1")
                            rows.add("atan2pi", c, x, "-1")
                            rows.add("atan2pi", c, x, "7.5E+300")
                if tininess == "b":
                    for text in ("1E-1999996", "-3E-1000000"):
                        rows.add("asinpi", c, Decimal(text))
                        rows.add("atanpi", c, Decimal(text))
                        rows.add("atan2pi", c, text, "1")
    # Precision sweep of moderate operands.
    samples = ("0.7", "0.123456789012345678901", "-0.31830988618379067", "3", "-12.345678901234567890123", "7E-5",
               "0.999999999")
    for precision in (*range(1, 61), 200, 220):
        for index, text in enumerate(samples):
            mode = ROUNDINGS[(precision + index) % len(ROUNDINGS)]
            spec = (precision, -(precision + 400), precision + 400, (precision + index) % 2)
            if index % 2:
                spec = (precision, -999999, 999999, 0)
            c = ctx(spec, mode, "ab"[(precision + index) % 2])
            x = c.python().create_decimal(Decimal(text))
            if abs(x) <= 1:
                rows.add("asinpi", c, x)
                rows.add("acospi", c, x)
            rows.add("atanpi", c, x)
            rows.add("atan2pi", c, x, samples[(index + 2) % len(samples)] if (precision % 2) else "-" + samples[(index + 3) % len(samples)].lstrip("-"))
    rows.certify_pending()
    return rows


# The table compiled into `library/src/decimal` runs in the quick gate. By default it is
# the full table (`SAMPLE_STEP = 1`: 19,134 rows run in about 2.4 s under the
# debug native build, source 2.2 MB, about 1.4 s more to build). Above about 5 s
# set a larger step and the generator keeps every exact row and one certified
# MPFR row in `step` per (operation, rounding) stratum
# (`--sample-step N`, see doc/manual/verification.md for when to do so). The
# data file is always the full table.
SAMPLE_STEP = 1
SAMPLED_OUTPUT = ROOT / "library/src/decimal/elementary_pi_inverse_rows_wbtest.mbt"
CHUNK_ROWS = 500
ROW_TYPE = "(String, String, Int32, Int32, Int32, Bool, String, String, String, String, String)"


def table_rows(rows: Rows) -> list[table.TableRow]:
    return [
        table.TableRow(op, c.rounding, c.precision, c.emin, c.emax, bool(c.clamp), c.tininess, x, None if y == "-" else y, 0, expected, flags)
        for op, c, x, y, expected, flags in rows.rows
    ]


def sampled_indices(rows: Rows, step: int = SAMPLE_STEP) -> list[int]:
    return table.stratified_sample(table_rows(rows), rows.certified, step)


def render(rows: Rows) -> str:
    """The full table, as `mpfr-decimal-random-v1` rows."""
    return table.render_table("pi_inverse", "tools/generate_decimal_pi_inverse_rows.py", table_rows(rows))


def render_sampled(rows: Rows, step: int = SAMPLE_STEP) -> str:
    """The table compiled into `library/src/decimal`: the full one, or every `step`-th row per stratum."""
    if step == 1:
        what = [
            "// The full table: the same rows as testdata/decimal/ieee/rows/pi_inverse.txt,",
            "// which the full gate also runs, through the conformance CLI, on every target.",
        ]
    else:
        what = [
            "// SAMPLE of testdata/decimal/ieee/rows/pi_inverse.txt (the full table, run by",
            "// the full gate): every exact row, and one MPFR row in " + str(step) + " of each",
            "// (operation, rounding) stratum.",
        ]
    lines = [
        "///|",
        "// Generated by tools/generate_decimal_pi_inverse_rows.py from exact rational",
        "// arithmetic and certified MPFR 4.2.2 enclosures rounded by libmpdec; do not edit.",
        *what,
        "// Columns: op, rounding, precision, e_min, e_max, clamp, tininess, x, y,",
        "// expected (compared with total_order_compare), flags.",
    ]
    kept = [rows.rows[index] for index in sampled_indices(rows, step)]
    chunks = [kept[i : i + CHUNK_ROWS] for i in range(0, len(kept), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        lines += ["", "///|", f"fn pii_rows_{index}() -> Array[", f"  {ROW_TYPE},", "] {", "  ["]
        for op, c, x, y, expected, flags in chunk:
            clamp = "true" if c.clamp else "false"
            lines.append(
                f'  ("{op}", "{c.rounding}", {c.precision}, {c.emin}, {c.emax}, {clamp}, "{c.tininess}", "{x}", "{y}", "{expected}", "{flags}"),'
            )
        lines += ["  ]", "}"]
    lines += ["", "///|", f"fn pii_rows() -> Array[{ROW_TYPE}] {{", "  let rows = []"]
    for index in range(len(chunks)):
        lines.append(f"  rows.append(pii_rows_{index}())")
    lines += ["  rows", "}"]
    return "\n".join(lines) + "\n"


def sampled_tokens(text: str) -> set[tuple[str, ...]]:
    """The (op ... flags) fields of every tuple row of a sampled MoonBit table."""
    import re

    fields = re.compile(r'\(\s*"(\w+)",\s*"(\w+)",\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(true|false),\s*"(\w)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\s*,?\s*\)')
    return {tuple(match.groups()) for match in fields.finditer(text)}


def full_tokens(text: str) -> set[tuple[str, ...]]:
    out = set()
    for line in table.data_lines(text):
        t = line.split()
        out.add((t[1], t[2], t[3], t[4], t[5], "true" if t[6] == "1" else "false", t[7], t[8], t[9], t[11], t[12]))
    return out


def print_strata(rows: Rows) -> None:
    kept = sampled_indices(rows)
    exact = rows.certified.count(False)
    print(f"exact rows kept in full: {exact}; MPFR rows {len(rows.rows) - exact}; sampled total {len(kept)}", file=sys.stderr)
    for op, rounding, full, sampled in table.stratum_counts(table_rows(rows), rows.certified, kept):
        print(f"  {op:8} {rounding:10} {full:5} -> {sampled:4}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if either committed table differs")
    parser.add_argument("--strata", action="store_true", help="print full and sampled rows per stratum")
    parser.add_argument(
        "--sample-step",
        type=int,
        default=SAMPLE_STEP,
        help="compile one MPFR row in N per stratum instead of the default (not with --check)",
    )
    args = parser.parse_args(argv)
    if args.check and args.sample_step != SAMPLE_STEP:
        parser.error("--check compares the committed tables, which use the default step")
    rows = build()
    text = render(rows)
    sampled = render_sampled(rows, args.sample_step)
    print(f"{len(rows.rows)} rows, {len(sampled_indices(rows, args.sample_step))} compiled, {rows.dropped} candidates not certified", file=sys.stderr)
    if args.strata:
        print_strata(rows)
    if args.check:
        status = 0
        if not table.check_table(OUTPUT, text):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            status = 1
        # `moon fmt` re-wraps long tuples; compare the tokens, not the layout.
        if not SAMPLED_OUTPUT.is_file() or pm1.normalized(SAMPLED_OUTPUT.read_text(encoding="utf-8")) != pm1.normalized(sampled):
            print(f"{SAMPLED_OUTPUT} is stale", file=sys.stderr)
            status = 1
        elif not sampled_tokens(SAMPLED_OUTPUT.read_text(encoding="utf-8")) <= full_tokens(OUTPUT.read_text(encoding="utf-8")):
            print("the sampled table is not a subset of the full table", file=sys.stderr)
            status = 1
        return status
    OUTPUT.write_text(text, encoding="utf-8")
    SAMPLED_OUTPUT.write_text(sampled, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
