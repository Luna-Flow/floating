#!/usr/bin/env python3
"""White-box rows for exponential-type decimal results near the range limits (#363).

Writes `library/src/decimal/exp_range_rows_wbtest.mbt`, a table of
`(op, rounding, precision, e_min, e_max, clamp, x, y, expected, flags)` executed
by `exp_range_wbtest.mbt` on every backend. The table is about results that are
just representable (the smallest subnormal, half of it, the largest finite
number) and results just out of range (below half of the smallest subnormal,
beyond the largest finite number), reached by arguments of the exponentials
`exp`, `exp2`, `exp10` (and the sibling operations `expm1`, `exp2m1`, `exp10m1`,
`sinh`, `cosh`, `pow`, `powr`, `pown`, `compound`, `rsqrt`) at and around the
thresholds of the coarse range decision (`x = +-k (1 - etiny)` and
`+-k (e_max + 1)`, `k = 3, 4, 1` for base e, 2, 10), and for the arguments of
issue #363.

No row comes from the library under test. The true value is computed with
Python `decimal` at 400 digits (exact where the value is a short integer power)
and rounded once by Python's `decimal` for the format and direction (libmpdec
semantics, GDA 1.70 rounding, Subnormal/Underflow/Clamped). This is only a
cross-check oracle: the standard decides (IEEE 754-2019 7.4 overflow by
rounding direction, 7.5 underflow, 9.2 correct rounding), and the expectation
table in the test file quotes the clauses. Flags use the letters of
`generate_decimal_pm1_rows.py`.

    python3 tools/generate_decimal_exp_range_rows.py && moon fmt
    python3 tools/generate_decimal_exp_range_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/exp_range_rows_wbtest.mbt"
CHUNK_ROWS = 500
ROW_TYPE = "(String, String, Int32, Int32, Int32, Bool, String, String, String, String)"
PREC = 400
ROUNDINGS = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "half_up": decimal.ROUND_HALF_UP,
    "half_down": decimal.ROUND_HALF_DOWN,
    "down": decimal.ROUND_DOWN,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
    "up": decimal.ROUND_UP,
    "05up": decimal.ROUND_05UP,
}
# (name, precision, e_min, e_max, clamp)
CONTEXTS = [
    ("narrow", 51, -14, 11, False),  # the context of issue #363
    ("decimal32", 7, -95, 96, True),
    ("decimal64", 16, -383, 384, True),
    ("decimal128", 34, -6143, 6144, True),
    ("wide", 34, -999999, 999999, False),
]
# 1 / log10(base) rounded up: the factor of the coarse decision.
FACTOR = {"exp": 3, "exp2": 4, "exp10": 1}
UNARY_OTHER = ("expm1", "exp2m1", "exp10m1", "sinh", "cosh")
BINARY = ("pow", "powr", "pown", "compound", "rsqrt")


def work() -> decimal.Context:
    return decimal.Context(
        prec=PREC, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[]
    )


W = work()
decimal.setcontext(W)
LN2 = W.ln(Decimal(2))
LN10 = W.ln(Decimal(10))
LN15 = W.ln(Decimal("1.5"))
LN125 = W.ln(Decimal("1.25"))
LN3 = W.ln(Decimal(3))


def exp_of(y: Decimal) -> Decimal:
    return W.exp(y)


def true_value(op: str, x: Decimal, y: Decimal | None, n: int | None) -> Decimal:
    if op in ("exp", "exp2", "exp10") and abs(x) < Decimal("1E-150"):
        # 1 + c x with c = 1, ln 2, ln 10: next to 1 on the side of x, and the
        # exact decimal is far beyond the 400 digits of the working context.
        c = {"exp": Decimal(1), "exp2": LN2, "exp10": LN10}[op]
        if abs(x) > Decimal("1E-390"):
            return Decimal(1) + c * x
        # An exact literal of 440 digits (the constructor does not round): 1
        # plus or minus 10^-439 lies on the side of x, and any target
        # precision rounds it as it rounds the true value.
        return Decimal("1." + "0" * 438 + "1") if x > 0 else Decimal("0." + "9" * 439)
    if op in ("expm1", "log1p") and abs(x) < Decimal("1E-150"):
        # f(x) = x (1 + e) with e = x / 2 (expm1) or -x / 2 (log1p), |e| < 10^-150:
        # on the side of x or of -x, by far less than a unit of any target
        # precision. The relative correction is taken as 10^-440 with that sign,
        # in an exact context (the operands have few digits).
        sign = (1 if x > 0 else -1) * (1 if op == "expm1" else -1)
        exact = decimal.Context(prec=1200, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
        return exact.multiply(x, exact.add(Decimal(1), Decimal(sign) * Decimal("1E-440")))
    if op == "log1p":
        return W.ln(1 + x)
    if op == "exp":
        return exp_of(x)
    if op == "exp2":
        if x == x.to_integral_value() and abs(x) <= 20000:
            k = int(x)
            return Decimal(2**k) if k >= 0 else Decimal(f"{5 ** -k}E{k}")
        return exp_of(W.multiply(x, LN2))
    if op == "exp10":
        if x == x.to_integral_value():
            return Decimal(f"1E{int(x)}")
        return exp_of(W.multiply(x, LN10))
    if op == "expm1" or op == "exp2m1" or op == "exp10m1":
        scale = {"expm1": Decimal(1), "exp2m1": LN2, "exp10m1": LN10}[op]
        e = exp_of(W.multiply(x, scale))
        if x < 0 and e < Decimal("1E-350"):
            return Decimal(-1) + Decimal("1E-350")
        return W.subtract(e, Decimal(1))
    if op == "sinh" or op == "cosh":
        e = exp_of(abs(x))
        half = W.divide(e, Decimal(2))
        value = half
        if abs(x) < 400:
            small = W.divide(exp_of(-abs(x)), Decimal(2))
            value = half - small if op == "sinh" else half + small
        return -value if (op == "sinh" and x < 0) else value
    if op == "rootn":  # x^(1/n), x > 0
        return exp_of(W.ln(x) / n)
    if op == "pow":  # 3^y
        return exp_of(W.multiply(y, LN3))
    if op == "powr":  # 2^y (y not an integer)
        return exp_of(W.multiply(y, LN2))
    if op == "pown":  # x^n, x > 0
        return exp_of(W.multiply(Decimal(n), W.ln(x)))
    if op == "compound":  # (1 + x)^n
        return exp_of(W.multiply(Decimal(n), W.ln(1 + x)))
    if op == "rsqrt":
        return exp_of(-W.ln(x) / 2)
    raise ValueError(op)


def letters(flags: dict) -> str:
    out = ""
    for key, letter in (
        (decimal.Inexact, "x"),
        (decimal.Rounded, "r"),
        (decimal.Overflow, "o"),
        (decimal.Subnormal, "s"),
        (decimal.Underflow, "u"),
        (decimal.Clamped, "c"),
    ):
        if flags.get(key):
            out += letter
    return out or "-"


def rounded(value: Decimal, spec, rounding: str) -> tuple[str, str]:
    _, precision, e_min, e_max, clamp = spec
    ctx = decimal.Context(
        prec=precision,
        rounding=ROUNDINGS[rounding],
        Emin=e_min,
        Emax=e_max,
        clamp=1 if clamp else 0,
        traps=[],
    )
    result = ctx.plus(value)
    return str(result), letters(ctx.flags)


def trim(x: Decimal, digits: int) -> Decimal:
    if x == 0:
        return x
    q = x.adjusted() - digits + 1
    return x.quantize(Decimal(1).scaleb(q), rounding=decimal.ROUND_HALF_EVEN, context=W)


def fmt(x: Decimal) -> str:
    return format(x, "f") if abs(x.adjusted()) < 12 else str(x)


def args_for(op: str, spec) -> list[Decimal]:
    """Arguments whose result lies just inside / outside the range."""
    _, precision, e_min, e_max, _ = spec
    etiny = e_min - precision + 1
    digits = min(precision, 40)
    nmax = Decimal(10**precision - 1).scaleb(e_max - precision + 1)
    unders = [
        Decimal("1.1").scaleb(etiny),
        Decimal("0.6").scaleb(etiny),
        Decimal("0.4").scaleb(etiny),
        Decimal("3").scaleb(etiny - 1),
        Decimal("0.5").scaleb(etiny - 1),
        Decimal(1).scaleb(etiny - 7),
    ]
    overs = [
        nmax * Decimal("0.99"),
        Decimal("0.5").scaleb(e_max + 1),
        Decimal(2).scaleb(e_max + 1),
        Decimal(1).scaleb(e_max + 8),
    ]
    scale = {"exp": Decimal(1), "exp2": LN2, "exp10": LN10}
    if op in scale:
        k = scale[op]
        xs = [trim(W.ln(t) / k, digits) for t in unders]
        xs += [trim(W.ln(t) / k, digits) for t in overs]
        factor = FACTOR[op]
        down = factor * (1 - etiny)
        up = factor * (e_max + 1)
        for d in ("1", "0.5", "0", "-0.5", "-1"):
            xs.append(Decimal(-down) + Decimal(d))
            xs.append(Decimal(up) + Decimal(d))
        xs += [
            Decimal("-6773329072.88"),
            Decimal("6773329072.88"),
            Decimal("-1E+12"),
            Decimal("1E+12"),
            Decimal("-2147483647.5"),
            Decimal("-3E+9"),
            Decimal("-7.5E+4"),
        ]
        return xs
    k = {
        "expm1": Decimal(1),
        "exp2m1": LN2,
        "exp10m1": LN10,
        "sinh": Decimal(1),
        "cosh": Decimal(1),
    }[op]
    half = op in ("sinh", "cosh")
    xs = [trim((W.ln(2 * t) if half else W.ln(t)) / k, digits) for t in overs]
    xs += [Decimal("6773329072.88"), Decimal("1E+12")]
    if op == "sinh":
        xs += [-x for x in xs]
    if op in ("expm1", "exp2m1", "exp10m1", "cosh"):
        xs += [Decimal("-6773329072.88"), Decimal("-1E+12")]
    return xs


# rootn arguments of #376: no exact root (the coefficient has no trailing zero, so
# `shift = exponent mod n` must be 0) and the large degrees that did not finish.
ROOTN_ARGS = [
    (Decimal("1E+7"), 3),
    (Decimal("1E+999999"), 1000000),
    (Decimal("7.5E+400000"), 1000000),
    (Decimal("2.5E-30"), 1000000),
    (Decimal("2.5E-30"), 2000000000),
    (Decimal("2.5E-30"), -2000000000),
    (Decimal("1E+999999"), 2000000000),
    (Decimal("3E+7"), 3),
    (Decimal("1E+11"), 1000000),
]
TINY_OPS = ("exp", "exp2", "exp10", "expm1", "log1p")
TINY_CONTEXTS = [CONTEXTS[0], CONTEXTS[1], CONTEXTS[3]]


def tiny_args(op: str, spec) -> list[Decimal]:
    """Tiny arguments on both sides of the thresholds of the tiny-argument decisions.

    exp, exp2, exp10: `top + 1 < -(p + 3)` with `|x| < 10^top` (one-sided next
    to 1); expm1, log1p: `adjusted(x) <= -(p + 12)` (scaled enclosure), and
    below the subnormal range for results under `10^(etiny - 2)`.
    """
    _, precision, e_min, _, _ = spec
    etiny = e_min - precision + 1
    edge = -(precision + 5) if op in ("exp", "exp2", "exp10") else -(precision + 12)
    exponents = [edge - 40, edge - 3, edge - 1, edge, edge + 1, edge + 3, edge + 25,
                 etiny - 3, etiny - 2, -1999996, -5000, -300]
    out = []
    for d in exponents:
        for mant in ("3", "7.5"):
            for sign in ("", "-"):
                out.append(Decimal(f"{sign}{mant}E{d}"))
    return out


def binary_args(op: str, spec) -> list[tuple]:
    """(x, y, n) triples for the binary operations."""
    _, precision, e_min, e_max, _ = spec
    etiny = e_min - precision + 1
    digits = min(precision, 40)
    nmax = Decimal(10**precision - 1).scaleb(e_max - precision + 1)
    targets = [
        Decimal("1.1").scaleb(etiny),
        Decimal("3").scaleb(etiny - 1),
        Decimal(1).scaleb(etiny - 7),
        nmax * Decimal("0.99"),
        Decimal(2).scaleb(e_max + 1),
        Decimal(1).scaleb(e_max + 8),
    ]
    rows = []
    for t in targets:
        lt = W.ln(t)
        if op == "pow":
            rows.append((Decimal(3), trim(lt / LN3, digits), None))
        elif op == "powr":
            rows.append((Decimal(2), trim(lt / LN2, digits), None))
        elif op == "pown":
            n = int((lt / LN15).to_integral_value())
            if abs(n) <= 2**31 - 1:
                rows.append((Decimal("1.5"), None, n))
        elif op == "compound":
            n = int((lt / LN125).to_integral_value())
            if abs(n) <= 2**31 - 1:
                rows.append((Decimal("0.25"), None, n))
        elif op == "rsqrt":
            x = trim(exp_of(-2 * lt), digits)
            # The operand must itself lie in the format (else invalid context).
            if x.adjusted() <= e_max and x >= Decimal(1).scaleb(etiny):
                rows.append((x, None, None))
    if op == "rsqrt":
        rows.append((Decimal(3).scaleb(etiny), None, None))
    return rows


def row(spec, rounding, op, x, y, n):
    _, precision, e_min, e_max, clamp = spec
    value = true_value(op, x, y, n)
    text, flags = rounded(value, spec, rounding)
    if flags in ("-", "c"):
        # An exact result: its cohort (the preferred exponent of 9.2.2, the
        # clamp fold-down) is not the subject of this table.
        return None
    return (
        op,
        rounding,
        precision,
        e_min,
        e_max,
        clamp,
        fmt(x),
        fmt(y) if y is not None else (str(n) if n is not None else ""),
        text,
        flags,
    )


def all_rows() -> list[tuple]:
    rows: list[tuple] = []
    seen = set()
    for spec in CONTEXTS:
        for rounding in ROUNDINGS:
            for op in ("exp", "exp2", "exp10") + UNARY_OTHER:
                for x in args_for(op, spec):
                    key = (spec[0], rounding, op, fmt(x))
                    if key in seen:
                        continue
                    seen.add(key)
                    r = row(spec, rounding, op, x, None, None)
                    if r:
                        rows.append(r)
            if spec in TINY_CONTEXTS:
                for op in TINY_OPS:
                    for x in tiny_args(op, spec):
                        key = (spec[0], rounding, op, fmt(x))
                        if key in seen:
                            continue
                        seen.add(key)
                        r = row(spec, rounding, op, x, None, None)
                        if r:
                            rows.append(r)
            # compound around the cheap decisions made before 1 + x is formed:
            # exponent10 > 0 with adjusted(x) >= p + 2, and n > 0 with
            # adjusted(x) < -(p + 2) (p being the precision of the context).
            # pown with a negative degree (#375): around the decisions on the
            # adjusted exponent of the power (underflow when n lb >= 2 - etiny,
            # overflow when n ub > e_max for the reciprocal) and for the operand
            # and degree of the issue.
            etiny_spec = spec[2] - spec[1] + 1
            for base, lb in (("3E+3", 3), ("3E-3", -3)):
                if lb > 0:
                    edge = -(-(2 - etiny_spec) // lb)  # smallest m with m lb >= 2 - etiny
                else:
                    edge = spec[3] // 2  # m ub' > e_max with ub = -2: 2 m > e_max
                for m in (edge - 2, edge - 1, edge, edge + 1, edge + 2):
                    if m >= 1:
                        r = row(spec, rounding, "pown", Decimal(base), None, -m)
                        if r:
                            rows.append(r)
            for count in (-2000000000, 2000000000, -3, 3):
                r = row(spec, rounding, "pown", Decimal("1E+999999"), None, count)
                if r:
                    rows.append(r)
            p = spec[1]
            for x in [Decimal(f"1E{p + 1}"), Decimal(f"1E{p + 2}"), Decimal(f"1E{p + 3}"),
                      Decimal(f"1E-{p + 1}"), Decimal(f"1E-{p + 2}"), Decimal(f"1E-{p + 3}"),
                      Decimal("3E+300"), Decimal("3E-300")]:
                for count in (2, -2, 3):
                    r = row(spec, rounding, "compound", x, None, count)
                    if r:
                        rows.append(r)
            if spec in TINY_CONTEXTS:
                for x, count in ROOTN_ARGS:
                    r = row(spec, rounding, "rootn", x, None, count)
                    if r:
                        rows.append(r)
            for op in BINARY:
                for x, y, n in binary_args(op, spec):
                    key = (spec[0], rounding, op, fmt(x), fmt(y) if y is not None else n)
                    if key in seen:
                        continue
                    seen.add(key)
                    r = row(spec, rounding, op, x, y, n)
                    if r:
                        rows.append(r)
    return rows


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(rows: list[tuple]) -> str:
    out = [
        "///|",
        "// Generated by tools/generate_decimal_exp_range_rows.py from Python decimal",
        "// (libmpdec) at 400 digits, a cross-check only; do not edit.",
        "// Columns: op, rounding, precision, e_min, e_max, clamp, x, y (or n),",
        "// expected (compared with compare_total), flags.",
        "",
    ]
    chunks = [rows[i : i + CHUNK_ROWS] for i in range(0, len(rows), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        out.append("///|")
        out.append(f"fn exp_range_rows_{index}() -> Array[{ROW_TYPE}] {{")
        out.append("  [")
        for r in chunk:
            op, rounding, p, lo, hi, clamp, x, y, expected, flags = r
            out.append(
                f"    ({quote(op)}, {quote(rounding)}, {p}, {lo}, {hi}, "
                f"{'true' if clamp else 'false'}, {quote(x)}, {quote(y)}, "
                f"{quote(expected)}, {quote(flags)}),"
            )
        out.append("  ]")
        out.append("}")
        out.append("")
    out.append("///|")
    out.append(f"fn exp_range_rows() -> Array[{ROW_TYPE}] {{")
    out.append(f"  let rows : Array[{ROW_TYPE}] = []")
    for index in range(len(chunks)):
        out.append(f"  for row in exp_range_rows_{index}() {{ rows.push(row) }}")
    out.append("  rows")
    out.append("}")
    out.append("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.set_int_max_str_digits(0)
    text = render(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        # moon fmt rewrites the layout: compare without whitespace and without
        # trailing commas.
        def norm(text: str) -> str:
            squeezed = "".join(text.split())
            for closer in (")", "]", "}"):
                squeezed = squeezed.replace("," + closer, closer)
            return squeezed

        if norm(current) != norm(text):
            print(f"{OUTPUT} is stale: run tools/generate_decimal_exp_range_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
