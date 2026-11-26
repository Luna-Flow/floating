#!/usr/bin/env python3
"""Binary integer decimal (BID) words of the decimal interchange formats, IEEE 754-2019 3.5.2.

Written from the text of 3.5.2 (binary encoding of the significand), with no code of the library, next to
`decimal_interchange_oracle.py` (the DPD side, same `Format` objects). The vectors of
`library/src/decimal/interchange_wbtest.mbt` are asserted in `decimal_interchange_vectors_test.py`.
"""

from __future__ import annotations

from typing import NamedTuple

from decimal_interchange_oracle import Format


class Datum(NamedTuple):
    sign: int
    kind: str  # "finite", "inf", "qnan" or "snan"
    coefficient: int  # the significand, or the payload of a NaN
    exponent: int  # q = E - bias; 0 for a non-finite datum


def trailing_bits(fmt: Format) -> int:
    return 10 * ((fmt.precision - 1) // 3)


def canonical_payload(fmt: Format, payload: int) -> int:
    """A NaN payload of 10^(p-1) or more is non-canonical and read as zero (3.5.2 a)."""
    return payload if payload < 10 ** (fmt.precision - 1) else 0


def encode(fmt: Format, datum: Datum) -> int:
    sign = datum.sign << (fmt.bits - 1)
    if datum.kind == "inf":
        return sign | (0b11110 << (fmt.bits - 6))
    if datum.kind in ("qnan", "snan"):
        flag = 1 << (fmt.bits - 7) if datum.kind == "snan" else 0
        return sign | (0b11111 << (fmt.bits - 6)) | flag | canonical_payload(fmt, datum.coefficient)
    m = trailing_bits(fmt) + 3  # the significand bits of the first form
    biased = datum.exponent + fmt.bias
    if datum.coefficient < 1 << m:  # G0 G1 is 00, 01 or 10: E then the significand
        return sign | (biased << m) | datum.coefficient
    # G0 G1 = 11: E, then the significand with the prefix 100 implied (8 + G(w+4))
    return sign | (0b11 << (fmt.bits - 3)) | (biased << (m - 2)) | (datum.coefficient - (1 << m))


def decode(fmt: Format, bits: int) -> Datum:
    sign = bits >> (fmt.bits - 1)
    combination = (bits >> (fmt.bits - 6)) & 0b11111
    if combination == 0b11110:
        return Datum(sign, "inf", 0, 0)
    t = trailing_bits(fmt)
    if combination == 0b11111:
        kind = "snan" if (bits >> (fmt.bits - 7)) & 1 else "qnan"
        return Datum(sign, kind, canonical_payload(fmt, bits & ((1 << t) - 1)), 0)
    m = t + 3
    exponent_bits = fmt.exponent_continuation + 2
    if (bits >> (fmt.bits - 3)) & 0b11 == 0b11:
        biased = (bits >> (m - 2)) & ((1 << exponent_bits) - 1)
        coefficient = (1 << m) + (bits & ((1 << (m - 2)) - 1))
    else:
        biased = (bits >> m) & ((1 << exponent_bits) - 1)
        coefficient = bits & ((1 << m) - 1)
    if coefficient >= 10**fmt.precision:  # non-canonical: the value used is zero
        coefficient = 0
    return Datum(sign, "finite", coefficient, biased - fmt.bias)
