#!/usr/bin/env python3
"""Rows for the binary to decimal endpoint conversions of `decimal_gda`.

Writes `library/src/decimal_gda/certified_endpoint_rows_wbtest.mbt` with two tables.

`dyadic_endpoint_rows`: `(negative, coefficient hex, exponent2, context, text, over, under)` for
`decimal_exact_dyadic_endpoint`. The value is `(-1)^negative * coefficient * 2^exponent2`.
`text` is its exact decimal: for `exponent2 >= 0` the integer `coefficient << exponent2`, for
`exponent2 < 0` the integer `coefficient * 5^k` with exponent `-k` (k = -exponent2) from which
trailing zeros are removed while the exponent is negative (the form the library returns; the
value is what the endpoint users need, the form is pinned here), printed by CPython `decimal` (`str`, the to-scientific-string of
GDA 1.70). `over` is true when the exact value is at least `10^(emax + 2)` and `under` when it is
below `10^(etiny - 2)`: the library may replace such a value by the representative
`1E+(emax + 2)` or `1E+(etiny - 2)` of the same sign (the exact `text` is also accepted, the
replacement is only licensed). Contexts: 0 is precision 34, emin -999999999, emax 999999999
(etiny = emin - precision + 1 = -1000000032); 1 is precision 7, emin -99, emax 99 (etiny -105).
`over` and `under` are decided here by exact integer comparison, with no model of the library.

`limb_edge_rows`: `(pattern, length, digit count, first 20 digits, last 20 digits)` for the
decimal digits of an integer given by a big-endian byte string: pattern `one` is 0x01 followed
by `length - 1` zero bytes and pattern `ones` is `length` bytes of 0xFF, so the integer is
`2^(8 (length - 1))` and `2^(8 length) - 1`. Lengths include 8917 and 8918 (the first length
whose bit count times 30103 exceeds Int32), 9000 and 20000. The digits are CPython integers.

    python3 tools/generate_decimal_gda_endpoint_rows.py && moon fmt
    python3 tools/generate_decimal_gda_endpoint_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal_gda/certified_endpoint_rows_wbtest.mbt"
SEED = 0xD1B54A32D192ED03

# precision, emin, emax
CONTEXTS = [(34, -999999999, 999999999), (7, -99, 99)]
EXPONENTS = [0, 1, 7, 63, 64, -1, -9, -63, -64, -200, 200]
LIMB_LENGTHS = [1, 2, 8, 9, 63, 64, 65, 300, 511, 512, 513, 1000, 2047, 4999, 5000, 8917, 8918, 9000, 20000]

Row = tuple[bool, str, int, int, str, bool, bool]
LimbRow = tuple[str, int, int, str, str]


def exact_text(negative: bool, coefficient: int, exponent2: int) -> str:
    if exponent2 >= 0:
        integer, exponent = coefficient << exponent2, 0
    else:
        integer, exponent = coefficient * 5 ** (-exponent2), exponent2
        while exponent < 0 and integer % 10 == 0:  # trailing zeros removed while the exponent is negative
            integer //= 10
            exponent += 1
    value = decimal.Decimal((1 if negative else 0, tuple(int(d) for d in str(integer)), exponent))
    return str(value)


def over_under(coefficient: int, exponent2: int, context: int) -> tuple[bool, bool]:
    """Exact comparison of `coefficient * 2^exponent2` with 10^(emax+2) and 10^(etiny-2)."""
    precision, emin, emax = CONTEXTS[context]
    etiny = emin - precision + 1

    def below(limit10: int) -> int:  # sign of value - 10^limit10
        if abs(limit10) > 100000:  # the values here have |log10| < 5000: decided by the sign of the limit
            return 1 if limit10 < 0 else -1
        lhs = coefficient * 2 ** max(exponent2, 0) * 10 ** max(-limit10, 0)
        rhs = 2 ** max(-exponent2, 0) * 10 ** max(limit10, 0)
        return (lhs > rhs) - (lhs < rhs)

    return below(emax + 2) >= 0, below(etiny - 2) < 0


def row(negative: bool, coefficient: int, exponent2: int, context: int) -> Row:
    over, under = over_under(coefficient, exponent2, context)
    text = exact_text(negative, coefficient, exponent2)
    digits = format(coefficient, "x")
    digits = digits if len(digits) % 2 == 0 else "0" + digits
    return (negative, digits, exponent2, context, text, over, under)


def build_dyadic() -> list[Row]:
    sys.set_int_max_str_digits(0)
    rng = random.Random(SEED)
    rows: list[Row] = []
    for iteration in range(140):
        length = 1 + rng.randrange(24) + (400 if iteration % 40 == 0 else 0)
        coefficient = int.from_bytes(rng.randbytes(length), "big")
        if iteration % 3 == 1:  # long runs of equal bytes, as the byte generator of the tests
            coefficient = int.from_bytes(bytes([255]) * length, "big") if iteration % 2 else 1 << (8 * length - 1)
        if coefficient == 0:
            continue
        negative = rng.randrange(2) == 0
        exponents = EXPONENTS + [-rng.randrange(1500), rng.randrange(1500)]
        for exponent2 in exponents:
            if length > 24 and abs(exponent2) > 200 and iteration % 40 != 0:
                continue
            context = rng.randrange(2)
            if length > 24:
                # keep the exact text short: one context only, no big negative exponents
                if exponent2 < -200:
                    continue
            rows.append(row(negative, coefficient, exponent2, context))
    # the ends of the exponent range of the narrow context: 10^101 and 10^-107 and their neighbours
    for exponent2 in (333, 334, 335, 336, 337, -349, -350, -351, -352, -353, -354):
        for coefficient in (1, 3, (1 << 20) + 1):
            for negative in (False, True):
                rows.append(row(negative, coefficient, exponent2, 1))
    return rows


def build_limbs() -> list[LimbRow]:
    sys.set_int_max_str_digits(0)
    rows: list[LimbRow] = [("ones", 0, 1, "0", "0")]
    for length in LIMB_LENGTHS:
        for pattern, value in (
            ("one", 1 << (8 * (length - 1))),
            ("ones", (1 << (8 * length)) - 1),
        ):
            digits = str(value)
            rows.append((pattern, length, len(digits), digits[:20], digits[-20:]))
    return rows


def render(rows: list[Row], limbs: list[LimbRow]) -> str:
    lines = [
        "///|",
        "// Columns of dyadic_endpoint_rows: negative, coefficient (hex), exponent2, context (0 wide, 1 narrow), exact text, over, under.",
        "// Columns of limb_edge_rows: pattern (one = 0x01 then zero bytes, ones = 0xFF bytes), length, digit count, first 20 digits, last 20 digits.",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_gda_endpoint_rows.py (CPython integers and `decimal`, libmpdec)",
        "// input: binary values (coefficient hex, exponent2, sign) in two contexts, with the exact decimal text and the exact over / under classification against 10^(emax+2) and 10^(etiny-2); byte strings of 1 to 20000 bytes with the digit count, first 20 and last 20 digits of their integer",
        "// library-ran: no",
        "",
        "///|",
        "let dyadic_endpoint_rows : Array[(Bool, String, Int32, Int32, String, Bool, Bool)] = [",
    ]
    for negative, hexa, e2, context, text, over, under in rows:
        b = lambda x: "true" if x else "false"
        lines.append(f'  ({b(negative)}, "{hexa}", {e2}, {context}, "{text}", {b(over)}, {b(under)}),')
    lines += ["]", "", "///|", "let limb_edge_rows : Array[(String, Int32, Int32, String, String)] = ["]
    for pattern, length, count, head, tail in limbs:
        lines.append(f'  ("{pattern}", {length}, {count}, "{head}", "{tail}"),')
    lines.append("]")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text_out = render(build_dyadic(), build_limbs())
    if args.check:
        norm = lambda s: re.sub(r"\s+", "", s).replace(",)", ")").replace(",]", "]")
        if not OUTPUT.is_file() or norm(OUTPUT.read_text(encoding="utf-8")) != norm(text_out):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text_out, encoding="utf-8")
    print(f"{OUTPUT}: {len(text_out.splitlines())} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
