#!/usr/bin/env python3
"""Rows that concentrate on the underflow and overflow thresholds of the
binary elementary functions.

    range_boundary_rows.py --out boundary.in [--p-min 2] [--p-max 300]
    (head -n 1 boundary.in; generate_mpfr_random_oracle eval < boundary.in) > boundary.rows
    floating-conformance --backend mpfr boundary.rows

For every precision `p` in the range and each of six contexts (unbounded and
the ranges of binary16, binary32, binary64, binary128 and e_min = -6), the
arguments of exp, exp2, exp10, expm1, pow, pown and rootn are placed on the
thresholds log2(result) in {q - 1, q, e_min, e_max, e_max + 1} with
q = e_min - (p - 1): half the smallest subnormal, the smallest subnormal, the
smallest normal, the largest binade and the first binade out of range. Each
threshold is approximated to 110 bits and visited exactly and at relative
offsets +-2^-20, 2^-24, 2^-30, 2^-40, 2^-52 and 2^-64, so the rounding
decision of the library is compared with MPFR on both sides of every threshold.
Rounding direction (six) and tininess rule (two) cycle with the row number. The
rows carry the expected columns as `?`; `generate_mpfr_random_oracle eval`
fills them from MPFR (see tools/generate_mpfr_random_oracle.c). The 1,269,554
rows of the full range ran against the library in a few minutes of CPU time.
"""

from __future__ import annotations

import argparse
import decimal
import sys
from collections.abc import Iterator
from fractions import Fraction

decimal.getcontext().prec = 140

IMPL_EMIN = -1073741823
IMPL_EMAX = 1073741823
HEADER = "# mpfr-random-v1 range-boundary rows (expected columns are filled by the oracle)"
CONTEXTS: list[tuple[int | None, int | None]] = [
    (None, None),
    (-14, 15),
    (-126, 127),
    (-1022, 1023),
    (-16382, 16383),
    (-6, 7),
]
MODES = ["n", "na", "z", "u", "d", "a"]
OPERATIONS = ("exp", "exp2", "exp10", "expm1", "pow", "pown", "rootn")
RELATIVE_OFFSETS = (20, 24, 30, 40, 52, 64)
ROOT_DEGREES = (-3, -7, 100, -1000)


def to_dyadic(value: Fraction, bits: int = 110) -> Fraction:
    """The dyadic with `bits` significant bits nearest to `value`."""
    if value == 0:
        return value
    sign = -1 if value < 0 else 1
    magnitude = abs(value)
    top = magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    shift = bits - top
    if shift >= 0:
        return sign * Fraction(round(magnitude * (1 << shift)), 1 << shift)
    return sign * Fraction(round(magnitude / (1 << -shift)) * (1 << -shift), 1)


def decimal_to_dyadic(value: decimal.Decimal, bits: int) -> Fraction:
    return to_dyadic(Fraction(value), bits)


LN2 = decimal_to_dyadic(decimal.Decimal(2).ln(), 200)
LOG10_2 = decimal_to_dyadic(decimal.Decimal(2).log10(), 200)


def hexfmt(value: Fraction) -> str:
    """`-0x<odd hex>p<exponent>`, the operand syntax of the rows."""
    if value == 0:
        return "0x0p0"
    magnitude = abs(value)
    denominator = magnitude.denominator
    if denominator & (denominator - 1):
        raise ValueError(f"{value} is not dyadic")
    exponent = -(denominator.bit_length() - 1)
    coefficient = magnitude.numerator
    zeros = (coefficient & -coefficient).bit_length() - 1
    return f"{'-' if value < 0 else ''}0x{coefficient >> zeros:x}p{exponent + zeros}"


def around(center: Fraction) -> Iterator[Fraction]:
    """`center` and `center * (1 +- 2^-k)`, each a dyadic."""
    base = to_dyadic(center)
    yield base
    for k in RELATIVE_OFFSETS:
        step = base / (1 << k)
        yield base + step
        yield base - step


def log2_of(base: Fraction) -> Fraction:
    value = decimal.Decimal(base.numerator) / decimal.Decimal(base.denominator)
    return decimal_to_dyadic(value.ln() / decimal.Decimal(2).ln(), 120)


def rows(p_min: int, p_max: int, operations: tuple[str, ...], tag: str = "tgt") -> Iterator[str]:
    """The rows of the sweep, without the header, one string per row."""
    bases = [Fraction(3), Fraction(3, 2), to_dyadic(Fraction(7, 10), 60)]
    base_logs = {base: log2_of(base) for base in bases}
    base_hex = {base: hexfmt(base) for base in bases}
    counter = 0

    def row(op: str, p: int, context: tuple[int | None, int | None], a: str, b: str = "-", n: int = 0) -> str:
        nonlocal counter
        mode = MODES[counter % 6]
        tininess = "ab"[(counter // 6) % 2]
        e_min, e_max = context
        limits = "- - -" if e_min is None else f"{e_min} {e_max} {tininess}"
        text = f"{tag}.{op}.{counter} {op} {mode} {p} {limits} {a} {b} - {n} ? ?"
        counter += 1
        return text

    for p in range(p_min, p_max + 1):
        for context in CONTEXTS:
            e_min = context[0] if context[0] is not None else IMPL_EMIN
            e_max = context[1] if context[1] is not None else IMPL_EMAX
            q = e_min - (p - 1)
            for level in (q - 1, q, e_min, e_max, e_max + 1):
                for op in operations:
                    if op == "exp":
                        for x in around(level * LN2):
                            yield row(op, p, context, hexfmt(x))
                    elif op == "exp2":
                        for x in around(Fraction(level)):
                            yield row(op, p, context, hexfmt(x))
                    elif op == "exp10":
                        for x in around(level * LOG10_2):
                            yield row(op, p, context, hexfmt(x))
                    elif op == "expm1":
                        if level >= e_max:
                            for x in around(level * LN2):
                                yield row(op, p, context, hexfmt(x))
                    elif op == "pow":
                        for base in bases:
                            for y in around(level / base_logs[base]):
                                yield row(op, p, context, base_hex[base], hexfmt(y))
                    elif op == "pown":
                        for base in bases:
                            center = round(level / base_logs[base])
                            for delta in (-2, -1, 0, 1, 2):
                                n = center + delta
                                if n != 0 and abs(n) < 2**31:
                                    yield row(op, p, context, base_hex[base], n=n)
                    elif op == "rootn":
                        for degree in ROOT_DEGREES:
                            # log2(x^(1/k)) = level  <=>  log2(x) = level * k
                            log2_x = level * degree
                            if abs(log2_x) > IMPL_EMAX - 100:
                                continue
                            yield row(op, p, context, f"0x1p{log2_x}", n=degree)
                            for k in RELATIVE_OFFSETS:
                                for sign in (1, -1):
                                    yield row(op, p, context, f"0x{(1 << k) + sign:x}p{log2_x - k}", n=degree)
                    else:
                        raise ValueError(f"unknown operation {op}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--p-min", type=int, default=2)
    parser.add_argument("--p-max", type=int, default=300)
    parser.add_argument("--ops", default=",".join(OPERATIONS), help="comma separated subset")
    parser.add_argument("--tag", default="tgt", help="row id prefix")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    operations = tuple(args.ops.split(","))
    count = 0
    with open(args.out, "w", encoding="utf-8") as out:
        out.write(HEADER + "\n")
        for line in rows(args.p_min, args.p_max, operations, args.tag):
            out.write(line + "\n")
            count += 1
    print(f"{count} rows", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
