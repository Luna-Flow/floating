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
Rounding direction (five) and tininess rule (two) cycle with the row number. The
rows carry the expected columns as `?`; `generate_mpfr_random_oracle eval`
fills them from MPFR (see tools/generate_mpfr_random_oracle.c). The 1,269,554
rows of the full range ran against the library in a few minutes of CPU time.

`rsqrt`, `compound` and `powr` take the same thresholds: `rsqrt` at
x = 2^(-2 level), `compound` at 1 + x = 2^(level / n) for n in
{-100, -7, -3, 3, 7, 100} and `powr` as `pow` with positive bases. The 718,824
rows of precisions 2 to 300 that these three give were compared with MPFR
(`mpfr_compound_si` needs the exact-rational correction of the generator).

`asinpi`, `atanpi` and `atan2pi` also take the underflow thresholds (the
argument at pi 2^level, or the ratio y / x at pi 2^level); once per context
they place `atanpi` at 1.5 2^t, `acospi` at 1.5 2^-t and `atan2pi` at a
leading-exponent difference D, for t and |D| from p + 4 to p + 12 around the
anchor rules at p + 8, and `asinpi` and `acospi` next to +-1. The 1,654,315
rows of precisions 2 to 300 compared with MPFR; `atan2pi` rows whose operands
differ by more than 100,000 binades are skipped by the generator (MPFR is too
slow there).
"""

from __future__ import annotations

import argparse
import decimal
import sys
from collections.abc import Iterator
from fractions import Fraction

import context_rules

decimal.getcontext().prec = 140

IMPL_EMIN = -1073741822  # 1 - IMPL_EMAX (IEEE 754-2019 3.3)
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
for _e_min, _e_max in CONTEXTS:  # a context is a format of IEEE 754-2019 3.3, or the precision alone
    context_rules.check_binary_context(53, _e_max, _e_min)
MODES = ["n", "na", "z", "u", "d"]
OPERATIONS = ("exp", "exp2", "exp10", "expm1", "pow", "pown", "rootn", "exp2m1", "exp10m1", "log2p1", "log10p1", "rsqrt", "compound", "powr", "asinpi", "acospi", "atanpi", "atan2pi")
RELATIVE_OFFSETS = (20, 24, 30, 40, 52, 64)
ROOT_DEGREES = (-3, -7, 100, -1000)
COMPOUND_DEGREES = (-3, -7, 3, 7, -100, 100)


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


LN10 = decimal_to_dyadic(decimal.Decimal(10).ln(), 200)
PI = decimal_to_dyadic(
    decimal.Decimal("3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651"),
    200,
)


def floor_log2(value: Fraction) -> int:
    """floor(log2(|value|)) of a nonzero Fraction."""
    magnitude = abs(value)
    k = magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    power = Fraction(1 << k) if k >= 0 else Fraction(1, 1 << -k)
    if magnitude < power:
        k -= 1
    return k


def scaled_hex(value: Fraction, level: int) -> str:
    """hexfmt(value * 2**level) without forming 2**level (|level| may be 2^30)."""
    text = hexfmt(value)
    mantissa, exponent = text.rsplit("p", 1)
    return f"{mantissa}p{int(exponent) + level}"


def pow2_minus_one_hex(exponent: Fraction) -> str | None:
    """hex of 2^exponent - 1 (110 bits), or None when it needs too long an operand."""
    whole = exponent.numerator // exponent.denominator
    frac = exponent - whole
    significand = decimal_to_dyadic((decimal.Decimal(frac.numerator) / decimal.Decimal(frac.denominator) * decimal.Decimal(2).ln()).exp(), 110)
    if whole >= 0:
        if whole < 120:
            return hexfmt(significand * (1 << whole) - 1)
        return scaled_hex(significand, whole)
    if whole < -400:
        return None
    return hexfmt(significand / (1 << -whole) - 1)


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
        mode = MODES[counter % len(MODES)]
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
                    elif op in ("exp2m1", "exp10m1"):
                        tiny_scale = 1 / (LN2 if op == "exp2m1" else LN10)
                        threshold = Fraction(1) if op == "exp2m1" else LOG10_2
                        if level >= e_max:
                            # 2^x - 1 and 10^x - 1 overflow near log2(result) = level
                            for x in around(level * threshold):
                                yield row(op, p, context, hexfmt(x))
                        elif level < e_min or level == e_min:
                            # tiny results: f(x) ~ x ln b, so x ~ 2^level / ln b
                            for x in around(tiny_scale):
                                # the operand must be representable in the format
                                if floor_log2(x) + level >= q:
                                    yield row(op, p, context, scaled_hex(x, level))
                        if level == q - 1:
                            # saturation towards -1 at 2^x < 2^-(p + 3)
                            for x in around(-(p + 3) * threshold):
                                yield row(op, p, context, hexfmt(x))
                    elif op in ("log2p1", "log10p1"):
                        if level <= e_min:
                            # tiny results: f(x) ~ x / ln b, so x ~ 2^level ln b
                            constant = LN2 if op == "log2p1" else LN10
                            for x in around(constant):
                                if floor_log2(x) + level >= q:
                                    yield row(op, p, context, scaled_hex(x, level))
                    elif op == "rsqrt":
                        # log2(1/sqrt x) = level  <=>  x = 2^(-2 level); operands in range only
                        if abs(2 * level) <= IMPL_EMAX - 100 and -2 * level >= q:
                            for x in around(Fraction(1)):
                                yield row(op, p, context, scaled_hex(x, -2 * level))
                    elif op == "compound":
                        for degree in COMPOUND_DEGREES:
                            # log2((1 + x)^n) = level  <=>  1 + x = 2^(level / n)
                            if abs(level) > 4 * 10**8:
                                continue
                            hexa = pow2_minus_one_hex(Fraction(level, degree))
                            if hexa is None:
                                continue
                            yield row(op, p, context, hexa, n=degree)
                            # a few relative offsets of 1 + x, as 1 + x +- 2^-k
                            for k in RELATIVE_OFFSETS:
                                shifted = pow2_minus_one_hex(Fraction(level, degree) + Fraction(1, 1 << k) / 7)
                                if shifted is not None:
                                    yield row(op, p, context, shifted, n=degree)
                    elif op == "powr":
                        for base in bases:
                            for y in around(level / base_logs[base]):
                                yield row(op, p, context, base_hex[base], hexfmt(y))
                    elif op in ("asinpi", "atanpi"):
                        # tiny results: f(x) ~ x / pi, so x ~ pi 2^level
                        if level <= e_min:
                            for x in around(PI):
                                if floor_log2(x) + level >= q:
                                    yield row(op, p, context, scaled_hex(x, level))
                        if level == e_max:
                            # (once per context) the exact constants and the anchors
                            if op == "atanpi":
                                # atanPi(x) = +-1/2 -+ delta for a huge |x|: the rule starts at 2^(p + 8)
                                for top in (p + 4, p + 6, p + 7, p + 8, p + 9, p + 12, e_max - 2):
                                    for x in around(Fraction(3, 2)):
                                        for sign in (1, -1):
                                            if q <= floor_log2(x) + top <= e_max:
                                                yield row(op, p, context, scaled_hex(sign * x, top))
                            else:
                                # near +-1 (and +-1/2, where asinPi is 1/6)
                                for k in (1, 2, 3, 4, p - 1, p, p + 1, p + 2, p + 8):
                                    if k >= 1:
                                        for sign in (1, -1):
                                            yield row(op, p, context, hexfmt(sign * (1 - Fraction(1, 1 << k))))
                    elif op == "acospi":
                        if level == e_max:
                            # acosPi(x) = 1/2 - asin(x)/pi clusters at 1/2 for a tiny |x| (2^-(p + 3) is
                            # where the rule starts), and at 0 and 1 next to +-1
                            for top in (-(p + 1), -(p + 2), -(p + 3), -(p + 4), -(p + 5), -(p + 8), -(p + 12), -2 * p, q + 2):
                                for x in around(Fraction(3, 2)):
                                    for sign in (1, -1):
                                        if q <= floor_log2(x) + top <= e_max:
                                            yield row(op, p, context, scaled_hex(sign * x, top))
                            for k in (1, 2, 3, 4, p - 1, p, p + 1, p + 2, p + 8):
                                if k >= 1:
                                    for sign in (1, -1):
                                        yield row(op, p, context, hexfmt(sign * (1 - Fraction(1, 1 << k))))
                    elif op == "atan2pi":
                        # x > 0 and a tiny ratio: atan2Pi ~ y / (pi x), a result on the underflow thresholds
                        if level <= e_min:
                            shift = max(0, IMPL_EMIN + 8 - level)
                            if shift <= IMPL_EMAX - 10:
                                for x in around(PI):
                                    if q <= floor_log2(x) + level + shift <= e_max and shift <= e_max:
                                        yield row(op, p, context, scaled_hex(x, level + shift), f"0x1p{shift}")
                        if level == e_max:
                            # (once per context) the anchors +-1/2 and +-1 for the extreme ratios: with
                            # D = top(y) - top(x), the rule starts at |D| = p + 8
                            for distance in (p + 4, p + 6, p + 7, p + 8, p + 9, p + 12, -(p + 4), -(p + 6), -(p + 7), -(p + 8), -(p + 9), -(p + 12)):
                                for x in around(Fraction(3, 2)):
                                    for x_sign in (1, -1):
                                        for y_sign in (1, -1):
                                            # the ordinate at 2^D and the abscissa at 1.x
                                            if q <= distance <= e_max:
                                                yield row(op, p, context, scaled_hex(y_sign * Fraction(1), distance), hexfmt(x_sign * x))
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
