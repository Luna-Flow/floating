#!/usr/bin/env python3
"""Rows for the division of operands above the recursive-division threshold (800 limbs and more).

Writes `library/src/binary/div_long_rows_wbtest.mbt`. The test of `bin_div_long_wbtest.mbt`
draws its operands from a small linear congruential generator; this program draws the same
operands with the same generator (`DivLongRandom::next` and `div_long_coeff`, written again here)
and computes the expected results with Python integers, which do not use this library:

* constructed rows: for a divisor `d` (51200 to 60001 bits), a quotient `q` of precision + 1 bits
  and a remainder `r`, the numerator `N = q d + r`; the table holds the bit length of `N` and
  `N mod (2^64 - 1)` and `N mod (2^64 + 1)` (so the test can check the numerator it built with
  its own multiplication), and for each rounding direction and sign whether the correctly
  rounded quotient is the truncation of q / 2 or one unit above it, and whether it is inexact;
* quotient rows: for two random operands of `bits` bits, the correctly rounded (ties to even)
  quotient to `bits` bits, as a hexadecimal significand and exponent; and the numerator of the
  exact-multiple case with the same checks.

    python3 tools/generate_div_long_rows.py && moon fmt
    python3 tools/generate_div_long_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/binary/div_long_rows_wbtest.mbt"
MASK = (1 << 64) - 1
MODES = ["RNE", "RNA", "RTZ", "RTP", "RTN"]
DIVISOR_BITS = [51200, 51264, 53000, 60001]
PRECISIONS = [53, 700, 3000]
QUOTIENT_BITS = [51200, 52000, 64000]


class Random:
    """`DivLongRandom` of bin_div_long_wbtest.mbt."""

    def __init__(self, state: int) -> None:
        self.state = state

    def next(self) -> int:
        self.state = (self.state * 6364136223846793005 + 1442695040888963407) & MASK
        return ((self.state >> 17) | (self.state << 47)) & MASK


def coeff(random: Random, bits: int) -> int:
    """`div_long_coeff`: a number of exactly `bits` bits."""
    value = 1
    while value.bit_length() < bits:
        value = (value << 32) + (random.next() >> 32)
    trimmed = value >> (value.bit_length() - bits)
    if trimmed.bit_length() < bits:
        return (1 << (bits - 1)) + trimmed
    return trimmed


def round_up(round_bit: bool, sticky: bool, lowest_kept: bool, negative: bool, mode: str) -> bool:
    """Whether the truncated quotient is incremented (IEEE 754-2019 4.3)."""
    inexact = round_bit or sticky
    if mode == "RNE":
        return round_bit and (sticky or lowest_kept)
    if mode == "RNA":
        return round_bit
    if mode == "RTZ":
        return False
    if mode == "RTP":
        return inexact and not negative
    return inexact and negative  # RTN


def weighted(n: int) -> int:
    """The sum of (i + 1) * w_i over the 64-bit words w_i of n (least significant first), mod 2^64."""
    total = 0
    index = 0
    while n:
        total += (index + 1) * (n & MASK)
        n >>= 64
        index += 1
    return total & MASK


def outcomes(q: int, r: int) -> str:
    """For each mode and sign (positive then negative): U if the result is (q >> 1) + 1, else D."""
    round_bit = bool(q & 1)
    sticky = r != 0
    lowest = bool((q >> 1) & 1)
    return "".join("U" if round_up(round_bit, sticky, lowest, negative, mode) else "D" for mode in MODES for negative in (False, True))


def constructed_rows() -> list[tuple]:
    random = Random(0x4D49_5353_494E_4721)
    rows = []
    for divisor_bits in DIVISOR_BITS:
        d = coeff(random, divisor_bits) + 1
        if d % 2 == 0:
            d += 1
        for precision in PRECISIONS:
            q_odd = coeff(random, precision + 1)
            if q_odd % 2 == 0:
                q_odd += 1
            q_even = q_odd + 1
            cases = [(q_even, 0), (q_odd, 0), (q_odd, d - 1), (q_even, d - 1), (q_odd, 1), (q_even, d >> 1)]
            for index, (q, r) in enumerate(cases):
                n = q * d + r
                rows.append((divisor_bits, precision, index, n.bit_length(), f"{n % MASK}", f"{weighted(n)}", outcomes(q, r), "I" if (q & 1) or r else "-"))
    return rows


def rounded_quotient(a: int, ea: int, b: int, eb: int, bits: int) -> tuple[int, int]:
    """(odd mantissa, exponent) of a 2^ea / (b 2^eb) rounded to `bits` bits, ties to even."""
    value = Fraction(a, b) * Fraction(2) ** (ea - eb)
    e = value.numerator.bit_length() - value.denominator.bit_length()
    while Fraction(2) ** e > value:
        e -= 1
    while Fraction(2) ** (e + 1) <= value:
        e += 1
    grid = e - bits + 1
    scaled = value / Fraction(2) ** grid if grid >= 0 else value * 2 ** (-grid)
    floor = scaled.numerator // scaled.denominator
    rest = scaled - floor
    count = floor + (1 if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and floor % 2 == 1) else 0)
    while count % 2 == 0:
        count //= 2
        grid += 1
    return count, grid


def quotient_rows() -> list[tuple]:
    random = Random(0x1357_9BDF_0246_8ACE)
    rows = []
    for bits in QUOTIENT_BITS:
        a = coeff(random, bits)
        b = coeff(random, bits)
        mantissa, exponent = rounded_quotient(a, -bits, b, -bits, bits)
        q = coeff(random, 700)
        n = q * (b >> ((b & -b).bit_length() - 1))  # the library keeps the odd significand of b
        rows.append((bits, f"0x{mantissa:x}p{exponent}", n.bit_length(), f"{n % MASK}", f"{weighted(n)}"))
    return rows


def render_file() -> str:
    lines = [
        "// Generated by tools/generate_div_long_rows.py; do not edit.",
        "// Division above the recursive-division threshold: results and numerator checks from Python integers.",
        "// constructed rows: (divisor bits, precision, case, bit length of N, N mod 2^64 - 1, weighted word sum of N, U or D per mode and sign, inexact);",
        "// quotient rows: (bits, the rounded quotient of two random operands, bit length and the two checks of q * b).",
        "// oracle-file: A",
        "// producer: tools/generate_div_long_rows.py",
        "// input: the operands of bin_div_long_wbtest.mbt, drawn again with the same generator in Python",
        "// library-ran: no",
        "",
        "///|",
        "fn div_long_constructed_rows() -> Array[(Int32, Int32, Int32, Int32, String, String, String, String)] {",
        "  [",
    ]
    for row in constructed_rows():
        lines.append("    (" + ", ".join(f'"{x}"' if isinstance(x, str) else str(x) for x in row) + "),")
    lines += ["  ]", "}", "", "///|",
              "fn div_long_quotient_rows() -> Array[(Int32, String, Int32, String, String)] {", "  ["]
    for row in quotient_rows():
        lines.append("    (" + ", ".join(f'"{x}"' if isinstance(x, str) else str(x) for x in row) + "),")
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = render_file()
    if args.check:
        squeeze = lambda value: "".join(value.split()).replace(",)", ")").replace(",]", "]")
        ok = OUTPUT.is_file() and squeeze(OUTPUT.read_text(encoding="utf-8")) == squeeze(text)
        if not ok:
            print(f"stale: {OUTPUT}", file=sys.stderr)
        return 0 if ok else 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT}: {len(text)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
