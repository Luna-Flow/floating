#!/usr/bin/env python3
"""Independent hulls of the interval product, quotient and integer powers, for the `interval` tests.

Level A in the sense of the oracle rule: no `interval` or `binary` code is used. The rows are computed
with Python `fractions` from the definition (IEEE 1788-2015 10.5.2, 10.5.3 and the power functions of
Table 9.1): the bounds of `x * y`, `x / y` (y without zero) and `x ^ n` are the exact extrema of the
function over the box of real points, rounded outward to p bits (the lower bound down, the upper
bound up). An infinite bound is the limit: 0 times an infinite bound is 0, a finite number over an
infinite bound is 0, an infinite bound over an infinite bound gives an infinity of the sign of the
quotient and 0. The operand bounds are the doubles of the corpus rounded to nearest, ties to even,
to p bits (what `Binary::from_double(d, precision=p)` is defined to give). The sign of a zero bound
is not part of the table (the tests of the zero signs check it).

Row format, one per line: `op p a_lo a_hi b_lo b_hi lo hi` (for `pown`: `pown p a_lo a_hi n - lo hi`);
numbers are `[-]0x<hex>p<exp>`, `inf` or `-inf`.

`--write` writes `library/src/interval/basic_ops_table_wbtest.mbt` (byte-stable); `--check`
recomputes it and compares.
"""

from __future__ import annotations

import argparse
import random
import sys
from fractions import Fraction
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/basic_ops_table_wbtest.mbt"
PRECISIONS = (24, 128)
CORPUS = (float("-inf"), -3.0, -0.1, 0.0, 0.3, 2.5, float("inf"))
POWERS = (1, 2, 3, 4, 5)
SEED = 20261125
FMA_ROWS = 600
WIDTH_ROWS = 400

# A bound is a Fraction or the strings "inf" and "-inf".
Bound = "Fraction | str"


def is_inf(x) -> bool:
    return isinstance(x, str)


def round_directed(x: Fraction, p: int, up: bool) -> Fraction:
    """x rounded to p significant bits toward +infinity (up) or -infinity."""
    if x == 0:
        return Fraction(0)
    sign = 1 if x > 0 else -1
    a = abs(x)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    while Fraction(2) ** e > a:
        e -= 1
    while Fraction(2) ** (e + 1) <= a:
        e += 1
    scale = Fraction(2) ** (p - 1 - e)
    scaled = a * scale
    floor = scaled.numerator // scaled.denominator
    exact = floor == scaled
    # toward +infinity: positive values round the magnitude up, negative ones down
    magnitude_up = (sign > 0) == up
    m = floor + (0 if exact or not magnitude_up else 1)
    return sign * Fraction(m) / scale


def round_nearest(x: Fraction, p: int) -> Fraction:
    if x == 0:
        return Fraction(0)
    down, up = round_directed(x, p, False), round_directed(x, p, True)
    if x - down < up - x:
        return down
    if x - down > up - x:
        return up
    # a tie: the one with an even last bit
    sign = 1 if x > 0 else -1
    a = abs(down)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    while Fraction(2) ** e > a:
        e -= 1
    while Fraction(2) ** (e + 1) <= a:
        e += 1
    m = a / Fraction(2) ** (e - p + 1)
    return down if m.numerator % 2 == 0 else up


def operand(d: float, p: int):
    if d == float("inf"):
        return "inf"
    if d == float("-inf"):
        return "-inf"
    return round_nearest(Fraction(d), p)


def sign_of(x) -> int:
    if is_inf(x):
        return 1 if x == "inf" else -1
    return (x > 0) - (x < 0)


def product_corner(a, b):
    """The value or the limit of a * b at two bounds: a list of values (an infinity may add 0)."""
    if is_inf(a) or is_inf(b):
        if (not is_inf(a) and a == 0) or (not is_inf(b) and b == 0):
            return [Fraction(0)]
        return ["inf" if sign_of(a) * sign_of(b) > 0 else "-inf"]
    return [a * b]


def quotient_corner(a, b):
    """The value or the limit of a / b (b is never 0)."""
    if is_inf(b):
        if is_inf(a):
            return ["inf" if sign_of(a) * sign_of(b) > 0 else "-inf", Fraction(0)]
        return [Fraction(0)]
    if is_inf(a):
        return ["inf" if sign_of(a) * sign_of(b) > 0 else "-inf"]
    return [a / b]


def key(x):
    if x == "inf":
        return (1, Fraction(0))
    if x == "-inf":
        return (-1, Fraction(0))
    return (0, x)


def hull(values, p: int):
    lo = min(values, key=key)
    hi = max(values, key=key)
    lo = lo if is_inf(lo) else round_directed(lo, p, False)
    hi = hi if is_inf(hi) else round_directed(hi, p, True)
    return lo, hi


def mul_hull(a, b, p: int):
    values = [v for x in a for y in b for v in product_corner(x, y)]
    return hull(values, p)


def div_hull(a, b, p: int):
    values = [v for x in a for y in b for v in quotient_corner(x, y)]
    return hull(values, p)


def power(x, n: int):
    if is_inf(x):
        return "inf" if (x == "inf" or n % 2 == 0) else "-inf"
    return x**n


def pown_hull(a, n: int, p: int):
    lo, hi = a
    ends = [power(lo, n), power(hi, n)]
    values = list(ends)
    if n % 2 == 0 and sign_of(lo) <= 0 <= sign_of(hi):
        values.append(Fraction(0))
    return hull(values, p)


def fma_hull(x, y, z, p: int):
    """The hull of x * y + z over finite boxes, exact, rounded outward once."""
    products = [a * b for a in x for b in y]
    return round_directed(min(products) + z[0], p, False), round_directed(max(products) + z[1], p, True)


def width_upper(lo: Fraction, hi: Fraction, p: int) -> Fraction:
    return round_directed(hi - lo, p, True)


def random_dyadic(rng: random.Random, exp_span: int) -> Fraction:
    """c * 2^e with 1 <= c <= 10^6 and -exp_span <= e < exp_span, of either sign."""
    c = rng.randrange(1, 1_000_001)
    e = rng.randrange(-exp_span, exp_span)
    value = Fraction(c) * Fraction(2) ** e
    return -value if rng.random() < 0.5 else value


def random_box(rng: random.Random, exp_span: int):
    a, b = random_dyadic(rng, exp_span), abs(random_dyadic(rng, exp_span))
    return (a, b) if a <= b else (b, a)


def extra_rows() -> list[str]:
    rng = random.Random(SEED)
    out: list[str] = []
    for _ in range(FMA_ROWS):
        x, y, z = (random_box(rng, 100) for _ in range(3))
        lo, hi = fma_hull(x, y, z, 53)
        out.append(" ".join(["fma", "53", *(fmt(v) for v in (*x, *y, *z, lo, hi))]))
    for _ in range(WIDTH_ROWS):
        lo, hi = random_box(rng, 200)
        out.append(" ".join(["width", "53", fmt(lo), fmt(hi), fmt(width_upper(lo, hi, 53))]))
    return out


def fmt(x) -> str:
    if is_inf(x):
        return x
    if x == 0:
        return "0x0p0"
    sign = "-" if x < 0 else ""
    a = abs(x)
    n, d = a.numerator, a.denominator
    assert d & (d - 1) == 0, "not a dyadic number"
    return f"{sign}0x{n:x}p-{d.bit_length() - 1}" if d > 1 else f"{sign}0x{n:x}p0"


def intervals(p: int):
    values = [operand(d, p) for d in CORPUS]
    out = []
    for i, lo in enumerate(values):
        for hi in values[i:]:
            if is_inf(lo) and lo == hi:
                continue  # [inf, inf] and [-inf, -inf] are not intervals (IEEE 1788-2015 10.2)
            out.append((lo, hi))
    return out


def contains_zero(b) -> bool:
    lo, hi = b
    return sign_of(lo) <= 0 <= sign_of(hi)


def rows() -> list[str]:
    out: list[str] = []
    for p in PRECISIONS:
        boxes = intervals(p)
        for a in boxes:
            for b in boxes:
                lo, hi = mul_hull(a, b, p)
                out.append(" ".join(["mul", str(p), fmt(a[0]), fmt(a[1]), fmt(b[0]), fmt(b[1]), fmt(lo), fmt(hi)]))
        for a in boxes:
            for b in boxes:
                if contains_zero(b):
                    continue
                lo, hi = div_hull(a, b, p)
                out.append(" ".join(["div", str(p), fmt(a[0]), fmt(a[1]), fmt(b[0]), fmt(b[1]), fmt(lo), fmt(hi)]))
        for a in boxes:
            for n in POWERS:
                lo, hi = pown_hull(a, n, p)
                out.append(" ".join(["pown", str(p), fmt(a[0]), fmt(a[1]), str(n), "-", fmt(lo), fmt(hi)]))
    out += extra_rows()
    return out


def render() -> str:
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_basic_ops_oracle.py",
        "// input: the hulls of x * y, x / y (y without zero) and x ^ n (n = 1..5) over the boxes (infinite singletons excluded) made of the bounds -inf, -3, -0.1, 0, 0.3, 2.5, inf at p = 24 and 128; 600 random fma hulls and 400 random widths (c * 2^e, c up to 10^6, exponents -200 to 199) at p = 53; Python fractions, rounded outward",
        "// library-ran: no",
        "// shares: nothing; the table is read with Binary::from_hex and String::split only",
        "// check: python3 tools/interval_basic_ops_oracle.py --check",
        "",
        "///|",
        "fn basic_ops_table() -> String {",
        "  (",
    ]
    lines += ["    #|" + row for row in rows()]
    lines += ["  )", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = render()
    if args.write:
        TARGET.write_text(text)
        print(f"wrote {TARGET.relative_to(REPO_ROOT)}: {text.count(chr(10) + '    #|')} rows")
        return 0
    if not TARGET.exists() or TARGET.read_text() != text:
        print("the generated file differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
