#!/usr/bin/env python3
"""An oracle for `BallFloat::from_string` and `BallFloatDecorated::from_string` that shares
no code with `ball_float`.

It evaluates an interval literal (IEEE 1788-2015 9.7 and 12.11) to its exact value with
Python's `Fraction`, then rounds each bound to `p` bits outward (the lower bound down, the
upper bound up) with integer arithmetic. The literal is read without the recursive-descent
structure of the parser: the string is classified by whole-string patterns (a special form,
an inf-sup or point form with the two bound strings cut at the comma, an uncertain form),
each bound string is evaluated from the groups of a pattern, and the uncertain form is
derived from the definition of the unit in the last place of 9.7.3 ("ulp(m) is `10^-d` with
`d` the number of digits after the point of `m`; `m?` is half an ulp, `m?r` is r ulps, a
direction `u` or `d` keeps one side, the exponent field multiplies the interval by `10^e`").

`--write` writes the generated table `library/src/ball_float/interval_literal_table_wbtest.mbt`
(byte-stable). `--check` recomputes it, compares with the file, and tests every generated
literal of rational form by a second way, cross-multiplication of the exact value against
the rounded ends (the rounded lower end is at most the value and the next float below it
is below, the rounded upper end is at least the value and the next float above it is above).
"""

from __future__ import annotations

import argparse
import math
import random
import re
import sys
from fractions import Fraction
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TABLE = REPO_ROOT / "library/src/ball_float/interval_literal_table_wbtest.mbt"
EMAX = 1073741823
EMIN = -1073741822
INF = math.inf

SPACE = "[ \t]*"
DEC = r"([+-]?)(\d*\.\d+|\d+\.?)(?:e([+-]?\d+))?"
HEX = r"([+-]?)0x([0-9a-f]*\.[0-9a-f]+|[0-9a-f]+\.?)p([+-]?\d+)"
RAT = r"([+-]?\d+)/(0*[1-9]\d*)"
INFLIT = r"([+-]?)(inf|infinity)"
UNCERTAIN = r"([+-]?)(\d*\.\d+|\d+\.?)\?(\?|\d*)([ud]?)(?:e([+-]?\d+))?"
DECORATION = r"_(trv|def|dac|com)"


class Err(Exception):
    """A rejected literal, with a category that names the rule that was broken."""

    def __init__(self, category: str):
        super().__init__(category)
        self.category = category


# ---------------------------------------------------------------------------
# numbers
# ---------------------------------------------------------------------------

# an exact value is (Fraction, shift2): value = fraction * 2**shift2, so a huge binary
# exponent never forms a big integer; or +-inf; huge decimal exponents are classified


def decimal_value(sign: str, significand: str, exponent: str | None):
    digits = significand.replace(".", "")
    point = significand.find(".")
    fraction_digits = 0 if point < 0 else len(significand) - point - 1
    e = int(exponent) if exponent is not None else 0
    mantissa = int(digits)
    value_exponent = e - fraction_digits
    return ("dec", -1 if sign == "-" else 1, mantissa, value_exponent)


def hex_value(sign: str, significand: str, exponent: str):
    digits = significand.replace(".", "")
    point = significand.find(".")
    fraction_digits = 0 if point < 0 else len(significand) - point - 1
    mantissa = int(digits, 16)
    value_exponent = int(exponent) - 4 * fraction_digits
    return ("hex", -1 if sign == "-" else 1, mantissa, value_exponent)


def number(text: str):
    """The exact description of a number literal, or raises Err."""
    lowered = text.lower()
    match = re.fullmatch(INFLIT, lowered)
    if match:
        return ("inf", -1 if match.group(1) == "-" else 1)
    match = re.fullmatch(HEX, lowered)
    if match:
        return hex_value(match.group(1), match.group(2), match.group(3))
    match = re.fullmatch(RAT, lowered)
    if match:
        numerator = int(match.group(1))
        return ("rat", -1 if numerator < 0 or match.group(1).startswith("-") else 1, abs(numerator), int(match.group(2)))
    match = re.fullmatch(DEC, lowered)
    if match:
        return decimal_value(match.group(1), match.group(2), match.group(3))
    if re.fullmatch(r"[+-]?\d*\.\d*/.*", lowered):
        raise Err("rational-numerator")
    if re.fullmatch(r"[+-]?\d+/.*", lowered):
        raise Err("rational-denominator")
    if re.fullmatch(r"[+-]?0x[0-9a-f.]*", lowered):
        raise Err("hex-exponent")
    raise Err("number")


# ---------------------------------------------------------------------------
# rounding
# ---------------------------------------------------------------------------


def floor_log2(m: Fraction) -> int:
    e = m.numerator.bit_length() - m.denominator.bit_length()
    if Fraction(2) ** e > m:
        e -= 1
    elif Fraction(2) ** (e + 1) <= m:
        e += 1
    return e


def flt(n: int, exponent: int):
    """A float value n * 2**exponent, kept as a pair so that a huge exponent never forms a
    big integer; zero is (0, 0)."""
    return (n, exponent) if n != 0 else (0, 0)


def flt_negate(x):
    if isinstance(x, float):
        return -x
    return flt(-x[0], x[1])


def flt_to_fraction(x):
    if isinstance(x, float):
        return x
    n, e = x
    return Fraction(n) * Fraction(2) ** e


def flt_lt(a, b) -> bool:
    return flt_cmp(a, b) < 0


def flt_cmp(a, b) -> int:
    if isinstance(a, float) or isinstance(b, float):
        fa = a if isinstance(a, float) else 0.0
        fb = b if isinstance(b, float) else 0.0
        if isinstance(a, float) and isinstance(b, float):
            return (a > b) - (a < b)
        if isinstance(a, float):
            return 1 if a > 0 else -1
        return -1 if b > 0 else 1
    na, ea = a
    nb, eb = b
    if na == 0 and nb == 0:
        return 0
    sa = (na > 0) - (na < 0)
    sb = (nb > 0) - (nb < 0)
    if sa != sb:
        return (sa > sb) - (sa < sb)
    # same sign, nonzero: compare magnitudes
    ma, mb = abs(na), abs(nb)
    ta, tb = ea + ma.bit_length(), eb + mb.bit_length()
    if ta != tb:
        order = 1 if ta > tb else -1
    else:
        shift = ma.bit_length() - mb.bit_length()
        left, right = (ma, mb << shift) if shift >= 0 else (ma << -shift, mb)
        order = (left > right) - (left < right)
    return order * sa


def round_fraction(q: Fraction, p: int, up: bool, shift2: int = 0):
    """RD or RU of the exact value q * 2**shift2 to p bits with the stored range of the
    library: gradual underflow down to the quantum 2^(EMIN-p+1), overflow to the largest
    finite float (the lower end) or +-inf. The result is a float or the pair of `flt`."""
    if q == 0:
        return flt(0, 0)
    negative = q < 0
    magnitude = -q if negative else q
    magnitude_up = up != negative
    e = floor_log2(magnitude) + shift2
    largest = flt(2**p - 1, EMAX - p + 1)
    if e > EMAX:
        result = INF if magnitude_up else largest
    else:
        quantum_exponent = max(e, EMIN) - p + 1
        if e < EMIN - p - 1:
            # below half the smallest stored value: RD is 0, RU the smallest
            result = flt(1, quantum_exponent) if magnitude_up else flt(0, 0)
        else:
            scaled = magnitude * Fraction(2) ** (shift2 - quantum_exponent)
            n = scaled.numerator // scaled.denominator
            if scaled.denominator != 1 and magnitude_up:
                n += 1
            if quantum_exponent + n.bit_length() - 1 > EMAX:
                result = INF if magnitude_up else largest
            else:
                result = flt(n, quantum_exponent)
    if isinstance(result, float):
        return -result if negative else result
    return flt_negate(result) if negative else result


def exact(desc) -> Fraction | float:
    """The exact value as a Fraction (or +-inf) when its size is affordable."""
    kind = desc[0]
    if kind == "inf":
        return desc[1] * INF
    sign, mantissa, exponent = desc[1], desc[2], desc[3]
    if kind == "dec":
        return sign * Fraction(mantissa) * Fraction(10) ** exponent
    if kind == "hex":
        return sign * Fraction(mantissa) * Fraction(2) ** exponent
    return sign * Fraction(mantissa, exponent)


def round_desc(desc, p: int, up: bool):
    """RD/RU of a number description; huge exponents are decided by their magnitude."""
    kind = desc[0]
    if kind == "inf":
        return desc[1] * INF
    if kind == "rat":
        return round_fraction(exact(desc), p, up)
    if desc[2] == 0:
        return flt(0, 0)
    sign, mantissa, exponent = desc[1], desc[2], desc[3]
    if mantissa == 0:
        return flt(0, 0)
    if kind == "dec":
        adjusted = exponent + len(str(mantissa))
        if adjusted > 340_000_000:
            return round_huge(sign, True, p, up)
        if adjusted < -340_000_000:
            return round_huge(sign, False, p, up)
        return round_fraction(exact(desc), p, up)
    return round_fraction(Fraction(sign * mantissa), p, up, shift2=exponent)


def round_huge(sign: int, huge: bool, p: int, up: bool):
    negative = sign < 0
    magnitude_up = up != negative
    if huge:
        result = INF if magnitude_up else flt(2**p - 1, EMAX - p + 1)
    else:
        result = flt(1, EMIN - p + 1) if magnitude_up else flt(0, 0)
    return flt_negate(result) if negative else result


def compare_descs(a, b):
    """-1, 0, 1 for the exact order of two number descriptions, or None if it needs a huge
    power (the library calls that case (b) of 12.12.7)."""
    ea = exact_if_small(a)
    eb = exact_if_small(b)
    if ea is None or eb is None:
        # two numbers of one radix are ordered exactly whatever their exponents: by the
        # sign, then the position of the leading digit, then the digits aligned
        if a[0] == b[0] and a[0] in ("dec", "hex"):
            return same_radix_order(a, b)
        return None
    return (ea > eb) - (ea < eb)


def same_radix_order(a, b) -> int:
    sa, ma, xa = a[1], a[2], a[3]
    sb, mb, xb = b[1], b[2], b[3]
    if ma == 0:
        sa = 0
    if mb == 0:
        sb = 0
    if sa != sb:
        return (sa > sb) - (sa < sb)
    if sa == 0:
        return 0
    base = 10 if a[0] == "dec" else 2
    size = (lambda m: len(str(m))) if base == 10 else (lambda m: m.bit_length())
    top_a, top_b = xa + size(ma), xb + size(mb)
    if top_a != top_b:
        magnitude = (top_a > top_b) - (top_a < top_b)
    else:
        # the same leading position: the exponents differ by less than the digit counts
        shift = xa - xb
        if shift >= 0:
            left, right = ma * base**shift, mb
        else:
            left, right = ma, mb * base ** (-shift)
        magnitude = (left > right) - (left < right)
    return sa * magnitude


def exact_if_small(desc):
    if desc[0] == "inf":
        return desc[1] * INF
    if desc[0] == "rat":
        return exact(desc)
    if desc[0] == "dec" and abs(desc[3]) <= 65536:
        return exact(desc)
    if desc[0] == "hex" and abs(desc[3]) <= 65536:
        return exact(desc)
    if desc[2] == 0:
        return Fraction(0)
    return None


# ---------------------------------------------------------------------------
# literals
# ---------------------------------------------------------------------------


DECORATIONS = ("trv", "def", "dac", "com")


def split_literal(text: str, p: int):
    """The bare literal and the decoration of a string; raises Err for the text that
    follows a valid bare literal and is not a decoration."""
    lowered = text.lower()
    prefix = re.match(r"\[[^\[\]]*\]", text)
    if prefix is None and not text.startswith("["):
        prefix = re.match(UNCERTAIN, lowered)
    if prefix is None:
        return text, None
    body, rest = text[: prefix.end()], text[prefix.end() :]
    if rest == "":
        return body, None
    # the bare part must be valid before the rest is judged
    inner = evaluate(body, p, True)
    if inner[0] == "err":
        raise Err(inner[1])
    if re.fullmatch(r"\[" + SPACE + r"nai" + SPACE + r"\]", body.lower()) and rest.startswith("_"):
        raise Err("nai-decoration")
    if rest.startswith("_"):
        word = rest[1:].lower()
        if word in DECORATIONS:
            return body, word
        if word[:3] in DECORATIONS and len(word) > 3:
            raise Err("decoration-trailing")
        raise Err("decoration-literal")
    if prefix is not None and not text.startswith("[") and rest[0].lower() == "e":
        raise Err("uncertain-exponent")
    raise Err("trailing")


def round_uncertain(bound, p: int, up: bool):
    """A bound of an uncertain form: an exact Fraction, or (when the exponent field is too long
    for a Fraction) a decimal description (+-1, integer, exponent)."""
    if isinstance(bound, tuple):
        return round_desc(("dec",) + bound, p, up)
    return round_fraction(bound, p, up)


def uncertain_bounds(match: re.Match):
    sign, significand, radius, direction, exponent = match.groups()
    if exponent is not None and abs(int(exponent)) > 1_000_000:
        return uncertain_bounds_symbolic(sign, significand, radius, direction, int(exponent))
    digits_after = 0 if "." not in significand else len(significand) - significand.index(".") - 1
    m = Fraction(int(significand.replace(".", "")), 10**digits_after)
    m = -m if sign == "-" else m
    ulp = Fraction(1, 10**digits_after)
    scale = Fraction(10) ** (int(exponent) if exponent is not None else 0)
    if radius == "?":
        # unbounded
        if direction == "u":
            return (m * scale, INF)
        if direction == "d":
            return (-INF, m * scale)
        return (-INF, INF)
    r = Fraction(1, 2) if radius == "" else Fraction(int(radius))
    lower = m if direction == "u" else m - r * ulp
    upper = m if direction == "d" else m + r * ulp
    return (lower * scale, upper * scale)


def uncertain_bounds_symbolic(sign, significand, radius, direction, exponent):
    """The bounds of an uncertain form with a long exponent field as decimal descriptions
    (sign, integer mantissa, exponent): the integers are scaled so that the radius is exact."""
    digits_after = 0 if "." not in significand else len(significand) - significand.index(".") - 1
    m = int(significand.replace(".", ""))
    m = -m if sign == "-" else m
    # work in units of 10^-(digits_after + 1): the default radius is half an ulp
    unit = 10 * m
    exponent_total = exponent - digits_after - 1

    def desc(value):
        if value == 0:
            return (1, 0, 0)
        return (1 if value > 0 else -1, abs(value), exponent_total)

    if radius == "?":
        if direction == "u":
            return (desc(unit), INF)
        if direction == "d":
            return (-INF, desc(unit))
        return (-INF, INF)
    r = 5 if radius == "" else 10 * int(radius)
    lower = unit if direction == "u" else unit - r
    upper = unit if direction == "d" else unit + r
    return (desc(lower), desc(upper))


def evaluate(text: str, p: int, decorated: bool):
    """('ok', lo, hi, decoration or None) for `from_string`, or ('err', category)."""
    try:
        body, decoration = split_literal(text, p)
        lowered = body.lower()
        if re.fullmatch(r"\[" + SPACE + r"nai" + SPACE + r"\]", lowered):
            if decoration is not None:
                raise Err("nai-decoration")
            if not decorated:
                raise Err("nai-bare")
            return ("nai",)
        if re.fullmatch(r"\[" + SPACE + r"(empty)?" + SPACE + r"\]", lowered):
            lo, hi, empty, bounded = None, None, True, True
        elif re.fullmatch(r"\[" + SPACE + r"entire" + SPACE + r"\]", lowered):
            lo, hi, empty, bounded = -INF, INF, False, False
        elif lowered.startswith("["):
            inner = re.fullmatch(r"\[" + SPACE + r"([^\[\]]*?)" + SPACE + r"\]", body)
            if inner is None:
                raise Err("structure")
            content = inner.group(1)
            if "," in content:
                if content.count(",") != 1:
                    raise Err("structure")
                left, right = (part.strip(" \t") for part in content.split(","))
                for part in (left, right):
                    if re.search(r"\s", part):
                        raise Err("number")
                descs = []
                for part, default in ((left, -1), (right, 1)):
                    descs.append(number(part) if part != "" else ("inf", default))
                if descs[0] == ("inf", 1):
                    raise Err("lower-inf")
                if descs[1] == ("inf", -1):
                    raise Err("upper-inf")
                order = compare_descs(descs[0], descs[1])
                if order is not None and order > 0:
                    raise Err("order")
                if re.search(r"\s", content.strip(" \t")) and False:
                    raise Err("number")
                lo_values = round_desc(descs[0], p, False)
                hi_values = round_desc(descs[1], p, True)
                if order is None:
                    other_lo = round_desc(descs[1], p, False)
                    other_hi = round_desc(descs[0], p, True)
                    lo_values = lo_values if flt_cmp(lo_values, other_lo) <= 0 else other_lo
                    hi_values = hi_values if flt_cmp(hi_values, other_hi) >= 0 else other_hi
                lo, hi, empty = lo_values, hi_values, False
                bounded = descs[0][0] != "inf" and descs[1][0] != "inf"
            else:
                if content == "" or re.search(r"\s", content):
                    raise Err("number")
                desc = number(content)
                if desc[0] == "inf":
                    raise Err("lower-inf" if desc[1] > 0 else "upper-inf")
                lo, hi, empty = round_desc(desc, p, False), round_desc(desc, p, True), False
                bounded = True
        else:
            match = re.fullmatch(UNCERTAIN, lowered)
            if match is None:
                head = lowered.split("?")[0] if "?" in lowered else None
                if head is not None and re.fullmatch(r"[0-9.+\-]*", head):
                    raise Err("uncertain-base" if not re.search(r"\d", head) else "uncertain-question")
                raise Err("structure")
            lo_exact, hi_exact = uncertain_bounds(match)
            lo = lo_exact if isinstance(lo_exact, float) else round_uncertain(lo_exact, p, False)
            hi = hi_exact if isinstance(hi_exact, float) else round_uncertain(hi_exact, p, True)
            empty = False
            bounded = not (isinstance(lo_exact, float) or isinstance(hi_exact, float))
        if not decorated and decoration is not None:
            raise Err("bare-decorated")
        if decoration is not None:
            if empty and decoration != "trv":
                raise Err("empty-decoration")
            if decoration == "com" and not bounded:
                raise Err("com-unbounded")
        final = decoration
        if decorated:
            if empty:
                final = "trv"
            else:
                if final is None:
                    final = "com"
                if final == "com" and (isinstance(lo, float) and lo == -INF or isinstance(hi, float) and hi == INF):
                    final = "dac"
        if empty:
            return ("empty", final)
        return ("ok", lo, hi, final)
    except Err as error:
        return ("err", error.category)


# ---------------------------------------------------------------------------
# the table
# ---------------------------------------------------------------------------

CATEGORY_SUBSTRING = {
    "rational-denominator": "the denominator must be a positive natural number",
    "rational-numerator": "the numerator must be an integer literal",
    "trailing": "unexpected character after the interval",
    "uncertain-exponent": "uncertain form exponent",
    "uncertain-base": "the base point m needs at least one decimal digit",
    "uncertain-question": "the question mark must follow the base point m directly",
    "decoration-literal": "decoration literal: expected trv, def, dac or com",
    "decoration-trailing": "unexpected characters after the decoration literal",
    "hex-exponent": "hexadecimal number literal",
    "number": "number literal",
    "structure": "inf-sup form",
    "lower-inf": "the lower bound may not be +inf",
    "upper-inf": "the upper bound may not be -inf",
    "order": "the lower bound is greater than the upper bound",
    "nai-decoration": "[nai] takes no decoration",
    "nai-bare": "[nai] is a decorated literal",
    "bare-decorated": "a bare interval literal has no decoration",
    "empty-decoration": "the empty interval is only permitted with the decoration trv",
    "com-unbounded": "the decoration com needs a bounded interval",
}


def hex_text(value) -> str:
    if isinstance(value, float):
        return "inf" if value > 0 else "-inf"
    n, e = value
    if n == 0:
        return "0"
    sign = "-" if n < 0 else ""
    return f"{sign}0x{abs(n):x}p{e}"


def entry_line(text: str, p: int, decorated: bool) -> str:
    """One tab-separated line: literal (tabs written as the two characters backslash t),
    precision, decorated, kind, decoration or category, lower bound, upper bound."""
    result = evaluate(text, p, decorated)
    assert "\\" not in text
    field = text.replace("\t", "\\t")
    flag = "true" if decorated else "false"
    if result[0] == "err":
        parts = (field, str(p), flag, "err", result[1], "", "")
    elif result[0] == "nai":
        parts = (field, str(p), flag, "nai", "", "", "")
    elif result[0] == "empty":
        parts = (field, str(p), flag, "empty", result[1] or "", "", "")
    else:
        _, lo, hi, decoration = result
        parts = (field, str(p), flag, "ok", decoration or "", hex_text(lo), hex_text(hi))
    return "\t".join(parts)


FIXED = [
    # Table 9.4 and Table 12.1
    "[1.e-3, 1.1e-3]", "[-0x1.3p-1, 2/3]", "[3.56]", "3.56?1", "3.56?1e2", "3.560?2", "3.56?",
    "3.560?2u", "-10?", "-10?u", "-10?12", "[]", "[entire]", "[-Inf, 2/3]", "[0x1.3p-1,]", "[,]",
    "-10??u", "-10??", "[ empty ]", "[EMPTY]", "[ 1 , 2 ]", "[\t1\t,\t2\t]", "[1,2]_com", "[1,2]_COM",
    "[1,2]_dac", "[1,2]_def", "[1,2]_trv", "[,]_dac", "[,]_def", "[,]_trv", "[]_trv", "[nai]", "[ nai ]",
    "3.56?1_def", "[0x1p-1074]", "[-0x1p+1073741823]", "[1e400000000, 1e500000000]", "[-1e500000000,-1e400000000]",
    "[1e-400000000]", "[0x1p+2000000000]", "[0x1p-2000000000]", "[0x1p+2147483647]", "[0x1p+2147483648]", "[-0x1p+1000000000000000]", "[0x1p-1000000000000000]", "[1e2147483648]", "[-1e-10000000000]", "[1e1000000000000000]", "[0x1p+99999999999999999999]", "1e3?", "5?e3", "[1/3]", "[-1/3]", "[1/3, 1/3]",
    "[0.1]", "[0.1, 1/10]", "[1/10, 0.1]", "[0.5, 0x1p-1]", "[inf]", "[-inf]", "[+inf, +inf]", "[-inf, -inf]",
    "[-inf, inf]", "[-Infinity, +Infinity]", "[0, 0]", "[-0, +0]", "[0x0p0]", "[00001.50]", "[1.5e0]",
    "[.5]", "[5.]", "[+.5e+1]",
    # the negative examples of 9.7.4 and 12.11.4
    "[1 000 000]", "[1.0 e3]", "[1,2!comment]", "[2,1]", "[5?1]", "@5 ?1@", "5??u_com", "[ganz]",
    "[1,]x", "[0,inf]_com", "empty", "[5?1]", "5???u", "[nai]_ill", "[]_ill", "[] def", "[]_def", "[]_com",
    "[entire]_com", "[nai]_com", "[nai]_trv", "[1/0]", "[1/00]", "[1/-2]", "[1.5/2]", "[0x1.8]", "[0x]", "[0x.p1]",
    "[e5]", "[1e]", "[1e+]", "[1,2,3]", "[1 2]", "[,2", "1,2", "[1;2]", "3.56 ?1", "3.56?1 ", " [1,2]", "[1,2] ",
    "3.56?1.5", "3.56?-1", "3.56??", "3.56?1e", "3.56?1x", "?1", ".?1", "1.2.3?1", "0x1p0?1",
    "[1,2]_", "[1,2]_xyz", "[1,2]_comx", "[1,2]com", "[ ]", "[  empty  ]", "[entire ]", "[ nai]",
]


# Exponent fields beyond every integer width (audit item 1 and 2 of the oracle rule), written as
# data: long fields of both signs on decimal and hexadecimal bounds in the point, pair and
# uncertain forms; the largest finite number, the first value above it, EMAX + 1; the smallest
# subnormal, the tie below it and the first underflow; NaI and `_ill` literals.
LONG_EXPONENTS = [
    "9223372036854775807", "9223372036854775808", "10000000000000000000",
    "18446744073709551615", "18446744073709551616", "18446744073709551617",
    "1234567890123456789012345678901234567890",
]
LONG_PRECISIONS = (8, 24, 53, 64, 113)
EMAX = (1 << 30) - 1


def long_exponent_entries() -> list[tuple[str, int, bool]]:
    entries = []
    for p in LONG_PRECISIONS:
        for exponent in LONG_EXPONENTS:
            for sign in ("", "-"):
                dec = f"1.5e{sign}{exponent}"
                hexa = f"0x1.8p{sign}{exponent}"
                for number in (dec, hexa):
                    entries.append((f"[{number}]", p, False))
                    entries.append((f"[-{number}, {number}]", p, False))
                    entries.append((f"[{number}, {number}]", p, True))
                entries.append((f"1?1e{sign}{exponent}", p, False))
                entries.append((f"-3.5?2ue{sign}{exponent}", p, False))
    return entries


def range_edge_entries() -> list[tuple[str, int, bool]]:
    entries = []
    for p in LONG_PRECISIONS:
        largest = f"0x{(1 << p) - 1:x}p{EMAX - p + 1}"
        above = f"0x{(1 << (p + 1)) - 1:x}p{EMAX - p}"
        smallest_exponent = -1073741821 - p
        for text in (
            f"[{largest}]", f"[-{largest}]", f"[{above}]", f"[-{above}]", f"[{largest}, {above}]",
            f"[0x1p+{EMAX + 1}]", f"[-0x1p+{EMAX + 1}]", f"[0x1p+{EMAX}]",
            f"[0x1p{smallest_exponent}]", f"[0x1p{smallest_exponent - 1}]", f"[0x3p{smallest_exponent - 2}]",
            f"[0x1p{smallest_exponent - 2}]", f"[-0x1p{smallest_exponent - 1}]", f"[0x1p{smallest_exponent}, 0x1p{smallest_exponent - 1}]",
        ):
            entries.append((text, p, False))
        entries.append((f"[{largest}]", p, True))
        entries.append((f"[0x1p{smallest_exponent - 1}]", p, True))
    for text in ("[1,2]_ill", "[entire]_ill", "[,]_ill", "[NaI]", "[nai]_ill", "[Nai]", "[]_ill", "[1]_ill", "3.56?1_ill"):
        for decorated in (False, True):
            entries.append((text, 53, decorated))
    # a pair of two radices at the limit of the exact comparison (audit item 3)
    entries.append(("[1e65537, 0x1266242e06c1b921f4e432aa84p217609]", 53, False))
    entries.append(("[1e65537]", 53, False))
    entries.append(("[0x1266242e06c1b921f4e432aa84p217609]", 53, False))
    return entries


def generated(rng: random.Random) -> list[tuple[str, int, bool]]:
    entries: list[tuple[str, int, bool]] = []
    precisions = (24, 53, 113)

    def digits(n):
        return "".join(rng.choice("0123456789") for _ in range(n))

    def dec_literal():
        sign = rng.choice(["", "", "-", "+"])
        integer = digits(rng.randint(0, 6))
        fraction = digits(rng.randint(0, 6))
        if integer == "" and fraction == "":
            integer = "0"
        significand = integer + ("." + fraction if fraction or rng.random() < 0.2 and integer else "")
        if significand.endswith(".") and integer == "":
            significand = "0."
        exponent = ""
        if rng.random() < 0.6:
            exponent = rng.choice(["e", "E"]) + rng.choice(["", "+", "-"]) + str(rng.randint(0, 400))
        return sign + significand + exponent

    def hex_literal():
        sign = rng.choice(["", "", "-", "+"])
        integer = "".join(rng.choice("0123456789abcdefABCDEF") for _ in range(rng.randint(1, 5)))
        fraction = "".join(rng.choice("0123456789abcdef") for _ in range(rng.randint(0, 5)))
        significand = integer + ("." + fraction if fraction else "")
        return sign + rng.choice(["0x", "0X"]) + significand + rng.choice(["p", "P"]) + rng.choice(["", "+", "-"]) + str(rng.randint(0, 1200))

    def rat_literal():
        return rng.choice(["", "-", "+"]) + digits(rng.randint(1, 8)) + "/" + str(rng.randint(1, 10**rng.randint(1, 8)))

    def number_text():
        kind = rng.random()
        if kind < 0.5:
            return dec_literal()
        if kind < 0.7:
            return hex_literal()
        if kind < 0.95:
            return rat_literal()
        return rng.choice(["inf", "-inf", "+Infinity", "INF"])

    def uncertain():
        sign = rng.choice(["", "-", "+"])
        integer = digits(rng.randint(1, 4))
        fraction = digits(rng.randint(0, 4))
        significand = integer + ("." + fraction if fraction else rng.choice(["", "."]))
        radius = rng.choice(["", "", str(rng.randint(0, 99)), "?"])
        direction = rng.choice(["", "", "u", "d"])
        exponent = "" if rng.random() < 0.6 else rng.choice(["e", "E"]) + rng.choice(["", "-", "+"]) + str(rng.randint(0, 30))
        return sign + significand + "?" + radius + direction + exponent

    decorations = ["", "", "", "_trv", "_def", "_dac", "_com", "_COM", "_Def"]
    for index in range(9000):
        p = precisions[index % 3]
        form = rng.random()
        if form < 0.45:
            text = "[" + rng.choice(["", " "]) + number_text() + rng.choice(["", " "]) + "," + rng.choice(["", " ", "\t"]) + number_text() + rng.choice(["", " "]) + "]"
        elif form < 0.55:
            text = "[" + number_text() + "]"
        elif form < 0.65:
            text = "[" + rng.choice(["", " "]) + number_text() + "," + rng.choice(["", " "]) + "]"
        elif form < 0.7:
            text = "[" + rng.choice(["", " "]) + "," + rng.choice(["", " "]) + number_text() + "]"
        else:
            text = uncertain()
        suffix = rng.choice(decorations)
        decorated = suffix != "" or rng.random() < 0.3
        entries.append((text + suffix, p, decorated))
    return entries


CHUNK = 400


def build() -> str:
    lines = [
        "///|",
        "/// Generated by `python3 tools/interval_literal_oracle.py --write`: the expected result of",
        "/// `from_string` for each literal, computed by an independent oracle (`Fraction`, no",
        "/// `ball_float` code). Each line is tab separated: literal (a tab inside it is written",
        "/// backslash t), precision, decorated, kind (ok, empty, nai, err), decoration or error",
        "/// category, lower bound as 0x<int>p<exp>, upper bound. The lines are split into chunks",
        "/// of 400 so that no top-level segment grows beyond the line limit.",
        "",
    ]
    rng = random.Random(1788)
    entries: list[str] = []
    for text in FIXED:
        for decorated in (False, True):
            entries.append(entry_line(text, 53, decorated))
    for text, p, decorated in generated(rng):
        entries.append(entry_line(text, p, decorated))
    for text, p, decorated in long_exponent_entries() + range_edge_entries():
        entries.append(entry_line(text, p, decorated))
    chunks = [entries[i : i + CHUNK] for i in range(0, len(entries), CHUNK)]
    for index, chunk in enumerate(chunks):
        lines.append("///|")
        lines.append(f"fn literal_table_{index}() -> String {{")
        lines.append("  (")
        lines.extend("    #|" + entry for entry in chunk)
        lines.append("  )")
        lines.append("}")
        lines.append("")
    lines.append("///|")
    lines.append("fn literal_tables() -> Array[String] {")
    lines.append("  [")
    for index in range(len(chunks)):
        lines.append(f"    literal_table_{index}(),")
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# the second way for the rational form
# ---------------------------------------------------------------------------


def next_float(value: Fraction, p: int, direction: int):
    """The float next to a rounded bound in the direction (+1 up, -1 down), as an exact value."""
    if value == 0:
        quantum = Fraction(2) ** (EMIN - p + 1)
        return direction * quantum
    e = floor_log2(abs(value))
    quantum = Fraction(2) ** (max(e, EMIN) - p + 1)
    step = quantum
    if abs(value) == Fraction(2) ** e and (direction < 0) == (value > 0) and e > EMIN:
        step = quantum / 2
    return value + direction * step


def check_rational_cross_multiplication(count: int = 20000) -> int:
    """For every generated rational bound: the rounded lower end times the denominator is at
    most the numerator and the float below it is below; the rounded upper end is at least
    and the float above it is above (compared by cross-multiplication, not by the rounding
    function)."""
    rng = random.Random(4242)
    checked = 0
    for index in range(count):
        p = (24, 53, 113)[index % 3]
        numerator = rng.randint(-10**rng.randint(1, 20), 10**rng.randint(1, 20))
        denominator = rng.randint(1, 10 ** rng.randint(1, 20))
        text = f"[{numerator}/{denominator}]"
        result = evaluate(text, p, False)
        assert result[0] == "ok", text
        lo, hi = flt_to_fraction(result[1]), flt_to_fraction(result[2])
        # compare p/q with a float f = n/d by cross-multiplication: p*d_f vs n_f*q
        def order(value) -> int:
            if isinstance(value, float):
                return 1 if value > 0 else -1
            return (numerator * value.denominator > value.numerator * denominator) - (
                numerator * value.denominator < value.numerator * denominator
            )

        assert order(lo) >= 0, (text, p, "lower end above the value")
        assert order(hi) <= 0, (text, p, "upper end below the value")
        below = next_float(lo, p, -1)
        above = next_float(hi, p, +1)
        assert order(below) > 0, (text, p, "the float below the lower end is not below the value")
        assert order(above) < 0, (text, p, "the float above the upper end is not above the value")
        checked += 1
    return checked


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = build()
    if args.write:
        TABLE.write_text(text, encoding="utf-8")
        print(f"wrote {TABLE.relative_to(REPO_ROOT)}: {text.count(chr(10) + '    #|')} entries")
        return 0
    ok = TABLE.exists() and TABLE.read_text(encoding="utf-8") == text
    if not ok:
        print("the generated table differs from the oracle; run --write and review")
    checked = check_rational_cross_multiplication()
    print(f"rational literals checked by cross-multiplication: {checked}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
