#!/usr/bin/env python3
"""Rows that replace non-independent oracles in the `decimal` test blocks (round 2 of #438).

Writes `library/src/decimal/oracle_repair_rows_wbtest.mbt`, tables only:

* `gap_446_rows`: plain `+` and `-` of two operands of 34 digits whose exponents are far apart
  (issue 446), expected text from CPython `decimal` (libmpdec) in the plain working context
  (precision 34, half-even, no clamp).
* `sticky_446_rows`: the sum of a 34-digit-or-shorter high operand and a far smaller one (the sticky
  absorption of issue 446), in the loop order of the test, from CPython `decimal`.
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


def quote(text: str) -> str:
    return '"' + text + '"'


def render() -> str:
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_oracle_rows.py (CPython `decimal`/libmpdec, Python integers and `math.gcd`)",
        "// input: issue 446 operand pairs, ten decimal texts at four binary precisions, and numerator/divisor pairs for the word divisor kernel (seeded)",
        "// library-ran: no",
        "// shares: nothing in the tables; the tests parse the operands with Decimal::from_string and compare text with text, or exact coefficients with Binary::compare",
        "// check: python3 tools/generate_decimal_oracle_rows.py --check",
        "",
        "///|",
        "let gap_446_rows : Array[(String, String)] = [",
    ]
    for plus, minus in gap_rows():
        out.append(f"  ({quote(plus)}, {quote(minus)}),")
    out += ["]", "", "///|", "let sticky_446_rows : Array[String] = ["]
    for text in sticky_rows():
        out.append(f"  {quote(text)},")
    out += ["]", "", "///|", "let pm1_tiny_rows : Array[(String, Int32, String, String)] = ["]
    for operation, precision, x_text, expected in pm1_rows():
        out.append(f"  ({quote(operation)}, {precision}, {quote(x_text)}, {quote(expected)}),")
    out += ["]", "", "///|", "let ball_rows : Array[(String, Int32, String, Int32, String, Int32)] = ["]
    for text, p, lo_c, lo_k, hi_c, hi_k in ball_rows():
        out.append(f"  ({quote(text)}, {p}, {quote(str(lo_c))}, {lo_k}, {quote(str(hi_c))}, {hi_k}),")
    out += ["]", "", "///|", "let word_divisor_rows : Array[(String, Int32, Bool, Int32)] = ["]
    for numerator, divisor, ends, remainder in word_rows():
        out.append(f"  ({quote(numerator)}, {divisor}, {'true' if ends else 'false'}, {remainder}),")
    out += ["]", ""]
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
