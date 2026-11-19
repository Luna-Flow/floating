#!/usr/bin/env python3
"""Rows for `Decimal::to_bin_float` at large exponents (#378).

Writes `src/decimal/to_bin_float_rows_wbtest.mbt`, a table of
`(decimal, precision, mode, expected coefficient, expected exponent2)` executed by
`to_bin_float_parts_wbtest.mbt`. The expected binary value is computed by exact
integer arithmetic in Python (`c * 10^e` rounded to `precision` bits in the named
direction: round to nearest with ties to even, toward zero, away from zero,
toward negative, toward positive), independent of the library and of the
previous implementation. The coefficient is the signed integer `C` with `|C| <
2^precision` and the value is `C * 2^exponent2`. Rows cover exponents near
+-2e5 and +-2e6 (the ends of the operand range of the math functions),
+-4096 (the switch to directed powers of 5), several coefficients, both signs and
every direction, plus values exactly representable and exactly halfway between
two binary numbers (the round-to-odd sticky bit), which need the exact
conversion because the bounds of 5^e straddle them.

    python3 tools/generate_decimal_to_bin_rows.py && moon fmt
    python3 tools/generate_decimal_to_bin_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/decimal/to_bin_float_rows_wbtest.mbt"
MODES = ["ToNearestEven", "TowardZero", "AwayFromZero", "TowardNegative", "TowardPositive"]
ROW_TYPE = "(String, Int32, String, String, Int32)"


def round_to_bits(numerator: int, denominator: int, precision: int, negative: bool, mode: str):
    """The rounding of numerator / denominator (> 0) to `precision` bits, as (C, k)."""
    # Choose k with 2^(p-1) <= value / 2^k < 2^p.
    k = numerator.bit_length() - denominator.bit_length() - precision
    while True:
        if k >= 0:
            q, r = divmod(numerator, denominator << k)
            den = denominator << k
        else:
            q, r = divmod(numerator << -k, denominator)
            den = denominator
        if q >= 1 << precision:
            k += 1
            continue
        if q < 1 << (precision - 1):
            k -= 1
            continue
        break
    inexact = r != 0
    if inexact:
        if mode == "ToNearestEven":
            twice = 2 * r
            up = twice > den or (twice == den and q & 1 == 1)
        elif mode == "TowardZero":
            up = False
        elif mode == "AwayFromZero":
            up = True
        elif mode == "TowardNegative":
            up = negative
        else:
            up = not negative
        if up:
            q += 1
            if q == 1 << precision:
                q >>= 1
                k += 1
    return (-q if negative else q), k


def value_parts(coefficient: int, exponent: int):
    if exponent >= 0:
        return coefficient * 10**exponent, 1
    return coefficient, 10 ** (-exponent)


def all_rows() -> list[tuple]:
    rows = []
    coefficients = [1, 3, 7, 9999999, 1234567, 1000000000000000000000000000000001,
                    9999999999999999999999999999999999]
    exponents = [200000, -200000, 1999990, -1999990, 4096, -4096, -4097, 4097]
    for precision in (53, 128):
        for exponent in exponents:
            for c in coefficients:
                for negative in (False, True):
                    for mode in MODES:
                        # a representative subset: all modes for two coefficients, the
                        # nearest mode for the rest
                        if c not in (3, 9999999999999999999999999999999999) and mode != "ToNearestEven":
                            continue
                        n, d = value_parts(c, exponent)
                        C, k = round_to_bits(n, d, precision, negative, mode)
                        text = ("-" if negative else "") + f"{c}E{exponent}"
                        rows.append((text, precision, mode, str(C), k))
    # Exactly representable and exactly halfway values at exponents 4096 and above:
    # c = 5^s m gives m / 2^s, dyadic. m with p bits is exact; m with p + 1 bits
    # (odd) is a midpoint of two p-bit numbers.
    for s in (4096, 4100, 5000):
        for precision, m_bits in ((53, 53), (53, 54), (113, 113), (113, 114)):
            for tweak in (1, 3):
                m = (1 << (m_bits - 1)) + tweak  # odd, exactly m_bits bits
                c = 5**s * m
                for negative in (False, True):
                    for mode in MODES:
                        n, d = value_parts(c, -s)
                        C, k = round_to_bits(n, d, precision, negative, mode)
                        text = ("-" if negative else "") + f"{c}E-{s}"
                        rows.append((text, precision, mode, str(C), k))
    # 10^e exactly representable at a precision above the bits of 5^e (positive e).
    for e in (4096, 4100):
        precision = (5**e).bit_length() + 5
        for negative in (False, True):
            for mode in MODES:
                n, d = value_parts(1, e)
                C, k = round_to_bits(n, d, precision, negative, mode)
                rows.append((("-" if negative else "") + f"1E{e}", precision, mode, str(C), k))
    return rows


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(rows: list[tuple]) -> str:
    out = [
        "///|",
        "// Generated by tools/generate_decimal_to_bin_rows.py from exact integer",
        "// arithmetic in Python; do not edit.",
        "// Columns: decimal, precision, mode, signed coefficient C, exponent2 k",
        "// (the expected value is C * 2^k).",
        "",
        "///|",
        f"fn to_bin_float_rows() -> Array[{ROW_TYPE}] {{",
        "  [",
    ]
    for text, precision, mode, coefficient, exponent in rows:
        out.append(f"    ({quote(text)}, {precision}, {quote(mode)}, {quote(coefficient)}, {exponent}),")
    out += ["  ]", "}", ""]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.set_int_max_str_digits(0)
    text = render(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""

        def norm(s: str) -> str:
            squeezed = "".join(s.split())
            for closer in (")", "]", "}"):
                squeezed = squeezed.replace("," + closer, closer)
            return squeezed

        if norm(current) != norm(text):
            print(f"{OUTPUT} is stale: run tools/generate_decimal_to_bin_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(text)} bytes, {len(rows_count(text))} rows)")
    return 0


def rows_count(text: str) -> list[str]:
    return [line for line in text.splitlines() if line.startswith('    ("')]


if __name__ == "__main__":
    raise SystemExit(main())
