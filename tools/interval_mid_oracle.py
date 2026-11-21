#!/usr/bin/env python3
"""Independent oracle for `Interval::midpoint`, `Interval::radius` and `to_midpoint_radius_string`.

Level A in the sense of the oracle rule: no `interval` code is used; the rows are computed with
Python integers (dyadic numbers `n * 2^e`, so the ends of the exponent range cost nothing) from
IEEE 1788-2015 12.12.8:

- mid(x) for a nonempty bounded x is the exact midpoint (lower + upper) / 2 rounded to nearest,
  ties to even (the tie-breaking of 4.3.1 of IEEE 754-2008, which a 754-conforming type shall
  follow), in the format of p bits whose exponents go down to `E_MIN` and below it on the grid
  of the smallest subnormal (the quantum `2^(E_MIN - p + 1)`); a midpoint of 0 is +0;
- rad(x) is the smallest number r of the format such that [lower, upper] is contained in
  [m - r, m + r] for that m: the larger of m - lower and upper - m, rounded toward positive.

For every row the oracle asserts the two inequalities exactly (`m - r <= lower`,
`m + r >= upper`) and that the next smaller number of the format would not do (r is smallest).

Each table line is tab separated: lower and upper bound as hexadecimal numbers, precision,
mid, rad (as `BinFloat::to_string` writes them: odd coefficient, `p`, exponent; `0` for zero).

`--write` writes `library/src/interval/midpoint_radius_table_wbtest.mbt` (byte-stable);
`--check` recomputes it and compares.
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TABLE = REPO_ROOT / "library/src/interval/midpoint_radius_table_wbtest.mbt"
E_MIN = 2 - (1 << 30)
CHUNK = 200

# A dyadic number is (n, e): the value n * 2^e with n a signed integer.
Dyadic = tuple[int, int]


def align(a: Dyadic, b: Dyadic) -> tuple[int, int, int]:
    e = min(a[1], b[1])
    return a[0] << (a[1] - e), b[0] << (b[1] - e), e


def add(a: Dyadic, b: Dyadic) -> Dyadic:
    x, y, e = align(a, b)
    return (x + y, e)


def neg(a: Dyadic) -> Dyadic:
    return (-a[0], a[1])


def cmp(a: Dyadic, b: Dyadic) -> int:
    x, y, _ = align(a, b)
    return (x > y) - (x < y)


def round_to(a: Dyadic, p: int, mode: str) -> Dyadic:
    """Round to a number of p bits on the grid whose quantum is at least 2^(E_MIN - p + 1).
    mode: 'nearest' (ties to even), 'up' (toward +infinity), 'down' (toward -infinity)."""
    n, e = a
    if n == 0:
        return (0, 0)
    sign = -1 if n < 0 else 1
    m = abs(n)
    top = e + m.bit_length() - 1
    q = max(top - p + 1, E_MIN - p + 1)
    shift = q - e
    if shift <= 0:
        return a
    quotient, remainder = divmod(m, 1 << shift)
    half = 1 << (shift - 1)
    if mode == "nearest":
        if remainder > half or (remainder == half and quotient % 2 == 1):
            quotient += 1
    elif mode == "up":
        # toward +infinity: a positive value rounds its magnitude up, a negative one down
        if sign > 0 and remainder > 0:
            quotient += 1
    elif mode == "down":
        if sign < 0 and remainder > 0:
            quotient += 1
    else:
        raise ValueError(mode)
    return (sign * quotient, q)


def halve(a: Dyadic) -> Dyadic:
    return (a[0], a[1] - 1)


def predecessor(r: Dyadic, p: int) -> Dyadic:
    """The largest number of the format below r > 0: r minus something below every quantum,
    rounded toward negative."""
    top = r[1] + r[0].bit_length() - 1
    tiny = max(E_MIN - p - 10, top - p - 10)
    return round_to(add(r, neg((1, tiny))), p, "down")


def mid_rad(lo: Dyadic, hi: Dyadic, p: int) -> tuple[Dyadic, Dyadic]:
    s = add(lo, hi)
    m = round_to(halve(s), p, "nearest")
    if m[0] == 0:
        m = (0, 0)
    below = add(m, neg(lo))
    above = add(hi, neg(m))
    big = below if cmp(below, above) >= 0 else above
    r = round_to(big, p, "up")
    # exact checks: containment, and r is smallest
    assert cmp(add(m, neg(r)), lo) <= 0 and cmp(add(m, r), hi) >= 0, (lo, hi, p)
    if r[0] != 0:
        smaller = predecessor(r, p)
        assert not (cmp(add(m, neg(smaller)), lo) <= 0 and cmp(add(m, smaller), hi) >= 0), (lo, hi, p)
    return m, r


def fmt(a: Dyadic) -> str:
    n, e = a
    if n == 0:
        return "0"
    while n % 2 == 0:
        n //= 2
        e += 1
    return f"{n}p{e}"


def hexa(a: Dyadic) -> str:
    n, e = a
    if n == 0:
        return "0x0p0"
    sign = "-" if n < 0 else ""
    n = abs(n)
    while n % 2 == 0:
        n //= 2
        e += 1
    return f"{sign}0x{n:x}p{e}"


def number(rng: random.Random, p: int, exp_lo: int, exp_hi: int) -> Dyadic:
    exp_lo = max(exp_lo, E_MIN - p + 1)
    exp_hi = max(exp_hi, exp_lo)
    bits = rng.randint(1, p)
    n = (rng.getrandbits(bits - 1) << 1 | 1) if bits > 1 else 1
    if bits > 1:
        n |= 1 << (bits - 1)
    n = -n if rng.random() < 0.4 else n
    return (n, rng.randint(exp_lo, exp_hi))


def ordered(a: Dyadic, b: Dyadic) -> tuple[Dyadic, Dyadic]:
    return (a, b) if cmp(a, b) <= 0 else (b, a)


def valid(a: Dyadic, p: int) -> bool:
    """A number of the format of p bits: at most p significant bits, on the grid of p bits."""
    n, e = a
    if n == 0:
        return True
    while n % 2 == 0:
        n //= 2
        e += 1
    return abs(n).bit_length() <= p and e >= E_MIN - p + 1


def rows() -> list[tuple[Dyadic, Dyadic, int]]:
    rng = random.Random(1788012)
    out: list[tuple[Dyadic, Dyadic, int]] = []
    precisions = (2, 3, 8, 24, 53, 64, 113)
    # point intervals, zero bounds, symmetric and one-sided intervals
    for p in precisions:
        one = (1, 0)
        out.append((one, one, p))
        out.append(((0, 0), (0, 0), p))
        out.append(((0, 0), (1, 0), p))
        out.append(((-1, 0), (0, 0), p))
        out.append(((-3, -1), (3, -1), p))
        out.append(((-1, 0), (1, 0), p))
    # a center that needs p + 1 bits: the bounds are numbers of p bits one unit apart
    for p in precisions:
        for e in (-30, 0, 7, 200):
            out.append((((1 << p) - 1, e), (1 << p, e), p))
            out.append(((1 << (p - 1), e), ((1 << (p - 1)) + 1, e), p))
            out.append(((-(1 << p), e), (-((1 << p) - 1), e), p))
    # a gap of more than 65,536 places
    for p in (8, 24, 53, 113):
        out.append(((-1, 70000), (1, 0), p))
        out.append(((1, -70000), (1, 0), p))
        out.append(((-3, 100000), (5, -100000), p))
        out.append(((1, 70000), (1, 70001), p))
        out.append(((-1, -70000), (1, 70000), p))
    # the bottom of the exponent range: bounds on the grid of the smallest subnormal
    for p in (2, 8, 24, 53, 113):
        q = E_MIN - p + 1
        out.append(((0, 0), (1, q), p))
        out.append(((1, q), (3, q), p))
        out.append(((1, q), (2, q), p))
        out.append(((-1, q), (1, q), p))
        out.append(((1, q), (1, E_MIN), p))
        out.append(((1, E_MIN - 3), (3, E_MIN - 2), p))
        out.append(((-5, q), (7, q), p))
    # random intervals
    for index in range(700):
        p = precisions[index % len(precisions)]
        span = rng.choice((8, 60, 400))
        base = rng.choice((0, 0, 0, E_MIN - 40, 5000))
        a = number(rng, p, base - span, base + span)
        b = number(rng, p, base - span, base + span)
        if rng.random() < 0.1:
            b = a
        lo, hi = ordered(a, b)
        out.append((lo, hi, p))
    # only intervals whose bounds are numbers of the format (a bound that is not one is rounded
    # outward by the constructor, which is not what this table tests)
    return [row for row in out if valid(row[0], row[2]) and valid(row[1], row[2])]


def build() -> str:
    table = []
    for lo, hi, p in rows():
        m, r = mid_rad(lo, hi, p)
        table.append("\t".join([hexa(lo), hexa(hi), str(p), fmt(m), fmt(r)]))
    lines = [
        "///|",
        "/// Generated by `python3 tools/interval_mid_oracle.py --write`: `midpoint`, `radius` of IEEE",
        "/// 1788-2015 12.12.8 computed with Python integers (level A, no `interval` code). Each line is",
        "/// tab separated: lower and upper bound (hexadecimal), precision, mid, rad.",
        "",
    ]
    chunks = [table[i : i + CHUNK] for i in range(0, len(table), CHUNK)]
    for index, chunk in enumerate(chunks):
        lines += ["///|", f"fn mid_rad_table_{index}() -> String {{", "  ("]
        lines += ["    #|" + row for row in chunk]
        lines += ["  )", "}", ""]
    names = [f"mid_rad_table_{i}()" for i in range(len(chunks))]
    lines += ["///|", "fn mid_rad_tables() -> Array[String] {", "  ["]
    lines += [f"    {name}," for name in names]
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = build()
    if args.write:
        TABLE.write_text(text, encoding="utf-8")
        print(f"wrote {TABLE.relative_to(REPO_ROOT)}: {text.count(chr(10) + '    #|')} rows")
        return 0
    ok = TABLE.exists() and TABLE.read_text(encoding="utf-8") == text
    if not ok:
        print("the generated table differs from the oracle; run --write and review")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
