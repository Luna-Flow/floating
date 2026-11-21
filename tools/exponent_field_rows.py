#!/usr/bin/env python3
"""Rows for the exponent field of a text reader (issues #597 and #624).

A reader that accumulates the exponent field in a 64-bit integer lands on the wrong side
of the range for a field of 2^63 or more: 9223372036854775808 wraps to a negative number.
The fields here are chosen so that a wrapping reader and a saturating one differ:
2^63 - 1, 2^63, 2^63 + 1, 10^19, 2^64 - 1, 2^64, 2^64 + 1 and a 40-digit field, each for
both signs of the exponent. Each is combined with the significands 1 and 0 (the result is a
signed zero whatever the exponent) and with both signs of the number, and, where the value can
be brought back into range (a small field after a long fraction), with a long fraction.
A long fraction cannot bring back a field of 2^63 or more: the text would need as many digits.

The expected values are exact arithmetic (`fractions`) and the rounding and range rule of
IEEE 754-2019 7.4 and 7.5 (overflow, underflow, tininess, the five rounding directions), written here
in Python and not taken from any reader. The rule is a parameter, so a reader of another radix
reuses the generator:

    rows = exponent_field_rows(radix, rule)   # radix 10 or 16

`rule` is any object with
    rule.name, rule.p, rule.emin, rule.emax        (the format; printed in the row)
    rule.zero(negative)            -> (printed result, flags)
    rule.far(negative, overflow, mode)   -> (printed result, flags)   # beyond every range
    rule.exact(value: Fraction, negative, mode, tininess) -> (printed result, flags)
`BinaryRule` below is the rule of a binary format; a decimal reader supplies a `DecimalRule`
with the same three methods (the printed form of the result is its own).
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction

import generate_hex_ctx_rows as binary  # round_grid, convert, convert_far, render: IEEE 754 7.4, 7.5

FIELDS = [
    2**63 - 1, 2**63, 2**63 + 1,
    10**19,
    2**64 - 1, 2**64, 2**64 + 1,
    10**39 + 7,  # 40 digits
]
MODES = ["RNE", "RTZ", "RTP", "RTN"]
# a field from this value upward is beyond every range: overflow for a positive exponent,
# underflow for a negative one (the exponent of the smallest binary format is below 2^31)
FAR = 2**31


@dataclass(frozen=True)
class BinaryRule:
    name: str
    p: int
    emin: int
    emax: int

    def zero(self, negative: bool):
        return ("-0" if negative else "0"), "---"

    def far(self, negative: bool, overflow: bool, mode: str):
        if overflow:
            away = {"RNE": True, "RNA": True, "RTZ": False, "RTP": not negative, "RTN": negative}[mode]
            text = ("-" if negative else "") + "inf" if away else binary.render(negative, 2**self.p - 1, self.emax - self.p + 1)
            return text, "I-O"
        away = {"RNE": False, "RNA": False, "RTZ": False, "RTP": not negative, "RTN": negative}[mode]
        return (binary.render(negative, 1, self.emin - self.p + 1) if away else ("-0" if negative else "0")), "IU-"

    def exact(self, value: Fraction, negative: bool, mode: str, tininess: str):
        if abs(self.emin) > 10**5:
            # the implementation range: 2^emin cannot be built; the value here is far inside it
            assert Fraction(1, 2**2000) < value < 2**2000
            e = binary.binade(value)
            grid = e - self.p + 1
            count = binary.round_grid(value, grid, mode, negative)
            result = count * Fraction(2) ** grid
            return binary.render(negative, count, grid), ("I--" if result != value else "---")
        return binary.convert(value, negative, self.p, self.emin, self.emax, mode, tininess)


def padded(value: int, width: int) -> str:
    return "0" * max(0, width - len(str(value))) + str(value)


def _row(radix, text, rule, mode, expected):
    return (radix, text, rule.name, rule.p, rule.emin, rule.emax, mode, "before", expected[0], expected[1])


def exponent_field_rows(radix: int, rule) -> list[tuple]:
    """(radix, text, format name, p, emin, emax, rounding, tininess, expected, flags)."""
    assert radix in (10, 16)
    rows = []
    marker = "e" if radix == 10 else "p"
    prefix = "" if radix == 10 else "0x"
    index = 0
    for field in FIELDS:
        for exp_negative in (False, True):
            for significand, is_zero in (("1", False), ("0", True)):
                for number_negative in (False, True):
                    spellings = [f"{'-' if exp_negative else '+'}{field}"]
                    if not exp_negative:
                        spellings.append(str(field))  # no sign
                    for field_text in spellings:
                        text = f"{'-' if number_negative else ''}{prefix}{significand}{marker}{field_text}"
                        modes = ["RNE"] if is_zero else MODES
                        for mode in modes:
                            if is_zero:
                                expected = rule.zero(number_negative)
                            else:
                                expected = rule.far(number_negative, not exp_negative, mode)
                            rows.append(_row(radix, text, rule, mode, expected))
                        index += 1
    # a long fraction that brings the value back into range (possible only for a small field):
    # 0.0...01e+(N+j) = 10^j, 0x.0...01p+(4N+4+j) = 2^j with N zeros before the digit
    zeros = 300
    for j in (0, 5, -5):
        for width in (1, 20, 40):
            for number_negative in (False, True):
                if radix == 10:
                    field = zeros + 1 + j
                    value = Fraction(10) ** j
                    text = f"{'-' if number_negative else ''}0.{'0' * zeros}1e{'+' if field >= 0 else '-'}{padded(abs(field), width)}"
                else:
                    field = 4 * (zeros + 1) + j
                    value = Fraction(2) ** j if j >= 0 else Fraction(1, 2 ** -j)
                    text = f"{'-' if number_negative else ''}0x.{'0' * zeros}1p{'+' if field >= 0 else '-'}{padded(abs(field), width)}"
                for mode in MODES:
                    rows.append(_row(radix, text, rule, mode, rule.exact(value, number_negative, mode, "before")))
    return rows


def edge_expected(rule, cls: str, negative: bool, mode: str):
    """The result for a value that is just inside one of four classes around the top of the range
    (written from IEEE 754-2019 4.3 and 7.4, with M the largest finite number, T = M + half an ulp
    and U = 2^(emax + 1)):
        below_max      M - tiny    (between the predecessor of M and M)
        above_max      M + tiny    (above M, below T)
        above_mid      T + tiny    (above T, below U; also T itself)
        above_top      U and above
    `away` is the direction that increases the magnitude (RTP for positive, RTN for negative)."""
    away = {"RNE": False, "RNA": False, "RTZ": False, "RTP": not negative, "RTN": negative}[mode]
    toward = mode == "RTZ" or (mode == "RTN" and not negative) or (mode == "RTP" and negative)
    nearest = mode in ("RNE", "RNA")
    top = rule.emax - rule.p + 1
    maximum = binary.render(negative, 2**rule.p - 1, top)
    previous = binary.render(negative, 2**rule.p - 2, top)
    if cls == "below_max":
        return (previous if toward else maximum), "I--"
    if cls == "above_max":
        if away:
            return rule.far(negative, True, mode)
        return maximum, "I--"
    if cls == "above_mid":
        if nearest or away:
            return rule.far(negative, True, mode)
        return maximum, "I--"
    assert cls == "above_top"
    return rule.far(negative, True, mode)


def edge_rows(rule, radix: int) -> list[tuple]:
    """The first literals above the largest finite number and their neighbours: 2^(emax + 1) and the
    midpoint above M in hexadecimal (exact) and in decimal (within a relative 1e-25 of each)."""
    from decimal import Decimal, getcontext

    e = rule.emax
    rows = []
    texts = []  # (text without sign, class)
    if radix == 16:
        ones = "f" * 13
        texts = [
            (f"0x1.{ones}p{e:+d}", "exact_max"),
            (f"0x1.{ones}7ffffffp{e:+d}", "above_max"),
            (f"0x1.{ones}8p{e:+d}", "above_mid"),
            (f"0x1.{ones}8000001p{e:+d}", "above_mid"),
            (f"0x1p{e + 1:+d}", "above_top"),
            (f"0x1.0000001p{e + 1:+d}", "above_top"),
            (f"0x1p{e + 2:+d}", "above_top"),
        ]
    else:
        import decimal

        getcontext().prec = 120
        getcontext().Emax = decimal.MAX_EMAX
        getcontext().Emin = decimal.MIN_EMIN
        two = Decimal(2)
        up = two ** (e + 1)
        maximum = up * (1 - two ** -rule.p)
        mid = up * (1 - two ** -(rule.p + 1))
        delta = Decimal("1e-25")
        for value, cls_below, cls_above in ((maximum, "below_max", "above_max"), (mid, "above_max", "above_mid"), (up, "above_mid", "above_top")):
            texts.append((format(value * (1 - delta), ".35e").replace("e+", "e+"), cls_below))
            texts.append((format(value * (1 + delta), ".35e"), cls_above))
    for text, cls in texts:
        for negative in (False, True):
            for mode in MODES:
                if cls == "exact_max":
                    expected = (binary.render(negative, 2**rule.p - 1, rule.emax - rule.p + 1), "---")
                else:
                    expected = edge_expected(rule, cls, negative, mode)
                rows.append(_row(radix, ("-" if negative else "") + text, rule, mode, expected))
    return rows


def all_rows() -> list[tuple]:
    rows = []
    for name, p, emin, emax in [("binary64", 53, -1022, 1023), ("unbounded53", 53, -1073741822, 1073741823)]:
        rule = BinaryRule(name, p, emin, emax)
        for radix in (10, 16):
            rows.extend(exponent_field_rows(radix, rule))
            rows.extend(edge_rows(rule, radix))
    seen, unique = set(), []
    for row in rows:
        key = row[:7]
        if key not in seen:
            seen.add(key)
            unique.append(row)
    return unique
