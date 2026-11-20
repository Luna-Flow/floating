#!/usr/bin/env python3
"""White-box rows for decimal rsqrt, compound and powr (issue #236, PR 2).

Writes `library/src/decimal/elementary_rcp_rows_wbtest.mbt`, a table of
`(op, rounding, precision, emin, emax, clamp, tininess, x, y, n, expected,
flags)` executed by `elementary_rcp_wbtest.mbt` on every backend. No row comes
from the library under test:

* exact results are computed with `fractions.Fraction`, written at the
  cohort member closest to the preferred exponent of IEEE 754-2019 9.2.2
  (-floor(Q(x)/2) for rSqrt, floor(n min(0, Q(x))) for compound,
  floor(y Q(x)) for powr) and rounded once by libmpdec (Python `decimal`);
* compound is never taken from MPFR (`mpfr_compound_si` 4.2.2 is wrong for
  n < 0 in the directed modes): inexact rows bracket the rational (1 + x)^n
  (`generate_mpfr_decimal_random.certify_exact_compound`);
* other inexact rows are the rounding of certified MPFR 4.2.2 enclosures
  (`tools/mpfr_decimal_enclosure.c`), kept only when both endpoints round to
  one result with one flag set and the result lies outside the enclosure.

Flags use the letters of `generate_decimal_pm1_rows.py`.

    python3 tools/generate_decimal_rcp_rows.py && moon fmt
    python3 tools/generate_decimal_rcp_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import sys
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

import generate_decimal_pm1_rows as pm1
import generate_mpfr_decimal_random as decm

sys.set_int_max_str_digits(0)
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/elementary_rcp_rows_wbtest.mbt"
ROUNDINGS = pm1.ROUNDINGS
DECIMAL32 = pm1.DECIMAL32
DECIMAL64 = pm1.DECIMAL64
DECIMAL128 = pm1.DECIMAL128
UNBOUNDED = (16, -999999, 999999, 0)
INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1
CHUNK_ROWS = 500
ROW_TYPE = "(String, String, Int32, Int32, Int32, Bool, String, String, String, Int32, String, String)"


def ctx(spec, rounding, tininess="b"):
    return pm1.ctx(spec, rounding, tininess)


def floor_div(a: int, b: int) -> int:
    return a // b


def nth_root(value: int, n: int) -> int | None:
    """The integer n-th root of value >= 0, if exact."""
    if value < 2:
        return value
    root = int(round(value ** (1.0 / n))) if value.bit_length() < 1000 else 1 << (value.bit_length() // n)
    # Newton from above.
    root = max(root, 1)
    while root**n < value:
        root *= 2
    while True:
        nxt = ((n - 1) * root + value // root ** (n - 1)) // n
        if nxt >= root:
            break
        root = nxt
    for candidate in (root - 1, root, root + 1):
        if candidate >= 0 and candidate**n == value:
            return candidate
    return None


def terminating(value: Fraction) -> bool:
    d = value.denominator
    for p in (2, 5):
        while d % p == 0:
            d //= p
    return d == 1


def exact_value(op: str, x: Decimal, y: Decimal | None, n: int) -> Fraction | None:
    if op == "rsqrt":
        if x <= 0:
            return None
        # x = c 10^e with e even (c an integer): 1/sqrt(x) = 10^(-e/2) / sqrt(c).
        _, digits, e = x.as_tuple()
        c = int("".join(map(str, digits)))
        if e % 2:
            c, e = c * 10, e - 1
        if c.bit_length() > 20000:
            return None
        root = nth_root(c, 2)
        if root is None:
            return None
        value = Fraction(1, root) * (Fraction(10) ** (-e // 2))
        return value if terminating(value) else None
    if op == "compound":
        if abs(n) > 20000 or abs(x.adjusted()) > 150:
            return None
        value = (1 + Fraction(x)) ** n
        return value if terminating(value) else None
    # powr, x > 0 finite, y finite
    assert y is not None
    if x == 1 and y.is_finite():
        return Fraction(1)
    if abs(x.adjusted()) > 400 or abs(y.adjusted()) > 12:
        return None
    q = Fraction(x)
    r = Fraction(y)
    if abs(r.numerator) > 20000 or r.denominator > 64:
        return None
    a, b = r.numerator, r.denominator
    rn, rd = nth_root(q.numerator, b), nth_root(q.denominator, b)
    if rn is None or rd is None:
        return None
    value = Fraction(rn, rd) ** a
    if len(str(value.numerator)) + len(str(value.denominator)) > 5000:
        return None
    return value if terminating(value) else None


def preferred_exponent(op: str, x: Decimal, y: Decimal | None, n: int) -> int:
    qx = x.as_tuple().exponent
    if op == "rsqrt":
        return -floor_div(qx, 2)
    if op == "compound":
        return n * min(0, qx)
    r = Fraction(y) * qx
    return r.numerator // r.denominator


def member(value: Fraction, preferred: int) -> Decimal:
    """The exact decimal `value` at the exponent closest to `preferred` that
    keeps it exact (padding zeros are left to the context rounding, which
    removes them, with Rounded, when they do not fit the precision)."""
    exact = pm1.fraction_decimal(value)
    sign, digits, exponent = exact.as_tuple()
    coefficient = int("".join(map(str, digits)))
    while coefficient and coefficient % 10 == 0:
        coefficient //= 10
        exponent += 1
    if preferred < exponent:
        coefficient *= 10 ** (exponent - preferred)
        exponent = preferred
    return Decimal((sign, tuple(int(c) for c in str(coefficient)), exponent))


class Rows:
    def __init__(self) -> None:
        self.rows: list[tuple] = []
        self.pending: list[tuple] = []
        self.seen: set = set()
        self.dropped = 0

    def add(self, op: str, context: decm.Context, x, y=None, n: int = 0) -> None:
        x = Decimal(x)
        y = None if y is None else Decimal(y)
        key = (op, context, str(x), str(y), n)
        if key in self.seen:
            return
        self.seen.add(key)
        if op == "compound" and x <= -1:
            raise ValueError("compound rows need x > -1")
        exact = exact_value(op, x, y, n)
        if exact is not None:
            expected, flags = pm1.round_exact(member(exact, preferred_exponent(op, x, y, n)), context)
            self.rows.append((op, context, str(x), "-" if y is None else str(y), n, expected, flags))
            return
        self.pending.append((op, context, x, y, n))

    def certify_pending(self) -> None:
        binary = decm.build_enclosure()
        candidates = []
        for index, (op, context, x, y, n) in enumerate(self.pending):
            operands = (x,) if y is None else (x, y)
            candidates.append(decm.Candidate(index, op, context, operands, n))
        compound = [c for c in candidates if c.op == "compound"]
        others = [c for c in candidates if c.op != "compound"]
        for candidate in compound:
            self.keep(candidate, decm.certify_exact_compound(candidate))
        for offset in range(0, len(others), decm.CHUNK):
            chunk = others[offset : offset + decm.CHUNK]
            for candidate, enclosure in zip(chunk, decm.enclose(chunk, binary)):
                self.keep(candidate, None if enclosure is None else decm.certify(candidate, enclosure))
        self.pending = []

    def keep(self, candidate, row) -> None:
        if row is None:
            self.dropped += 1
            return
        fields = row.split()
        self.rows.append((candidate.op, candidate.context, fields[8], fields[9], candidate.integer, fields[11], fields[12]))


def build() -> Rows:
    work = decimal.getcontext()
    work.prec = 5000
    work.Emax = decimal.MAX_EMAX
    work.Emin = decimal.MIN_EMIN
    work.traps[decimal.Inexact] = True
    rows = Rows()
    # rSqrt: exact cases (x = 2^(2i) 5^(2j) 10^(2k)) in several cohort
    # members, their neighbours, every mode at small precisions.
    exact_x = ["4", "4.0", "4.00", "400E-2", "0.040E+2", "16", "0.25", "0.0625", "25", "625", "6.25",
               "0.04", "1E+2", "1.00E+2", "100", "1", "1.0", "1E-6", "1E+6", "0.0016", "390625", "1.5625E-2",
               str(4**10), str(4**20), str(25**8), str(Decimal(4) ** 30), "2.56", "1.6E+3"]
    for precision in (1, 2, 3, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        modes = ROUNDINGS if precision in (1, 3, 16) else ("half_even", "floor", "05up")
        for mode in modes:
            c = ctx(spec, mode)
            for text in exact_x:
                x = Decimal(text)
                if len(x.as_tuple().digits) <= max(precision, 40):
                    rows.add("rsqrt", c, x)
                    if len(x.as_tuple().digits) < precision:
                        ulp = Decimal((0, (1,), x.adjusted() - precision + 1))
                        rows.add("rsqrt", c, x + ulp)
                        rows.add("rsqrt", c, x - ulp)
    # Powers of four beyond p + 1 result digits (left to the enclosure).
    for mode in ROUNDINGS:
        for precision in (3, 7):
            c = ctx((precision, -999999, 999999, 0), mode)
            for a in (8, 9, 10, 12, 20):
                rows.add("rsqrt", c, Decimal(4**a))
                rows.add("rsqrt", c, Decimal(25**a))
    # rSqrt range: results near the overflow and underflow limits of the
    # interchange formats and operands at the operand limits.
    for spec in (DECIMAL32, DECIMAL64, DECIMAL128):
        p, emin, emax = spec[0], spec[1], spec[2]
        etiny = emin - p + 1
        for mode in ROUNDINGS:
            for tininess in ("b", "a"):
                c = ctx(spec, mode, tininess)
                for k in (-2 * emax - 2, -2 * emax - 1, -2 * emax, -2 * emax + 1, -2 * emin, -2 * emin + 1,
                          -2 * emin + 2, -2 * etiny, -2 * etiny + 1, -2 * etiny + 4, -2 * etiny - 2):
                    for mantissa in ("1", "3", "9.99"):
                        rows.add("rsqrt", c, Decimal(f"{mantissa}E{k}"))
                for text in ("1E-1999997", "7.5E-1999990", "1E+999999", "2.5E+999998"):
                    rows.add("rsqrt", c, Decimal(text))
    # rSqrt precision sweep.
    samples = ("2", "3", "0.5", "12.345678901234567890123", "7E-301", "9.9999E+250", "0.999999999")
    for precision in (*range(1, 61), 200, 220):
        for index, text in enumerate(samples):
            mode = ROUNDINGS[(precision + index) % len(ROUNDINGS)]
            spec = (precision, -(precision + 400), precision + 400, (precision + index) % 2)
            if index % 2:
                spec = (precision, -999999, 999999, 0)
            c = ctx(spec, mode, "ab"[(precision + index) % 2])
            x = c.python().create_decimal(Decimal(text))
            rows.add("rsqrt", c, x)
    # compound: exact cases and cohorts, neighbours, large |n|, x near -1,
    # tiny x (the anchored path), overflow and underflow.
    for precision in (1, 2, 3, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        modes = ROUNDINGS if precision in (1, 3, 16) else ("half_even", "floor", "05up")
        for mode in modes:
            c = ctx(spec, mode)
            for text in ("0.05", "0.1", "0.10", "-0.5", "1", "2", "-0.75", "0.5", "1.5", "-0.25", "9", "0.01", "1E+1"):
                for n in (1, 2, 3, 7, 10, -1, -2, -3, -7, 20, -20):
                    rows.add("compound", c, Decimal(text), None, n)
            for text in ("0.0500000001", "-0.4999999", "1E-20", "-1E-20", "3E-12", "-0.999999", "1E+20"):
                for n in (1, 3, -3, 1000, -1000, INT32_MAX, INT32_MIN, 123456789):
                    rows.add("compound", c, Decimal(text), None, n)
    for spec in (DECIMAL32, DECIMAL64, DECIMAL128, (16, -3000, 3000, 0)):
        for mode in ROUNDINGS:
            for tininess in ("b", "a"):
                c = ctx(spec, mode, tininess)
                for text in ("1E-30", "-1E-30", "7E-400", "-3E-6200", "1E-1999990", "-9.9E-1999997"):
                    for n in (1, -1, 7, -7, INT32_MAX, INT32_MIN):
                        rows.add("compound", c, Decimal(text), None, n)
                p = spec[0]
                for text, n in (("1.5", 600), ("1.5", -600), ("0.5", 1300), ("-0.5", 1300), ("-0.5", -1300),
                                ("9", spec[2]), ("9", -(spec[2] - spec[1]) - 3), ("0.0001", 2000000),
                                ("-0.0001", 9000000), ("1E-5", -100000000)):
                    rows.add("compound", c, Decimal(text), None, n)
    # powr: exact cases with their preferred exponents, the pow domain, and
    # inexact rows.
    # Exact powers of ten with a non-integer exponent ((1E-300)^1.2 = 1E-360,
    # issue #349) are included. Not here: 1E+4^0.25, where pow raises the
    # GDA-only Rounded flag for an exact result at its preferred exponent.
    pairs = [("4", "0.5"), ("4.00", "0.5"), ("32", "0.2"), ("0.25", "-0.5"), ("1.00", "2"), ("1.00", "-2"),
             ("1", "1E+10"), ("1.0", "0.5"), ("8", "1.5"), ("2", "10"), ("10", "-3"),
             ("0.0016", "0.25"), ("2", "0.5"), ("10", "1.5"), ("0.5", "-7.25"), ("3", "2.5"), ("2E-300", "1.2"),
             ("9.99E+200", "1.9"), ("7", "-123.456"), ("1.0000001", "1E+7"), ("2.5", "-2"),
             ("1E-300", "1.2"), ("1E-5", "1.2"), ("1E-5", "-1.2"), ("1E+10", "0.5"), ("1E-4", "-0.25"),
             ("1000E-8", "1.2")]
    for precision in (1, 3, 7, 16, 34):
        spec = (precision, -999999, 999999, 0)
        for mode in ROUNDINGS if precision in (1, 16) else ("half_even", "ceiling", "05up"):
            c = ctx(spec, mode)
            for a, b in pairs:
                x = Decimal(a)
                if len(x.as_tuple().digits) <= precision:
                    rows.add("powr", c, x, Decimal(b), 0)
    for spec in (DECIMAL32, DECIMAL64, DECIMAL128):
        for mode in ROUNDINGS:
            for tininess in ("b", "a"):
                c = ctx(spec, mode, tininess)
                emax, emin = spec[2], spec[1]
                for a, b in (("10", str(emax)), ("10", str(emax + 0.5)), ("2", str(int((emax + 1) * 3.3219))),
                             ("0.1", str(-emin + 0.5)), ("10", str(emin - spec[0] + 0.25)), ("10", str(emin - 0.5))):
                    rows.add("powr", c, Decimal(a), Decimal(b), 0)
    rows.certify_pending()
    return rows


def render(rows: Rows) -> str:
    lines = [
        "///|",
        "// Generated by tools/generate_decimal_rcp_rows.py from exact rational arithmetic",
        "// and certified MPFR 4.2.2 enclosures rounded by libmpdec; do not edit.",
        "// Columns: op, rounding, precision, e_min, e_max, clamp, tininess, x, y, n,",
        "// expected (compared with total_order_compare), flags.",
    ]
    chunks = [rows.rows[i : i + CHUNK_ROWS] for i in range(0, len(rows.rows), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        # Functions, not top-level lets: the initializer of every top-level
        # value shares one Wasm function, whose local count Wasm limits.
        lines += ["", "///|", f"fn rcp_rows_{index}() -> Array[", f"  {ROW_TYPE},", "] {", "  ["]
        for op, c, x, y, n, expected, flags in chunk:
            clamp = "true" if c.clamp else "false"
            lines.append(
                f'  ("{op}", "{c.rounding}", {c.precision}, {c.emin}, {c.emax}, {clamp}, "{c.tininess}", "{x}", "{y}", {n}, "{expected}", "{flags}"),'
            )
        lines += ["  ]", "}"]
    lines += ["", "///|", f"fn rcp_rows() -> Array[{ROW_TYPE}] {{", "  let rows = []"]
    for index in range(len(chunks)):
        lines.append(f"  rows.append(rcp_rows_{index}())")
    lines += ["  rows", "}"]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the committed table differs")
    args = parser.parse_args(argv)
    rows = build()
    text = render(rows)
    print(f"{len(rows.rows)} rows, {rows.dropped} candidates not certified", file=sys.stderr)
    if args.check:
        if pm1.normalized(OUTPUT.read_text(encoding="utf-8")) != pm1.normalized(text):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
