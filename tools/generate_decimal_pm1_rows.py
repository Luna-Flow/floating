#!/usr/bin/env python3
"""White-box rows for decimal exp2m1, exp10m1, log2p1 and log10p1 (issue #236).

Writes `library/src/decimal/elementary_pm1_rows_wbtest.mbt`, a table of
`(op, rounding, precision, emin, emax, clamp, tininess, x, expected, flags)`
executed by `elementary_pm1_wbtest.mbt` on every backend. No row comes from the
library under test:

* exact cases (integer x for exp2m1/exp10m1; 1 + x an integer power of the
  base for log2p1/log10p1) are computed with `fractions.Fraction`, written as
  the exact decimal whose exponent is the preferred exponent 0 when the value
  allows it (IEEE 754-2019 9.2.2) or the least one otherwise, and rounded once
  by libmpdec (Python `decimal`) in the row's context;
* every other row is the rounding of a certified MPFR 4.2.2 enclosure
  (`tools/mpfr_decimal_enclosure.c` through `generate_mpfr_decimal_random`),
  kept only when both endpoints round to one result with one flag set and the
  result lies outside the enclosure (so the value is certainly inexact); for
  b^x - 1 with x so far below zero that 768 bits cannot separate the value
  from -1, a libmpdec enclosure at 40 + 4p digits takes its place.

Flags use the letters of the `mpfr-decimal-random-v1` rows (x inexact,
r rounded, o overflow, s subnormal, u underflow, c clamped), with Subnormal =
tiny and Underflow = tiny and inexact under the row's tininess rule (b: before
rounding, IEEE 754-2019 7.5 for decimal; a: after rounding).

    python3 tools/generate_decimal_pm1_rows.py && moon fmt
    python3 tools/generate_decimal_pm1_rows.py --check
"""

from __future__ import annotations

import argparse
import re
import decimal
import sys
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

import generate_mpfr_decimal_random as decm

sys.set_int_max_str_digits(0)
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/elementary_pm1_rows_wbtest.mbt"
ROUNDINGS = ("half_even", "half_up", "half_down", "down", "ceiling", "floor", "up", "05up")
OPS = ("exp2m1", "exp10m1", "log2p1", "log10p1")
DECIMAL32 = (7, -95, 96, 1)
DECIMAL64 = (16, -383, 384, 1)
DECIMAL128 = (34, -6143, 6144, 1)
# The widest context the math functions accept (math_context_is_restricted).
UNBOUNDED = (16, -999999, 999999, 0)
WIDE = 10**7


def integer_member(n: int, precision: int) -> Decimal | None:
    """The integer n written with at most `precision` digits, if it can be."""
    digits = str(abs(n)).rstrip("0")
    zeros = len(str(abs(n))) - len(digits)
    if len(digits) > precision:
        return None
    return Decimal((1 if n < 0 else 0, tuple(int(c) for c in digits), zeros))


def ctx(spec: tuple[int, int, int, int], rounding: str, tininess: str = "b") -> decm.Context:
    precision, emin, emax, clamp = spec
    return decm.Context(precision, rounding, emin, emax, clamp, tininess)


def exact_value(op: str, x: Decimal) -> Fraction | None:
    """The exact rational value, or None when the value is irrational."""
    # Cheap rejections first (a Fraction of 1E-1999996 is slow to normalise):
    # b^x is rational only for integer x, and 1 + x = b^k needs |x| >= 1/2.
    if op in ("exp2m1", "exp10m1"):
        if x.adjusted() < 0 or x != x.to_integral_value():
            return None
    elif abs(x) < Decimal("0.5"):
        return None
    q = Fraction(x)
    if op in ("exp2m1", "exp10m1"):
        if q.denominator != 1:
            return None
        base = 2 if op == "exp2m1" else 10
        n = q.numerator
        if abs(n) > 200_000:
            return None
        return Fraction(base) ** n - 1
    base = 2 if op == "log2p1" else 10
    s = q + 1
    if s <= 0:
        return None
    k = 0
    while s.denominator == 1 and s.numerator % base == 0:
        s /= base
        k += 1
    while s.numerator == 1 and s.denominator % base == 0:
        s *= base
        k -= 1
    return Fraction(k) if s == 1 else None


def fraction_decimal(value: Fraction) -> Decimal:
    """`value` (with a 2^a 5^b denominator) as the exact decimal of least
    exponent that is still >= 0 when the value is an integer (the preferred
    exponent 0) and of the fewest fraction digits otherwise."""
    num, den = value.numerator, value.denominator
    scale = 0
    while den % 10 == 0:
        den //= 10
        scale += 1
    while den % 2 == 0:
        den //= 2
        num *= 5
        scale += 1
    while den % 5 == 0:
        den //= 5
        num *= 2
        scale += 1
    assert den == 1
    sign = 1 if num < 0 else 0
    digits = tuple(int(c) for c in str(abs(num)))
    return Decimal((sign, digits, -scale))


def letters(flags: set[str], inexact: bool, tiny: bool, infinite: bool) -> str:
    out = ""
    if inexact:
        out += "x"
    if "Rounded" in flags:
        out += "r"
    if "Overflow" in flags:
        out += "o"
    if tiny and not infinite:
        out += "s"
        if inexact:
            out += "u"
    if "Clamped" in flags:
        out += "c"
    return out or "-"


def round_exact(value: Decimal, context: decm.Context) -> tuple[str, str]:
    python = context.python()
    result = python.create_decimal(value)
    flags = decm.flag_names(python)
    inexact = "Inexact" in flags
    if value.is_zero():
        tiny = False
    elif context.tininess == "b":
        tiny = value.adjusted() < context.emin
    else:
        unbounded = context.unbounded().create_decimal(value)
        tiny = (not unbounded.is_zero()) and unbounded.adjusted() < context.emin
    return str(result), letters(flags, inexact, tiny, result.is_infinite())


def libmpdec_certify(candidate: decm.Candidate) -> str | None:
    """Fallback for b^x - 1 with x far below zero, where the 768-bit MPFR
    enclosure cannot leave -1: b^x from libmpdec at 40 + 4p digits (its power
    and exp are within one ulp), widened by 10^-(digits - 5) relative, and
    `1` subtracted exactly; the row is kept only when both endpoints round
    alike (the same acceptance rule as `generate_mpfr_decimal_random.certify`)."""
    if candidate.op not in ("exp2m1", "exp10m1"):
        return None
    x = candidate.operands[0]
    digits = 40 + 4 * candidate.context.precision
    with decimal.localcontext() as local:
        local.prec = digits
        local.Emax = decimal.MAX_EMAX
        local.Emin = decimal.MIN_EMIN
        local.traps[decimal.Inexact] = False
        local.traps[decimal.Rounded] = False
        power = Decimal(2 if candidate.op == "exp2m1" else 10) ** x
    slack = Decimal((0, (1,), -(digits - 5)))
    with decimal.localcontext() as exact:
        exact.prec = decimal.MAX_PREC
        exact.Emax = decimal.MAX_EMAX
        exact.Emin = decimal.MIN_EMIN
        lower = power * (1 - slack) - 1
        upper = power * (1 + slack) - 1
    context = candidate.context
    results = []
    for endpoint in (lower, upper):
        python = context.python()
        result = python.create_decimal(endpoint)
        flags = decm.flag_names(python)
        rounded_unbounded = context.unbounded().create_decimal(endpoint)
        tiny_after = (not rounded_unbounded.is_zero()) and rounded_unbounded.adjusted() < context.emin
        tiny_before = endpoint.adjusted() < context.emin
        results.append((result, flags, tiny_after if context.tininess == "a" else tiny_before))
    (low, low_flags, low_tiny), (high, high_flags, high_tiny) = results
    if low.compare_total(high) != 0 or low_tiny != high_tiny:
        return None
    for name in ("Rounded", "Clamped", "Overflow"):
        if (name in low_flags) != (name in high_flags):
            return None
    if low.is_finite() and lower <= low <= upper:
        return None
    text = letters(low_flags, True, low_tiny, low.is_infinite())
    return " ".join([
        "fallback", candidate.op, context.rounding, str(context.precision), str(context.emin),
        str(context.emax), str(context.clamp), context.tininess, str(x), "-", "0", str(low), text,
    ])


class Rows:
    def __init__(self) -> None:
        self.rows: list[tuple] = []
        self.pending: list[tuple[str, decm.Context, Decimal]] = []
        self.dropped = 0
        self.seen: set[tuple] = set()

    def add(self, op: str, context: decm.Context, x: Decimal | str, member: bool = True) -> None:
        """Adds a row; `member=False` admits an operand outside the format
        (the decimal math functions take exact operands in an extended
        context, so 1E-1999996 is a legal decimal64 operand)."""
        x = Decimal(x)
        key = (op, context, str(x))
        if key in self.seen:
            return
        self.seen.add(key)
        if not x.is_finite() or x.is_zero():
            raise ValueError(f"{x} is not finite and nonzero")
        if member and context.python().create_decimal(x) != x:
            raise ValueError(f"{x} is not a member of {context}")
        if op in ("log2p1", "log10p1") and x <= -1:
            raise ValueError("log rows need x > -1")
        exact = exact_value(op, x)
        if exact is not None:
            expected, flags = round_exact(fraction_decimal(exact), context)
            self.rows.append((op, context, str(x), expected, flags))
        else:
            self.pending.append((op, context, x))

    def certify_pending(self) -> None:
        binary = decm.build_enclosure()
        candidates = [
            decm.Candidate(index, op, context, (x,), 0)
            for index, (op, context, x) in enumerate(self.pending)
        ]
        for offset in range(0, len(candidates), decm.CHUNK):
            chunk = candidates[offset : offset + decm.CHUNK]
            for candidate, enclosure in zip(chunk, decm.enclose(chunk, binary)):
                row = None if enclosure is None else decm.certify(candidate, enclosure)
                if row is None:
                    row = libmpdec_certify(candidate)
                if row is None:
                    self.dropped += 1
                    continue
                fields = row.split()
                self.rows.append((candidate.op, candidate.context, fields[8], fields[11], fields[12]))
        self.pending = []


def build() -> Rows:
    # Operand arithmetic below must be exact.
    work = decimal.getcontext()
    work.prec = 5000
    work.Emax = decimal.MAX_EMAX
    work.Emin = decimal.MIN_EMIN
    work.traps[decimal.Inexact] = True
    rows = Rows()
    # Exact integer cases of exp2m1/exp10m1 and their neighbours, the exact
    # cases of log2p1/log10p1 and theirs; the gate 4 (p + 2) of the exact path
    # and the values beyond it (exp2(n) delegation, the 10^n cluster).
    for precision in (1, 2, 3, 5, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        bound = 4 * (precision + 2)
        modes = ROUNDINGS if precision in (1, 7) else ("half_even", "floor", "05up")
        for mode in modes:
            c = ctx(spec, mode)
            ns = sorted({*range(1, 6), bound - 1, bound, bound + 1, 3 * bound})
            for n in ns:
                for op in ("exp2m1", "exp10m1"):
                    for value in (n, -n):
                        x = integer_member(value, precision)
                        if x is not None:
                            rows.add(op, c, x)
            # Neighbours n +- 10^-(p - digits(n)) at the precision.
            for n in (1, 2, 3, bound):
                for sign in (1, -1):
                    digits = len(str(n))
                    if digits >= precision:
                        continue
                    step = Decimal(1).scaleb(-(precision - digits))
                    for x in (sign * n + step, sign * n - step):
                        if x != 0:
                            rows.add("exp2m1", c, x)
                            rows.add("exp10m1", c, x)
            for k in (1, 2, 3, 4, 10, 20, 60, 100):
                for op, base in (("log2p1", 2), ("log10p1", 10)):
                    up = base**k - 1
                    if len(str(up)) <= precision:
                        rows.add(op, c, Decimal(up))
                        if len(str(up + 1)) <= precision:
                            rows.add(op, c, Decimal(up + 1))
                        if up > 1:
                            rows.add(op, c, Decimal(up - 1))
                    down = fraction_decimal(Fraction(1, base**k) - 1)
                    if len(down.as_tuple().digits) <= precision:
                        rows.add(op, c, down)
                        ulp = Decimal(1).scaleb(down.as_tuple().exponent)
                        rows.add(op, c, down + ulp)
                        if down - ulp > -1:
                            rows.add(op, c, down - ulp)
    # log2p1(2^k - 1) = k with k longer than the precision (rounded, possibly
    # at a midpoint): k = 15, 25, 35, 95, 105 at p = 1.
    for mode in ROUNDINGS:
        c = ctx((1, -999999, 999999, 0), mode)
        for k in (15, 25, 35, 95, 105, 250):
            rows.add("log2p1", ctx((80, -999999, 999999, 0), mode), Decimal(2**k - 1))
            rows.add("log10p1", ctx((k + 1, -999999, 999999, 0), mode), Decimal(10**k - 1))
            rows.add("log10p1", ctx((k + 1, -999999, 999999, 0), mode), fraction_decimal(Fraction(1, 10**k) - 1))
        for k in (15, 25, 35):
            rows.add("log2p1", ctx((k + 1, -999999, 999999, 0), mode), fraction_decimal(Fraction(1, 2**k) - 1))
    # The 10^n - 1 and 2^n - 1 clusters far beyond the gate, the overflow
    # edge and the coarse overflow guard, in the interchange formats.
    for spec, emax in ((DECIMAL32, 96), (DECIMAL64, 384), (DECIMAL128, 6144)):
        for mode in ROUNDINGS:
            c = ctx(spec, mode)
            p = spec[0]
            for n in (4 * (p + 2) + 1, emax - 1, emax, emax + 1, emax + 2, emax + 3):
                rows.add("exp10m1", c, Decimal(n))
            two = int((emax + 1) * 3.321928094887362)
            for n in (4 * (p + 2) + 1, two - 2, two - 1, two, two + 1, two + 2, two + 6):
                rows.add("exp2m1", c, Decimal(n))
            for x in (Decimal(emax) + Decimal("0.5"), Decimal(emax + 1) - Decimal(1).scaleb(-(p - len(str(emax + 1)))),
                      Decimal(two) + Decimal("0.25")):
                if len(x.as_tuple().digits) <= p:
                    rows.add("exp10m1", c, x)
                    rows.add("exp2m1", c, x)
    # Saturation towards -1 (non-integer x at and beyond -(p + 2), -(4p + 8)).
    for precision in (1, 2, 3, 7, 16, 34, 60):
        for mode in ROUNDINGS:
            c = ctx((precision, -999999, 999999, 0), mode)
            for t in (precision + 2, 4 * precision + 8):
                for delta in ("0.5", "-0.5", "3.25", "-0.25"):
                    x = -Decimal(t) + Decimal(delta)
                    if len(x.as_tuple().digits) <= precision and x < 0:
                        rows.add("exp10m1", c, x)
                        rows.add("exp2m1", c, x)
    # Tiny arguments down to 10^-1999996 (the least adjusted exponent of a
    # math operand), both signs, every mode, both tininess rules, the
    # interchange formats (whose range clips the result) and a wide context.
    # The wide context stays at +-3000: an in-range endpoint near 10^-3000 is
    # expanded exactly (doc/manual/verification.md), which is the cost of a row.
    for spec in (DECIMAL32, DECIMAL64, DECIMAL128, (16, -3000, 3000, 0)):
        for mode in ROUNDINGS:
            for tininess in ("b", "a"):
                c = ctx(spec, mode, tininess)
                etiny = spec[1] - spec[0] + 1
                ks = (3, spec[0] + 3, -spec[1], -etiny - 1, -etiny, -etiny + 1, 6200, 1999996)
                if tininess == "a":
                    ks = (-spec[1], -etiny, 1999990)
                for k in ks:
                    for mantissa in ("7", "-3"):
                        x = Decimal(f"{mantissa}E{-k}")
                        if x.adjusted() < -1999996:
                            continue
                        for op in OPS:
                            rows.add(op, c, x, member=False)
    # Tininess at the normal/subnormal boundary: f(x) just below 10^emin.
    for spec in (DECIMAL32, DECIMAL64, (5, -10, 10, 0)):
        p, emin = spec[0], spec[1]
        target = Decimal(1).scaleb(emin)
        for op, base, invert in (("exp2m1", 2, False), ("exp10m1", 10, False),
                                 ("log2p1", 2, True), ("log10p1", 10, True)):
            with decimal.localcontext() as local:
                local.prec = 60
                local.traps[decimal.Inexact] = False
                factor = Decimal(base).ln()
                centre = target * factor if invert else target / factor
            for ulps in (-1, 0, 1):
                with decimal.localcontext() as local:
                    local.prec = p
                    local.Emin = -10**8
                    local.traps[decimal.Inexact] = False
                    x = (+centre).next_plus() if ulps > 0 else +centre
                    for _ in range(abs(ulps)):
                        x = x.next_plus() if ulps > 0 else x.next_minus()
                for mode in ROUNDINGS:
                    for tininess in ("b", "a"):
                        rows.add(op, ctx(spec, mode, tininess), x, member=False)
                        rows.add(op, ctx(spec, mode, tininess), -x, member=False)
    # Precision sweep 1..60, 200, 220 with all modes cycling, bounded
    # (decimal-like) and unbounded ranges; generic operands of every scale.
    samples = ("0.7", "-0.3", "12.345678901234567890123", "-0.999999", "3.5E+2", "-0.5000000001E-7")
    for precision in (*range(1, 61), 200, 220):
        for index, text in enumerate(samples):
            mode = ROUNDINGS[(precision + index) % len(ROUNDINGS)]
            bounded = (precision, -(precision + 30), precision + 30, (precision + index) % 2)
            unbounded = (precision, -999999, 999999, 0)
            for spec in ((bounded, unbounded) if index % 2 == 0 else (bounded,)) if precision <= 60 else (unbounded,):
                c = ctx(spec, mode, "ab"[(precision + index) % 2])
                x = c.python().create_decimal(Decimal(text))
                if x.is_zero():
                    continue
                for op in OPS:
                    if op.startswith("log") and x <= -1:
                        continue
                    rows.add(op, c, x)
    # Long operands at precision 200: near -1 (log poles) and near integers.
    for precision in (200, 220):
        c = ctx((precision, -999999, 999999, 0), "half_even")
        for tail in (52, 150, precision):
            near = Decimal("-0." + "9" * tail)  # -1 + 10^-tail
            if len(near.as_tuple().digits) <= precision:
                rows.add("log2p1", c, near)
                rows.add("log10p1", c, near)
            above = Decimal("3." + "0" * (tail - 1) + "1")  # 3 + 10^-tail
            if len(above.as_tuple().digits) <= precision:
                rows.add("exp2m1", c, above)
                rows.add("exp10m1", c, above)
    # Log overflow in a context with a tiny e_max, and clamping of an exact
    # result (63 = 2^6 - 1 at p = 3, e_max = 1 must be written 630E-1).
    for mode in ROUNDINGS:
        for clamp in (0, 1):
            c = ctx((3, -2, 1, clamp), mode)
            for x in ("63", "7", "1E+3", "1E+30", "9.99E+1", "-0.875", "0.5"):
                for op in OPS:
                    xd = Decimal(x)
                    if c.python().create_decimal(xd) == xd:
                        rows.add(op, c, xd)
    rows.certify_pending()
    return rows


CHUNK_ROWS = 500  # rows per top-level array (a MoonBit text segment has a line limit)
ROW_TYPE = "(String, String, Int32, Int32, Int32, Bool, String, String, String, String)"


def render(rows: Rows) -> str:
    lines = [
        "///|",
        "// Generated by tools/generate_decimal_pm1_rows.py from exact rational arithmetic",
        "// and certified MPFR 4.2.2 enclosures rounded by libmpdec; do not edit.",
        "// Columns: op, rounding, precision, e_min, e_max, clamp, tininess, x,",
        "// expected (compared with total_order_compare), flags.",
    ]
    chunks = [rows.rows[i : i + CHUNK_ROWS] for i in range(0, len(rows.rows), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        # Functions, not top-level lets: a top-level value is constructed when
        # the test process starts, for every test of the package.
        lines += ["", "///|", f"fn pm1_rows_{index}() -> Array[", f"  {ROW_TYPE},", "] {", "  ["]
        for op, c, x, expected, flags in chunk:
            clamp = "true" if c.clamp else "false"
            lines.append(
                f'  ("{op}", "{c.rounding}", {c.precision}, {c.emin}, {c.emax}, {clamp}, "{c.tininess}", "{x}", "{expected}", "{flags}"),'
            )
        lines += ["  ]", "}"]
    lines += ["", "///|", f"fn pm1_rows() -> Array[{ROW_TYPE}] {{", "  let rows = []"]
    for index in range(len(chunks)):
        lines.append(f"  rows.append(pm1_rows_{index}())")
    lines += ["  rows", "}"]
    return "\n".join(lines) + "\n"


def normalized(text: str) -> str:
    compact = re.sub(r"\s+", "", text)
    return compact.replace(",)", ")").replace(",]", "]")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the committed table differs")
    args = parser.parse_args(argv)
    rows = build()
    text = render(rows)
    print(f"{len(rows.rows)} rows, {rows.dropped} candidates not certified", file=sys.stderr)
    if args.check:
        # `moon fmt` re-wraps long tuples; compare the tokens, not the layout.
        if normalized(OUTPUT.read_text(encoding="utf-8")) != normalized(text):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
