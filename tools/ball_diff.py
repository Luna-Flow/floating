#!/usr/bin/env python3
"""Differential stage of `BallFloat` against MPFR, untimed (issue #438; oracle audit).

One seeded generator writes rows of operand intervals, `tools/ball_mpfr_oracle.c`
computes the tightest result of every row with MPFR directly (directed
roundings in the exponent range and with the gradual underflow of `bin_float`,
`tools/mpfr_ours.h`), and the test of `tooling/src/differential/ball_mpfr` runs the
rows on `BallFloat` and compares both bounds as canonical text. The oracle shares
no code with the library; the generator is only a source of operands (what it
meant to hit is checked from the oracle's own flags: a class that does not reach
its band is an error, see `check_coverage`).

    python3 tools/ball_diff.py gen --out DIR       write the rows
    python3 tools/ball_diff.py run [--out DIR]     rows, oracle, test, verdict

Operations: add, sub, mul, div, sqr, sqrt, fma (IEEE 1788-2015 12.10.2: the basic
operations shall be tightest, so the bounds must be equal), and exp and ln (valid
only: the result must enclose the tightest one, and may not be wider than
`ACCURATE_ULPS` units of the last place; no second oracle, MPFR only). Row format
(`ball-diff-v1`): `id op size class operand...`, an operand is `lo:hi`, two values
`[-]0x<hex>p<exp>`, exact.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
ORACLE_SOURCE = REPO_ROOT / "tools" / "ball_mpfr_oracle.c"
DEFAULT_OUT = REPO_ROOT / ".tmp" / "ball_diff"
KNOWN_FILE = REPO_ROOT / "tools" / "ball_diff_known.txt"
SEED = 20261121
PRECISIONS: tuple[int, ...] = (53, 128, 512)
ROWS_PER_CELL = 12
# precisions added to a class: the rows of issue 569 (exp at the overflow threshold) failed from 146 bits up
CLASS_PRECISIONS: dict[str, tuple[int, ...]] = {"XOV": (117, 146, 175, 292)}

EMAX = (1 << 30) - 1  # the largest leading-bit exponent of a finite value of bin_float
EMIN = 1 - EMAX  # the smallest normal number is 2**EMIN

OPS: tuple[str, ...] = ("add", "sub", "mul", "div", "sqr", "sqrt", "fma", "exp", "ln")
ARITY = {"add": 2, "sub": 2, "mul": 2, "div": 2, "sqr": 1, "sqrt": 1, "fma": 3, "exp": 1, "ln": 1}
ARITHMETIC_OPS = ("add", "sub", "mul", "div", "sqr", "sqrt", "fma")
ELEMENTARY_OPS = ("exp", "ln")
ACCURATE_ULPS = 1024  # an enclosing result wider than this many units of the last place is reported (the standard says "should be accurate")

# class -> operations it applies to, and the oracle flag it must reach in at least one row of every cell
CLASSES: dict[str, tuple[tuple[str, ...], str | None]] = {
    "R": (OPS, None),  # ordinary operands, mid-range exponents
    "OV": (("add", "sub", "mul", "div", "sqr", "fma"), "o"),  # results one unit from the overflow threshold, both sides
    "SUB": (("add", "sub", "mul", "div", "sqr", "sqrt", "fma"), "si"),  # results (or operands) in the subnormal band
    "FAR": (("add", "sub", "fma"), None),  # operands of very different exponents
    "FEW": (OPS, None),  # operands with fewer significant bits than the precision
    "WIDE": (OPS, None),  # bounds with more bits than the precision: the ball rounds them outward
    "Z": (("add", "sub", "mul", "div", "sqr", "sqrt", "fma", "exp"), None),  # intervals with a zero bound
    "XOV": (("exp",), "o"),  # exp at the overflow threshold (issue 569): arguments next to (e_max + 1) ln 2
    "XUF": (("exp",), "sz"),  # exp at the underflow thresholds: arguments next to e_min ln 2 and to the smallest subnormal and its half
    "LNE": (("ln",), None),  # ln at the ends of the range and next to 1
}


# ---------------------------------------------------------------------------
# Values: sign, integer mantissa, exponent (never materialised as integers of 2^2^30)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Value:
    negative: bool
    mantissa: int  # 0 for zero
    exponent: int  # the value is (-1)^negative * mantissa * 2^exponent

    def text(self) -> str:
        if self.mantissa == 0:
            return "0x0p0"
        return f"{'-' if self.negative else ''}0x{self.mantissa:x}p{self.exponent}"

    def neg(self) -> "Value":
        return Value(not self.negative and self.mantissa != 0, self.mantissa, self.exponent)

    def lead(self) -> int:
        """The exponent of the leading bit: 2^lead <= |value| < 2^(lead+1)."""
        return self.exponent + self.mantissa.bit_length() - 1


ZERO = Value(False, 0, 0)


def compare(a: Value, b: Value) -> int:
    """-1, 0 or 1: the order of two values, exact (no integer of 2^(2^30) is formed)."""
    if a.mantissa == 0 and b.mantissa == 0:
        return 0
    sa = 0 if a.mantissa == 0 else (-1 if a.negative else 1)
    sb = 0 if b.mantissa == 0 else (-1 if b.negative else 1)
    if sa != sb:
        return -1 if sa < sb else 1
    # the same sign, nonzero: compare magnitudes
    if a.lead() != b.lead():
        magnitude = -1 if a.lead() < b.lead() else 1
    else:
        e = min(a.exponent, b.exponent)
        ma, mb = a.mantissa << (a.exponent - e), b.mantissa << (b.exponent - e)
        magnitude = (ma > mb) - (ma < mb)
    return magnitude * sa


def value(mantissa: int, exponent: int, negative: bool = False) -> Value:
    return Value(negative and mantissa != 0, mantissa, exponent)


def quantum(p: int) -> int:
    """The exponent of the smallest positive number at precision p (2^quantum)."""
    return EMIN - p + 1


def max_finite(p: int) -> Value:
    return value((1 << p) - 1, EMAX + 1 - p)


def random_mantissa(rng: random.Random, bits: int) -> int:
    return rng.getrandbits(bits - 1) | (1 << (bits - 1))


def round_shift(x: int, shift: int) -> int:
    """x / 2^shift rounded to nearest, ties to even (shift >= 0)."""
    if shift <= 0:
        return x << -shift
    q, r = divmod(x, 1 << shift)
    half = 1 << (shift - 1)
    if r > half or (r == half and q & 1):
        q += 1
    return q


def fit(mantissa: int, exponent: int, p: int) -> Value:
    """The value mantissa * 2^exponent rounded to p bits."""
    extra = mantissa.bit_length() - p
    if extra > 0:
        mantissa = round_shift(mantissa, extra)
        exponent += extra
        if mantissa.bit_length() > p:  # carried into a new bit
            mantissa >>= 1
            exponent += 1
    return value(mantissa, exponent)


def with_lead(rng: random.Random, p: int, lead: int) -> Value:
    return value(random_mantissa(rng, p), lead - (p - 1))


def one_ulp_up(x: Value, p: int) -> Value:
    """The next value of at least the same precision above x, for a positive x of up to p bits;
    x itself when that would be above the largest finite value."""
    m, e = x.mantissa, x.exponent
    if m.bit_length() < p:  # fewer bits: add one unit of the last bit it has
        up = value(m + 1, e)
    else:
        m += 1
        if m.bit_length() > p:
            m >>= 1
            e += 1
        up = value(m, e)
    return x if up.lead() > EMAX else up


Interval = tuple[Value, Value]


def point(x: Value) -> Interval:
    return (x, x)


def shaped(x: Value, p: int, shape: str, rng: random.Random) -> Interval:
    """An interval around the positive value x. Shapes: `pt`, `ulp`, `neg_pt`, `neg_ulp`, `mixed`."""
    if shape == "pt":
        return (x, x)
    if shape == "ulp":
        return (x, one_ulp_up(x, p))
    if shape == "neg_pt":
        return (x.neg(), x.neg())
    if shape == "neg_ulp":
        return (one_ulp_up(x, p).neg(), x.neg())
    if shape == "mixed":
        return (x.neg(), one_ulp_up(x, p))
    raise ValueError(shape)


SHAPES = ("pt", "ulp", "neg_pt", "neg_ulp", "mixed")
POSITIVE_SHAPES = ("pt", "ulp")


# ---------------------------------------------------------------------------
# Partners: the second operand that puts a product, quotient or square at a target
# ---------------------------------------------------------------------------


def product_partner(a: Value, target_n: int, target_e: int, p: int) -> Value:
    """b with a*b ~ target_n * 2^target_e (within one unit of the last bit of b): b = target / a."""
    t = p + a.mantissa.bit_length() - target_n.bit_length() + 1
    q = (target_n << max(t, 0)) // a.mantissa
    e = target_e - a.exponent - max(t, 0)
    return fit(q, e, p)


def quotient_dividend(b: Value, target_n: int, target_e: int, p: int) -> Value:
    """a with a/b ~ target_n * 2^target_e: a = target * b."""
    return fit(target_n * b.mantissa, target_e + b.exponent, p)


def square_root_of(target_n: int, target_e: int, p: int) -> Value:
    """a with a*a ~ target_n * 2^target_e, a of p bits."""
    # scale so that the root has at least p bits: target * 2^(2k) with the exponent even
    extra = max(2 * p - target_n.bit_length() + 2, 0)
    if (target_e - extra) % 2:
        extra += 1
    root = math.isqrt(target_n << extra)
    return fit(root, (target_e - extra) // 2, p)


# ---------------------------------------------------------------------------
# ln 2 and the arguments of exp and ln at the thresholds
# ---------------------------------------------------------------------------

LN2_BITS = 1400


def ln2_fixed(bits: int = LN2_BITS) -> int:
    """ln 2 * 2^bits, floor, from the series sum 1/(k 2^k) in integers (error below 2^-bits * 2)."""
    total = 0
    k = 1
    term = 1 << bits
    while term:
        term >>= 1
        total += term // k
        k += 1
    return total


LN2 = ln2_fixed()


def times_ln2(n: int, p: int) -> Value:
    """n * ln 2 rounded to p bits (the series is exact to 2^-1400 relative to 1; p <= 512 and |n| < 2^31 leave 800 spare bits)."""
    scaled = abs(n) * LN2
    bits = scaled.bit_length()
    shift = bits - p
    mantissa = round_shift(scaled, shift)
    exponent = shift - LN2_BITS
    return fit(mantissa, exponent, p) if n >= 0 else fit(mantissa, exponent, p).neg()


def step(x: Value, k: int, p: int) -> Value:
    """x moved by k units of its last place (k may be negative), keeping p bits, zero never reached by the callers."""
    sign = -1 if x.negative else 1
    mantissa = sign * x.mantissa + k
    moved = value(abs(mantissa), x.exponent, mantissa < 0)
    return x if moved.lead() > EMAX else moved


# ---------------------------------------------------------------------------
# Row generators
# ---------------------------------------------------------------------------

Operands = list[Interval]


def lead_range(rng: random.Random, low: int, high: int) -> int:
    return rng.randint(low, high)


def class_r(op: str, p: int, i: int, rng: random.Random) -> Operands:
    a = shaped(with_lead(rng, p, lead_range(rng, -8, 8)), p, SHAPES[i % 5], rng)
    b = shaped(with_lead(rng, p, lead_range(rng, -8, 8)), p, SHAPES[(i // 5 + 1) % 5], rng)
    c = shaped(with_lead(rng, p, lead_range(rng, -8, 8)), p, SHAPES[(i + 2) % 5], rng)
    return finish_operands(op, p, a, b, c, rng)


def finish_operands(op: str, p: int, a: Interval, b: Interval, c: Interval, rng: random.Random) -> Operands:
    """The operands of `op` from three candidate intervals, made legal: sqrt of a positive interval, division by an interval without zero."""
    if op == "sqrt":
        # the interval of the absolute values of the two bounds, in order
        x, y = Value(False, a[0].mantissa, a[0].exponent), Value(False, a[1].mantissa, a[1].exponent)
        return [(y, x) if compare(x, y) > 0 else (x, y)]
    if op == "ln":
        x, y = Value(False, a[0].mantissa, a[0].exponent), Value(False, a[1].mantissa, a[1].exponent)
        x = x if x.mantissa else value(1, a[1].exponent)
        y = y if y.mantissa else x
        return [(y, x) if compare(x, y) > 0 else (x, y)]
    if op == "div":
        if b[0].negative != b[1].negative:  # contains zero: use its negative or positive half
            b = (b[1], b[1]) if not b[1].negative else (b[0], b[0])
        return [a, b]
    if ARITY[op] == 1:
        return [a]
    if ARITY[op] == 2:
        return [a, b]
    return [a, b, c]


def class_ov(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Results next to the overflow threshold 2^(EMAX+1): below it, at it and above it, on both signs."""
    k = rng.choice([-3, -2, -1, 0, 1, 2, 3])
    n = (1 << p) + k  # the target is n * 2^(EMAX+1-p), within 3 units of the last bit of 2^(EMAX+1)
    e = EMAX + 1 - p
    shape = SHAPES[i % 5]
    sign_flip = i % 2 == 1
    if op == "mul" or op == "fma":
        a = with_lead(rng, p, EMAX // 2 + rng.randint(-20, 20))
        b = product_partner(a, n, e, p)
        c = ZERO if op == "mul" else with_lead(rng, p, rng.randint(EMAX - 100, EMAX))
        ai = shaped(a, p, shape, rng)
        bi = shaped(b, p, shape if shape != "mixed" else "ulp", rng)
        ci = shaped(c, p, "pt", rng) if c.mantissa else point(ZERO)
        if op == "fma" and sign_flip:
            ci = (ci[1].neg(), ci[0].neg())
        return [ai, bi] if op == "mul" else [ai, bi, ci]
    if op == "div":
        b = with_lead(rng, p, rng.randint(-40, -2))
        a = quotient_dividend(b, n, e, p)
        return [shaped(a, p, shape if shape != "mixed" else "ulp", rng), shaped(b, p, "pt" if i % 3 else "ulp", rng)]
    if op == "sqr":
        a = square_root_of(n, e, p)
        return [shaped(a, p, shape, rng)]
    # add and sub: the largest finite value and an addend of about half its last bit
    big = max_finite(p)
    j = rng.choice([-1, 0, 1])
    small = value((1 << (p - 1)) + j, EMAX - p - (p - 1))
    pair = (shaped(big, p, "pt", rng), shaped(small, p, "pt" if i % 3 else "ulp", rng))
    if op == "sub":  # big - (-small)
        pair = (pair[0], (pair[1][1].neg(), pair[1][0].neg()))
    if sign_flip:
        pair = ((pair[0][1].neg(), pair[0][0].neg()), (pair[1][1].neg(), pair[1][0].neg()))
    return list(pair)


def class_sub(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Results in the subnormal band: products, quotients and squares aimed at the grid of 2^(EMIN-p+1), operands on that grid for sums and roots."""
    q = quantum(p)
    kind = i % 6
    if kind == 0:
        n, e = 1, q  # the smallest subnormal
    elif kind == 1:
        n, e = rng.choice([1, 3, 5, 7]), q - 1  # a tie between two subnormals
    elif kind == 2:
        n, e = (1 << (p - 1)) + rng.choice([-2, -1, 0, 1, 2]), q  # next to the smallest normal number
    elif kind == 3:
        n, e = rng.randint(2, (1 << (p - 1)) - 1), q  # inside the band
    elif kind == 4:
        n, e = 1, q - rng.randint(1, 3)  # below the smallest subnormal: rounds to zero or to it, by direction
    else:
        n, e = rng.randint(2, 40), q  # a few quanta
    shape = SHAPES[(i // 2) % 5]
    if op in ("mul", "fma"):
        a = with_lead(rng, p, EMIN // 2 + rng.randint(-20, 20))
        b = product_partner(a, n, e, p)
        c = ZERO
        ai, bi = shaped(a, p, shape, rng), shaped(b, p, "pt" if shape == "mixed" else shape, rng)
        return [ai, bi] if op == "mul" else [ai, bi, point(c)]
    if op == "div":
        b = with_lead(rng, p, rng.randint(2, 30))
        a = quotient_dividend(b, n, e, p)
        if a.exponent < q:  # operands on the grid only
            a = value(max(a.mantissa >> (q - a.exponent), 1), q)
        return [shaped(a, p, "pt" if shape == "mixed" else shape, rng), shaped(b, p, "pt", rng)]
    if op == "sqr":
        a = square_root_of(n, e, p)
        return [shaped(a, p, shape, rng)]
    if op == "sqrt":
        a = value(rng.choice([1, 3, 5, (1 << (p - 1)) - 1, rng.randint(1, 1 << (p - 1))]), q)
        return [(a, a if i % 2 else one_ulp_up(a, p))]
    # add and sub: operands that are multiples of the quantum, summing across 2^EMIN
    a = value((1 << (p - 1)) - rng.choice([0, 1, 2, 5]), q)
    b = value(rng.choice([1, 1, 2, 3, 7]), q)
    pair = [(a, a if i % 2 else one_ulp_up(a, p)), (b, b)]
    if i % 4 >= 2:
        pair = [(x[1].neg(), x[0].neg()) for x in pair]
    return pair


def class_far(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Operands whose exponents differ by far more than the precision."""
    gaps = [p, p + 1, p + 2, 2 * p, 1000, 100000, 10000000, EMAX - 10, EMAX]
    gap = gaps[i % len(gaps)]
    big_lead = rng.randint(-8, 8) if gap < EMAX - 20 else rng.randint(0, 8)
    small_lead = big_lead - gap
    if small_lead < EMIN:  # keep the small operand on the grid of the format
        small_lead = EMIN + rng.randint(0, 8)
    big = with_lead(rng, p, big_lead)
    small = with_lead(rng, p, small_lead)
    ai = shaped(big, p, "pt" if i % 2 else "ulp", rng)
    bi = shaped(small, p, "pt" if (i // 2) % 2 else "ulp", rng)
    if i % 4 >= 2:
        bi = (bi[1].neg(), bi[0].neg())
    if op == "fma":
        return [ai, point(with_lead(rng, p, rng.randint(-4, 4))), bi]
    return [ai, bi]


def class_few(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Operands with 1 to 6 significant bits, at the usual and at extreme exponents."""
    def few() -> Value:
        bits = rng.randint(1, 6)
        lead = rng.choice([rng.randint(-8, 8), EMAX - rng.randint(0, 3), EMIN + p + rng.randint(0, 3)])
        return value(random_mantissa(rng, bits), lead - (bits - 1))

    a = shaped(few(), p, SHAPES[i % 5] if i % 5 != 4 else "pt", rng)
    b = shaped(few(), p, SHAPES[(i + 1) % 5] if (i + 1) % 5 != 4 else "pt", rng)
    c = shaped(few(), p, "pt", rng)
    if op in ("mul", "fma"):  # keep products inside the format: leads halved
        a = shaped(value(random_mantissa(rng, rng.randint(1, 6)), rng.randint(-30, 30)), p, "pt", rng)
        b = shaped(value(random_mantissa(rng, rng.randint(1, 6)), rng.randint(-30, 30)), p, "ulp" if i % 2 else "pt", rng)
        c = shaped(value(random_mantissa(rng, rng.randint(1, 6)), rng.randint(-30, 30)), p, "pt", rng)
    if op == "div":
        a = shaped(few(), p, "pt", rng)
        b = shaped(value(random_mantissa(rng, rng.randint(1, 6)), rng.randint(-30, 30)), p, "pt", rng)
    return finish_operands(op, p, a, b, c, rng)


def class_wide(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Bounds of p + 16 bits: the ball of precision p holds the bounds rounded outward."""
    def wide() -> Interval:
        lead = rng.randint(-8, 8)
        lo = value(random_mantissa(rng, p + 16), lead - (p + 15))
        hi = value(lo.mantissa + rng.choice([0, 1, 3, 1 << 8, 1 << 20]), lo.exponent)
        if i % 3 == 0:
            return (lo.neg(), lo.neg()) if hi == lo else (hi.neg(), lo.neg())
        return (lo, hi)

    a, b, c = wide(), wide(), wide()
    return finish_operands(op, p, a, b, c, rng)


def class_z(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """Intervals with a zero bound, and the point zero."""
    def with_zero(j: int) -> Interval:
        x = with_lead(rng, p, rng.randint(-8, 8))
        return [(ZERO, x), (x.neg(), ZERO), (ZERO, ZERO), (ZERO, one_ulp_up(x, p)), (x.neg(), x)][j % 5]

    a = with_zero(i)
    b = with_zero(i + 2)
    c = with_zero(i + 4)
    if op == "div":  # the denominator has no zero inside; a zero bound is only legal for sqrt and the numerators
        b = shaped(with_lead(rng, p, rng.randint(-8, 8)), p, "pt" if i % 2 else "ulp", rng)
        if i % 3 == 0:
            b = (b[1].neg(), b[0].neg())
    if op == "sqrt":
        a = [(ZERO, with_lead(rng, p, rng.randint(-8, 8))), (ZERO, ZERO)][i % 2]
    return finish_operands(op, p, a, b, c, rng)


def exp_interval(x: Value, p: int, i: int) -> Interval:
    """A point, an interval of one or a few units of the last place above x, or one around x (a step either side)."""
    shape = i % 4
    if shape == 0:
        return (x, x)
    if shape == 1:
        return (x, step(x, 1, p))
    if shape == 2:
        return (step(x, -1, p), step(x, 2, p))
    return (step(x, -3, p), step(x, 3, p))


def class_xov(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """exp at the overflow threshold: arguments next to (EMAX + 1) ln 2, on both sides of it."""
    centre = times_ln2(EMAX + 1, p)
    k = (i // 4) % 7 - 3
    return [exp_interval(step(centre, k, p), p, i)]


def class_xuf(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """exp at the underflow side: next to the smallest normal number, the smallest subnormal and its half."""
    targets = [EMIN, quantum(p) + 1, quantum(p), quantum(p) - 1, EMIN - p // 2]
    centre = times_ln2(targets[i % len(targets)], p)  # the targets are negative exponents: x = n ln 2 with n < 0
    k = (i // len(targets)) % 5 - 2
    return [exp_interval(step(centre, k, p), p, i // 2)]


def class_lne(op: str, p: int, i: int, rng: random.Random) -> Operands:
    """ln at the ends of the range and next to 1 (the result next to zero)."""
    kind = i % 6
    if kind == 0:
        x = max_finite(p)
    elif kind == 1:
        x = value(1, quantum(p))
    elif kind == 2:
        x = value(1 << (p - 1), 1 - p)  # 1
    elif kind == 3:
        x = value((1 << (p - 1)) + 1, 1 - p)  # 1 + one unit
    elif kind == 4:
        x = value(1 << (p - 1), EMIN - (p - 1))  # the smallest normal number
    else:
        x = value((1 << p) - 1, -p)  # 1 - one unit
    shape = (i // 6) % 3
    if kind == 0:  # the largest finite value: nothing above it
        return [[(x, x), (step(x, -1, p), x), (step(x, -3, p), x)][shape]]
    if shape == 0:
        return [(x, x)]
    if shape == 1:
        return [(step(x, -1, p), step(x, 1, p))] if x.mantissa > 1 else [(x, step(x, 1, p))]
    return [(x, step(x, 2, p))]


GENERATORS: dict[str, Callable[[str, int, int, random.Random], Operands]] = {
    "R": class_r,
    "OV": class_ov,
    "SUB": class_sub,
    "FAR": class_far,
    "FEW": class_few,
    "WIDE": class_wide,
    "Z": class_z,
    "XOV": class_xov,
    "XUF": class_xuf,
    "LNE": class_lne,
}


@dataclass(frozen=True)
class Row:
    id: str
    op: str
    size: int
    klass: str
    operands: tuple[Interval, ...]

    def __post_init__(self) -> None:
        for lo, hi in self.operands:
            for bound in (lo, hi):
                if bound.mantissa and (bound.lead() > EMAX or (bound.exponent + (bound.mantissa & -bound.mantissa).bit_length() - 1) < quantum(self.size)):
                    raise ValueError(f"row {self.id}: the operand {bound.text()} is not a number of the format (above the largest finite value or off the grid of the smallest subnormal)")
            if compare(lo, hi) > 0:
                raise ValueError(f"row {self.id}: lower bound {lo.text()} above upper bound {hi.text()}")
        if self.op == "ln" and compare(self.operands[0][0], ZERO) <= 0:
            raise ValueError(f"row {self.id}: ln of an interval that is not positive")
        if self.op == "sqrt" and self.operands[0][0].negative:
            raise ValueError(f"row {self.id}: sqrt of an interval below zero")
        if self.op == "div":
            lo, hi = self.operands[1]
            if compare(lo, ZERO) <= 0 <= compare(hi, ZERO):
                raise ValueError(f"row {self.id}: the divisor contains zero")

    def line(self) -> str:
        parts = " ".join(f"{lo.text()}:{hi.text()}" for lo, hi in self.operands)
        return f"{self.id} {self.op} {self.size} {self.klass} {parts}"


def generate_rows(seed: int = SEED, precisions: Sequence[int] = PRECISIONS, per_cell: int = ROWS_PER_CELL,
                  classes: Iterable[str] | None = None, ops: Iterable[str] | None = None) -> list[Row]:
    wanted_classes = set(classes) if classes is not None else set(CLASSES)
    wanted_ops = set(ops) if ops is not None else set(OPS)
    rows: list[Row] = []
    for klass, (applicable, _) in CLASSES.items():
        if klass not in wanted_classes:
            continue
        for op in applicable:
            if op not in wanted_ops:
                continue
            for p in sorted(set(precisions) | set(CLASS_PRECISIONS.get(klass, ()))):
                rng = random.Random(f"ball-diff:{seed}:{op}:{klass}:{p}")
                for i in range(per_cell):
                    operands = GENERATORS[klass](op, p, i, rng)
                    rows.append(Row(f"{seed}.{op}.{klass}.{p}.{i}", op, p, klass, tuple(operands)))
    return rows


def format_rows(rows: Sequence[Row], seed: int = SEED) -> str:
    return f"# ball-diff-v1 seed={seed}\n# id op size class operand...\n" + "\n".join(row.line() for row in rows) + "\n"


# ---------------------------------------------------------------------------
# Coverage of the oracle's flags (pure)
# ---------------------------------------------------------------------------


def parse_oracle(text: str) -> dict[str, tuple[str, str, str, str]]:
    """id -> (lo, hi, flags, echo)."""
    result = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(" ")
        result[fields[0]] = (fields[1], fields[2], fields[3], fields[4])
    return result


def coverage(rows: Sequence[Row], oracle: dict[str, tuple[str, str, str, str]]) -> dict[tuple[str, str, int], dict[str, int]]:
    """Per (class, op, size): rows, and rows with each oracle flag."""
    table: dict[tuple[str, str, int], dict[str, int]] = {}
    for row in rows:
        cell = table.setdefault((row.klass, row.op, row.size), {"rows": 0, "o": 0, "s": 0, "i": 0, "z": 0, "u": 0})
        cell["rows"] += 1
        flags = oracle[row.id][2]
        for flag in "osizu":
            if flag in flags:
                cell[flag] += 1
    return table


def check_coverage(table: dict[tuple[str, str, int], dict[str, int]]) -> list[str]:
    """The classes that were meant to reach a band and did not (an error of the generator, not of the library)."""
    errors = []
    for (klass, op, size), cell in sorted(table.items()):
        required = CLASSES[klass][1]
        if required is not None and sum(cell[flag] for flag in required) == 0:
            errors.append(f"class {klass} {op} {size}: none of {cell['rows']} rows reached the band (flag {required})")
    return errors


def render_coverage(table: dict[tuple[str, str, int], dict[str, int]]) -> str:
    out = ["| class | op | bits | rows | overflow | subnormal result | subnormal operand | to zero | undecided |", "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for (klass, op, size), cell in sorted(table.items()):
        out.append(f"| {klass} | {op} | {size} | {cell['rows']} | {cell['o']} | {cell['s']} | {cell['i']} | {cell['z']} | {cell['u']} |")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# A second oracle, in Python integers, for the cross-check of the MPFR one
# ---------------------------------------------------------------------------
#
# Every bound is computed from the exact corner values with integer arithmetic and
# one directed rounding (to p bits, with the exponent range and the gradual
# underflow of `bin_float`). It shares nothing with MPFR, with the C oracle or with
# the library. It reads the operands from the rows; the rows whose exponents differ
# by more than `MAX_GAP` bits are skipped (an exact sum would need a huge integer).

MAX_GAP = 4000
INF = Value(False, 1, 10**12)  # a sentinel above every finite value (compare() only looks at the leading bit)
NEG_INF = Value(True, 1, 10**12)


class Skipped(Exception):
    """A row the integer oracle does not compute (exponent gap above MAX_GAP)."""


def round_directed(num: int, exp: int, sticky: bool, negative: bool, up: bool, p: int, ranged: bool = True) -> Value:
    """(-1)^negative * (num + sticky*epsilon) * 2^exp rounded to p bits toward +inf (up) or -inf, in the range of bin_float.

    `sticky` says that the exact value is a little above `num * 2^exp` (in magnitude): a quotient or root with a remainder.
    """
    if num == 0:
        return ZERO
    bits = num.bit_length()
    target = exp + bits - p
    if ranged:
        target = max(target, quantum(p))
    q, rem = num, 0
    if target > exp:
        q, rem = divmod(num, 1 << (target - exp))
    else:
        target = exp
    inexact = rem != 0 or sticky
    if inexact and (up != negative):  # away from zero
        q += 1
    if q == 0:
        return ZERO
    if q.bit_length() > p:
        q >>= 1
        target += 1
    result = Value(negative, q, target)
    if ranged and result.lead() > EMAX:
        largest = max_finite(p)
        if up:
            return Value(True, largest.mantissa, largest.exponent) if negative else INF
        return NEG_INF if negative else largest
    return result


def py_text(x: Value) -> str:
    """The canonical text of a value of the integer oracle (the form of mpfr_ours.h)."""
    if x.mantissa == 0:
        return "0"
    if x.exponent == 10**12 and x.mantissa == 1:
        return "-inf" if x.negative else "inf"
    m, e = x.mantissa, x.exponent
    trailing = (m & -m).bit_length() - 1
    return f"{'-' if x.negative else ''}0b{bin(m >> trailing)[2:]}p{e + trailing}"


def read_text(text: str) -> Value:
    negative = text.startswith("-")
    mantissa, exponent = text.lstrip("-")[2:].split("p")
    return value(int(mantissa, 16), int(exponent), negative)


def corner(op: str, args: Sequence[Value], p: int, up: bool) -> Value:
    """One corner: the operation on exact values, rounded once in the direction `up`."""
    if op in ("add", "sub", "fma"):
        terms: list[tuple[int, int]] = []  # (signed mantissa, exponent)
        if op == "fma":
            a, b, c = args
            terms = [((-1 if a.negative != b.negative else 1) * a.mantissa * b.mantissa, a.exponent + b.exponent), (-c.mantissa if c.negative else c.mantissa, c.exponent)]
        else:
            a, b = args
            sign_b = -1 if (b.negative != (op == "sub")) else 1
            terms = [(-a.mantissa if a.negative else a.mantissa, a.exponent), (sign_b * b.mantissa, b.exponent)]
        live = [t for t in terms if t[0] != 0]
        if not live:
            return ZERO
        top = max(e + m.bit_length() for m, e in live)
        low = min(e for _, e in live)
        if top - low > MAX_GAP:
            raise Skipped()
        total = sum(m << (e - low) for m, e in live)
        return round_directed(abs(total), low, False, total < 0, up, p)
    if op in ("mul", "sqr"):
        a, b = (args[0], args[0]) if op == "sqr" else args
        return round_directed(a.mantissa * b.mantissa, a.exponent + b.exponent, False, a.negative != b.negative, up, p)
    if op == "div":
        a, b = args
        if a.mantissa == 0:
            return ZERO
        shift = p + 2 + b.mantissa.bit_length() - a.mantissa.bit_length()
        shift = max(shift, 0)
        q, r = divmod(a.mantissa << shift, b.mantissa)
        return round_directed(q, a.exponent - b.exponent - shift, r != 0, a.negative != b.negative, up, p)
    if op == "sqrt":
        (a,) = args
        if a.mantissa == 0:
            return ZERO
        shift = max(2 * (p + 2) - a.mantissa.bit_length(), 0)
        if (a.exponent - shift) % 2:
            shift += 1
        root = math.isqrt(a.mantissa << shift)
        return round_directed(root, (a.exponent - shift) // 2, root * root != a.mantissa << shift, False, up, p)
    raise ValueError(op)


def py_oracle(row: Row) -> tuple[str, str]:
    """The tightest interval of a row, by the integer oracle: (lo, hi) canonical texts; raises Skipped
    (the elementary functions have no second oracle: exp and ln are only required to enclose)."""
    if row.op in ELEMENTARY_OPS:
        raise Skipped()
    p = row.size
    # the operands as the ball holds them: every bound rounded outward to p bits, without a range
    operands = [(round_directed(abs(read(lo).mantissa), read(lo).exponent, False, read(lo).negative, False, p, ranged=False),
                 round_directed(abs(read(hi).mantissa), read(hi).exponent, False, read(hi).negative, True, p, ranged=False))
                for lo, hi in ((lo.text(), hi.text()) for lo, hi in row.operands)]  # fmt: skip
    import itertools

    if row.op == "sqr" and compare(operands[0][0], ZERO) < 0 < compare(operands[0][1], ZERO):
        top = max((corner("sqr", (x,), p, True) for x in operands[0]), key=lambda v: (v.lead(), v.mantissa))
        return "0", py_text(top)
    if row.op == "sqrt":
        return py_text(corner("sqrt", (operands[0][0],), p, False)), py_text(corner("sqrt", (operands[0][1],), p, True))
    if row.op == "sqr" and compare(operands[0][1], ZERO) <= 0:
        lo_arg, hi_arg = operands[0][1], operands[0][0]
        return py_text(corner("sqr", (lo_arg,), p, False)), py_text(corner("sqr", (hi_arg,), p, True))
    if row.op == "sqr":
        return py_text(corner("sqr", (operands[0][0],), p, False)), py_text(corner("sqr", (operands[0][1],), p, True))
    lows = []
    highs = []
    for combo in itertools.product(*[(iv[0], iv[1]) for iv in operands]):
        lows.append(corner(row.op, combo, p, False))
        highs.append(corner(row.op, combo, p, True))
    least = lows[0]
    for v in lows[1:]:
        if compare(v, least) < 0:
            least = v
    greatest = highs[0]
    for v in highs[1:]:
        if compare(v, greatest) > 0:
            greatest = v
    return py_text(least), py_text(greatest)


def read(text: str) -> Value:
    return read_text(text)


def same_zero(text: str) -> str:
    """The two zeros are one number in the set-based flavour."""
    return "0" if text == "-0" else text


def crosscheck(rows: Sequence[Row], oracle: dict[str, tuple[str, str, str, str]]) -> tuple[int, int, list[str]]:
    """(rows that agree, rows skipped, disagreements) of the MPFR oracle with the integer oracle."""
    agree, skipped, bad = 0, 0, []
    for row in rows:
        lo, hi, flags, _ = oracle[row.id]
        if "u" in flags:
            skipped += 1
            continue
        try:
            mine = py_oracle(row)
        except Skipped:
            skipped += 1
            continue
        if tuple(same_zero(x) for x in mine) == (same_zero(lo), same_zero(hi)):
            agree += 1
        else:
            bad.append(f"{row.id} {row.op} {row.size}: mpfr {lo} {hi} python {mine[0]} {mine[1]}")
    return agree, skipped, bad


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------


def capture(command: Sequence[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, **kwargs)  # type: ignore[call-overload]


def build_oracle(out_dir: Path, prefix: Path, cc: str) -> Path:
    binary = out_dir / "ball_mpfr_oracle"
    command = [cc, "-O1", "-std=c11", "-Wall", "-Wextra", f"-I{prefix / 'include'}", f"-I{REPO_ROOT / 'tools'}", str(ORACLE_SOURCE),
               "-o", str(binary), f"-L{prefix / 'lib'}", f"-Wl,-rpath,{prefix / 'lib'}", "-lmpfr", "-lgmp"]  # fmt: skip
    done = capture(command)
    if done.returncode != 0:
        raise RuntimeError("oracle build failed:\n" + done.stdout)
    return binary


def parse_known(text: str) -> dict[str, str]:
    """`<row id> #<issue>` per line (comments with `#` at the start of a line): the rows that differ today and have an issue."""
    known = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        row_id, _, issue = line.partition(" ")
        if not issue.startswith("#"):
            raise ValueError(f"known row without an issue number: {line}")
        known[row_id] = issue
    return known


def split_failures(failures: Sequence[str], known: dict[str, str], ran: Iterable[str]) -> tuple[list[str], list[str], list[str]]:
    """(unknown failing lines, known failing ids, known ids that ran and agree: stale entries)."""
    failing_ids = {line.split()[1]: line for line in failures}
    unknown = [line for row_id, line in failing_ids.items() if row_id not in known]
    still = sorted(row_id for row_id in failing_ids if row_id in known)
    ran_ids = set(ran)
    stale = sorted(row_id for row_id in known if row_id in ran_ids and row_id not in failing_ids)
    return unknown, still, stale


def command_gen(args: argparse.Namespace) -> int:
    args.out.mkdir(parents=True, exist_ok=True)
    rows = generate_rows(args.seed, args.precisions, args.per_cell, args.classes, args.ops)
    path = args.out / "inputs.txt"
    path.write_text(format_rows(rows, args.seed), encoding="utf-8")
    print(f"{len(rows)} rows: {path}")
    return 0


def parse_test_output(text: str) -> tuple[int, int, int, list[str]]:
    """(rows, failed, undecided, failure lines) from the test's output."""
    failures = [line for line in text.splitlines() if line.startswith("BALLDIFF_FAIL")]
    for line in text.splitlines():
        if line.startswith("BALLDIFF_SUMMARY"):
            fields = dict(part.split("=") for part in line.split()[1:])
            return int(fields["rows"]), int(fields["failed"]), int(fields["undecided"]), failures
    raise RuntimeError("the test printed no BALLDIFF_SUMMARY line:\n" + text[-3000:])


def command_run(args: argparse.Namespace) -> int:
    args.out.mkdir(parents=True, exist_ok=True)
    rows = generate_rows(args.seed, args.precisions, args.per_cell, args.classes, args.ops)
    inputs = args.out / "inputs.txt"
    inputs.write_text(format_rows(rows, args.seed), encoding="utf-8")
    oracle_binary = build_oracle(args.out, args.prefix, args.cc)
    oracle_path = args.out / "oracle.txt"
    done = capture([str(oracle_binary), str(inputs), str(oracle_path)])
    if done.returncode != 0:
        print("oracle failed:\n" + done.stdout)
        return 2
    oracle = parse_oracle(oracle_path.read_text(encoding="utf-8"))
    table = coverage(rows, oracle)
    print(render_coverage(table))
    errors = check_coverage(table)
    for error in errors:
        print("GENERATOR ERROR: " + error)
    agree, skipped, bad = crosscheck(rows, oracle)
    print(f"oracle cross-check (MPFR against Python integers): {agree} rows agree, {skipped} skipped (exponent gap above {MAX_GAP} bits, or undecided), {len(bad)} disagree")
    for line in bad[:20]:
        print("ORACLE DISAGREEMENT: " + line)
    errors += [f"the two oracles disagree on {len(bad)} rows"] if bad else []
    env = dict(os.environ, BALLDIFF_INPUTS=str(inputs), BALLDIFF_ORACLE=str(oracle_path))
    command = ["sh", "tools/run_moon_clean_exec.sh", "test", "--release", "tooling/src/differential/ball_mpfr", "--target", "native", "--no-parallelize"]  # fmt: skip
    done = capture(command, cwd=REPO_ROOT, env=env)
    (args.out / "test.log").write_text(done.stdout, encoding="utf-8")
    total, failed, undecided, failures = parse_test_output(done.stdout)
    known = parse_known(KNOWN_FILE.read_text(encoding="utf-8")) if KNOWN_FILE.exists() else {}
    unknown, still, stale = split_failures(failures, known, (row.id for row in rows))
    for line in unknown[:40]:
        print(line)
    for row_id in still:
        print(f"known difference {row_id} ({known[row_id]})")
    for row_id in stale:
        print(f"STALE: {row_id} ({known[row_id]}) agrees with MPFR now: remove it from {KNOWN_FILE.name}")
    print(
        f"ball_float against MPFR: {total} rows, {failed} differ ({len(still)} known with an issue, {len(unknown)} new), "
        f"{undecided} undecided (MPFR's answer failed an exact check), {len(stale)} stale known entries"
    )
    return 0 if not unknown and not stale and not errors else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--out", type=Path, default=DEFAULT_OUT)
        p.add_argument("--seed", type=int, default=SEED)
        p.add_argument("--precisions", type=int, nargs="+", default=list(PRECISIONS))
        p.add_argument("--per-cell", type=int, default=ROWS_PER_CELL, help="rows per (class, operation, precision)")
        p.add_argument("--classes", nargs="+", choices=sorted(CLASSES), default=None)
        p.add_argument("--ops", nargs="+", choices=OPS, default=None)

    gen = sub.add_parser("gen", help="write the rows")
    common(gen)
    gen.set_defaults(func=command_gen)
    run = sub.add_parser("run", help="rows, oracle, the BallFloat test, verdict; exit status 1 when any row differs")
    common(run)
    run.add_argument("--prefix", type=Path, default=Path(os.environ.get("EXTBENCH_PREFIX", "/opt/homebrew")), help="prefix holding include/ and lib/ of MPFR and GMP")
    run.add_argument("--cc", default=os.environ.get("CC", "cc"))
    run.set_defaults(func=command_run)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
