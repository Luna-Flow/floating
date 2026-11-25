#!/usr/bin/env python3
"""Rows for the certified exponential of `decimal_gda` (`decimal_certified_exp_result`).

Writes `library/src/decimal_gda/certified_exp_rows_wbtest.mbt`, a table of
`(group, precision, e_min, e_max, extended, clamp, mode, argument, expected text, flags)`.

The expected value is computed by Python `decimal` (libmpdec) and is not taken from the library:
`exp(x)` is evaluated in a context of precision `precision + 200` (correctly rounded, half even,
exponent range at the maximum), which is more than 10^-(precision + 150) away from any rounding
boundary of the target for the arguments below (they are not exact: `exp(x)` of a nonzero
rational is irrational), and that value is then rounded to the target context
`Context(prec=precision, rounding=mode, Emin=e_min, Emax=e_max, clamp=clamp)` by `plus`, which gives
the result, the overflow, underflow and subnormal behaviour, and the flags. The flags are the
letters of `x r i z o u s c` (inexact, rounded, invalid, division by zero, overflow, underflow,
subnormal, clamped). Infinity is written `inf` or `-inf`. The contexts with `extended` false are the
subset arithmetic of GDA 1.70 Appendix A, for which CPython (extended arithmetic only) has no
answer after an overflow or underflow ("results after these errors are undefined"): such a row has
the text `?` and only the flags x, r, i, z, o, u are compared.

Groups: 0 random arguments of 1 to 40 digits (adjusted exponent -40 to 3, both signs) in
precisions 1 to 100, half even, exponent range +-999999; 1 arguments `ln(m)` for a midpoint `m`
between two results of the context (the exponential lies within 10^-(precision + 50) of a rounding
boundary); 2 the decimal32, decimal64, decimal128 and odd contexts, every rounding mode, subset
and extended; 3 large arguments from -3E+6 to 2999999 around the 10^3 bound of the midpoint route; 4 the overflow
and underflow thresholds of decimal32, decimal64 and decimal128 (arguments within 3 of ln(10)(emax + 1) and
-ln(10)(-etiny), around the guards 3(emax + 1) and 3(1 - etiny), and from -1000 to -150), five rounding modes; 5 the rows of group 4 beyond those guards on which the library gives the wrong
directed result (issue 796), kept apart so that the `#skip` block of the defect is exactly those rows.

    python3 tools/generate_decimal_gda_exp_rows.py && moon fmt
    python3 tools/generate_decimal_gda_exp_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal_gda/certified_exp_rows_wbtest.mbt"
SEED = 0xE7A1BC0FFEE

MODES: dict[str, str] = {
    "HalfEven": decimal.ROUND_HALF_EVEN,
    "HalfUp": decimal.ROUND_HALF_UP,
    "HalfDown": decimal.ROUND_HALF_DOWN,
    "Down": decimal.ROUND_DOWN,
    "Ceiling": decimal.ROUND_CEILING,
    "Floor": decimal.ROUND_FLOOR,
    "Up": decimal.ROUND_UP,
    "ZeroFiveUp": decimal.ROUND_05UP,
}
FLAG_LETTERS = [
    (decimal.Inexact, "x"),
    (decimal.Rounded, "r"),
    (decimal.InvalidOperation, "i"),
    (decimal.DivisionByZero, "z"),
    (decimal.Overflow, "o"),
    (decimal.Underflow, "u"),
    (decimal.Subnormal, "s"),
    (decimal.Clamped, "c"),
]
PRECISIONS = [1, 2, 5, 9, 16, 17, 20, 34, 40, 64, 100]
SHAPES = [
    (7, -101, 96, False, True),
    (16, -398, 384, False, True),
    (34, -6176, 6144, False, True),
    (16, -398, 384, True, False),
    (34, -6176, 6144, True, False),
    (3, -20, 20, False, False),
    (1, -5, 5, True, False),
    (25, -999, 999, False, False),
]
LARGE = [
    "-3.00E+6", "-2999999", "-1E+5", "-123456.5", "-10001", "-10000", "-1001", "-1000",
    "-999.99", "-999", "-500", "-1.5", "1.5", "999", "999.99", "1000", "1001", "9999",
    "10000", "10001", "123456.5", "1E+5", "2999999",
]

FORMATS = [("decimal32", 7, -95, 96), ("decimal64", 16, -383, 384), ("decimal128", 34, -6143, 6144)]
EDGE_MODES = ["HalfEven", "Down", "Up", "Floor", "Ceiling"]

Row = tuple[int, int, int, int, bool, bool, str, str, str, str]


def text(value: decimal.Decimal) -> str:
    if value.is_infinite():
        return "-inf" if value.is_signed() else "inf"
    return str(value)


def expected(
    precision: int, e_min: int, e_max: int, extended: bool, clamp: bool, mode: str, argument: str
) -> tuple[str, str]:
    high = decimal.Context(
        prec=precision + 200,
        rounding=decimal.ROUND_HALF_EVEN,
        Emax=decimal.MAX_EMAX,
        Emin=decimal.MIN_EMIN,
        traps=[],
    )
    exact = high.exp(decimal.Decimal(argument))
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
    flags = "".join(letter if target.flags[flag] else "." for flag, letter in FLAG_LETTERS)
    if not extended and (target.flags[decimal.Overflow] or target.flags[decimal.Underflow]):
        # GDA 1.70 Appendix A, "Exceptional condition and rounding mode rules": in the subset
        # arithmetic overflow and underflow are errors and "results after these errors are
        # undefined", and subnormal numbers are not part of it. The value is not compared ("?")
        # and neither are the flags s and c, which only the extended arithmetic defines here.
        return "?", flags
    return text(result), flags


def random_argument(rng: random.Random) -> str:
    count = 1 + rng.randrange(40)
    digits = [1 + rng.randrange(9)] + [rng.randrange(10) for _ in range(count - 1)]
    adjusted = rng.randrange(44) - 40
    sign = rng.randrange(2)
    return str(decimal.Decimal((sign, tuple(digits), adjusted - (count - 1))))


def row(group: int, shape: tuple[int, int, int, bool, bool], mode: str, argument: str) -> Row:
    precision, e_min, e_max, extended, clamp = shape
    result, flags = expected(precision, e_min, e_max, extended, clamp, mode, argument)
    return (group, precision, e_min, e_max, extended, clamp, mode, argument, result, flags)


def edge_arguments(precision: int, e_min: int, e_max: int) -> list[str]:
    """Arguments around the overflow threshold ln(10)(emax + 1) and the underflow threshold -ln(10)(-etiny),
    around the guards 3(emax + 1) and 3(-etiny + 1) of the coarse decision, and in the range -1000 to -100."""
    etiny = e_min - precision + 1
    over = round(2.302585092994046 * (e_max + 1))
    under = round(2.302585092994046 * (-etiny))
    out = [str(over + d) for d in range(-3, 4)] + [str(-(under + d)) for d in range(-3, 4)]
    for guard in (3 * (e_max + 1), 3 * (1 - etiny)):
        out += [str(guard + d) for d in (-2, -1, 0, 1)] + [str(-(guard + d)) for d in (-2, -1, 0, 1)]
    out += [str(x) for x in (-150, -210, -240, -400, -999, -1000, -1001, -3000, 2 * (e_max + 1), 2 * (e_max + 1) + 5)]
    seen: list[str] = []
    for x in out:
        if x not in seen:
            seen.append(x)
    return seen


def known_defect(result: Row, e_min: int, e_max: int, precision: int) -> bool:
    """Rows of the defect of issue 796: beyond the guard 3 (emax + 1) the library gives Infinity in
    the directed modes that give the largest finite number, and beyond the guard -3 (1 - etiny) it
    gives zero in the modes that give the smallest subnormal (the expected value is CPython's)."""
    argument = int(result[7])
    text = result[8]
    etiny = e_min - precision + 1
    over = argument >= 3 * (e_max + 1) and "inf" not in text
    under = argument <= -3 * (1 - etiny) and not text.startswith(("0", "-0"))
    return over or under


def build() -> list[Row]:
    rng = random.Random(SEED)
    rows: list[Row] = []
    for _ in range(300):
        precision = PRECISIONS[rng.randrange(len(PRECISIONS))]
        rows.append(row(0, (precision, -999999, 999999, True, False), "HalfEven", random_argument(rng)))
    high = decimal.Context(prec=400, rounding=decimal.ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)
    for _ in range(120):
        precision = PRECISIONS[rng.randrange(len(PRECISIONS))]
        digits = [1 + rng.randrange(9)] + [rng.randrange(10) for _ in range(precision - 1)] + [5]
        midpoint = decimal.Decimal((0, tuple(digits), rng.randrange(3) - precision - 1))
        argument = decimal.Context(prec=precision + 60, rounding=decimal.ROUND_HALF_EVEN).ln(midpoint)
        rows.append(row(1, (precision, -999999, 999999, True, False), "HalfEven", str(argument)))
    for shape in SHAPES:
        for mode in MODES:
            for _ in range(3):
                rows.append(row(2, shape, mode, random_argument(rng)))
    for precision in (3, 16, 34):
        for argument in LARGE:
            rows.append(row(3, (precision, -999999, 999999, True, True), "HalfEven", argument))
    for _name, precision, e_min, e_max in FORMATS:
        for mode in EDGE_MODES:
            for argument in edge_arguments(precision, e_min, e_max):
                shape = (precision, e_min, e_max, True, True)
                result = row(4, shape, mode, argument)
                if known_defect(result, e_min, e_max, precision):
                    result = (5,) + result[1:]
                rows.append(result)
    del high
    return rows


def render(rows: list[Row]) -> str:
    lines = [
        "///|",
        "// Columns: group, precision, e_min, e_max, extended, clamp, mode, argument, expected text, flags (x r i z o u s c).",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_gda_exp_rows.py (CPython `decimal`, libmpdec)",
        "// input: exponential arguments of 1 to 40 digits and large arguments, in decimal32, decimal64, decimal128 and odd contexts, all eight rounding rules, subset and extended; the expected value and flags are exp evaluated 200 digits wider and rounded to the context by libmpdec",
        "// library-ran: no",
        "",
        "///|",
        "let exp_rows : Array[(Int32, Int32, Int32, Int32, Bool, Bool, String, String, String, String)] = [",
    ]
    b = lambda x: "true" if x else "false"
    for group, p, lo, hi, ext, clamp, mode, arg, result, flags in rows:
        lines.append(f'  ({group}, {p}, {lo}, {hi}, {b(ext)}, {b(clamp)}, "{mode}", "{arg}", "{result}", "{flags}"),')
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
    print(f"{OUTPUT}: {len(text_out.splitlines()) - 9} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
