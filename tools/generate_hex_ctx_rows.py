#!/usr/bin/env python3
"""Rows for `BinFloat::from_hex_ctx` (issue #256, IEEE 754-2019 5.12.3).

Writes `library/src/bin_float/hex_ctx_rows_wbtest.mbt`: hexSequences with more
significant bits than the precision (exact, below, at and above the midpoint of
every rounding position), in the normal range, in the subnormal range, around
the overflow threshold and below the smallest subnormal, in binary16, 32, 64,
128, two toy formats and the implementation range of an unbounded context, with
all six rounding directions and both tininess rules.

The expected value and flags come from exact rational arithmetic (`fractions`),
written from the standard and independent of the library:

* the exact value is M * 2^E with M the integer of the hexDigits;
* the rounding position is the quantum 2^(e - p + 1) of the binade e of the
  value, or 2^(emin - p + 1) below 2^emin (the subnormal grid);
* inexact when the rounded value differs from the exact one;
* overflow when the value rounded with an unbounded exponent range exceeds the
  largest finite number (5.12.3, 7.4): the result is the infinity or the largest
  finite number by the direction;
* underflow when inexact and tiny: tiny before rounding is a nonzero exact value
  below 2^emin, after rounding the same for the value rounded with an unbounded
  exponent range (7.5).

    python3 tools/generate_hex_ctx_rows.py && moon fmt
    python3 tools/generate_hex_ctx_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/bin_float/hex_ctx_rows_wbtest.mbt"

# name, precision, emin, emax (the exponent of the smallest normal and of the largest finite)
FORMATS = [
    ("binary16", 11, -14, 15),
    ("binary32", 24, -126, 127),
    ("binary64", 53, -1022, 1023),
    ("binary128", 113, -16382, 16383),
    ("toy5", 5, -6, 7),
    ("toy2", 2, -2, 3),
    # the implementation range of an unbounded context
    ("unbounded53", 53, -1073741823, 1073741823),
]
MODES = ["RNE", "RNA", "RTZ", "RTP", "RTN", "RAZ"]


def round_grid(value: Fraction, grid: int, mode: str, negative: bool) -> int:
    """`value` (positive) in units of 2^grid, rounded by `mode`; returns the integer count."""
    scaled = value / Fraction(2) ** grid if grid >= 0 else value * 2 ** (-grid)
    floor = scaled.numerator // scaled.denominator
    rest = scaled - floor
    if rest == 0:
        return floor
    if mode == "RNE":
        up = rest > Fraction(1, 2) or (rest == Fraction(1, 2) and floor % 2 == 1)
    elif mode == "RNA":
        up = rest >= Fraction(1, 2)
    elif mode == "RTZ":
        up = False
    elif mode == "RTP":
        up = not negative
    elif mode == "RTN":
        up = negative
    else:  # RAZ
        up = True
    return floor + 1 if up else floor


def binade(value: Fraction) -> int:
    """floor(log2(value)) for a positive rational."""
    e = value.numerator.bit_length() - value.denominator.bit_length()
    while Fraction(2) ** e > value:
        e -= 1
    while Fraction(2) ** (e + 1) <= value:
        e += 1
    return e


def render(negative: bool, count: int, grid: int) -> str:
    """`count * 2^grid` as the library prints it: an odd mantissa and a binary exponent."""
    if count == 0:
        return "-0" if negative else "0"
    while count % 2 == 0:
        count //= 2
        grid += 1
    return f"{'-' if negative else ''}{count}p{grid}"


def convert_far(mantissa: int, exponent2: int, negative: bool, p: int, emin: int, emax: int, mode: str):
    """A value whose binary exponent is too large to build as a rational: it lies far
    above 2^(emax + 1) (overflow) or far below half the smallest subnormal (underflow)."""
    top = exponent2 + mantissa.bit_length() - 1
    if top > emax + 1:
        away = {
            "RNE": True, "RNA": True, "RAZ": True, "RTZ": False,
            "RTP": not negative, "RTN": negative,
        }[mode]
        text = ("-" if negative else "") + "inf" if away else render(negative, 2**p - 1, emax - p + 1)
        return text, "I-O"
    assert top < emin - p - 2, (mantissa, exponent2)
    away = {"RNE": False, "RNA": False, "RTZ": False, "RTP": not negative, "RTN": negative, "RAZ": True}[mode]
    return (render(negative, 1, emin - p + 1) if away else ("-0" if negative else "0")), "IU-"


def convert(value: Fraction, negative: bool, p: int, emin: int, emax: int, mode: str, tininess: str):
    """(printed result, flags) of rounding the positive `value` into the format."""
    if value == 0:
        return ("-0" if negative else "0"), "---"
    e = binade(value)
    grid = max(e, emin) - p + 1
    count = round_grid(value, grid, mode, negative)
    # the value rounded with an unbounded exponent range
    unbounded = round_grid(value, e - p + 1, mode, negative) * Fraction(2) ** (e - p + 1)
    result = count * Fraction(2) ** grid
    inexact = result != value
    max_finite = (2**p - 1) * Fraction(2) ** (emax - p + 1)
    overflow = unbounded > max_finite
    if overflow:
        away = {
            "RNE": True, "RNA": True, "RAZ": True, "RTZ": False,
            "RTP": not negative, "RTN": negative,
        }[mode]
        text = ("-" if negative else "") + "inf" if away else render(negative, 2**p - 1, emax - p + 1)
        return text, "I-O"
    tiny_before = value < Fraction(2) ** emin
    tiny_after = unbounded < Fraction(2) ** emin
    tiny = tiny_before if tininess == "before" else tiny_after
    underflow = inexact and tiny
    flags = ("I" if inexact else "-") + ("U" if underflow else "-") + "-"
    return render(negative, count, grid), flags


def hex_text(mantissa: int, exponent2: int, negative: bool, style: int) -> str:
    """A hexSequence of the value mantissa * 2^exponent2, in one of several spellings."""
    digits = format(mantissa, "x")
    sign = "-" if negative else ""
    if style == 0:  # integer significand
        return f"{sign}0x{digits}p{exponent2}"
    if style == 1:  # a point after the first digit
        exp = exponent2 + 4 * (len(digits) - 1)
        rest = digits[1:] or "0"
        return f"{sign}0X{digits[0]}.{rest.upper()}P{exp:+d}"
    # a leading point: 0x.hhh p E
    exp = exponent2 + 4 * len(digits)
    return f"{sign}0x.{digits}p{exp}"


def sequences(p: int, emin: int, emax: int, name: str):
    """(mantissa, exponent2) pairs around every rounding position of the format."""
    out = []
    rich = p in (5, 11)  # two small formats get every combination
    extra = [1, 3, 5] if rich else [1, 4]
    base = (1 << (p - 1)) | 1  # a p-bit odd integer
    tops = [0, 3, emin, emin - 1, emin - 2, emax - 1, emax] if rich else [0, emin, emin - 1, emax]
    tails = ("zero", "low", "below", "at", "above", "all") if rich else ("zero", "below", "at", "above")
    for top in tops:
        for k in extra:
            for tail in tails:
                half = 1 << (k - 1)
                r = {"zero": 0, "low": 1, "below": half - 1, "at": half, "above": half + 1, "all": (1 << k) - 1}[tail]
                m = (base << k) | r
                # top bit of m is at position p + k - 1: place it at binade `top`
                out.append((m, top - (p + k - 1)))
    # the subnormal grid: values with few bits well below emin
    for shift in range(0, p + 3, max(1, (p + 3) // 8)):
        for r in ((1, 3, 5) if rich else (3,)):
            out.append((r, emin - p + 1 - shift))
    # around the overflow threshold: the largest finite value and the midpoint above it
    top = emax + 1
    out.append(((1 << p) - 1, emax - p + 1))  # the largest finite number, exact
    out.append((((1 << p) - 1) << 1 | 1, emax - p))  # the midpoint to 2^(emax+1)
    out.append((((1 << p) - 1) << 2 | 3, emax - p - 1))  # above the midpoint
    out.append((((1 << p) - 1) << 2 | 1, emax - p - 1))  # below the midpoint
    # far outside the range
    out.append((1, emax + 100))
    out.append((1, emin - p - 100))
    out.append((0xDEADBEEF, 5_000_000_000))
    out.append((0xDEADBEEF, -5_000_000_000))
    # zeros
    out.append((0, 0))
    out.append((0, 123))
    return out


def build() -> list[tuple]:
    rows = []
    for name, p, emin, emax in FORMATS:
        seqs = sequences(p, emin, emax, name)
        for index, (mantissa, exponent2) in enumerate(seqs):
            if name == "unbounded53":
                # only the symbolic rows: a rational at 2^(+-10^9) cannot be built
                top = exponent2 + mantissa.bit_length() - 1 if mantissa else 0
                if not (mantissa and abs(exponent2) > 10**6 and (top > emax + 1 or top < emin - p - 2)):
                    continue
            negative = index % 2 == 0
            for mode in MODES:
                for tininess in ("before", "after"):
                    text = hex_text(mantissa, exponent2, negative, index % 3)
                    if mantissa and abs(exponent2) > 10**6:
                        expected, flags = convert_far(mantissa, exponent2, negative, p, emin, emax, mode)
                    else:
                        value = Fraction(mantissa) * (Fraction(2) ** exponent2 if exponent2 >= 0 else Fraction(1, 2 ** (-exponent2)))
                        expected, flags = convert(value, negative, p, emin, emax, mode, tininess)
                    rows.append((text, name, p, emin, emax, mode, tininess, expected, flags))
    # drop duplicates of rows that do not depend on the tininess rule
    seen = set()
    unique = []
    for row in rows:
        key = row[:6] + ((row[6],) if "U" in row[8] else ())
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)
    return unique


def render_file(rows: list[tuple]) -> str:
    lines = [
        "// Generated by tools/generate_hex_ctx_rows.py; do not edit.",
        "// BinFloat::from_hex_ctx against exact rational arithmetic (IEEE 754-2019 5.12.3):",
        "// (hexSequence, format, precision, e_min, e_max, rounding, tininess, expected, flags).",
        "",
        "///|",
        "fn hex_ctx_rows() -> Array[(String, String, Int32, Int32, Int32, String, String, String, String)] {",
        "  [",
    ]
    for text, name, p, emin, emax, mode, tininess, expected, flags in rows:
        lines.append(f'    ("{text}", "{name}", {p}, {emin}, {emax}, "{mode}", "{tininess}", "{expected}", "{flags}"),')
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = render_file(build())
    if args.check:
        squeeze = lambda value: "".join(value.split()).replace(",)", ")").replace(",]", "]")
        ok = OUTPUT.is_file() and squeeze(OUTPUT.read_text(encoding="utf-8")) == squeeze(text)
        if not ok:
            print(f"stale: {OUTPUT}", file=sys.stderr)
        return 0 if ok else 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT}: {len(text.splitlines()) - 9} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
