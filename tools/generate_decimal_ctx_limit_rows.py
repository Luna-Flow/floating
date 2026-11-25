#!/usr/bin/env python3
"""Rows for `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx` and `fma_ctx` of `decimal` at the limits of the exponent range (#806).

Writes `library/src/decimal/ctx_limit_rows_wbtest.mbt`, a table of
`(op, rounding, precision, e_min, e_max, a, b, c, result, flags)`. The contexts
put `e_max` at the stored limit 2147483646 and just below it, and `e_min` at and
below the smallest stored exponent -2147483645, so that `e_max + 2`,
`e_min - 1` and the like leave `Int32`. The operands are built around the
limits: adjusted exponents within three decades of `e_max`, exponents within
three of the smallest stored exponent.

Every expected row comes from CPython `decimal` (libmpdec), never from this
library: the result of `Context.add`, `subtract`, `multiply`, `divide`, `fma`
in a context with the same precision, Emin, Emax, rounding, clamp off. Flags are
x Inexact, o Overflow, u Underflow in that order, `-` for none (the other flags
the library has are not raised by these rows). The first rows are the six rows of
issue 806. The random part uses a fixed seed.

    python3 tools/generate_decimal_ctx_limit_rows.py && moon fmt
    python3 tools/generate_decimal_ctx_limit_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal/ctx_limit_rows_wbtest.mbt"

E_MAX = 2147483646
E_STORE_MIN = -2147483645

ROUNDINGS = {
    "HalfEven": decimal.ROUND_HALF_EVEN,
    "HalfUp": decimal.ROUND_HALF_UP,
    "HalfDown": decimal.ROUND_HALF_DOWN,
    "Down": decimal.ROUND_DOWN,
    "Ceiling": decimal.ROUND_CEILING,
    "Floor": decimal.ROUND_FLOOR,
    "Up": decimal.ROUND_UP,
    "ZeroFiveUp": decimal.ROUND_05UP,
}
# (e_min offset above the lowest e_min allowed by precision, e_max). The lowest
# e_min of a precision is E_STORE_MIN + precision - 1: its etiny is the smallest
# stored exponent, the `e_tiny` of the plain working context. A context with a
# lower etiny asks for a result below every storable exponent.
RANGES = [
    (0, E_MAX),
    (1, E_MAX),
    (2, E_MAX),
    (0, E_MAX - 1),
    (1, E_MAX - 2),
    (2, E_MAX - 3),
    (None, 10),
]
PRECISIONS = [1, 2, 3, 5, 12]
COEFFICIENTS = [
    1, 5, 9, 10, 50, 99, 99999, 12345, 99949, 99950, 100001, 999999999999,
    123456789012, 500000000001,
]
OPS = ["add", "sub", "mul", "div", "fma"]
FLAGS = [("x", decimal.Inexact), ("o", decimal.Overflow), ("u", decimal.Underflow)]
CHUNK = 100
ROW_TYPE = "(String, DecimalRound, Int32, Int32, Int32, String, String, String, String, String)"
ISSUE_PRECISION = 3
ISSUE_RANGE = (E_STORE_MIN + 2, E_MAX)
ISSUE_OPERANDS = [
    ("99999E2147483642", "5E2147483643"),
    ("99999E2147483642", "50E2147483642"),
    ("99999E2147483642", "99E2147483642"),
]


def context(rounding: str, p: int, e_min: int, e_max: int) -> decimal.Context:
    return decimal.Context(
        prec=p, rounding=ROUNDINGS[rounding], Emin=e_min, Emax=e_max,
        clamp=0, traps=[], flags=[],
    )


def evaluate(op: str, rounding: str, p: int, e_min: int, e_max: int,
             a: str, b: str, c: str) -> tuple[str, str]:
    ctx = context(rounding, p, e_min, e_max)
    x, y, z = decimal.Decimal(a), decimal.Decimal(b), decimal.Decimal(c)
    if op == "add":
        r = ctx.add(x, y)
    elif op == "sub":
        r = ctx.subtract(x, y)
    elif op == "mul":
        r = ctx.multiply(x, y)
    elif op == "div":
        r = ctx.divide(x, y)
    else:
        r = ctx.fma(x, y, z)
    text = "".join(l for l, f in FLAGS if ctx.flags[f]) or "-"
    return str(r).replace("Infinity", "inf"), text


def operand(rng: random.Random, high: bool) -> str:
    coefficient = rng.choice(COEFFICIENTS)
    digits = len(str(coefficient))
    sign = "-" if rng.random() < 0.4 else ""
    if high:
        adjusted = E_MAX - rng.randint(0, 3)
        exponent = adjusted - digits + 1
    else:
        exponent = E_STORE_MIN + rng.randint(0, 3)
    return f"{sign}{coefficient}E{exponent}"


def small(rng: random.Random) -> str:
    coefficient = rng.choice(COEFFICIENTS[:8])
    sign = "-" if rng.random() < 0.4 else ""
    return f"{sign}{coefficient}E{rng.randint(-3, 3)}"


def build() -> list[tuple[str, ...]]:
    rows: list[tuple[str, ...]] = []
    for rounding in ROUNDINGS:
        for a, b in ISSUE_OPERANDS:
            rows.append(finish("sub", rounding, ISSUE_PRECISION, *ISSUE_RANGE, a, b, "0"))
            rows.append(finish("add", rounding, ISSUE_PRECISION, *ISSUE_RANGE, a, "-" + b, "0"))
    # A carry out of the largest coefficient at the top of the range: 9.99..9E+emax
    # rounds up to 1E+(emax+1), which overflows (7.4). The same through each
    # operation, in every rounding mode, at e_max = 2147483646 and just below.
    for e_max in (E_MAX, E_MAX - 1):
        e_min = E_STORE_MIN + 4
        top = [
            ("div", "999999999999E%d" % (e_max - 14), "1E-3", "0"),
            ("div", "999999999999E%d" % (e_max - 11), "1", "0"),
            ("div", "999999999999E%d" % (e_max - 11), "10", "0"),
            ("div", "-999999999999E%d" % (e_max - 14), "1E-3", "0"),
            ("div", "999999999999E%d" % (e_max - 14), "3E-3", "0"),
            ("mul", "999999999999E%d" % (e_max - 11), "1", "0"),
            ("mul", "999999999999E%d" % (e_max - 14), "1000", "0"),
            ("mul", "-999999999999E%d" % (e_max - 14), "1000", "0"),
            ("add", "999999999999E%d" % (e_max - 11), "1", "0"),
            ("add", "999999999999E%d" % (e_max - 11), "0E0", "0"),
            ("fma", "999999999999E%d" % (e_max - 11), "1", "0"),
            ("fma", "999999999999E%d" % (e_max - 14), "1000", "1"),
        ]
        for rounding in ROUNDINGS:
            for op, a, b, c in top:
                rows.append(finish(op, rounding, 5, e_min, e_max, a, b, c))
    rng = random.Random(806)
    for op in OPS:
        for _ in range(320):
            p = rng.choice(PRECISIONS)
            offset, e_max = rng.choice(RANGES)
            e_min = -9 if offset is None else E_STORE_MIN + p - 1 + offset
            rounding = rng.choice(list(ROUNDINGS))
            kind = rng.choice(["high", "high", "low", "mixed"])
            if kind == "high":
                a, b, c = operand(rng, True), operand(rng, True), operand(rng, True)
            elif kind == "low":
                a, b, c = operand(rng, False), operand(rng, False), operand(rng, False)
            else:
                a, b, c = operand(rng, True), operand(rng, False), small(rng)
            if op in ("mul", "div"):
                if rng.random() < 0.5:
                    b = small(rng)
            if op == "fma" and rng.random() < 0.5:
                b = small(rng)
            if not stored(a, b, c, op):
                continue
            rows.append(finish(op, rounding, p, e_min, e_max, a, b, c))
    return rows


def stored(a: str, b: str, c: str, op: str) -> bool:
    for s in (a, b) + ((c,) if op == "fma" else ()):
        d = decimal.Decimal(s)
        if d.as_tuple().exponent < E_STORE_MIN:
            return False
        if d.adjusted() > E_MAX:
            return False
    return True


def finish(op: str, rounding: str, p: int, e_min: int, e_max: int,
           a: str, b: str, c: str) -> tuple[str, ...]:
    r, f = evaluate(op, rounding, p, e_min, e_max, a, b, c)
    return (op, rounding, str(p), str(e_min), str(e_max), a, b, c, r, f)


def render(rows: list[tuple[str, ...]]) -> str:
    lines = [
        "///|",
        "// Generated by tools/generate_decimal_ctx_limit_rows.py from CPython `decimal` (libmpdec); do not edit.",
        "// Columns: op, rounding, precision, e_min, e_max, a, b, c (fma only), result, flags (x o u, or -).",
        "",
        "///|",
    ]
    chunks = [rows[i : i + CHUNK] for i in range(0, len(rows), CHUNK)]
    for n, chunk in enumerate(chunks):
        lines += ["", "///|", f"let ctx_limit_rows_{n} : Array[{ROW_TYPE}] = ["]
        for op, rd, p, lo, hi, a, b, c, r, fl in chunk:
            lines.append(f'  ("{op}", {rd}, {p}, {lo}, {hi}, "{a}", "{b}", "{c}", "{r}", "{fl}"),')
        lines.append("]")
    names = " + ".join(f"ctx_limit_rows_{n}" for n in range(len(chunks)))
    lines += ["", "///|", f"let ctx_limit_chunks : Array[Array[{ROW_TYPE}]] = [",
              "  " + ", ".join(f"ctx_limit_rows_{n}" for n in range(len(chunks))), "]"]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    rows = build()
    text_out = render(rows)
    if args.check:
        norm = lambda s: re.sub(r"\s+", "", s).replace(",)", ")").replace(",]", "]")
        if not OUTPUT.is_file() or norm(OUTPUT.read_text(encoding="utf-8")) != norm(text_out):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text_out, encoding="utf-8")
    print(f"{OUTPUT}: {len(rows)} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
