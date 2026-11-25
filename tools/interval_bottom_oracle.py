#!/usr/bin/env python3
"""Independent oracle for the bottom of the exponent range and the far margins of the `interval` package.

Level A in the sense of the oracle rule: no `interval` or `binary` code is used. Every number is a
dyadic `n * 2^e` held by Python integers, so the ends of the exponent range and gaps of 100,000
places cost nothing. The rules are those of IEEE 1788-2015:

- the constructor rounds the lower bound down and the upper bound up to a number of p bits on the
  grid whose quantum is at least 2^(E_MIN - p + 1) (below the range floor the numbers of p bits are
  those multiples of that quantum; 10.2, 12.12.7);
- mid(x) is the exact (lower + upper) / 2 rounded to nearest, ties to even, in that format;
  rad(x) is the smallest number r with x inside [mid - r, mid + r]; wid(x) is upper - lower rounded
  toward +infinity (12.12.8);
- from_midpoint_radius(c, r) is the hull [c - r, c + r] rounded outward once each (12.12.7);
- fma(x, y, z) is the hull of x * y + z, exact until one outward rounding (12.10.2, tightest);
- midpoint_ctx at the context precision q is the exact centre rounded to nearest even at q bits.

Table lines (space separated; a number is `[-]0x<hex>p<exp>`, a long number is written as the
comma separated tokens `<hex digits>` and `<digit>*<count>` (a run of equal digits)
of its hexadecimal digits, then `p<exp>`):

  mid LO HI P         MID RAD WID          (the constructor's rounded bounds are not printed)
  mpr C R P           LO HI MID            (endpoints of from_midpoint_radius, and the midpoint of that interval)
  fma P XLO XHI YLO YHI ZLO ZHI   LO HI
  sum A B             SUM HALF             (exact)
  ctx IP CP LO HI     MID                  (midpoint_ctx at context precision CP)

`--write` writes `library/src/interval/bottom_table_wbtest.mbt` (byte-stable); `--check` compares.
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import interval_mid_oracle as m  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/bottom_table_wbtest.mbt"
E_MIN = m.E_MIN
PRECISION_MAX = 268435456
CHUNK = 250

Dyadic = m.Dyadic


def canon(a: Dyadic) -> Dyadic:
    """The odd-numerator form (zero is (0, 0))."""
    n, e = a
    if n == 0:
        return (0, 0)
    trailing = (abs(n) & -abs(n)).bit_length() - 1
    return (n >> trailing, e + trailing)


def run_hex(n: int) -> str:
    """The hexadecimal digits of n >= 0 as comma separated tokens: plain digits, and `<digit>*<count>`
    for a run of at least 16 equal digits."""
    digits = f"{n:x}"
    tokens: list[str] = []
    position = 0
    for found in re.finditer(r"(.)\1{15,}", digits):
        if found.start() > position:
            tokens.append(digits[position : found.start()])
        tokens.append(f"{found.group(1)}*{found.end() - found.start()}")
        position = found.end()
    if position < len(digits):
        tokens.append(digits[position:])
    return ",".join(tokens)


def expand_hex(runs: str) -> str:
    """The inverse of `run_hex`."""
    out = []
    for token in runs.split(","):
        digit, star, count = token.partition("*")
        out.append(digit * int(count) if star and len(digit) == 1 else token)
    return "".join(out)


def text(a: Dyadic) -> str:
    n, e = canon(a)
    if n == 0:
        return "0x0p0"
    sign = "-" if n < 0 else ""
    return f"{sign}0x{run_hex(abs(n))}p{e}"


def outward(lo: Dyadic, hi: Dyadic, p: int) -> tuple[Dyadic, Dyadic]:
    return m.round_to(lo, p, "down"), m.round_to(hi, p, "up")


def mul(a: Dyadic, b: Dyadic) -> Dyadic:
    return (a[0] * b[0], a[1] + b[1])


def hull_mul_add(x: tuple[Dyadic, Dyadic], y: tuple[Dyadic, Dyadic], z: tuple[Dyadic, Dyadic], p: int) -> tuple[Dyadic, Dyadic]:
    corners = [mul(a, b) for a in x for b in y]
    low, high = corners[0], corners[0]
    for c in corners:
        if m.cmp(c, low) < 0:
            low = c
        if m.cmp(c, high) > 0:
            high = c
    return m.round_to(m.add(low, z[0]), p, "down"), m.round_to(m.add(high, z[1]), p, "up")


def width_up(lo: Dyadic, hi: Dyadic, p: int) -> Dyadic:
    return m.round_to(m.add(hi, m.neg(lo)), p, "up")


def mid_of(lo: Dyadic, hi: Dyadic, p: int, q: int | None = None) -> Dyadic:
    """The centre of [lo, hi] rounded to nearest even at q bits (default p)."""
    s = m.add(lo, hi)
    centre = m.round_to(m.halve(s), p if q is None else q, "nearest")
    return (0, 0) if centre[0] == 0 else centre


def odd_number(rng: random.Random, max_bits: int) -> int:
    bits = 1 + rng.randrange(max_bits)
    return rng.getrandbits(bits) | 1


def signed(rng: random.Random, n: int) -> int:
    return -n if rng.randrange(2) == 0 else n


def rows() -> list[str]:
    out: list[str] = []
    # mid: the constructor rounds the exact bounds outward first
    for shift in (60, 45, 40, 30, 10, 3):
        for x, y in ((1, 3), (1, 5), (3, 5), (5, 7), (1, 7), (7, 9), (9, 15)):
            for p in (24, 53, 113):
                out.append(mid_line((x, E_MIN - shift), (y, E_MIN - shift), p))
    rng = random.Random(20261126)
    for _ in range(1200):
        x = odd_number(rng, 60)
        y = odd_number(rng, 60)
        a = (x, E_MIN - 70 + rng.randrange(90))
        b = (y, E_MIN - 70 + rng.randrange(90))
        lo, hi = m.ordered(a, b)
        out.append(mid_line(lo, hi, (24, 53, 113, 128)[rng.randrange(4)]))
    # a zero bound with the smallest stored value, the precision limit
    out.append(mid_line((0, 0), (1, E_MIN - 52), 53))
    out.append(mid_line((0, 0), (3, E_MIN - 52), 53))
    lowest = E_MIN - PRECISION_MAX + 1
    out.append(mid_line((1, lowest), (1, lowest + 1), PRECISION_MAX))
    # the interval of the issue, and negative bounds
    out.append(mid_line((1, E_MIN - 60), (3, E_MIN - 60), 113))
    for _ in range(300):
        x = signed(rng, odd_number(rng, 60))
        y = signed(rng, odd_number(rng, 60))
        lo, hi = m.ordered((x, E_MIN - 40 + rng.randrange(80)), (y, E_MIN - 40 + rng.randrange(80)))
        out.append(mid_line(lo, hi, (24, 53, 113)[rng.randrange(3)]))
    # mpr: centre and radius, near the bottom and away from it
    rng = random.Random(20261127)
    for _ in range(1500):
        c = (odd_number(rng, 60), E_MIN - 70 + rng.randrange(90))
        r = (rng.randrange(1000) + 1, E_MIN - 70 + rng.randrange(90))
        out.append(mpr_line(c, r, (24, 53, 113)[rng.randrange(3)]))
    for _ in range(800):
        c = (rng.randrange(1000000) + 1, rng.randrange(400) - 200)
        r = (rng.randrange(1000) + 1, rng.randrange(400) - 250)
        out.append(mpr_line(c, r, 53))
    out.append(mpr_line((133022375522373997, -1073741877), (389, -1073741869), 53))
    out.append(mpr_line((4296885932855670455593739022497658821269217831, -1073741878), (34625, -1073741882), 128))
    for _ in range(1500):
        c = (signed(rng, rng.getrandbits(129 + rng.randrange(72)) | (1 << 128) | 1), E_MIN - 60 + rng.randrange(120))
        r = (rng.getrandbits(8 * (1 + rng.randrange(11))) | 1, E_MIN - 60 + rng.randrange(120))
        out.append(mpr_line(c, r, (24, 53, 64, 113, 128)[rng.randrange(5)]))
    # fma at the bottom
    rng = random.Random(20261128)
    for _ in range(1500):
        p = (53, 113, 128)[rng.randrange(3)]
        bits = 1 + rng.randrange(40)

        def bound(low_exp: int, span: int, big: bool = True) -> Dyadic:
            n = (rng.getrandbits(bits) | 1) if big else rng.randrange(64) + 1
            return (n if rng.randrange(2) else -n, low_exp + rng.randrange(span))

        x = m.ordered(bound(E_MIN - 60, 60), bound(E_MIN - 60, 60))
        y = m.ordered(bound(-6, 4, False), bound(-6, 4, False))
        z = m.ordered(bound(E_MIN - 60, 60), bound(E_MIN - 60, 60))
        out.append(fma_line(p, x, y, z))
    t = (1, E_MIN - 3)
    out.append(fma_line(53, (t, t), ((1, 0), (1, 0)), (t, t)))
    # sum: the exact sum of two numbers at the bottom, and its half
    rng = random.Random(20261129)
    for _ in range(800):
        a = (odd_number(rng, 40), E_MIN - 60 + rng.randrange(70))
        b = (odd_number(rng, 40), E_MIN - 60 + rng.randrange(70))
        s = m.add(a, b)
        out.append(f"sum {text(a)} {text(b)} {text(s)} {text(m.halve(s))}")
    # ctx: midpoint_ctx around the margin of the far addend
    for ip in (24, 53, 200):
        for cp in (53, 65535, 65536, 65537, 70000, 140000):
            for span in (10, 100, 65535, 65536, 65600, 100000, 131000):
                small, large = (5, 0), (3, span)
                for lo, hi in (
                    (small, large),
                    (m.neg(large), small),
                    (m.neg(large), m.neg(small)),
                    (m.neg(small), large),
                ):
                    lo_r, hi_r = outward(lo, hi, ip)
                    out.append(f"ctx {ip} {cp} {text(lo)} {text(hi)} {text(mid_of(lo_r, hi_r, ip, cp))}")
    out.append(f"ctx 53 200000 {text((1, 0))} {text((1, 100000))} {text(mid_of((1, 0), (1, 100000), 53, 200000))}")
    return out


def mid_line(lo: Dyadic, hi: Dyadic, p: int) -> str:
    lo_r, hi_r = outward(lo, hi, p)
    centre, radius = m.mid_rad(lo_r, hi_r, p)
    return f"mid {text(lo)} {text(hi)} {p} {text(centre)} {text(radius)} {text(width_up(lo_r, hi_r, p))}"


def mpr_line(c: Dyadic, r: Dyadic, p: int) -> str:
    lo = m.round_to(m.add(c, m.neg(r)), p, "down")
    hi = m.round_to(m.add(c, r), p, "up")
    lo_r, hi_r = lo, hi  # the endpoints are numbers of p bits already
    return f"mpr {text(c)} {text(r)} {p} {text(lo)} {text(hi)} {text(mid_of(lo_r, hi_r, p))}"


def fma_line(p: int, x: tuple[Dyadic, Dyadic], y: tuple[Dyadic, Dyadic], z: tuple[Dyadic, Dyadic]) -> str:
    xo, yo, zo = outward(*x, p), outward(*y, p), outward(*z, p)
    lo, hi = hull_mul_add(xo, yo, zo, p)
    operands = " ".join(text(v) for pair in (x, y, z) for v in pair)
    return f"fma {p} {operands} {text(lo)} {text(hi)}"


def build() -> str:
    table = rows()
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_bottom_oracle.py (Python integers, no interval or binary code)",
        "// input: intervals, centres and radii, fma operands and sums at the bottom of the exponent range, far from it, and midpoint_ctx",
        "//   around the margin of the far addend; the rounding rules of IEEE 1788-2015 10.2, 12.10.2, 12.12.7, 12.12.8",
        "// library-ran: no",
        "// shares: nothing; the table is read with Binary::from_hex, String::split and a run expander only",
        "// check: python3 tools/interval_bottom_oracle.py --check",
        "",
    ]
    chunks = [table[i : i + CHUNK] for i in range(0, len(table), CHUNK)]
    for index, chunk in enumerate(chunks):
        lines += ["///|", f"fn bottom_table_{index}() -> String {{", "  ("]
        lines += ["    #|" + row for row in chunk]
        lines += ["  )", "}", ""]
    lines += ["///|", "fn bottom_tables() -> Array[String] {", "  ["]
    lines += [f"    bottom_table_{i}()," for i in range(len(chunks))]
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    content = build()
    if args.write:
        TARGET.write_text(content, encoding="utf-8")
        print(f"wrote {TARGET.relative_to(REPO_ROOT)}: {content.count(chr(10) + '    #|')} rows")
        return 0
    if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != content:
        print("the generated table differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
