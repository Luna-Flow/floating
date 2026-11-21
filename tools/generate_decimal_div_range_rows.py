#!/usr/bin/env python3
"""Rows for `library/src/decimal/div_range_issue676_wbtest.mbt`.

The issue 676 table, then a seeded sweep of the plain operators `/`, `+`, `-`, `*`
over operand exponents at the bottom and the top of the stored range of `decimal`
(smallest exponent -2147483645, largest adjusted exponent 2147483646). The expected
value of every row is computed by CPython `decimal` (libmpdec) in the plain working
context (precision 34, half-even, no clamp) and written in the text format of
`Decimal::to_string`, so that the test compares text with text.

Run:    python3 tools/generate_decimal_div_range_rows.py > rows.mbt
Check:  python3 tools/generate_decimal_div_range_rows.py --check library/src/decimal/div_range_issue676_wbtest.mbt
        (regenerates the row table and compares it with the one in the file; the
        generator's header line with the Python and libmpdec versions is not compared)
"""

from __future__ import annotations

import argparse
import decimal
import random
import sys
from typing import NamedTuple

SEED = 676
ROWS_PER_OPERATOR = 500
TINY = -2147483645
EMAX = 2147483646
DEFAULT_PRECISION = 34
DIGIT_COUNTS = (1, 1, 2, 3, 5, 9, 10, 18, 19, 30, 33, 34)
ISSUE_ROWS: tuple[tuple[str, str], ...] = (
    ("123456789012345678E-2", "25E+2147483645"),
    ("123456789012345678E-2", "250E+2147483644"),
    ("123456789012345678E-2147483645", "25E+2"),
    ("123456789012345678E-2147483645", "250E+1"),
    ("123456789012345678E-2147483645", "250E+2"),
    ("123456789012345678E-1073741824", "25E+1073741824"),
    ("123456789012345678E-1073741824", "250E+1073741824"),
    ("1E-1", "12E+2147483644"),
)
EXPONENTS: tuple[int, ...] = (
    tuple(range(-2147483648, -2147483630))
    + tuple(range(2147483630, 2147483648))
    + (-1073741824, 1073741824, -2, 0, 2, -1073741823, 1073741823)
    + (-2147483645, 2147483645, -1000000000, 1000000000)
)
OPERATORS = ("/", "+", "-", "*")


class Row(NamedTuple):
    operator: str
    left: str
    right: str


def plain_context() -> decimal.Context:
    """The plain working context of `decimal`, as a libmpdec context."""
    return decimal.Context(
        prec=DEFAULT_PRECISION,
        rounding=decimal.ROUND_HALF_EVEN,
        Emax=EMAX,
        Emin=TINY + DEFAULT_PRECISION - 1,
        clamp=0,
        traps=[],
    )


def operand_text(coefficient: int, exponent: int, negative: bool) -> str:
    """An operand with its exponent moved into the stored range of its digits."""
    digits = len(str(coefficient))
    stored = min(max(exponent, TINY), EMAX - (digits - 1))
    return f"{'-' if negative else ''}{coefficient}E{stored}"


def random_coefficient(generator: random.Random) -> int:
    digit_count = generator.choice(DIGIT_COUNTS)
    if digit_count == 1:
        return generator.randint(1, 9)
    return generator.randint(10 ** (digit_count - 1), 10**digit_count - 1)


def rows() -> list[Row]:
    """The eight rows of the issue, then the seeded sweep."""
    generator = random.Random(SEED)
    table = [Row("/", left, right) for left, right in ISSUE_ROWS]
    for operator in OPERATORS:
        for _ in range(ROWS_PER_OPERATOR):
            operands = []
            for _ in range(2):
                coefficient = random_coefficient(generator)
                exponent = generator.choice(EXPONENTS)
                negative = generator.random() < 0.2
                operands.append(operand_text(coefficient, exponent, negative))
            table.append(Row(operator, operands[0], operands[1]))
    return table


def library_text(value: decimal.Decimal) -> str:
    """CPython's text of a result, with the special values spelled as in `Decimal::to_string`."""
    text = str(value)
    return {"Infinity": "inf", "-Infinity": "-inf", "NaN": "nan"}.get(text, text)


def expected(row: Row, context: decimal.Context) -> str:
    left = decimal.Decimal(row.left)
    right = decimal.Decimal(row.right)
    operations = {
        "/": context.divide,
        "+": context.add,
        "-": context.subtract,
        "*": context.multiply,
    }
    return library_text(operations[row.operator](left, right))


def table_text() -> str:
    context = plain_context()
    lines = [
        "///|",
        "let sweep_676_rows : Array[(String, String, String, String)] = [",
    ]
    for row in rows():
        fields = ", ".join(
            f'"{field}"' for field in (*row, expected(row, context))
        )
        lines.append(f"  ({fields}),")
    lines.append("]")
    return "\n".join(lines) + "\n"


def versions_comment() -> str:
    return (
        f"// generated with Python {sys.version.split()[0]}, "
        f"libmpdec {decimal.__libmpdec_version__}\n"
    )


def squeeze(text: str) -> str:
    """Whitespace removed: `moon fmt` may re-wrap the table."""
    return "".join(text.split()).replace(",)", ")")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", metavar="FILE", help="compare with the rows in FILE")
    arguments = parser.parse_args(argv)
    text = table_text()
    if arguments.check is None:
        sys.stdout.write(versions_comment() + text)
        return 0
    with open(arguments.check, encoding="utf-8") as handle:
        committed = handle.read()
    if squeeze(text) in squeeze(committed):
        print("rows match")
        return 0
    print("rows differ from the generator", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
