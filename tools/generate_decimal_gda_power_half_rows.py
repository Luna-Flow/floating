#!/usr/bin/env python3
"""Rows for `power(x, 0.5)` and `power(x, -0.5)` of `decimal_gda` (issue 397).

Writes `library/src/decimal_gda/power_half_rows_wbtest.mbt`, the table `issue397_rows` of
`(context, rounding mode, base, exponent, expected value text, expected flags)` executed by
`power_half_clamped_issue397_wbtest.mbt`: 6 contexts, 5 rounding modes, 10 bases and the four
spellings `0.5`, `0.50`, `5E-1` and `-0.5` of the exponent, 1200 rows.

The value is computed by CPython `decimal` (libmpdec): `x ** 0.5` is `sqrt(x)` and `x ** -0.5` is
`1 / sqrt(x)`, evaluated in a context of precision `precision + 120` (correctly rounded, half even,
widest exponent range) and rounded to the row's context
`Context(prec, rounding, Emin, Emax, clamp)` by `plus`, which gives the overflow (`Infinity`), the
underflow and the subnormal behaviour. GDA 1.70 *power* makes the result of a non-integral power
inexact, with a coefficient of exactly `precision` digits whose exponent is the smallest: a result
with fewer digits is padded with zeros to `precision` digits (`quantize`, but not below Etiny = emin - precision + 1), except zero, which keeps
the exponent CPython gives. The flags are `x` and `r` for every row, the overflow, underflow,
subnormal letters of CPython, and the clamped letter only for a result that rounds to zero (the GDA
1.70 sentence of *Clamped* quoted in the header of the test file: the padded form of a nonzero result
is never altered); letters `x r i z o u s c`.

    python3 tools/generate_decimal_gda_power_half_rows.py && moon fmt
    python3 tools/generate_decimal_gda_power_half_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal_gda/power_half_rows_wbtest.mbt"

# name, precision, emin, emax, clamp
CONTEXTS = [
    ("clamped e_max < precision - 1", 5, -10, 0, True),
    ("clamped e_max 1", 3, -5, 1, True),
    ("not clamped", 5, -10, 0, False),
    ("decimal32", 7, -95, 96, True),
    ("decimal64", 16, -383, 384, True),
    ("decimal128", 34, -6143, 6144, True),
]
MODES = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "down": decimal.ROUND_DOWN,
    "up": decimal.ROUND_UP,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
}
BASES = ["0.01", "4", "1E+2", "0.25", "2", "1.0E+4", "9", "1E-9", "1E+20", "1E-5"]
EXPONENTS = ["0.5", "0.50", "5E-1", "-0.5"]
FLAGS = [(decimal.Overflow, "o"), (decimal.Underflow, "u"), (decimal.Subnormal, "s"), (decimal.Clamped, "c")]

Row = tuple[str, str, str, str, str, str]


def value_text(value: decimal.Decimal, precision: int, e_tiny: int) -> str:
    if value.is_infinite():
        return "-Infinity" if value.is_signed() else "Infinity"
    if value.is_zero():
        return str(value)
    digits = len(value.as_tuple().digits)
    if digits < precision:
        padded = value.scaleb(0).quantize(
            decimal.Decimal(1).scaleb(max(value.adjusted() - (precision - 1), e_tiny)),
            context=decimal.Context(prec=precision + 5, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN),
        )
        return str(padded)
    return str(value)


def power_half(context: tuple[str, int, int, int, bool], mode: str, base: str, exponent: str) -> tuple[str, str]:
    _name, precision, e_min, e_max, clamp = context
    high = decimal.Context(
        prec=precision + 120, rounding=decimal.ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[]
    )
    root = high.sqrt(decimal.Decimal(base))
    exact = high.divide(decimal.Decimal(1), root) if exponent.startswith("-") else root
    target = decimal.Context(
        prec=precision,
        rounding=MODES[mode],
        Emin=e_min,
        Emax=e_max,
        clamp=1 if clamp else 0,
        traps=[],
        flags=[],
    )
    result = target.plus(exact)
    # GDA 1.70 Clamped: the exponent altered to fit; the padded form of a nonzero result is never
    # altered, so Clamped is kept only for a result that rounds to zero (issue 397)
    keep = lambda flag: target.flags[flag] and (flag is not decimal.Clamped or result.is_zero())
    letters = "".join(letter if keep(flag) else "." for flag, letter in FLAGS)
    return value_text(result, precision, e_min - (precision - 1)), "xr..%s" % letters


def build() -> list[Row]:
    rows: list[Row] = []
    for context in CONTEXTS:
        for mode in MODES:
            for base in BASES:
                for exponent in EXPONENTS:
                    value, flags = power_half(context, mode, base, exponent)
                    rows.append((context[0], mode, base, exponent, value, flags))
    return rows


def render(rows: list[Row]) -> str:
    lines = [
        "///|",
        "// Columns: context, rounding mode, base, exponent, expected value text, expected flags.",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_gda_power_half_rows.py (CPython `decimal`, libmpdec)",
        "// input: 10 bases, the exponents 0.5, 0.50, 5E-1 and -0.5, six contexts (decimal32, 64, 128 and three narrow ones, clamped or not), five rounding modes; the expected value is sqrt or 1 / sqrt evaluated 120 digits wider and rounded to the context by libmpdec, padded to the precision as GDA 1.70 power requires",
        "// library-ran: no",
        "",
        "///|",
        "let issue397_rows : Array[(String, String, String, String, String, String)] = [",
    ]
    for row in rows:
        lines.append("  (" + ", ".join('"%s"' % item for item in row) + "),")
    lines.append("]")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text_out = render(build())
    if args.check:
        norm = lambda s: re.sub(r"\s+", "", s).replace(",)", ")").replace(",]", "]")
        if not OUTPUT.is_file() or norm(OUTPUT.read_text(encoding="utf-8")) != norm(text_out):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text_out, encoding="utf-8")
    print(f"{OUTPUT}: {len(rows := build())} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
