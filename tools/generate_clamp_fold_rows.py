#!/usr/bin/env python3
"""Rows for the quantize of a zero under clamp (issues 234 and 419).

Writes `tooling/src/consistency/clamp_fold_rows_wbtest.mbt`, a table of
`(context, zero, target exponent, expected text, flags)` read by
`clamp_fold_agreement_wbtest.mbt`. The expected result and flags come from CPython
`decimal` (libmpdec, an implementation of the General Decimal Arithmetic specification):
`Context(prec, Emax, Emin, clamp=1, ROUND_HALF_EVEN).quantize(zero, 1E<target>)` with all
traps off. The flags column is the string of the signals Inexact (x), InvalidOperation
(i), Overflow (o), Underflow (u), Clamped (c), with a dot for a signal that is not
raised. The library does not run.

    python3 tools/generate_clamp_fold_rows.py
    python3 tools/generate_clamp_fold_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tooling/src/consistency/clamp_fold_rows_wbtest.mbt"
CONTEXTS = [
    ("decimal32", 7, -95, 96),
    ("decimal64", 16, -383, 384),
    ("decimal128", 34, -6143, 6144),
    ("small", 5, -2, 3),
]
ZEROS = ["0", "-0", "0E+5", "0E-3", "-0E+2"]
SIGNALS = [("x", decimal.Inexact), ("i", decimal.InvalidOperation), ("o", decimal.Overflow),
           ("u", decimal.Underflow), ("c", decimal.Clamped)]


def targets(precision: int, e_min: int, e_max: int) -> list[int]:
    top = e_max - precision + 1
    return [e_min - precision + 1, -1, 0, 1, top - 2, top - 1, top, top + 1, top + 2,
            (top + e_max) // 2, e_max - 1, e_max, e_max + 1]


def quantize_zero(precision: int, e_min: int, e_max: int, zero: str, target: int) -> tuple[str, str]:
    context = decimal.Context(prec=precision, Emax=e_max, Emin=e_min, clamp=1,
                              rounding=decimal.ROUND_HALF_EVEN, traps=[])
    quantum = decimal.Decimal(f"1E{target:+d}" if target >= 0 else f"1E{target}")
    result = context.quantize(decimal.Decimal(zero), quantum)
    flags = "".join(letter if context.flags[signal] else "." for letter, signal in SIGNALS)
    text = "NaN" if result.is_nan() else str(result)
    return text, flags


def all_rows() -> list[tuple[str, str, int, str, str]]:
    rows = []
    for name, precision, e_min, e_max in CONTEXTS:
        for zero in ZEROS:
            for target in targets(precision, e_min, e_max):
                text, flags = quantize_zero(precision, e_min, e_max, zero, target)
                rows.append((name, zero, target, text, flags))
    return rows


def render(rows: list[tuple[str, str, int, str, str]]) -> str:
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_clamp_fold_rows.py (CPython `decimal`, libmpdec: Context(prec, Emax, Emin, clamp=1).quantize)",
        "// input: decimal32, decimal64, decimal128 and a small context (p 5, emin -2, emax 3), five zeros, 13 targets around",
        "//   emax - p + 1 and up to emax + 1",
        "// Columns: context, zero, target exponent, expected text, signals x i o u c (a dot when not raised).",
        "// library-ran: no",
        "",
        "///|",
        "let clamp_fold_rows : Array[(String, String, Int32, String, String)] = [",
    ]
    for name, zero, target, text, flags in rows:
        out.append(f'  ("{name}", "{zero}", {target}, "{text}", "{flags}"),')
    out += ["]", ""]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if "".join(current.split()) != "".join(text.split()):
            print(f"{OUTPUT} is stale: run tools/generate_clamp_fold_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(all_rows())} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
