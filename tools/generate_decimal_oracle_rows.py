#!/usr/bin/env python3
"""Rows that replace non-independent oracles in the `decimal` test blocks (round 2 of #438).

Writes `library/src/decimal/oracle_repair_rows_wbtest.mbt`, tables only:

* `gap_446_rows`: plain `+` and `-` of two operands of 34 digits whose exponents are far apart
  (issue 446), expected text from CPython `decimal` (libmpdec) in the plain working context
  (precision 34, half-even, no clamp).
* `sticky_446_rows`: the sum of a 34-digit-or-shorter high operand and a far smaller one (the sticky
  absorption of issue 446), in the loop order of the test, from CPython `decimal`.
* `to_binary_grid_rows`: `Decimal::to_binary` over a grid of coefficients and exponents, as `(text, precision,
  mode, C, k)` with value C * 2^k (the rounding of `generate_decimal_to_bin_rows.round_to_bits`).
* `from_binary_rows`, `from_binary_mode_rows`, `from_binary_boundary_rows`: `Decimal::from_binary` of the dyadic
  values of issue 467 rounded to p digits (exact integer arithmetic, then CPython `decimal` `plus`).
* `exact_division_rows`: dividend, divisor, context and the exact quotient with its flags, or `none` for a
  quotient without a finite decimal expansion (`math.gcd`, CPython `divide`).
* `pi_ref_lo_hex` and `pi_ref_hi_hex`: pi by Machin's formula in Python integers, 2048 fractional bits
  (`tools/interval_pi_oracle.py`), the enclosure `[RD(pi), RU(pi)]` after rounding to p bits.
* `pm1_tiny_rows`: `(operation, precision, x, expected)`, tiny arguments of exp2m1, exp10m1, log2p1 and
  log10p1 placed next to a rounding midpoint, from series at 150 digits in CPython `decimal`.
* `ball_rows`: `(text, precision, lower C, lower k, upper C, upper k)`, the two directed
  roundings of the exact decimal value to `precision` bits, as the signed integer `C` with
  value `C * 2^k`, by exact integer arithmetic (`generate_decimal_to_bin_rows.round_to_bits`).
* `word_divisor_rows`: `(numerator, divisor, terminates, remainder)`: whether `numerator / divisor`
  has a finite decimal expansion and the remainder of the integer division, from Python integers
  (`math.gcd`, `%`).

    python3 tools/generate_decimal_oracle_rows.py > /dev/null && moon fmt   # writes the file
    python3 tools/generate_decimal_oracle_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import math
import random
import sys
from pathlib import Path

import generate_decimal_to_bin_rows as to_bin
import interval_pi_oracle

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/oracle_repair_rows_wbtest.mbt"
PRECISION = 34
EMAX = 2147483646
TINY = -2147483645
WORD_SEED = 0x2545F4914F6CDD1D
DIVISOR_LIMIT = 3000
LIMB_BOUND_DIVISORS = (999999999, 999999937, 536870912, 1953125, 500000000)

# (a coefficient, a exponent, b coefficient, b exponent), the shapes of the test of issue 446
GAP_CASES: tuple[tuple[int, int, int, int], ...] = (
    (1, 900_000, 1, -900_000),
    (1, 900_000, -1, -900_000),
    (-1, 900_000, 1, -900_000),
    (9999999999999999999999999999999999, 500_000, 1, -400_000),
    (9999999999999999999999999999999999, 500_000, -1, -400_000),
    (5, 0, 3, -700_000),
    (5, 0, -3, -700_000),
    (12345, -10, 6, 400_000),
)
BALL_TEXTS = (
    "0.1", "-0.1", "3E-1000", "-7.5E-5000", "1.5E+3000", "123456789E-9",
    "9999999999999999999999999999999999E-6176", "-3E-30000", "5E+10", "0.0003",
)
BALL_PRECISIONS = (53, 128, 200, 640)


STICKY_PRECISIONS = (1, 2, 5, 34)
STICKY_HIGH = (1, 9, 12345, 5000000000000, 9999999999999999999999999999999999, 1000000000000000000000000000000000)
STICKY_LOW = (1, 5, 7, 99)


def sticky_gaps(precision: int) -> tuple[int, ...]:
    return (precision - 1, precision, precision + 1, precision + 2, precision + 3, precision + 7, precision + 40, 5000)


def plain_context() -> decimal.Context:
    return decimal.Context(
        prec=PRECISION,
        rounding=decimal.ROUND_HALF_EVEN,
        Emax=EMAX,
        Emin=TINY + PRECISION - 1,
        clamp=0,
        traps=[],
    )


def library_text(value: decimal.Decimal) -> str:
    """CPython's text, with the special values spelled as in `Decimal::to_string`."""
    text = str(value)
    return {"Infinity": "inf", "-Infinity": "-inf", "NaN": "nan"}.get(text, text)


def gap_rows() -> list[tuple[str, str]]:
    context = plain_context()
    rows = []
    for a_coeff, a_exp, b_coeff, b_exp in GAP_CASES:
        a = decimal.Decimal(f"{a_coeff}E{a_exp}")
        b = decimal.Decimal(f"{b_coeff}E{b_exp}")
        rows.append((library_text(context.add(a, b)), library_text(context.subtract(a, b))))
    return rows


def sticky_rows() -> list[str]:
    """Expected text of `high + low` for the loop order of the sticky absorption test of issue 446:
    precision, high coefficient, low coefficient, gap, high negative, low negative (innermost).
    Operands are rounded to `precision` digits (half-even), as `Decimal::make` does, and the sum is
    rounded once in a context of that precision."""
    rows = []
    for precision in STICKY_PRECISIONS:
        context = decimal.Context(
            prec=precision, rounding=decimal.ROUND_HALF_EVEN, Emax=EMAX, Emin=-EMAX, clamp=0, traps=[]
        )
        for high in STICKY_HIGH:
            for low in STICKY_LOW:
                for gap in sticky_gaps(precision):
                    for high_negative in (False, True):
                        for low_negative in (False, True):
                            exponent = -gap - len(str(low)) - len(str(high))
                            a = context.create_decimal(f"{'-' if high_negative else ''}{high}E0")
                            b = context.create_decimal(f"{'-' if low_negative else ''}{low}E{exponent}")
                            rows.append(library_text(context.add(a, b)))
    return rows


PM1_PRECISION = 3
PM1_ADJUSTED = (-16, -20, -24, -30, -40)
PM1_OPERATIONS = ("exp2m1", "exp10m1", "log2p1", "log10p1")
PM1_WORK = decimal.Context(prec=160, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
PM1_SIGNIFICANT = 60


def pm1_value(operation: str, x: decimal.Decimal) -> decimal.Decimal:
    """f(x) for tiny x to about 150 digits: the series of expm1 and log1p, with the slope of the base."""
    work = PM1_WORK
    base = decimal.Decimal(2 if operation.endswith("2m1") or operation == "log2p1" else 10)
    ln_base = work.ln(base)
    if operation.startswith("exp"):
        y = work.multiply(x, ln_base)
        total = decimal.Decimal(0)
        term = decimal.Decimal(1)
        for k in range(1, 12):
            term = work.divide(work.multiply(term, y), decimal.Decimal(k))
            total = work.add(total, term)
        return total
    total = decimal.Decimal(0)
    power = decimal.Decimal(1)
    for k in range(1, 12):
        power = work.multiply(power, x)
        term = work.divide(power, decimal.Decimal(k))
        total = work.add(total, term if k % 2 == 1 else -term)
    return work.divide(total, ln_base)


def pm1_slope(operation: str) -> decimal.Decimal:
    base = decimal.Decimal(2 if operation.endswith("2m1") or operation == "log2p1" else 10)
    ln_base = PM1_WORK.ln(base)
    return ln_base if operation.startswith("exp") else PM1_WORK.divide(decimal.Decimal(1), ln_base)


def pm1_rows() -> list[tuple[str, int, str, str]]:
    """Tiny arguments whose first-order value c x lies a few 10^-20 relative below or above a midpoint of
    the p-digit grid, so that the relative correction d of f(x) = c x (1 + d) (d about +c x / 2 for the
    exponentials, -x / 2 for the logarithms) puts the true value on the other side of the midpoint. A
    shortcut whose enclosure of the factor (1 +- 2^k) is narrower than |d| rounds such a value wrongly;
    the correct bound (2^k >= 4 |x|) cannot decide it. Expected value: f(x) to 150 digits, rounded once
    half-even to PM1_PRECISION digits."""
    rounding = decimal.Context(prec=PM1_PRECISION, rounding=decimal.ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
    rows = []
    for operation in PM1_OPERATIONS:
        slope = pm1_slope(operation)
        for adjusted in PM1_ADJUSTED:
            # the midpoint 1.235 x 10^(adjusted) between the grid points 1.23 and 1.24 (3 digits)
            midpoint = decimal.Decimal(f"1.235E{adjusted}")
            x0 = PM1_WORK.divide(midpoint, slope)
            # d = y / 2 with y = c x for expm1 (y = ln b x), d = -x / 2 for log1p
            correction = PM1_WORK.divide(midpoint if operation.startswith("exp") else x0, decimal.Decimal(2))
            direction = 1 if operation.startswith("exp") else -1
            # c x = M (1 - direction |d| / 2): f(x) = c x (1 + direction |d|) crosses M by |d| / 2
            offset = PM1_WORK.divide(PM1_WORK.multiply(decimal.Decimal(direction), correction), decimal.Decimal(2))
            first_order = PM1_WORK.multiply(midpoint, PM1_WORK.subtract(decimal.Decimal(1), offset))
            x_exact = PM1_WORK.divide(first_order, slope)
            x_text = format(PM1_WORK.create_decimal(x_exact).quantize(decimal.Decimal(1).scaleb(x_exact.adjusted() - PM1_SIGNIFICANT + 1), context=PM1_WORK), "f")
            x = decimal.Decimal(x_text)
            rows.append((operation, PM1_PRECISION, str(x), library_text(rounding.plus(pm1_value(operation, x)))))
    return rows


def exact_parts(text: str) -> tuple[bool, int, int]:
    """(negative, numerator, denominator) of the exact decimal value of `text`."""
    value = decimal.Decimal(text)
    sign, digits, exponent = value.as_tuple()
    coefficient = int("".join(map(str, digits)))
    numerator, denominator = to_bin.value_parts(coefficient, int(exponent))
    return bool(sign), numerator, denominator


def ball_rows() -> list[tuple[str, int, int, int, int, int]]:
    rows = []
    for text in BALL_TEXTS:
        negative, numerator, denominator = exact_parts(text)
        for precision in BALL_PRECISIONS:
            lo_c, lo_k = to_bin.round_to_bits(numerator, denominator, precision, negative, "TowardNegative")
            hi_c, hi_k = to_bin.round_to_bits(numerator, denominator, precision, negative, "TowardPositive")
            rows.append((text, precision, lo_c, lo_k, hi_c, hi_k))
    return rows


OUTWARD_TEXTS = (
    "1E-30", "-1E-30", "123.456E-400", "-7.25E-3000", "9.99E+300", "-3.5E+250", "0.1",
    "-0.1", "1E-5000", "2E+5000",
)
OUTWARD_DIGITS = (8, 32, 60)
OUTWARD_BITS = 200
OUTWARD_WIDE = 80


def exact_dyadic(coefficient: int, exponent2: int) -> decimal.Decimal:
    """The exact decimal value of coefficient * 2^exponent2 (any sign), in a context wide enough to hold it."""
    wide = decimal.Context(prec=20000, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
    if exponent2 >= 0:
        return wide.create_decimal(coefficient << exponent2)
    return wide.divide(wide.create_decimal(coefficient * 5 ** (-exponent2)), wide.create_decimal(10 ** (-exponent2)))


def directed(value: decimal.Decimal, digits: int, rounding: str) -> decimal.Decimal:
    context = decimal.Context(prec=digits, rounding=rounding, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
    return context.plus(value)


def outward_rows() -> list[tuple[str, int, str, str, str, str]]:
    """(text, digits, lo_min, lo_max, hi_min, hi_max) for the 200-bit directed binary endpoints of the text:
    the outward endpoint `lo` (rounded down to about `digits` digits) satisfies lo_min <= lo <= lo_max, and
    hi_min <= hi <= hi_max for the upper one. lo_max is the exact lower endpoint rounded down to 80 digits (lo
    is on a coarser grid and not above the exact endpoint), lo_min is the exact one rounded down to `digits`
    digits and one unit of that grid further (the trimming error is far below one unit); hi likewise."""
    rows = []
    wide = decimal.Context(prec=20000, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
    for text in OUTWARD_TEXTS:
        negative, numerator, denominator = exact_parts(text)
        lo_c, lo_k = to_bin.round_to_bits(numerator, denominator, OUTWARD_BITS, negative, "TowardNegative")
        hi_c, hi_k = to_bin.round_to_bits(numerator, denominator, OUTWARD_BITS, negative, "TowardPositive")
        lower = exact_dyadic(lo_c, lo_k)
        upper = exact_dyadic(hi_c, hi_k)
        for digits in OUTWARD_DIGITS:
            floor_d = directed(lower, digits, decimal.ROUND_FLOOR)
            ceil_d = directed(upper, digits, decimal.ROUND_CEILING)
            lo_min = wide.subtract(floor_d, wide.create_decimal((0, (1,), floor_d.as_tuple().exponent)))
            hi_max = wide.add(ceil_d, wide.create_decimal((0, (1,), ceil_d.as_tuple().exponent)))
            lo_max = directed(lower, OUTWARD_WIDE, decimal.ROUND_FLOOR)
            hi_min = directed(upper, OUTWARD_WIDE, decimal.ROUND_CEILING)
            rows.append(tuple([text, digits] + [library_text(v) for v in (lo_min, lo_max, hi_min, hi_max)]))
    return rows


def outward_binary_rows() -> list[tuple[str, int, int, int, int]]:
    """(text, lower C, lower k, upper C, upper k): the 200-bit directed endpoints of each text."""
    rows = []
    for text in OUTWARD_TEXTS:
        negative, numerator, denominator = exact_parts(text)
        lo_c, lo_k = to_bin.round_to_bits(numerator, denominator, OUTWARD_BITS, negative, "TowardNegative")
        hi_c, hi_k = to_bin.round_to_bits(numerator, denominator, OUTWARD_BITS, negative, "TowardPositive")
        rows.append((text, lo_c, lo_k, hi_c, hi_k))
    return rows


def prime_to_ten(divisor: int) -> int:
    while divisor % 2 == 0:
        divisor //= 2
    while divisor % 5 == 0:
        divisor //= 5
    return divisor


def terminates(numerator: int, divisor: int) -> bool:
    """`numerator / divisor` has a finite decimal expansion: the reduced denominator is 2^a 5^b."""
    return prime_to_ten(divisor // math.gcd(numerator, divisor)) == 1


def digits_text(generator: random.Random, count: int) -> str:
    """A number of `count` digits; runs of nines and zeros make carries and cancellations frequent."""
    style = generator.randrange(5)
    out = []
    for index in range(count):
        if style == 0:
            digit = 9
        elif style == 1 and generator.randrange(3) != 0:
            digit = 0
        else:
            digit = generator.randrange(10)
        out.append("1" if index == 0 and digit == 0 else str(digit))
    return "".join(out)


def word_rows() -> list[tuple[str, int, bool, int]]:
    generator = random.Random(WORD_SEED)
    counts = (1, 5, 9, 10, 18, 19, 30, 45)
    rows = []
    for divisor in range(1, DIVISOR_LIMIT):
        count = counts[divisor % len(counts)]
        numerator = int(digits_text(generator, count))
        if divisor % 2 == 0:
            # a multiple of the part prime to 10: the quotient terminates
            numerator *= prime_to_ten(divisor)
        rows.append((str(numerator), divisor, terminates(numerator, divisor), numerator % divisor))
    for divisor in LIMB_BOUND_DIVISORS:
        numerator = int(digits_text(generator, 40))
        rows.append((str(numerator), divisor, terminates(numerator, divisor), numerator % divisor))
    return rows


def pi_hex_bounds() -> tuple[str, str]:
    """pi by Machin's formula in Python integers (tools/interval_pi_oracle.py): the two hexadecimal bounds
    with 2048 fractional bits, outward by a margin far above the series error; `[RD(lo), RU(hi)]` at p bits is
    `[RD(pi), RU(pi)]` for every p from 2 to 2048 (proved by `interval_pi_oracle.check_rounding_claim`)."""
    lo, hi = interval_pi_oracle.pi_bounds()
    interval_pi_oracle.check_rounding_claim(lo, hi)
    fraction = interval_pi_oracle.FRACTION_BITS
    return f"0x{lo:x}p-{fraction}", f"0x{hi:x}p-{fraction}"


PYTHON_MODES = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "half_up": decimal.ROUND_HALF_UP,
    "down": decimal.ROUND_DOWN,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
}
# (base mantissa, base exponent2) of the values of the issue 467 test: small integers and doubles
FROM_BINARY_BASES: tuple[tuple[int, int], ...] = (
    (1, 0), (3, 0), (5, 0), (7, 0), (10, 0), (100, 0), (255, 0), (12345, 0),
    (4503599627370497, 0), (3602879701896397, -55), (6004799503160661, -54), (4768371582031250, 21),
    (8264081201172544, -26), (1, -1), (9007199254740991, 0),
)
FROM_BINARY_SHIFTS = (-6000, -5000, -3000, -2049, -1100, -1025, -1024, -1000, -100, -60, -1, 0, 1, 60, 100, 1000, 1024, 1025, 1100, 2049, 3000, 5000)
FROM_BINARY_PRECISIONS = (1, 2, 3, 5, 9, 17, 34, 100)
FROM_BINARY_MODES = tuple(PYTHON_MODES)
BOUNDARY_KEPT = ("1", "2", "12", "13", "12345", "12346", "99999999999999999",
                 "1234567890123456789012345678901234", "1234567890123456789012345678901235")
BOUNDARY_TAILS = (0, 499, 500, 501)


def exact_binary_decimal(mantissa: int, exponent2: int) -> decimal.Decimal:
    """The exact decimal value of mantissa * 2^exponent2 at the least exponent that is at most 0:
    the integer for a non-negative exponent, else mantissa * 5^k / 10^k with the trailing zeros of the
    coefficient removed while the exponent is negative (the expansion of `from_binary`)."""
    if exponent2 >= 0:
        return decimal.Decimal(mantissa << exponent2)
    k = -exponent2
    coefficient = abs(mantissa) * 5**k
    exponent = -k
    while exponent < 0 and coefficient % 10 == 0:
        coefficient //= 10
        exponent += 1
    return decimal.Decimal((1 if mantissa < 0 else 0, tuple(map(int, str(coefficient))), exponent))


def round_decimal(value: decimal.Decimal, precision: int, mode: str) -> str:
    context = decimal.Context(prec=precision, rounding=PYTHON_MODES[mode], Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
    return library_text(context.plus(value))


def from_binary_rows(rotate_modes: bool) -> list[tuple[str, int, bool, int, str, str]]:
    """(mantissa, exponent2, negative, precision, mode, expected) for every base, shift and sign; the
    precision and, when `rotate_modes`, the mode rotate with the row index, otherwise half-even."""
    rows = []
    index = 0
    for mantissa, base_exponent in FROM_BINARY_BASES:
        for shift in FROM_BINARY_SHIFTS:
            for negative in (False, True):
                precision = FROM_BINARY_PRECISIONS[index % len(FROM_BINARY_PRECISIONS)]
                mode = FROM_BINARY_MODES[(index // 2) % len(FROM_BINARY_MODES)] if rotate_modes else "half_even"
                value = exact_binary_decimal(-mantissa if negative else mantissa, base_exponent + shift)
                rows.append((str(mantissa), base_exponent + shift, negative, precision, mode, round_decimal(value, precision, mode)))
                index += 1
    return rows


def boundary_rows() -> list[str]:
    """Expected text of T * 10^1100 (T = kept * 1000 + tail) rounded to the digits of `kept`, in the loop
    order of the test: kept, tail, sign, mode (five modes, in `FROM_BINARY_BOUNDARY_MODES` order)."""
    modes = ("half_even", "half_up", "down", "ceiling", "floor")
    rows = []
    for kept in BOUNDARY_KEPT:
        precision = len(kept)
        for tail in BOUNDARY_TAILS:
            for negative in (False, True):
                value = decimal.Decimal((1 if negative else 0, tuple(map(int, str(int(kept) * 1000 + tail))), 1100))
                for mode in modes:
                    rows.append(round_decimal(value, precision, mode))
    return rows


DIVISION_CASES = 120
DIVISION_SEED = 0x9E3779B97F4A7C15
DIVISION_E_MAX = 999999
DIVISION_SPECS = (
    (7, 96, "half_even", True), (16, 384, "half_even", True), (34, 6144, "half_even", True),
) + tuple(
    (p, DIVISION_E_MAX, mode, False)
    for p in (1, 2, 3, 7, 16, 34, 60)
    for mode in ("half_even", "half_up", "ceiling", "floor", "down")
)


def exact_division_rows() -> list[tuple[int, int, str, bool, str, str, str]]:
    """(precision, e_max, rounding, clamp, dividend, divisor, expected): `none` when the quotient has no
    finite decimal expansion, else the rounded quotient and flags (as the plain rows)."""
    generator = random.Random(DIVISION_SEED)
    rows = []
    for iteration in range(DIVISION_CASES):
        precision, e_max, mode, clamp = DIVISION_SPECS[iteration % len(DIVISION_SPECS)]
        part = int(digits_text(generator, generator.randint(1, 30)))
        twos = generator.choice((0, 1, 3, 8, 9, 12, 30))
        fives = generator.choice((0, 1, 5, 8, 9, 14))
        divisor = part * 2**twos * 5**fives
        exponent = generator.randint(-20, 20)
        dividend_digits = int(digits_text(generator, generator.randint(1, 60)))
        sign = "-" if generator.randrange(2) == 0 else ""
        dividends = (
            f"{sign}{dividend_digits}E{exponent}",
            f"{sign}{dividend_digits * part}E{exponent}",
            f"{sign}{dividend_digits * divisor}E{exponent}",
            f"{divisor}",
            "1",
        )
        for dividend in dividends:
            rows.append((precision, e_max, mode, clamp, dividend, str(divisor), division_expected(precision, e_max, mode, clamp, dividend, divisor)))
    return rows


def division_expected(precision: int, e_max: int, mode: str, clamp: bool, dividend: str, divisor: int) -> str:
    value = decimal.Decimal(dividend)
    sign, digits, exponent = value.as_tuple()
    numerator = int("".join(map(str, digits)))
    reduced = divisor // math.gcd(numerator, divisor)
    for prime in (2, 5):
        while reduced % prime == 0:
            reduced //= prime
    if reduced != 1:
        return "none"
    context = decimal.Context(
        prec=precision, rounding=PYTHON_MODES[mode], Emax=e_max, Emin=1 - e_max, clamp=1 if clamp else 0, traps=[]
    )
    quotient = context.divide(value, decimal.Decimal(divisor))
    flags = "".join(
        letter if context.flags[signal] else "."
        for signal, letter in ((decimal.Inexact, "x"), (decimal.Underflow, "u"), (decimal.Overflow, "o"))
    )
    return f"{library_text(quotient)} {flags}"


GRID_COEFFICIENTS = (1, 3, 7, 9999999, 1234567, 9007199254740993, 5000000000000000,
                     1000000000000000000000000000000001, 9999999999999999999999999999999999,
                     1000000000000000000000000000000000, 4503599627370497)
GRID_EXPONENTS = (0, 1, 2, 5, 22, 23, -1, -2, -5, -22, -23, -100, -383, -1000, -4095, -4096, -4097,
                  -6176, 100, 4096, 4097, 6144, -20000, -60000, -150000)
GRID_PRECISIONS = (1, 2, 24, 53, 64, 113, 128, 200, 600)


def grid_rows() -> list[tuple[str, int, str, str, int]]:
    """(text, precision, mode, coefficient C, exponent2 k) of `Decimal::to_binary`, value C * 2^k, over
    coefficients, exponents (around the power caches at 4096 and the huge ones), both signs; each value gets
    two (precision, mode) pairs rotating with the row index. Exact integer arithmetic, no library."""
    rows = []
    index = 0
    for coefficient in GRID_COEFFICIENTS:
        for exponent in GRID_EXPONENTS:
            for negative in (False, True):
                for offset in range(2):
                    precision = GRID_PRECISIONS[(index * 2 + offset) % len(GRID_PRECISIONS)]
                    if abs(exponent) > 10000:
                        precision = (53, 128)[offset % 2]
                    mode = to_bin.GRID_MODES[(index + offset * 2) % len(to_bin.GRID_MODES)]
                    n, d = to_bin.value_parts(coefficient, exponent)
                    c, k = to_bin.round_to_bits(n, d, precision, negative, mode)
                    text = ("-" if negative else "") + f"{coefficient}E{exponent}"
                    rows.append((text, precision, mode, str(c), k))
                index += 1
    return rows


CHUNK_ROWS = 100


def table_lines(name: str, row_type: str, rows: list[str]) -> list[str]:
    """A table as chunked functions plus one function that joins them: a top-level `let` of
    many tuples makes the module initialiser of a wasm test build exceed the limit on locals."""
    out: list[str] = []
    chunks = [rows[i : i + CHUNK_ROWS] for i in range(0, len(rows), CHUNK_ROWS)]
    for index, chunk in enumerate(chunks):
        out += ["///|", f"fn {name}_{index}() -> Array[{row_type}] {{", "  ["]
        out += [f"    {row}" for row in chunk]
        out += ["  ]", "}", ""]
    out += ["///|", f"fn {name}() -> Array[{row_type}] {{", f"  let rows : Array[{row_type}] = []"]
    out += [f"  for row in {name}_{index}() {{ rows.push(row) }}" for index in range(len(chunks))]
    out += ["  rows", "}", ""]
    return out


def quote(text: str) -> str:
    return '"' + text + '"'


def b(flag: bool) -> str:
    return "true" if flag else "false"


def render() -> str:
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_oracle_rows.py (CPython `decimal`/libmpdec, Python integers, `math.gcd` and Machin's formula)",
        "// input: issue 446 operand pairs and sticky absorption sums, a to_binary grid, from_binary of dyadic values, exact division rows, ten decimal texts at four binary precisions, pm1 arguments next to a rounding midpoint, numerator/divisor pairs for the word divisor kernel, and the bounds of pi (seeded)",
        "// library-ran: no",
        "// shares: nothing in the tables; the tests parse the operands with Decimal::from_string and compare text with text, or exact coefficients with Binary::compare",
        "// check: python3 tools/generate_decimal_oracle_rows.py --check",
        "",
    ]
    out += table_lines(
        "gap_446_rows", "(String, String)", [f"({quote(a)}, {quote(c)})," for a, c in gap_rows()]
    )
    out += table_lines("sticky_446_rows", "String", [f"{quote(t)}," for t in sticky_rows()])
    out += table_lines(
        "to_binary_grid_rows",
        "(String, Int32, String, String, Int32)",
        [f"({quote(t)}, {p}, {quote(m)}, {quote(c)}, {k})," for t, p, m, c, k in grid_rows()],
    )
    binary_type = "(String, Int32, Bool, Int32, String, String)"
    for name, rotate in (("from_binary_rows", False), ("from_binary_mode_rows", True)):
        out += table_lines(
            name,
            binary_type,
            [
                f"({quote(m)}, {e}, {b(n)}, {p}, {quote(mode)}, {quote(x)}),"
                for m, e, n, p, mode, x in from_binary_rows(rotate)
            ],
        )
    out += table_lines("from_binary_boundary_rows", "String", [f"{quote(t)}," for t in boundary_rows()])
    out += table_lines(
        "exact_division_rows",
        "(Int32, Int32, String, Bool, String, String, String)",
        [
            f"({p}, {e}, {quote(m)}, {b(c)}, {quote(d)}, {quote(v)}, {quote(x)}),"
            for p, e, m, c, d, v, x in exact_division_rows()
        ],
    )
    lo_hex, hi_hex = pi_hex_bounds()
    out += ["///|", f"let pi_ref_lo_hex : String = {quote(lo_hex)}", "", "///|", f"let pi_ref_hi_hex : String = {quote(hi_hex)}", ""]
    out += table_lines(
        "pm1_tiny_rows",
        "(String, Int32, String, String)",
        [f"({quote(o)}, {p}, {quote(x)}, {quote(e)})," for o, p, x, e in pm1_rows()],
    )
    out += table_lines(
        "ball_rows",
        "(String, Int32, String, Int32, String, Int32)",
        [
            f"({quote(t)}, {p}, {quote(str(lc))}, {lk}, {quote(str(hc))}, {hk}),"
            for t, p, lc, lk, hc, hk in ball_rows()
        ],
    )
    out += table_lines(
        "outward_rows",
        "(String, Int32, (String, String, String, String))",
        [f"({quote(t)}, {d}, ({quote(a)}, {quote(c)}, {quote(e)}, {quote(f)}))," for t, d, a, c, e, f in outward_rows()],
    )
    out += table_lines(
        "outward_binary_rows",
        "(String, String, Int32, String, Int32)",
        [f"({quote(t)}, {quote(str(lc))}, {lk}, {quote(str(hc))}, {hk})," for t, lc, lk, hc, hk in outward_binary_rows()],
    )
    out += table_lines(
        "word_divisor_rows",
        "(String, Int32, Bool, Int32)",
        [f"({quote(n)}, {d}, {b(e)}, {r})," for n, d, e, r in word_rows()],
    )
    return "\n".join(out)


def squeeze(text: str) -> str:
    """Whitespace removed: `moon fmt` may re-wrap the tables."""
    squeezed = "".join(text.split())
    for closer in (")", "]", "}"):
        squeezed = squeezed.replace("," + closer, closer)
    return squeezed


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="compare with the committed file")
    arguments = parser.parse_args(argv)
    sys.set_int_max_str_digits(0)
    text = render()
    if arguments.check:
        committed = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if squeeze(committed) == squeeze(text):
            print("rows match")
            return 0
        print(f"{OUTPUT} differs from the generator", file=sys.stderr)
        return 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
