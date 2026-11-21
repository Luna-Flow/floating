#!/usr/bin/env python3
"""Rows for `library/src/decimal/quantum_ctx_wbtest.mbt`.

IEEE 754-2019 5.3.2: for a finite x, quantum(x) is the number (0, q, 1), that is
1 x 10^q, with q the exponent of x. The expected text of every row is built from
the definition: the exponent q of the operand is read from the digits of the
operand text with Python integers, and the number (0, q, 1) is printed by CPython
`decimal` (libmpdec) in the format of `Decimal::to_string`. Nothing of the library
is used.

Run:    python3 tools/generate_decimal_quantum_rows.py
Check:  python3 tools/generate_decimal_quantum_rows.py --check library/src/decimal/quantum_ctx_wbtest.mbt
        (the row table is compared with the one in FILE, whitespace ignored)
"""

from __future__ import annotations

import argparse
import decimal
import sys

# decimal128: precision 34, emax 6144, smallest exponent etiny = -6176, largest
# exponent q = emax - p + 1 = 6111.
ETINY = -6176
QMAX = 6111

COEFFICIENTS: tuple[str, ...] = (
    "1", "10", "100", "5", "123", "9999999999999999999999999999999999",
    "1000000000000000000000000000000000",
)
EXPONENTS: tuple[int, ...] = (
    0, 1, -1, 2, -2, 7, -7, 33, -33, 100, -100, 6000, -6000, QMAX, ETINY,
    ETINY + 1, -6143, -6144, -6150,
)


def operand_text(sign: str, coefficient: str, exponent: int) -> str:
    return f"{sign}{coefficient}E{exponent}"


def exponent_of(text: str) -> int:
    """The exponent q of an operand text `[-]<digits>E<q>`."""
    return int(text.split("E")[1])


def quantum_text(exponent: int) -> str:
    """The number (0, q, 1) printed by CPython decimal, as `Decimal::to_string` does."""
    return str(decimal.Decimal((0, (1,), exponent)))


def finite_rows() -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for coefficient in COEFFICIENTS:
        for exponent in EXPONENTS:
            for sign in ("", "-"):
                digits = len(coefficient)
                # an operand is a number of decimal128: adjusted exponent at most 6144
                if exponent + digits - 1 > 6144:
                    continue
                text = operand_text(sign, coefficient, exponent)
                rows.append((text, quantum_text(exponent_of(text))))
    for sign in ("", "-"):
        for exponent in (0, 5, -5, ETINY, QMAX):
            text = operand_text(sign, "0", exponent)
            rows.append((text, quantum_text(exponent)))
    return rows


def table_text() -> str:
    lines = ["///|", "let quantum_rows : Array[(String, String)] = ["]
    for operand, expected in finite_rows():
        lines.append(f'  ("{operand}", "{expected}"),')
    lines.append("]")
    return "\n".join(lines) + "\n"


def versions_comment() -> str:
    return (
        f"// generated with Python {sys.version.split()[0]}, "
        f"libmpdec {decimal.__libmpdec_version__}\n"
    )


def squeeze(text: str) -> str:
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
