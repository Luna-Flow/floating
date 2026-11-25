#!/usr/bin/env python3
"""Rows for `Decimal::from_binary_raw` of `decimal_gda` (binary value to decimal).

Writes `library/src/decimal_gda/from_binary_rows_wbtest.mbt`, a table of
`(negative, coefficient hex, exponent2, precision, mode, text, exponent10)`: the binary
value is `(-1)^negative * coefficient * 2^exponent2`, the result is that value converted
to a decimal of `precision` digits in the rounding mode `mode`.

The expected values come from CPython integers and `decimal` (libmpdec), not from the
library. The exact decimal value is built by integer arithmetic: for `exponent2 >= 0` the
integer `coefficient << exponent2` with exponent 0 (the cohort is not reduced), for
`exponent2 < 0` the integer `coefficient * 5^k` with exponent `-k` (k = -exponent2) from which
trailing zeros are removed while the exponent is negative (the preferred exponent of an
exact result). That decimal is then rounded to `precision` digits by
`Context(prec=precision, rounding=ROUND_*, Emin, Emax very wide).plus`, which is correctly
rounded for all eight rounding rules of GDA 1.70 (HalfEven, HalfUp, HalfDown, Down,
Ceiling, Floor, Up, ZeroFiveUp = ROUND_05UP). `text` is `str()` of the result (the
to-scientific-string of GDA 1.70) and `exponent10` its exponent.

Rows (deterministic, seeded): the powers of two and of ten and their neighbours at
binary exponents 0, 1, -1, +-shift and +-2000 (both ends of the range the surrogate bound
uses), every sign, rounding rules and precisions in rotation; and the bases and shifts of issue 467, and random coefficients of 1
to 24 bytes (some of 300 bytes) at 0, +-1, +-63, +-64 and random exponents to +-2000.

    python3 tools/generate_decimal_gda_from_binary_rows.py && moon fmt
    python3 tools/generate_decimal_gda_from_binary_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal_gda/from_binary_rows_wbtest.mbt"

MODES: dict[str, str] = {
    "HalfEven": decimal.ROUND_HALF_EVEN,
    "HalfUp": decimal.ROUND_HALF_UP,
    "HalfDown": decimal.ROUND_HALF_DOWN,
    "Down": decimal.ROUND_DOWN,
    "Ceiling": decimal.ROUND_CEILING,
    "Floor": decimal.ROUND_FLOOR,
    "Up": decimal.ROUND_UP,
    "ZeroFiveUp": decimal.ROUND_05UP,
}
MODE_NAMES = list(MODES)
SHIFTS = [0, 1, 3, 4, 10, 31, 32, 33, 52, 53, 63, 64, 65, 127, 128, 129, 256, 419]
PRECISIONS = [1, 3, 17, 34, 1000]
RANDOM_PRECISIONS = [1, 2, 5, 9, 16, 17, 34, 50, 100, 250]
SEED = 0x2545F4914F6CDD1D

Row = tuple[bool, str, int, int, str, str, int]


def exact_parts(coefficient: int, exponent2: int) -> tuple[int, int]:
    """The exact decimal `(integer, exponent10)` of `coefficient * 2^exponent2`."""
    if exponent2 >= 0:
        return coefficient << exponent2, 0
    k = -exponent2
    integer = coefficient * 5**k
    exponent = -k
    while exponent < 0 and integer % 10 == 0:
        integer //= 10
        exponent += 1
    return integer, exponent


def convert(negative: bool, coefficient: int, exponent2: int, precision: int, mode: str) -> tuple[str, int]:
    """Text and exponent of the exact value rounded to `precision` digits by `mode`."""
    integer, exponent = exact_parts(coefficient, exponent2)
    exact = decimal.Decimal((1 if negative else 0, tuple(int(d) for d in str(integer)), exponent))
    ctx = decimal.Context(
        prec=precision,
        rounding=MODES[mode],
        Emax=decimal.MAX_EMAX,
        Emin=decimal.MIN_EMIN,
        traps=[],
        flags=[],
    )
    result = ctx.plus(exact)
    exponent10 = result.as_tuple().exponent
    assert isinstance(exponent10, int)
    return str(result), exponent10


def hex_of(value: int) -> str:
    digits = format(value, "x")
    return digits if len(digits) % 2 == 0 else "0" + digits


def row(negative: bool, coefficient: int, exponent2: int, precision: int, mode: str) -> Row:
    text, exponent10 = convert(negative, coefficient, exponent2, precision, mode)
    return (negative, hex_of(coefficient), exponent2, precision, mode, text, exponent10)


def build() -> list[Row]:
    rows: list[Row] = []
    for shift in SHIFTS:
        for base in (1 << shift, 10 ** (shift // 3)):
            for delta in (-1, 0, 1):
                n = base + delta
                if n <= 0:
                    continue
                for index, exponent2 in enumerate([0, -1, -shift, shift, -2000, 2000]):
                    for negative in (False, True):
                        precision = PRECISIONS[(shift + index + delta) % 4]  # 1000 only below
                        mode = MODE_NAMES[(shift + index + delta + int(negative)) % 8]
                        rows.append(row(negative, n, exponent2, precision, mode))
    rng = random.Random(SEED)
    for iteration in range(400):
        length = 1 + rng.randrange(300) if iteration % 10 == 1 else 1 + rng.randrange(24)
        coefficient = int.from_bytes(rng.randbytes(length), "big")
        if coefficient == 0:
            continue
        negative = rng.randrange(2) == 0
        span = 400 if length > 24 else 2000
        for exponent2 in (0, 1, -1, 63, -63, 64, -64, rng.randrange(span), -rng.randrange(span)):
            precision = RANDOM_PRECISIONS[rng.randrange(len(RANDOM_PRECISIONS))]
            mode = MODE_NAMES[rng.randrange(8)]
            if iteration % 10 != 1 and iteration % 2 != 0:
                continue  # half of the random iterations are kept
            rows.append(row(negative, coefficient, exponent2, precision, mode))
    # the bases and shifts of issue 467 (the bounded form), half even, precisions in rotation
    bases467 = [1, 3, 5, 7, 10, 255, 12345, 3602879701896397]
    shifts467 = [-6000, -3000, -2049, -1100, -1025, -1024, 1024, 1025, 1100, 2049, 3000, 6000]
    precisions467 = [1, 2, 3, 5, 9, 17, 34, 100, 400]
    for i, base in enumerate(bases467):
        for j, shift in enumerate(shifts467):
            rows.append(row(False, base, shift, precisions467[(i + j) % 9], "HalfEven"))
    # precision 1000 at the ends of the exponent range
    for index, (coefficient, exponent2) in enumerate(
        [(3, 2000), (3, -2000), ((1 << 200) + 1, 2000), ((1 << 200) + 1, -1000), (10**30 + 7, -63)]
    ):
        for mode in MODE_NAMES:
            rows.append(row(index % 2 == 1, coefficient, exponent2, 1000, mode))
    return rows


def render(rows: list[Row]) -> str:
    lines = [
        "///|",
        "// Columns: negative, coefficient (big-endian hex), exponent2, precision, rounding mode, text, exponent10.",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_gda_from_binary_rows.py (CPython integers and `decimal`, libmpdec)",
        "// input: binary values (coefficient hex, exponent2, sign) at the powers of two and of ten and their neighbours and random coefficients, exponent2 from -2000 to 2000, precision 1 to 1000, all eight rounding rules; expected text and exponent10 are the exact value rounded to the precision by libmpdec",
        "// library-ran: no",
        "",
        "///|",
        "let from_binary_rows : Array[(Bool, String, Int32, Int32, String, String, Int32)] = [",
    ]
    for negative, hexa, exponent2, precision, mode, text, exponent10 in rows:
        flag = "true" if negative else "false"
        lines.append(f'  ({flag}, "{hexa}", {exponent2}, {precision}, "{mode}", "{text}", {exponent10}),')
    lines.append("]")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    sys.set_int_max_str_digits(0)
    text_out = render(build())
    if args.check:
        norm = lambda s: re.sub(r"\s+", "", s).replace(",)", ")").replace(",]", "]")
        if not OUTPUT.is_file() or norm(OUTPUT.read_text(encoding="utf-8")) != norm(text_out):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text_out, encoding="utf-8")
    print(f"{OUTPUT}: {len(text_out.splitlines()) - 10} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
