#!/usr/bin/env python3
"""IEEE 754-2019 decimal interchange encodings (clause 3.5.2, densely packed decimal), in Python.

An independent encoder and decoder of the three decimal interchange formats, written from
the layout of the standard (sign, combination field, exponent continuation, coefficient
continuation in declets) and the DPD table of the declet (Cowlishaw's densely packed
decimal, the table of Wikipedia "Densely packed decimal"). Used to write the expected
hexadecimal words of the interchange tests of `tooling/src/consistency`; the library does
not run. Also rounds a finite decimal to a format (the rounding of 4.3.1 for decimal
formats, ties to even by default) so that a test can state the encoding of a value that
the format cannot hold exactly.

    python3 tools/decimal_interchange_oracle.py 1.23E+96 decimal32
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from fractions import Fraction


@dataclass(frozen=True)
class Format:
    name: str
    bits: int
    precision: int
    emax: int
    exponent_continuation: int  # bits of the exponent continuation, w

    @property
    def bias(self) -> int:
        return self.emax + self.precision - 2

    @property
    def qmin(self) -> int:
        return -self.bias

    @property
    def qmax(self) -> int:
        return self.emax - self.precision + 1


DECIMAL32 = Format("decimal32", 32, 7, 96, 6)
DECIMAL64 = Format("decimal64", 64, 16, 384, 8)
DECIMAL128 = Format("decimal128", 128, 34, 6144, 12)
FORMATS = {f.name: f for f in (DECIMAL32, DECIMAL64, DECIMAL128)}


def encode_declet(digits: tuple[int, int, int]) -> int:
    """Three decimal digits to a 10-bit declet."""
    bits = []
    for d in digits:
        bits.append([(d >> 3) & 1, (d >> 2) & 1, (d >> 1) & 1, d & 1])
    a, b, c, d = bits[0]
    e, f, g, h = bits[1]
    i, j, k, m = bits[2]
    key = (a, e, i)
    if key == (0, 0, 0):
        pqr, stu, v, wxy = (b, c, d), (f, g, h), 0, (j, k, m)
    elif key == (0, 0, 1):
        pqr, stu, v, wxy = (b, c, d), (f, g, h), 1, (0, 0, m)
    elif key == (0, 1, 0):
        pqr, stu, v, wxy = (b, c, d), (j, k, h), 1, (0, 1, m)
    elif key == (0, 1, 1):
        pqr, stu, v, wxy = (b, c, d), (1, 0, h), 1, (1, 1, m)
    elif key == (1, 0, 0):
        pqr, stu, v, wxy = (j, k, d), (f, g, h), 1, (1, 0, m)
    elif key == (1, 0, 1):
        pqr, stu, v, wxy = (f, g, d), (0, 1, h), 1, (1, 1, m)
    elif key == (1, 1, 0):
        pqr, stu, v, wxy = (j, k, d), (0, 0, h), 1, (1, 1, m)
    else:
        pqr, stu, v, wxy = (0, 0, d), (1, 1, h), 1, (1, 1, m)
    out = 0
    for bit in (*pqr, *stu, v, *wxy):
        out = (out << 1) | bit
    return out


_DECODE: dict[int, tuple[int, int, int]] = {}


def decode_declet(declet: int) -> tuple[int, int, int]:
    """A 10-bit declet to three decimal digits: the inverse of the encoding table (a declet
    outside the 1000 canonical ones decodes as the standard says, by its table row; only the
    canonical declets are accepted here)."""
    if not _DECODE:
        for n in range(1000):
            digits = (n // 100, n // 10 % 10, n % 10)
            _DECODE[encode_declet(digits)] = digits
        # the 24 redundant codes (p q free in the all-large row: bits v w x s t = 1) decode as
        # the canonical code with p = q = 0 (3.5.2: a non-canonical declet is accepted)
        for code in range(1024):
            if code not in _DECODE:
                _DECODE[code] = _DECODE[code & 0b0011111111]
    return _DECODE[declet]


def pack_coefficient_digits(digits: list[int], count: int) -> int:
    """The `count` declets of `digits` (most significant first, left padded with zeros)."""
    digits = [0] * (3 * count - len(digits)) + digits
    value = 0
    for index in range(count):
        value = (value << 10) | encode_declet(tuple(digits[3 * index : 3 * index + 3]))
    return value


def encode_finite(negative: bool, coefficient: int, exponent: int, fmt: Format) -> int:
    """The word of coefficient * 10^exponent; the coefficient has at most `precision` digits and
    the exponent is within the format (no rounding and no clamping here)."""
    if not (0 <= coefficient < 10**fmt.precision):
        raise ValueError("coefficient out of range")
    if not (fmt.qmin <= exponent <= fmt.qmax):
        raise ValueError("exponent out of range")
    digits = [int(c) for c in str(coefficient).rjust(fmt.precision, "0")]
    lead, rest = digits[0], digits[1:]
    biased = exponent + fmt.bias
    top2 = biased >> fmt.exponent_continuation
    ec = biased & ((1 << fmt.exponent_continuation) - 1)
    if lead < 8:
        combination = (top2 << 3) | lead
    else:
        combination = 0b11000 | (top2 << 1) | (lead & 1)
    cc_declets = (fmt.precision - 1) // 3
    cc = pack_coefficient_digits(rest, cc_declets)
    cc_bits = 10 * cc_declets
    word = int(negative)
    word = (word << 5) | combination
    word = (word << fmt.exponent_continuation) | ec
    word = (word << cc_bits) | cc
    return word


def encode_infinity(negative: bool, fmt: Format) -> int:
    return (int(negative) << (fmt.bits - 1)) | (0b11110 << (fmt.bits - 6))


def encode_nan(negative: bool, signaling: bool, payload: int, fmt: Format) -> int:
    cc_declets = (fmt.precision - 1) // 3
    digits = [int(c) for c in str(payload)] if payload else []
    cc = pack_coefficient_digits(digits, cc_declets)
    word = (int(negative) << (fmt.bits - 1)) | (0b11111 << (fmt.bits - 6))
    if signaling:
        word |= 1 << (fmt.bits - 7)
    return word | cc


def hex_word(word: int, fmt: Format) -> str:
    return "#" + format(word, "0%dX" % (fmt.bits // 4))


def decode_finite(word: int, fmt: Format):
    """(negative, coefficient, exponent) of a finite word, canonical or not."""
    negative = bool(word >> (fmt.bits - 1))
    combination = (word >> (fmt.bits - 6)) & 0b11111
    ec = (word >> (fmt.bits - 6 - fmt.exponent_continuation)) & ((1 << fmt.exponent_continuation) - 1)
    if combination >> 3 == 0b11:
        top2, lead = (combination >> 1) & 0b11, 8 + (combination & 1)
    else:
        top2, lead = combination >> 3, combination & 0b111
    cc_declets = (fmt.precision - 1) // 3
    digits = [lead]
    for index in range(cc_declets):
        shift = 10 * (cc_declets - 1 - index)
        digits.extend(decode_declet((word >> shift) & 0x3FF))
    coefficient = int("".join(map(str, digits)))
    exponent = ((top2 << fmt.exponent_continuation) | ec) - fmt.bias
    return negative, coefficient, exponent


def round_to_format(negative: bool, coefficient: int, exponent: int, fmt: Format, mode: str = "half_even"):
    """Round and clamp coefficient * 10^exponent to `fmt` (IEEE 754-2019 4.3.1, 7.4, 7.5).

    Returns (kind, coefficient, exponent, flags) with kind "finite" or "inf" and `flags` the
    set of {"inexact", "overflow", "underflow"}.
    """
    flags: set[str] = set()
    p = fmt.precision
    digits = len(str(coefficient)) if coefficient else 0
    drop = max(digits - p, fmt.qmin - exponent, 0)
    if drop > 0 and coefficient:
        q, r = divmod(coefficient, 10**drop)
        if r:
            flags.add("inexact")
            half = Fraction(r, 10**drop)
            if mode == "half_even":
                up = half > Fraction(1, 2) or (half == Fraction(1, 2) and q % 2 == 1)
            elif mode == "half_up":
                up = half >= Fraction(1, 2)
            elif mode == "down":
                up = False
            elif mode == "up":
                up = True
            elif mode == "floor":
                up = negative
            elif mode == "ceiling":
                up = not negative
            else:
                raise ValueError(mode)
            if up:
                q += 1
        coefficient, exponent = q, exponent + drop
        if len(str(coefficient)) > p:  # 999..9 rounded up
            coefficient //= 10
            exponent += 1
    elif drop > 0:
        exponent += drop
    if coefficient and exponent < fmt.qmin:
        raise ValueError("unreachable")
    if "inexact" in flags and exponent == fmt.qmin and (coefficient == 0 or len(str(coefficient)) < p):
        flags.add("underflow")
    if exponent > fmt.qmax:
        if coefficient == 0:
            exponent = fmt.qmax
        else:
            shift = exponent - fmt.qmax
            if len(str(coefficient)) + shift > p:
                flags.update({"overflow", "inexact"})
                return "inf", 0, 0, flags
            coefficient *= 10**shift
            exponent = fmt.qmax
    return "finite", coefficient, exponent, flags


def main(argv: list[str]) -> int:
    text, name = argv[1], argv[2]
    fmt = FORMATS[name]
    negative = text.startswith("-")
    body = text.lstrip("+-")
    mantissa, _, exp = body.lower().partition("e")
    whole, _, frac = mantissa.partition(".")
    coefficient = int(whole + frac)
    exponent = int(exp or 0) - len(frac)
    kind, c, e, flags = round_to_format(negative, coefficient, exponent, fmt)
    word = encode_infinity(negative, fmt) if kind == "inf" else encode_finite(negative, c, e, fmt)
    print(hex_word(word, fmt), sorted(flags))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
