#!/usr/bin/env python3
"""Rows for `to_binary` of a decimal with a very large exponent (issue 468).

Writes `tooling/src/consistency/to_binary_large_rows_wbtest.mbt`, a table of
`(decimal, precision, mode, expected)` read by `to_binary_exponent_issue468_wbtest.mbt`.
The expected value is the IEEE 754-2019 conversion of `c * 10^e` to a binary format of
`precision` bits whose exponent range is the implementation range of the library
(`e_max` 1073741823, `e_min` 1 - `e_max`, with subnormal numbers): rounded once, in the
named direction; overflow and underflow as the direction says (clauses 4.3.1, 7.4, 7.5).
It is written as `inf`, `-inf`, `0`, `-0`, or `<odd coefficient>p<exponent2>` for the
value `odd * 2^exponent2`.

Python integers only; the library does not run. Exponents up to 3.3e8 are beyond an exact
power (10^323000000 has a billion bits), so for `|e| > EXACT_LIMIT` the power `5^|e|` is
enclosed by two integers of `WORK_BITS` bits obtained by squaring with directed
truncation, and a row is written only when the lower and the upper end of the enclosure
round to the same result (every rounding is monotone, so the exact value then rounds to
it too); otherwise the generator stops. No row is an exact value or a tie at such an
exponent: `c * 10^e` with `|e| > EXACT_LIMIT` and `c` of at most 34 digits is not
representable in 113 bits.

    python3 tools/generate_to_binary_large_rows.py
    python3 tools/generate_to_binary_large_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tooling/src/consistency/to_binary_large_rows_wbtest.mbt"
E_MAX = 1073741823
E_MIN = 1 - E_MAX
MODES = ["ToNearestEven", "ToNearestAway", "TowardZero", "TowardPositive", "TowardNegative"]
EXACT_LIMIT = 20000
WORK_BITS = 640
CHUNK_ROWS = 100

COEFFICIENTS = [1, 3, 7, 123456789, 9999999999999999999999999999999999]
EXPONENTS = [
    -330000000, -323000000, -320000000, -300000000, -30000000, -10000000, -1000000,
    1000000, 10000000, 30000000, 300000000, 320000000, 323000000, 330000000,
]
# 2^1073741824 = 10^323228496.17..., so these exponents straddle the overflow
# threshold, and their negatives the smallest subnormal and the smallest normal.
BOUNDARY_EXPONENTS = [323228494, 323228495, 323228496, 323228497, 323228498, 323228499]
BOUNDARY_COEFFICIENTS = [1, 3]
PRECISIONS = [24, 53, 113]
BOUNDARY_PRECISIONS = [24, 113]


def ieee_round(m: int, s: int, negative: bool, mode: str, precision: int):
    """Round `m * 2^s` (m > 0) once. Returns ('inf',), ('zero',) or ('fin', C, k) with C > 0
    the odd coefficient of the finite result (the value is C * 2^k)."""
    top = s + m.bit_length() - 1
    grid = (top if top >= E_MIN else E_MIN) - precision + 1
    drop = grid - s
    if drop <= 0:
        q, inexact, half = m << -drop, False, 0
        up = False
    else:
        q, r = divmod(m, 1 << drop)
        inexact = r != 0
        half = (r > (1 << (drop - 1))) - (r < (1 << (drop - 1)))  # 1 above, 0 tie, -1 below
        if not inexact:
            up = False
        elif mode == "ToNearestEven":
            up = half > 0 or (half == 0 and q & 1 == 1)
        elif mode == "ToNearestAway":
            up = half >= 0
        elif mode == "TowardZero":
            up = False
        elif mode == "TowardPositive":
            up = not negative
        else:
            up = negative
    if up:
        q += 1
    if q == 0:
        return ("zero",)
    top_result = grid + q.bit_length() - 1
    if top_result > E_MAX:
        to_infinity = mode in ("ToNearestEven", "ToNearestAway") or (
            mode == "TowardPositive" and not negative
        ) or (mode == "TowardNegative" and negative)
        if to_infinity:
            return ("inf",)
        return ("fin", (1 << precision) - 1, E_MAX - precision + 1)
    while q & 1 == 0:
        q >>= 1
        grid += 1
    return ("fin", q, grid)


def power5_enclosure(e: int):
    """(lo, hi, s): integers with lo * 2^s <= 5^e <= hi * 2^s, e >= 0, both of at most
    WORK_BITS bits."""
    lo, hi, s = 1, 1, 0
    for bit in bin(e)[2:]:
        # square
        lo, hi, s = lo * lo, hi * hi, 2 * s
        lo, hi, s = shrink(lo, hi, s)
        if bit == "1":
            lo, hi = lo * 5, hi * 5
            lo, hi, s = shrink(lo, hi, s)
    return lo, hi, s


def shrink(lo: int, hi: int, s: int):
    extra = hi.bit_length() - WORK_BITS
    if extra > 0:
        lo >>= extra
        hi = (hi >> extra) + 1
        s += extra
    return lo, hi, s


def value_enclosure(c: int, e: int):
    """((m_lo, s_lo), (m_hi, s_hi)) with m_lo * 2^s_lo <= c * 10^e <= m_hi * 2^s_hi."""
    if abs(e) <= EXACT_LIMIT:
        if e >= 0:
            m = c * 5**e
            return (m, e), (m, e)
        # c / 5^|e| * 2^e: scale the numerator so that the quotient has many bits
        n = 5 ** (-e)
        shift = n.bit_length() + 64 + c.bit_length()
        q, r = divmod(c << shift, n)
        lo = (q, e - shift)
        hi = (q + (1 if r else 0), e - shift)
        return lo, hi
    lo5, hi5, s5 = power5_enclosure(abs(e))
    if e > 0:
        return (c * lo5, e + s5), (c * hi5, e + s5)
    # c * 2^e / 5^|e|: reciprocal of the enclosure, 1 / 5^|e| in [1/hi5, 1/lo5] * 2^-s5
    shift = hi5.bit_length() + WORK_BITS
    q_lo = (c << shift) // hi5
    q_hi = -((-(c << shift)) // lo5)
    return (q_lo, e - shift - s5), (q_hi, e - shift - s5)


def convert(c: int, e: int, negative: bool, mode: str, precision: int):
    low, high = value_enclosure(c, e)
    a = ieee_round(low[0], low[1], negative, mode, precision)
    b = ieee_round(high[0], high[1], negative, mode, precision)
    if a != b:
        raise SystemExit(f"enclosure too wide for {c}E{e} {mode} p={precision}: {a} {b}")
    return a


def expected_text(result, negative: bool) -> str:
    if result[0] == "inf":
        return "-inf" if negative else "inf"
    if result[0] == "zero":
        return "-0" if negative else "0"
    _, c, k = result
    return f"{'-' if negative else ''}{c}p{k}"


def all_rows() -> list[tuple[str, int, str, str]]:
    rows: list[tuple[str, int, str, str]] = []

    def add(c: int, e: int, precision: int) -> None:
        for negative in (False, True):
            for mode in MODES:
                result = convert(c, e, negative, mode, precision)
                text = ("-" if negative else "") + f"{c}E{e}"
                rows.append((text, precision, mode, expected_text(result, negative)))

    for e in EXPONENTS:
        for c in COEFFICIENTS:
            for p in PRECISIONS:
                add(c, e, p)
    for e in BOUNDARY_EXPONENTS:
        for c in BOUNDARY_COEFFICIENTS:
            for p in BOUNDARY_PRECISIONS:
                add(c, e, p)
                add(c, -e, p)
    return rows


def quote(text: str) -> str:
    return '"' + text + '"'


def render(rows: list[tuple[str, int, str, str]]) -> str:
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_to_binary_large_rows.py (Python integers: the power 5^|e| enclosed by two",
        "//   640-bit integers, a row written only when both ends round alike)",
        "// input: coefficients 1, 3, 7, 123456789 and 34 nines; decimal exponents from -330000000 to 330000000 and the",
        "//   overflow and underflow thresholds (323228494 to 323228499 and their negatives); precisions 24, 53, 113;",
        "//   both signs; five rounding directions; the binary range of the library (e_max 1073741823, subnormal numbers)",
        "// Columns: decimal, precision, rounding direction, expected: inf, -inf, 0, -0 or <odd C>p<k> for C * 2^k.",
        "// library-ran: no",
        "",
    ]
    chunks = [rows[i : i + CHUNK_ROWS] for i in range(0, len(rows), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        out += ["///|", f"fn to_binary_large_rows_{index}() -> Array[(String, Int32, String, String)] {{", "  ["]
        for text, precision, mode, expected in chunk:
            out.append(f"    ({quote(text)}, {precision}, {quote(mode)}, {quote(expected)}),")
        out += ["  ]", "}", ""]
    out += ["///|", "fn to_binary_large_rows() -> Array[(String, Int32, String, String)] {",
            "  let rows : Array[(String, Int32, String, String)] = []"]
    for index in range(len(chunks)):
        out.append(f"  for row in to_binary_large_rows_{index}() {{ rows.push(row) }}")
    out += ["  rows", "}", ""]
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
            print(f"{OUTPUT} is stale: run tools/generate_to_binary_large_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
