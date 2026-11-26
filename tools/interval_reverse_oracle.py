#!/usr/bin/env python3
"""Independent oracle for `pow_rev1` and `pow_rev2` at a point base and a point result.

Level A in the sense of the oracle rule: no `interval` code is used. The values are computed with
the Python `decimal` module (correctly rounded `ln` and `exp` at 400 digits) and Python integers,
from the definitions of IEEE 1788-2015 Table 10.1:

- `pow_rev1(b, c)` with a point exponent `b` and a point result `c > 0` is the set of x > 0 with
  x^b = c, that is x = c^(1/b) = 2^(log2(c) / b);
- `pow_rev2(a, c)` with a point base `a > 0` and a point result `c > 0` is the exponent
  y = ln(c) / ln(a) = log2(c) / log2(a).

The enclosure of an irrational value t is `[RD(t), RU(t)]` on the grid of p bits whose quantum is
at least `2^(E_MIN - p + 1)`, E_MIN = 2 - 2^30. The value is built as `m * 2^n` with m in [1, 2) so
that the huge exponents (2^1e9, 2^(2^30)) cost nothing, and every row is computed at two decimal
precisions and must give the same two ends (a value near a rounding boundary would not).

Each table line is tab separated: name, kind (`p1` or `p2`), precision, first operand, second
operand (hexadecimal, as `Binary::from_hex` reads them), lower end, upper end.

`--write` writes `library/src/interval/reverse_table_wbtest.mbt` (byte-stable); `--check` recomputes
it and compares.
"""

from __future__ import annotations

import argparse
import sys
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TABLE = REPO_ROOT / "library/src/interval/reverse_table_wbtest.mbt"
E_MIN = 2 - (1 << 30)
E_MAX = (1 << 30) - 1

# A dyadic number is (n, e): the value n * 2^e with n an integer.
Dyadic = tuple[int, int]


def odd(a: Dyadic) -> Dyadic:
    n, e = a
    if n == 0:
        return (0, 0)
    while n % 2 == 0:
        n //= 2
        e += 1
    return (n, e)


def hexa(a: Dyadic) -> str:
    n, e = odd(a)
    if n == 0:
        return "0x0p0"
    sign = "-" if n < 0 else ""
    return f"{sign}0x{abs(n):x}p{e}"


def log2(a: Dyadic, digits: int) -> Decimal:
    """log2 of a positive dyadic number, `digits` decimal digits."""
    n, e = odd(a)
    assert n > 0
    with localcontext() as ctx:
        ctx.prec = digits
        ctx.Emin = -(10**12)
        ctx.Emax = 10**12
        return Decimal(e) + Decimal(n).ln() / Decimal(2).ln()


def round_value(mant: Fraction, n: int, p: int) -> tuple[Dyadic, Dyadic]:
    """[RD, RU] at p bits of mant * 2^n, mant in [1, 2), on the grid of the format (the quantum is
    at least 2^(E_MIN - p + 1)); the value must lie in the finite range."""
    assert 1 <= mant < 2
    assert n <= E_MAX
    q = max(n - p + 1, E_MIN - p + 1)
    scaled = mant * Fraction(2) ** (n - q)  # the value in units of 2^q
    lo = scaled.numerator // scaled.denominator
    hi = lo + (0 if scaled.denominator == 1 else 1)
    assert scaled.denominator != 1, "an exact value is not a table row"
    return (lo, q), (hi, q)


def value_pow2(exponent: Decimal, digits: int) -> tuple[Fraction, int]:
    """2^exponent as (mant, n): mant in [1, 2), the value mant * 2^n."""
    with localcontext() as ctx:
        ctx.prec = digits
        ctx.Emin = -(10**12)
        ctx.Emax = 10**12
        n = int(exponent.to_integral_value(rounding="ROUND_FLOOR"))
        frac = exponent - n
        mant = (frac * Decimal(2).ln()).exp()
        return Fraction(mant), n


def signed_bounds(negative: bool, mant: Fraction, n: int, p: int) -> tuple[Dyadic, Dyadic]:
    lo, hi = round_value(mant, n, p)
    if negative:
        return (-hi[0], hi[1]), (-lo[0], lo[1])
    return lo, hi


def ends_p1(beta: Dyadic, c: Dyadic, p: int) -> tuple[Dyadic, Dyadic]:
    """The ends of c^(1/beta) at p bits."""
    result = []
    for digits in (400, 450):
        with localcontext() as ctx:
            ctx.prec = digits
            ctx.Emin = -(10**12)
            ctx.Emax = 10**12
            b = Decimal(odd(beta)[0]) * Decimal(2) ** odd(beta)[1]
            exponent = log2(c, digits) / b
        mant, n = value_pow2(exponent, digits)
        result.append(signed_bounds(False, mant, n, p))
    assert result[0] == result[1]
    return result[0]


def ends_p2(a: Dyadic, c: Dyadic, p: int) -> tuple[Dyadic, Dyadic]:
    """The ends of ln(c) / ln(a) at p bits."""
    result = []
    for digits in (400, 450):
        with localcontext() as ctx:
            ctx.prec = digits
            ctx.Emin = -(10**12)
            ctx.Emax = 10**12
            quotient = log2(c, digits) / log2(a, digits)
            negative = quotient < 0
            magnitude = abs(quotient)
            n = int(magnitude.ln().__truediv__(Decimal(2).ln()).to_integral_value(rounding="ROUND_FLOOR"))
            mant = Fraction(magnitude) / Fraction(2) ** n
        # a floor on the logarithm can be off by one next to a power of two
        if mant >= 2:
            mant /= 2
            n += 1
        elif mant < 1:
            mant *= 2
            n -= 1
        result.append(signed_bounds(negative, mant, n, p))
    assert result[0] == result[1]
    return result[0]


def rows() -> list[tuple[str, str, int, Dyadic, Dyadic]]:
    out: list[tuple[str, str, int, Dyadic, Dyadic]] = []
    two_less = ((1 << 41) - 1, -40)  # 2 - 2^-40
    for p in (53, 113):
        # the top binade and the subnormal range of the forward power
        out.append((f"p1-top-{p}", "p1", p, (1, -30), two_less))
        out.append((f"p1-sub-{p}", "p1", p, (-1, -30), two_less))
        # 1 / (3 * 2^(2^30 - 2)) = 2^E_MIN / 3: a rational below the normal range
        out.append((f"p1-third-{p}", "p1", p, (-1, 0), (3, (1 << 30) - 2)))
    # 1/9 at 8 bits: a denominator of 4 bits; RD = 227 * 2^-11, RU = 228 * 2^-11
    out.append(("p1-ninth-8", "p1", 8, (-1, 0), (9, 0)))
    out.append(("p1-ninth-53", "p1", 53, (-1, 0), (9, 0)))
    # 2^(1 / (1 + 2^-500)) at 501 bits
    out.append(("p1-near-two-501", "p1", 501, ((1 << 500) + 1, -500), (2, 0)))
    # a base one unit from 1, three results
    for name, a in (("up", ((1 << 52) + 1, -52)), ("down", ((1 << 53) - 1, -53))):
        for cname, c in (("2", (2, 0)), ("half", (1, -1)), ("10", (10, 0))):
            out.append((f"p2-{name}-{cname}-53", "p2", 53, a, c))
    # extreme bases and results
    out.append(("p2-huge-base-2-53", "p2", 53, (1, 1000000000), (2, 0)))
    out.append(("p2-huge-base-3-53", "p2", 53, (1, 1000000000), (3, 0)))
    out.append(("p2-tiny-base-2-53", "p2", 53, (1, -1000000000), (2, 0)))
    # the edges of the stored range
    for p in (53, 113):
        largest = ((1 << p) - 1, E_MAX - p + 1)
        smallest = (1, E_MIN - p + 1)
        out.append((f"p2-top-{p}", "p2", p, largest, (1, E_MAX)))
        out.append((f"p2-sub-{p}", "p2", p, smallest, (2, 0)))
        out.append((f"p2-big-{p}", "p2", p, (2, 0), largest))
    return out


def build() -> str:
    table = []
    for name, kind, p, x, y in rows():
        lo, hi = (ends_p1 if kind == "p1" else ends_p2)(x, y, p)
        table.append("\t".join([name, kind, str(p), hexa(x), hexa(y), hexa(lo), hexa(hi)]))
    lines = [
        "///|",
        "/// Generated by `python3 tools/interval_reverse_oracle.py --write`: the ends of `pow_rev1` and",
        "/// `pow_rev2` at a point base and a point result (IEEE 1788-2015 Table 10.1) computed with the",
        "/// Python `decimal` module (level A, no `interval` code). Each line is tab separated: name, kind,",
        "/// precision, first operand, second operand, lower end, upper end (hexadecimal).",
        "fn reverse_table() -> String {",
        "  (",
    ]
    lines += ["    #|" + row for row in table]
    lines += ["  )", "}"]
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
