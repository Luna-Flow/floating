#!/usr/bin/env python3
"""Rows for the conversions between decimal and binary formats (IEEE 754-2019
5.4.2, issue 223).

Writes `library/src/decimal/convert_format_rows_wbtest.mbt`, the tables executed
by `convert_format_wbtest.mbt`:

* `mpfr_strtofr_rows` and `mpfr_getstr_rows`: rows taken from the committed MPFR
  4.2.2 corpora `testdata/bin_float/mpfr-4.2.2-strtofr.txt` (decimal text to a
  binary value, `mpfr_strtofr`) and `mpfr-4.2.2-decimal-output.txt` (a binary
  value to n digits, `mpfr_get_str`), every `STRIDE`-th row of each cell, so the
  expected values and the inexact flags are MPFR's. They run through
  `Decimal::to_bin_float_ctx` and `Decimal::from_bin_float_ctx`.
* `decimal_to_binary_rows` and `binary_to_decimal_rows`: every pair among
  decimal32/64/128 and binary16/32/64/128, every IEEE rounding direction, with
  value, flags (inexact, overflow, underflow) and, for binary to decimal, the
  coefficient and the exponent of the preferred-exponent rule. The expected values
  are computed by exact integer arithmetic below (`Fraction`), independent of the
  library, with MPFR's rows above as the cross-check of the rounding core.
* `convert_format_rows`: decimal to decimal conversions with the preferred
  exponent Q(source), cohort and exponent-range cases.

    python3 tools/generate_decimal_conversion_rows.py && moon fmt
    python3 tools/generate_decimal_conversion_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/convert_format_rows_wbtest.mbt"
STRTOFR = ROOT / "testdata/bin_float/mpfr-4.2.2-strtofr.txt"
GETSTR = ROOT / "testdata/bin_float/mpfr-4.2.2-decimal-output.txt"
STRIDE = 4
sys.set_int_max_str_digits(0)

BINARY = {"binary16": (11, -14, 15), "binary32": (24, -126, 127), "binary64": (53, -1022, 1023), "binary128": (113, -16382, 16383)}
DECIMAL = {"decimal32": (7, -95, 96), "decimal64": (16, -383, 384), "decimal128": (34, -6143, 6144)}
BIN_MODES = ["ties_even", "ties_away", "toward_zero", "toward_positive", "toward_negative"]
DEC_MODES = ["half_even", "half_up", "down", "ceiling", "floor"]  # half_up is ties to away


def round_integer(numerator: int, denominator: int, negative: bool, mode: str) -> int:
    """numerator / denominator (>= 0) rounded to an integer in the direction."""
    q, r = divmod(numerator, denominator)
    if r == 0:
        return q
    twice = 2 * r
    if mode in ("ties_even", "half_even"):
        up = twice > denominator or (twice == denominator and q & 1 == 1)
    elif mode in ("ties_away", "half_up"):
        up = twice >= denominator
    elif mode in ("toward_zero", "down"):
        up = False
    elif mode in ("toward_positive", "ceiling"):
        up = not negative
    else:
        up = negative
    return q + 1 if up else q


def binary_round(value: Fraction, p: int, emin: int, emax: int, mode: str):
    """The binary rounding of `value` (IEEE 754-2019 4.3, 7.4, 7.5, tininess after
    rounding): (kind, signed integer coefficient C, exponent k, inexact, overflow,
    underflow) with the value C * 2^k, kind in {"finite", "inf"}."""
    if value == 0:
        return ("finite", 0, 0, False, False, False)
    negative = value < 0
    a = abs(value)
    # exponent of the leading bit: 2^e <= a < 2^(e+1)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** e > a:
        e -= 1
    quantum_exp = max(e, emin) - (p - 1)
    q = a / Fraction(2) ** quantum_exp
    c = round_integer(q.numerator, q.denominator, negative, mode)
    inexact = c != q
    # tininess after rounding: the value rounded as if the exponent range were
    # unbounded is below 2^emin
    unb_exp = e - (p - 1)
    qu = a / Fraction(2) ** unb_exp
    cu = round_integer(qu.numerator, qu.denominator, negative, mode)
    tiny = Fraction(cu) * Fraction(2) ** unb_exp < Fraction(2) ** emin
    underflow = inexact and tiny
    if c == 1 << p:  # carried into the next binade
        c >>= 1
        quantum_exp += 1
    if quantum_exp + p - 1 > emax:  # overflow
        to_inf = mode in ("ties_even", "ties_away") or (mode == "toward_positive" and not negative) or (mode == "toward_negative" and negative)
        if to_inf:
            return ("inf", -1 if negative else 1, 0, True, True, False)
        return ("finite", -((1 << p) - 1) if negative else (1 << p) - 1, emax - (p - 1), True, True, False)
    return ("finite", -c if negative else c, quantum_exp, inexact, False, underflow)


def decimal_round(value: Fraction, p: int, emin: int, emax: int, mode: str):
    """The decimal rounding with the preferred exponent (IEEE 754-2019 5.4.2: an
    exact binary to decimal conversion has the preferred exponent 0, an inexact one
    the least): (kind, signed coefficient, exponent, inexact, overflow, underflow)."""
    etiny = emin - p + 1
    if value == 0:
        return ("finite", 0, 0, False, False, False)
    negative = value < 0
    a = abs(value)
    adjusted = len(str(a.numerator)) - len(str(a.denominator))
    if a < Fraction(10) ** adjusted:
        adjusted -= 1
    target = max(adjusted - (p - 1), etiny)
    q = a / Fraction(10) ** target
    c = round_integer(q.numerator, q.denominator, negative, mode)
    inexact = c != q
    # tiny before rounding (decimal): adjusted exponent below emin
    underflow = inexact and adjusted < emin
    if c == 10**p:
        c //= 10
        target += 1
    if len(str(c)) + target - 1 > emax:  # overflow
        to_inf = mode in ("half_even", "half_up", "up") or (mode == "ceiling" and not negative) or (mode == "floor" and negative)
        if to_inf:
            return ("inf", -1 if negative else 1, 0, True, True, False)
        return ("finite", -(10**p - 1) if negative else 10**p - 1, emax - p + 1, True, True, False)
    if not inexact:
        # preferred exponent 0: the exponent closest to 0 with at most p digits
        coefficient, exponent = c, target
        low = max(etiny, len(str(c)) + exponent - p)  # fewest-digit bound is exponent + digits - p
        while exponent < 0 and coefficient % 10 == 0:
            coefficient //= 10
            exponent += 1
        while exponent > 0 and len(str(coefficient)) < p and exponent > low:
            coefficient *= 10
            exponent -= 1
        c, target = coefficient, exponent
    return ("finite", -c if negative else c, target, inexact, False, underflow)


def exact_cohort(coefficient: int, exponent: int, p: int):
    """The cohort member of the exact decimal value `coefficient * 10^exponent` that an
    exact binary to decimal conversion returns in a context of precision `p`
    (IEEE 754-2019 5.4.2, preferred exponent 0; 5.2, the member whose exponent is
    closest to the preferred one when that one does not exist): the exponent in
    `[exponent + digits - p, exponent]` (trailing zeros stripped first) that is
    closest to 0, and whether digits were dropped (`rounded`, only zeros).
    Returns (coefficient, exponent, rounded)."""
    stripped = coefficient
    while stripped % 10 == 0 and stripped != 0:
        stripped //= 10
        exponent += 1
    digits = len(str(stripped))
    low = exponent + digits - p  # smallest exponent that keeps at most p digits
    high = exponent  # largest exponent at which the value is an integer
    if high - low < 3000:
        best = min(range(low, high + 1), key=lambda e: (abs(e), e))
    else:  # closest to 0 in [low, high], in closed form
        best = 0 if low <= 0 <= high else (high if high < 0 else low)
    rounded = exponent >= 0 and digits + exponent > p
    return stripped * 10 ** (exponent - best), best, rounded


def hex_literal(c: int, k: int) -> str:
    sign = "-" if c < 0 else ""
    return f"{sign}0x{abs(c):x}p{k}"


def q(text: str) -> str:
    return '"' + text + '"'


def mpfr_rows() -> tuple[list[tuple], list[tuple]]:
    strtofr = []
    cell: dict[tuple, int] = {}
    for line in STRTOFR.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        precision, rounding, literal, expected, inexact, overflow, underflow = line.split()
        key = (precision, rounding)
        cell[key] = cell.get(key, 0) + 1
        if cell[key] % STRIDE == 1:
            strtofr.append((literal, int(precision), rounding, expected, inexact == "1", overflow == "1", underflow == "1"))
    getstr = []
    cell = {}
    for line in GETSTR.read_text().splitlines():
        if not line or line.startswith("#") or not line.startswith("fixed"):
            continue
        _, digits, precision, rounding, value, expected_digits, expected_exponent, inexact = line.split()
        key = (digits, precision, rounding)
        cell[key] = cell.get(key, 0) + 1
        if cell[key] % STRIDE == 1:
            cohort = ("", 0, False)
            if inexact == "0":
                # MPFR's digits are padded to n; the exact cohort member is derived from
                # the value with the rule of IEEE 754-2019 5.4.2 and 5.2
                digit_string = expected_digits.rstrip("0") or "0"
                exponent10 = int(expected_exponent) - len(expected_digits) + 1 + (len(expected_digits) - len(digit_string))
                cohort_coefficient, cohort_exponent, cohort_rounded = exact_cohort(int(digit_string), exponent10, int(digits))
                cohort = (str(cohort_coefficient), cohort_exponent, cohort_rounded)
            getstr.append((int(digits), int(precision), rounding, value, expected_digits, int(expected_exponent), inexact == "1", *cohort))
    return strtofr, getstr


DECIMAL_VALUES = [
    "0", "-0", "1", "-1", "0.1", "-0.1", "0.2", "0.3", "1.5", "2.5", "3.14159265358979", "100", "65504", "65519", "65520", "65521", "-65520", "65536",
    "1E+10", "1E+38", "3.4028235E+38", "3.4028236E+38", "3.4028235677973366E+38", "1.7976931348623157E+308", "1.797693134862315708E+308", "1E+309", "1E+4932", "1.18973149535723176508575932662800702E+4932", "1E+5000",
    "5.96E-8", "2.98E-8", "2.9802322387695312E-8", "2.98023223876953125E-8", "2.980232238769531251E-8", "6.1E-5", "6.103515625E-5", "6.1035156249999999E-5", "1.17549435E-38", "1.4E-45", "7E-46", "7.006492321624085E-46", "7.006492321624086E-46",
    "4.9E-324", "2.47E-324", "2.4703282292062327E-324", "2.4703282292062328E-324", "1E-400", "1E-5000", "1E-5000", "1E-100", "1E-4966", "6.4751751194380251109244389582276465525E-4966", "3.6E-4951",
    "1.00048828125", "1.000488281250000001", "1.00048828124999999", "9.99999999999999E+22", "4.5036E+15", "9007199254740993", "9007199254740992.5", "16777217", "16777216.5", "123456789", "1E+22", "0.5", "-0.5", "1E+1000",
]
BINARY_VALUES_HEX = [
    "0x1p0", "-0x1p0", "0x3p-1", "0x1p-1", "0x1p-3", "0x5p-1", "0x1p10", "0x1p20", "0x1fffp-10", "0x7ffp-10", "0x1p-24", "0x1p-14", "0x3p-25", "0x1p100", "0x1p-100", "0x1fffffp104", "0x1p127", "0x1p-149", "0x1p1023", "0x1p-1074", "0x1p-1022",
    "0x1fffffffffffffp971", "0x1p16383", "0x1p-16494", "0x1p-16382", "0x1ffffffffffffffffffffffffffffp16271", "0x1p300", "0x1p-300", "0x1p500", "0x1p-500", "0x15p-3", "0x1234567p-20", "0x7fffp-2", "0x1p-9", "0x1fffffffp-30", "-0x1p-1074", "-0x1p20", "-0x1p16383",
    "0x1p5000", "0x1p-5000", "0x1p-3000", "0x1p3000", "0x1p-20000",
]
DEC_FORMAT_VALUES = [
    "0", "-0", "0E+5", "0E-5", "1", "1.0", "1.00", "1.000000", "1000000", "1E+6", "100E+4", "1.5E+90", "1E+90", "1E+91", "1E+96", "9.999999E+96", "1E+97", "-9.999999E+96", "1E-95", "1E-101", "1E-102", "1.2345678E+96",
    "0.000001", "9999999", "99999999", "12345678", "1234567.5", "1234567.4", "1234567.6", "-1234567.5", "12345678901234567", "1234567890123456.5", "1.234567890123456789E+300", "9.999999999999999E+384", "1E+385", "1E-398", "1E-399",
    "1.2345678901234567890123456789012345E+5000", "1E+6144", "1E+6145", "1E-6176", "1E-6177", "1.5E-6176", "9.5E-102", "1.5E-101", "5E-102", "4E-102", "7E+89", "7.0E+90", "7.00E+91", "1234567E+90", "12345670E+90",
]


def decimal_value(text: str) -> Fraction:
    return Fraction(Decimal(text))


LARGE_MODES = ["half_even", "half_up", "down", "ceiling", "floor", "up"]
LARGE_EXPONENTS = [4_194_305, 5_000_000, 8_388_608, 16_777_216, 100_000_000, 1_000_000_000, -4_194_305, -5_000_000, -8_388_608, -100_000_000, -1_000_000_000]
LARGE_MANTISSAS = [1, 3, 0x1FFFFFFFFFFFFF, 0x10000000000001, 0xABCDEF123456789]


def large_binary_rows() -> list[str]:
    """Binary values far beyond a binary exponent of 2^22, converted to a wide decimal
    context (exponent range of +-999,999,999): the correctly rounded digits computed
    with Python `decimal` at `precision + 80` digits (independent of the library),
    used only when the digits after the kept ones are neither all zero nor all nine,
    so that the rounding of the high precision value is the rounding of the exact one."""
    import decimal

    rows = []
    for mantissa in LARGE_MANTISSAS:
        for exponent in LARGE_EXPONENTS:
            for negative in (False, True):
                for p in (16, 34):
                    work = decimal.Context(prec=p + 80, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
                    value = work.multiply(Decimal(mantissa), work.power(Decimal(2), Decimal(exponent)))
                    digits = value.as_tuple().digits
                    tail = digits[p : p + 40]
                    if all(d == 0 for d in tail) or all(d == 9 for d in tail):
                        continue
                    for mode in LARGE_MODES:
                        decimal_mode = {
                            "half_even": decimal.ROUND_HALF_EVEN,
                            "half_up": decimal.ROUND_HALF_UP,
                            "down": decimal.ROUND_DOWN,
                            "ceiling": decimal.ROUND_CEILING,
                            "floor": decimal.ROUND_FLOOR,
                            "up": decimal.ROUND_UP,
                        }[mode]
                        signed = work.minus(value) if negative else value
                        context = decimal.Context(prec=p, rounding=decimal_mode, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
                        result = context.plus(signed)
                        sign, rdigits, rexponent = result.as_tuple()
                        coefficient = "".join(map(str, rdigits))
                        hexa = ("-" if negative else "") + f"0x{mantissa:x}p{exponent}"
                        rows.append(f"({q(hexa)}, {p}, {q(mode)}, {q(coefficient)}, {rexponent}, {'true' if negative else 'false'})")
    return rows


COHORT_PRECISIONS = [7, 16, 34]
COHORT_VALUES = [
    (1, 20), (1, 22), (4, 17), (1, 16), (1, 15), (1, 6), (3, 9), (12, 7), (1, 7), (1, 0), (96, 0), (5, 0), (1, 1), (1, 2), (25, 3),
    (1, 30), (7, 40), (123, 50), (1, 300), (3, 300), (1, 5000), (7, 5000),
]


def exact_cohort_rows() -> list[str]:
    """Exact binary values `c * 10^k` (built as `c * 5^k` times `2^k`, exactly) converted
    to decimal contexts of precision 7, 16 and 34 (exponent range +-999,999): the whole
    cohort member, coefficient, exponent and the `rounded` flag, compared without stripping.
    The expected member comes from `exact_cohort`, a search over the exponents (the rule of
    IEEE 754-2019 5.4.2 and 5.2) in Python integers."""
    rows = []
    for coefficient, k in COHORT_VALUES:
        for negative in (False, True):
            for p in COHORT_PRECISIONS:
                c, e, rounded = exact_cohort(coefficient, k, p)
                mantissa = coefficient * 5**k
                hexa = ("-" if negative else "") + f"0x{mantissa:x}p{k}"
                rows.append(f"({q(hexa)}, {p}, {q(str(c))}, {e}, {'true' if negative else 'false'}, {'true' if rounded else 'false'})")
    return rows


def emit(rows_name: str, row_type: str, rows: list[str]) -> list[str]:
    out = [f"///|\nlet {rows_name} : Array[{row_type}] = ["]
    out += [f"  {row}," for row in rows]
    out.append("]\n")
    return out


def all_rows() -> list[str]:
    out = [
        "// Generated by tools/generate_decimal_conversion_rows.py from the MPFR 4.2.2 corpora and exact",
        "// integer arithmetic. Do not edit; run the tool.\n",
    ]
    strtofr, getstr = mpfr_rows()
    out += emit(
        "mpfr_strtofr_rows",
        "(String, Int32, String, String, Bool, Bool, Bool)",
        [f"({q(l)}, {p}, {q(r)}, {q('+inf' if e == 'inf' else e)}, {'true' if i else 'false'}, {'true' if o else 'false'}, {'true' if u else 'false'})" for l, p, r, e, i, o, u in strtofr],
    )
    out += emit(
        "mpfr_getstr_rows",
        "(Int32, Int32, String, String, String, Int32, Bool, String, Int32, Bool)",
        [
            f"({d}, {p}, {q(r)}, {q(v)}, {q(e)}, {x}, {'true' if i else 'false'}, {q(c)}, {ce}, {'true' if cr else 'false'})"
            for d, p, r, v, e, x, i, c, ce, cr in getstr
        ],
    )
    d2b = []
    for text in DECIMAL_VALUES:
        value = decimal_value(text)
        for name, (p, emin, emax) in BINARY.items():
            for mode in BIN_MODES:
                kind, c, k, inexact, overflow, underflow = binary_round(value, p, emin, emax, mode)
                expected = ("inf" if c < 0 else "+inf") if kind == "inf" else hex_literal(c, k)
                if kind == "inf":
                    expected = "-inf" if c < 0 else "+inf"
                if kind == "finite" and c == 0:
                    expected = "-0" if (text.startswith("-") or (value < 0)) else "0"
                d2b.append(f"({q(text)}, {q(name)}, {q(mode)}, {q(expected)}, {'true' if inexact else 'false'}, {'true' if overflow else 'false'}, {'true' if underflow else 'false'})")
    out += emit("decimal_to_binary_rows", "(String, String, String, String, Bool, Bool, Bool)", d2b)
    b2d = []
    for hexa in BINARY_VALUES_HEX:
        negative = hexa.startswith("-")
        mant, exp = hexa.lstrip("-")[2:].split("p")
        value = Fraction(int(mant, 16)) * Fraction(2) ** int(exp)
        value = -value if negative else value
        for name, (p, emin, emax) in DECIMAL.items():
            for mode in DEC_MODES:
                kind, c, e, inexact, overflow, underflow = decimal_round(value, p, emin, emax, mode)
                shape = "inf" if kind == "inf" else "finite"
                b2d.append(
                    f"({q(hexa)}, {q(name)}, {q(mode)}, {q(shape)}, {q(str(abs(c)) if kind == 'finite' else '')}, {e if kind == 'finite' else 0}, {'true' if c < 0 or (c == 0 and negative) else 'false'}, "
                    f"{'true' if inexact else 'false'}, {'true' if overflow else 'false'}, {'true' if underflow else 'false'})"
                )
    out += emit("binary_to_decimal_rows", "(String, String, String, String, String, Int32, Bool, Bool, Bool, Bool)", b2d)
    out += emit("exact_cohort_rows", "(String, Int32, String, Int32, Bool, Bool)", exact_cohort_rows())
    out += emit("large_binary_rows", "(String, Int32, String, String, Int32, Bool)", large_binary_rows())
    d2d = []
    for text in DEC_FORMAT_VALUES:
        d = Decimal(text)
        sign, digits, exponent = d.as_tuple()
        coefficient = int("".join(map(str, digits)))
        for name, (p, emin, emax) in DECIMAL.items():
            value = Fraction(d)
            kind, c, e, inexact, overflow, underflow = decimal_round(value, p, emin, emax, "half_even") if False else decimal_convert(coefficient, exponent, bool(sign), p, emin, emax)
            shape = "inf" if kind == "inf" else "finite"
            d2d.append(
                f"({q(text)}, {q(name)}, {q(shape)}, {q(str(coefficient_of(kind, c)))}, {e if kind == 'finite' else 0}, {'true' if sign or False else 'false'}, "
                f"{'true' if inexact else 'false'}, {'true' if overflow else 'false'}, {'true' if underflow else 'false'})"
            )
    out += emit("convert_format_rows", "(String, String, String, String, Int32, Bool, Bool, Bool, Bool)", d2d)
    return out


def coefficient_of(kind: str, c: int) -> int:
    return abs(c) if kind == "finite" else 0


def decimal_convert(coefficient: int, exponent: int, negative: bool, p: int, emin: int, emax: int):
    """decimal to decimal with the preferred exponent Q(source): round half even to
    the destination, keep the quantum of the source when exact and in range."""
    etiny = emin - p + 1
    etop = emax - p + 1
    if coefficient == 0:
        e = min(max(exponent, etiny), etop)
        return ("finite", 0, e, False, False, False)
    digits = len(str(coefficient))
    adjusted = exponent + digits - 1
    if adjusted > emax and digits <= p:
        pass
    target = max(adjusted - (p - 1), etiny)
    # exact when the source quantum (exponent) can stay: coefficient fits p digits and exponent >= etiny
    value = Fraction(coefficient) * Fraction(10) ** exponent
    q = value / Fraction(10) ** target
    c = round_integer(q.numerator, q.denominator, negative, "half_even")
    inexact = c != q
    underflow = inexact and adjusted < emin
    if c == 10**p:
        c //= 10
        target += 1
    if len(str(c)) + target - 1 > emax:
        return ("inf", -1 if negative else 1, 0, True, True, False)
    if not inexact:
        # keep the exponent of the source if it is representable: a coefficient of at most p digits
        # at an exponent in [etiny, etop]; a source exponent above etop is folded down to etop.
        if digits <= p and exponent >= etiny:
            if exponent > etop:
                return ("finite", -coefficient * 10 ** (exponent - etop) if negative else coefficient * 10 ** (exponent - etop), etop, False, False, False)
            return ("finite", -coefficient if negative else coefficient, exponent, False, False, False)
    return ("finite", -c if negative else c, target, inexact, False, underflow)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = "\n".join(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""

        def norm(source: str) -> str:
            # `moon fmt` re-wraps the table and adds trailing commas.
            squeezed = "".join(source.split())
            for closer in (")", "]", "}"):
                squeezed = squeezed.replace("," + closer, closer)
            return squeezed

        if norm(current) != norm(text):
            print(f"{OUTPUT} is stale: run tools/generate_decimal_conversion_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
