#!/usr/bin/env python3
"""Rows for the correctly rounded operations on wide operands (IEEE 754-2019 5.4.1, 4.3, 7.4, 7.5).

Writes `library/src/binary/arith_rows_wbtest.mbt`: add, mul, div and sqrt of operands of up to
`p` bits, with `p` from 2 to 4097, in the implementation range (a context given a precision and
nothing else) and in the interchange formats binary16, binary32 and binary64 (overflow and the
subnormal range), in all five rounding directions. The operands are built to hit what a fast
path gets wrong: ties and neighbours of ties, carries out of all-ones, cancellation, a gap
larger than the precision (sticky bit), exact quotients and their neighbours, perfect squares
and their neighbours, odd and even exponents.

The expected value and the flags are exact rational arithmetic (`fractions`, `math.isqrt`) and
the rounding rule of `generate_hex_ctx_rows` (a quantum 2^(e - p + 1), the subnormal grid,
overflow and underflow of 7.4 and 7.5). They do not come from the library. A table row is

    (operation, p, e_min, e_max, rounding, tininess, left, right, expected, flags)

where `left` and `right` are hexSequences of at most `p` bits (`right` is "" for sqrt).

    python3 tools/generate_arith_rows.py && moon fmt
    python3 tools/generate_arith_rows.py --check
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from fractions import Fraction
from pathlib import Path

import generate_hex_ctx_rows as rounding

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/binary/arith_rows_wbtest.mbt"
MODES = ["RNE", "RNA", "RTZ", "RTP", "RTN"]
IMPL_EMIN, IMPL_EMAX = -1073741822, 1073741823
PRECISIONS = [2, 3, 11, 24, 53, 54, 61, 62, 63, 64, 65, 113, 127, 128, 129, 192, 255, 256, 257, 300, 512, 600, 1000, 1024, 2048, 4097, 8192]
FORMATS = [("binary16", 11, -14, 15), ("binary32", 24, -126, 127), ("binary64", 53, -1022, 1023)]
Operand = tuple[bool, int, int]  # negative, odd or any positive mantissa, binary exponent


def hex_text(operand: Operand) -> str:
    negative, mantissa, exponent = operand
    return f"{'-' if negative else ''}0x{mantissa:x}p{exponent}"


def value_of(operand: Operand) -> Fraction:
    negative, mantissa, exponent = operand
    magnitude = Fraction(mantissa) * Fraction(2) ** exponent
    return -magnitude if negative else magnitude


def finish(value: Fraction, p: int, emin: int, emax: int, mode: str, tininess: str, zero_negative: bool = False):
    """(printed result, flags) of rounding `value` into the context (p, emin, emax)."""
    if value == 0:
        return ("-0" if zero_negative else "0"), "---"
    negative = value < 0
    magnitude = -value if negative else value
    if abs(emin) > 10**5:
        # the implementation range: 2^emin cannot be built; the value is far inside it
        assert Fraction(1, 2**40000) < magnitude < 2**40000
        grid = rounding.binade(magnitude) - p + 1
        count = rounding.round_grid(magnitude, grid, mode, negative)
        exact = count * Fraction(2) ** grid == magnitude
        return rounding.render(negative, count, grid), ("---" if exact else "I--")
    return rounding.convert(magnitude, negative, p, emin, emax, mode, tininess)


def sqrt_finish(value: Fraction, p: int, mode: str):
    """Correctly rounded square root of a positive `value` in the implementation range."""
    assert value > 0
    e = rounding.binade(value) // 2  # the binade of the root
    grid = e - p + 1
    # root / 2^grid = sqrt(value / 2^(2 grid)); floor by integer square root of the floor
    scaled = value / Fraction(2) ** (2 * grid) if grid >= 0 else value * 2 ** (-2 * grid)
    floor = math.isqrt(scaled.numerator // scaled.denominator)
    exact = Fraction(floor) ** 2 == scaled
    if exact:
        count = floor
    else:
        midpoint_square = Fraction(floor) ** 2 + floor + Fraction(1, 4)  # (floor + 1/2)^2
        if mode == "RNE":
            up = scaled > midpoint_square or (scaled == midpoint_square and floor % 2 == 1)
        elif mode == "RNA":
            up = scaled >= midpoint_square
        elif mode == "RTP":
            up = True
        else:  # RTZ, RTN: the root is positive
            up = False
        count = floor + 1 if up else floor
    return rounding.render(False, count, grid), ("---" if exact else "I--")


def bits(rng: random.Random, width: int, kind: int) -> int:
    """A positive integer of exactly `width` bits: random, sparse, all ones or a power of two."""
    if width == 1:
        return 1
    top = 1 << (width - 1)
    if kind == 0:
        return top | rng.getrandbits(width - 1)
    if kind == 1:
        value = top
        for _ in range(rng.randint(0, 3)):
            value |= 1 << rng.randrange(width - 1)
        return value
    if kind == 2:
        return (1 << width) - 1
    return top


def operand(rng: random.Random, width: int, around: int) -> Operand:
    return rng.random() < 0.5, bits(rng, width, rng.randrange(4)), around + rng.randint(-3, 3)


def add_cases(rng: random.Random, p: int) -> list[tuple[Operand, Operand]]:
    cases = []
    around = rng.randint(-150, 150)
    a = operand(rng, p, around)
    mant, exp = a[1], a[2]
    # a tie: half an ulp of a, and half an ulp plus and minus a bit
    tie = (a[0], 1, exp - 1)
    cases.append((a, tie))
    cases.append((a, (a[0], 3, exp - 2)))  # 3/4 ulp
    cases.append((a, (a[0], 1, exp - 2)))  # quarter ulp
    cases.append((a, (a[0], (1 << (p - 1)) + 1, exp - p)))  # half an ulp plus a bit: just above the tie
    # the carry out of all ones
    ones = (False, (1 << p) - 1, around)
    cases.append((ones, (False, 1, around)))
    cases.append((ones, (False, 1, around - 1)))
    # cancellation: a minus a plus a few low bits
    delta = bits(rng, rng.randint(1, min(p, 40)), rng.randrange(4))
    negated = (not a[0], mant, exp)
    cases.append((a, negated))
    cases.append((a, (not a[0], mant, exp)))
    cases.append(((a[0], mant + delta, exp), (not a[0], mant, exp)) if mant.bit_length() == (mant + delta).bit_length() else (a, negated))
    # a gap larger than the precision: the small operand only matters as a sticky bit
    cases.append((a, operand(rng, rng.randint(1, p), exp - p - rng.randint(3, 40))))
    cases.append((operand(rng, rng.randint(1, p), exp - p - 5), a))
    # two all-ones operands a few places apart: the carry and the borrow between the two words
    # of a one-word operand pair (a shifted operand spills into the second word)
    for gap in (1, 3, max(1, p // 3)):
        for same_sign in (True, False):
            cases.append(((False, (1 << p) - 1, around), (not same_sign, (1 << p) - 1, around - gap)))
            cases.append(((False, (1 << p) - 1, around - gap), (not same_sign, (1 << p) - 1, around)))
    # a power of two against all ones, shifted so that the low words of the aligned operands
    # compare the other way from the whole values (a borrow out of the low word)
    for gap in (1, 2, 3, 4, 5):
        cases.append(((False, 1 << (p - 1), around + gap), (True, (1 << p) - 1, around)))
        cases.append(((True, (1 << p) - 1, around), (False, 1 << (p - 1), around + gap)))
    # random pairs of different widths
    for _ in range(3):
        cases.append((operand(rng, rng.randint(1, p), around), operand(rng, rng.randint(1, p), around + rng.randint(-p, p))))
    return cases


def mul_cases(rng: random.Random, p: int) -> list[tuple[Operand, Operand]]:
    cases = []
    ones = (False, (1 << p) - 1, rng.randint(-100, 100))
    cases.append((ones, ones))
    cases.append((ones, (False, 3, 0)))
    half = max(1, p // 2)
    # an exact product: both factors of at most p/2 bits
    cases.append((operand(rng, half, rng.randint(-60, 60)), operand(rng, half, rng.randint(-60, 60))))
    # a product that lands near a tie: (2^k + 1)(2^m + 1) style
    cases.append(((False, (1 << (p - 1)) + 1, 0), (False, (1 << (p - 1)) + 1, 0)))
    cases.append(((False, (1 << (p - 1)) | 1, 5), (False, 3, -7)))
    for _ in range(6):
        cases.append((operand(rng, rng.randint(1, p), rng.randint(-100, 100)), operand(rng, rng.randint(1, p), rng.randint(-100, 100))))
    return cases


def div_cases(rng: random.Random, p: int) -> list[tuple[Operand, Operand]]:
    cases = []
    half = max(1, p // 2)
    divisor_bits = bits(rng, rng.randint(1, half), rng.randrange(4))
    quotient_bits = bits(rng, rng.randint(1, max(1, p - divisor_bits.bit_length() + 1)), rng.randrange(4))
    dividend = divisor_bits * quotient_bits
    if dividend.bit_length() <= p:
        cases.append(((False, dividend, 0), (False, divisor_bits, 0)))  # an exact quotient
        for step in (1, -1):
            if (dividend + step).bit_length() <= p and dividend + step > 0:
                cases.append(((False, dividend + step, 0), (False, divisor_bits, 0)))  # its neighbours
    cases.append(((False, 1, 0), (False, 3, 0)))
    cases.append(((False, 1, 0), (False, (1 << p) - 1, 0)))
    cases.append(((False, (1 << p) - 1, 0), (False, (1 << (p - 1)), 0)))  # all ones over a power of two
    cases.append(((False, (1 << p) - 1, 0), (False, (1 << p) - 3 if p > 2 else 1, 0)))
    for _ in range(6):
        cases.append((operand(rng, rng.randint(1, p), rng.randint(-100, 100)), operand(rng, rng.randint(1, p), rng.randint(-100, 100))))
    return cases


def sqrt_cases(rng: random.Random, p: int) -> list[Operand]:
    cases: list[Operand] = []
    root = bits(rng, rng.randint(1, max(1, p // 2)), rng.randrange(4))
    square = root * root
    for delta in (0, 1, -1):
        if square + delta > 0 and (square + delta).bit_length() <= p:
            cases.append((False, square + delta, 0))
            cases.append((False, square + delta, 1))  # an odd exponent
            cases.append((False, square + delta, -6))
    cases.append((False, 1, 0))
    cases.append((False, 1, 1))
    cases.append((False, (1 << p) - 1, 0))
    cases.append((False, (1 << p) - 1, 1))
    cases.append((False, (1 << (p - 1)) + 1, -2))
    for _ in range(5):
        cases.append((False, bits(rng, rng.randint(1, p), rng.randrange(4)), rng.randint(-100, 100)))
    return cases


def range_cases(rng: random.Random, p: int, emin: int, emax: int) -> list[tuple[str, Operand, Operand | None]]:
    """The edges of a format: overflow, the largest finite number, the subnormal range."""
    top = emax - p + 1  # exponent of the unit of the largest finite number
    low = emin - p + 1  # exponent of the smallest subnormal
    maximum = (False, (1 << p) - 1, top)
    out: list[tuple[str, Operand, Operand | None]] = []
    out.append(("add", maximum, (False, 1, top - 1)))  # M plus half an ulp: the midpoint above M
    out.append(("add", maximum, (False, 1, top)))  # M plus one ulp: overflow
    out.append(("add", maximum, (False, 3, top - 2)))
    out.append(("add", (False, 1, low), (False, 1, low)))  # 2 smallest subnormals
    out.append(("add", (False, 1, emin), (True, 1, low)))  # 2^emin minus the smallest subnormal
    out.append(("add", (False, 1, emin), (True, 1, emin)))  # exact zero
    out.append(("mul", (False, 1, emin), (False, 1, -1)))  # half of the smallest normal: subnormal, exact
    out.append(("mul", (False, 3, emin - 1), (False, 3, -3)))
    out.append(("mul", (False, 1, low), (False, 1, -1)))  # half the smallest subnormal: a tie to zero
    out.append(("mul", (False, 3, low), (False, 1, -1)))  # 1.5 smallest subnormals
    out.append(("mul", (False, 1 << (p - 1), emax - p + 1), (False, 1, 1)))  # 2^emax times 2: overflow
    out.append(("mul", (False, (1 << p) - 1, top), (False, (1 << p) - 1, 0)))
    out.append(("div", (False, 1, emin), (False, 2, 0)))
    out.append(("div", (False, 1, low), (False, 3, 0)))
    out.append(("div", (False, 3, low), (False, 2, 0)))
    out.append(("div", maximum, (False, 1, -1)))  # M / (1/2): overflow
    out.append(("div", (False, 1, emax), (False, 3, -2)))
    out.append(("div", (False, 1, 0), (False, 1, emin - 1)))  # 2^-emin...: overflow for most formats
    return out


def apply(op: str, left: Operand, right: Operand | None, p: int, emin: int, emax: int, mode: str, tininess: str):
    a = value_of(left)
    if op == "sqrt":
        return sqrt_finish(a, p, mode)
    assert right is not None
    b = value_of(right)
    if op == "add":
        return finish(a + b, p, emin, emax, mode, tininess, zero_negative=(mode == "RTN"))
    if op == "mul":
        return finish(a * b, p, emin, emax, mode, tininess)
    assert op == "div"
    return finish(a / b, p, emin, emax, mode, tininess)


def widest(*operands: Operand | None) -> int:
    return max(o[1].bit_length() for o in operands if o is not None)


def build() -> list[tuple]:
    rows: list[tuple] = []
    rng = random.Random(20261121)
    counter = 0
    for p in PRECISIONS:
        count_limit = 3 if p >= 4097 else 5 if p >= 1000 else (8 if p >= 256 else 100)
        for op, generator in (("add", add_cases), ("mul", mul_cases), ("div", div_cases)):
            cases = generator(rng, p)
            if len(cases) > count_limit:
                cases = cases[:count_limit] + rng.sample(cases[count_limit:], min(2, len(cases) - count_limit))
            for left, right in cases:
                assert widest(left, right) <= p, (op, p)
                counter += 1
                mode = MODES[counter % 5]
                expected, flags = apply(op, left, right, p, IMPL_EMIN, IMPL_EMAX, mode, "before")
                rows.append((op, p, IMPL_EMIN, IMPL_EMAX, mode, "before", hex_text(left), hex_text(right), expected, flags))
                if p <= 65 and mode != "RNE":  # the paths of one-word operands are all ties to even without a context
                    expected, flags = apply(op, left, right, p, IMPL_EMIN, IMPL_EMAX, "RNE", "before")
                    rows.append((op, p, IMPL_EMIN, IMPL_EMAX, "RNE", "before", hex_text(left), hex_text(right), expected, flags))
        cases_sqrt = sqrt_cases(rng, p)
        if len(cases_sqrt) > count_limit:
            cases_sqrt = cases_sqrt[:count_limit] + rng.sample(cases_sqrt[count_limit:], 2)
        for left in cases_sqrt:
            assert widest(left) <= p
            counter += 1
            mode = MODES[counter % 5]
            expected, flags = apply("sqrt", (False, left[1], left[2]), None, p, IMPL_EMIN, IMPL_EMAX, mode, "before")
            rows.append(("sqrt", p, IMPL_EMIN, IMPL_EMAX, mode, "before", hex_text((False, left[1], left[2])), "", expected, flags))
            if p <= 65 and mode != "RNE":
                expected, flags = apply("sqrt", (False, left[1], left[2]), None, p, IMPL_EMIN, IMPL_EMAX, "RNE", "before")
                rows.append(("sqrt", p, IMPL_EMIN, IMPL_EMAX, "RNE", "before", hex_text((False, left[1], left[2])), "", expected, flags))
    for _name, p, emin, emax in FORMATS:
        for op, left, right in range_cases(rng, p, emin, emax):
            for mode in MODES:
                for tininess in ("before", "after"):
                    expected, flags = apply(op, left, right, p, emin, emax, mode, tininess)
                    rows.append((op, p, emin, emax, mode, tininess, hex_text(left), hex_text(right) if right else "", expected, flags))
    return rows


def render_file(rows: list[tuple]) -> str:
    lines = [
        "// Generated by tools/generate_arith_rows.py; do not edit.",
        "// add, mul, div and sqrt rounded once, exact rational arithmetic and the range rule of IEEE 754-2019 4.3, 7.4, 7.5:",
        "// (operation, p, e_min, e_max, rounding, tininess, left, right, expected, flags).",
        "// oracle-file: A",
        "// producer: tools/generate_arith_rows.py",
        "// input: operands of up to p bits (ties, carries, cancellation, gaps, exact and neighbouring quotients, perfect squares, format edges)",
        "// library-ran: no",
        "",
        "///|",
        "fn arith_rows() -> Array[(String, Int32, Int32, Int32, String, String, String, String, String, String)] {",
        "  [",
    ]
    for op, p, emin, emax, mode, tininess, left, right, expected, flags in rows:
        lines.append(f'    ("{op}", {p}, {emin}, {emax}, "{mode}", "{tininess}", "{left}", "{right}", "{expected}", "{flags}"),')
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    rows = build()
    text = render_file(rows)
    if args.check:
        squeeze = lambda value: "".join(value.split()).replace(",)", ")").replace(",]", "]")
        ok = OUTPUT.is_file() and squeeze(OUTPUT.read_text(encoding="utf-8")) == squeeze(text)
        if not ok:
            print(f"stale: {OUTPUT}", file=sys.stderr)
        return 0 if ok else 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT}: {len(rows)} rows, {len(text)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
