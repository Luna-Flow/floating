#!/usr/bin/env python3
"""Check the nearest-away (`na`) arithmetic rows of a `mpfr-random-v1` file with exact arithmetic.

The MPFR generator (`generate_mpfr_random_oracle.c`) computes these rows with MPFR's
nearest-away wrapper and, for a result below the smallest normal number, rounds on the
subnormal grid itself because `mpfr_subnormalize` has no nearest-away mode. This program is
a second, independent oracle for the same class: it forms the exact result of `add`, `sub`,
`mul`, `div` and `fma` with integer and `Fraction` arithmetic (no MPFR, no library) and
rounds it to nearest with ties away from zero on the grid of the context (precision `p`
bits in the normal range, the weight `2^(emin - p + 1)` of the last place below it). It
compares the expected value and the flags: inexact, and underflow under the tininess rule
of the row. Rows with an overflow, a special operand, an exact zero result, a zero divisor
or exponents more than 5,000 binades apart in a sum are counted as skipped.

Usage: `check_random_rna_rows.py FILE...` (exit status 1 on a mismatch).
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

IMPLEMENTATION_EMAX = 1073741823
MAX_ADDEND_GAP = 5000
OPERATIONS = ("add", "sub", "mul", "div", "fma")

# An exact number: sign * ratio * 2^exponent, ratio in [1, 2); sign 0 is zero.
Number = tuple[int, Fraction, int]
ZERO: Number = (0, Fraction(0), 0)


def normalize(sign: int, ratio: Fraction, exponent: int) -> Number:
    if ratio == 0 or sign == 0:
        return ZERO
    shift = ratio.numerator.bit_length() - ratio.denominator.bit_length()
    scaled = ratio / Fraction(2) ** shift if shift >= 0 else ratio * Fraction(2) ** (-shift)
    shift_exponent = shift
    while scaled >= 2:
        scaled /= 2
        shift_exponent += 1
    while scaled < 1:
        scaled *= 2
        shift_exponent -= 1
    return (sign, scaled, exponent + shift_exponent)


def parse_number(token: str) -> Number | None:
    """`[-]0xMANTISSAp EXPONENT` as an exact number; `None` for `-`, an infinity or a NaN."""
    match = re.fullmatch(r"(-?)0x([0-9a-f]+)p(-?\d+)", token)
    if match is None:
        return None
    mantissa = int(match.group(2), 16)
    if mantissa == 0:
        return ZERO
    return normalize(-1 if match.group(1) else 1, Fraction(mantissa), int(match.group(3)))


def multiply(left: Number, right: Number) -> Number:
    return normalize(left[0] * right[0], left[1] * right[1], left[2] + right[2])


def divide(left: Number, right: Number) -> Number:
    return normalize(left[0] * right[0], left[1] / right[1], left[2] - right[2])


def add(left: Number, right: Number) -> Number | None:
    if left[0] == 0:
        return right
    if right[0] == 0:
        return left
    if abs(left[2] - right[2]) > MAX_ADDEND_GAP:
        return None
    base = min(left[2], right[2])
    total = left[0] * left[1] * Fraction(2) ** (left[2] - base) + right[0] * right[1] * Fraction(2) ** (right[2] - base)
    if total == 0:
        return ZERO
    return normalize(1 if total > 0 else -1, abs(total), base)


def negate(value: Number) -> Number:
    return (-value[0], value[1], value[2])


def round_away(value: Number, grid: int) -> Number:
    """The multiple of `2^grid` nearest to `value`, a tie going away from zero."""
    sign, ratio, exponent = value
    shift = exponent - grid
    if shift < -1:
        return ZERO
    quotient = ratio * Fraction(2) ** shift
    whole = quotient.numerator // quotient.denominator
    if quotient - whole >= Fraction(1, 2):
        whole += 1
    return normalize(sign, Fraction(whole), grid) if whole else ZERO


def same(left: Number, right: Number) -> bool:
    return left == right if left[0] != 0 and right[0] != 0 else left[0] == right[0]


@dataclass(frozen=True)
class Row:
    ident: str
    operation: str
    precision: int
    emin: int
    emax: int
    tininess: str
    operands: tuple[Number | None, ...]
    expected: Number | None
    flags: str


def parse_row(line: str) -> Row | None:
    """A `na` row of one of the checked operations, else `None`."""
    fields = line.split()
    if len(fields) < 13 or fields[2] != "na" or fields[1] not in OPERATIONS:
        return None
    emin = 1 - IMPLEMENTATION_EMAX if fields[4] == "-" else int(fields[4])
    emax = IMPLEMENTATION_EMAX if fields[5] == "-" else int(fields[5])
    operands = tuple(parse_number(token) for token in fields[7:10])
    return Row(fields[0], fields[1], int(fields[3]), emin, emax, fields[6], operands, parse_number(fields[11]), fields[12])


def exact_result(row: Row) -> Number | None:
    first, second, third = row.operands
    if first is None:
        return None
    if row.operation in ("add", "sub"):
        if second is None:
            return None
        return add(first, second if row.operation == "add" else negate(second))
    if second is None:
        return None
    if row.operation == "mul":
        return multiply(first, second)
    if row.operation == "div":
        return None if second[0] == 0 else divide(first, second)
    if third is None:
        return None
    return add(multiply(first, second), third)


@dataclass
class Report:
    checked: int = 0
    tiny: int = 0
    skipped: int = 0
    failures: list[str] | None = None

    def __post_init__(self) -> None:
        self.failures = []


def check_row(row: Row) -> str | None:
    """`None` when the row is right (or not checkable here: `skip`), else the reason it is wrong."""
    exact = exact_result(row)
    if exact is None or exact[0] == 0 or row.expected is None:
        return "skip"
    tiny = exact[2] < row.emin
    grid = row.emin - row.precision + 1 if tiny else exact[2] - row.precision + 1
    result = round_away(exact, grid)
    if result[0] != 0 and result[2] > row.emax:
        return "skip"
    problems = []
    if not same(result, row.expected):
        problems.append("value")
    inexact = not same(result, exact)
    if ("x" in row.flags) != inexact:
        problems.append("inexact flag")
    if tiny and inexact and row.tininess in ("a", "b"):
        if row.tininess == "b":
            underflow = True
        else:
            at_precision = round_away(exact, exact[2] - row.precision + 1)
            underflow = at_precision[0] == 0 or at_precision[2] < row.emin
        if ("u" in row.flags) != underflow:
            problems.append("underflow flag")
    return ", ".join(problems) if problems else None


def check_text(text: str) -> Report:
    report = Report()
    assert report.failures is not None
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        row = parse_row(line)
        if row is None:
            continue
        outcome = check_row(row)
        if outcome == "skip":
            report.skipped += 1
            continue
        report.checked += 1
        if row.operands and (exact := exact_result(row)) is not None and exact[2] < row.emin:
            report.tiny += 1
        if outcome is not None:
            report.failures.append(f"{row.ident}: {outcome}")
    return report


def main(arguments: list[str]) -> int:
    status = 0
    for name in arguments:
        report = check_text(Path(name).read_text(encoding="utf-8"))
        assert report.failures is not None
        print(f"{name}: {report.checked} rows checked ({report.tiny} with a result below the smallest normal), {report.skipped} skipped, {len(report.failures)} wrong")
        for failure in report.failures[:10]:
            print(f"  {failure}")
        status = status or (1 if report.failures else 0)
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
