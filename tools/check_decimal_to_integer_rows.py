#!/usr/bin/env python3
"""Checks the rows of `library/src/decimal/to_integer_wbtest.mbt` (issue 226) with exact rational arithmetic.

Each row is `(text, mode, Int, Int64, UInt, UInt64, changed)`: the integer the text rounds to in the
rounding direction `mode` (IEEE 754-2019 4.3.1 and 5.8, the General Decimal Arithmetic modes), or `none`
when the value is not a number, infinite, or outside the range of the destination type, and whether
rounding changed the value. The rows are recomputed here with `fractions.Fraction`, independent of the
library, and every row must agree.

    python3 tools/check_decimal_to_integer_rows.py
"""

from __future__ import annotations

import decimal
import math
import re
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "library/src/decimal/to_integer_wbtest.mbt"
ROW = re.compile(r'\("([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)", (true|false)\)')
RANGES = ((-(2**31), 2**31 - 1), (-(2**63), 2**63 - 1), (0, 2**32 - 1), (0, 2**64 - 1))
SPECIALS = ("NaN", "-NaN", "sNaN", "Infinity", "-Infinity")


def rounded(value: Fraction, mode: str) -> int:
    """`value` rounded to an integer in the named direction."""
    floor = math.floor(value)
    if value == floor:
        return floor
    toward_zero = math.trunc(value)
    away = toward_zero + (-1 if value < 0 else 1)
    distance = abs(value - toward_zero)
    if mode == "down":
        return toward_zero
    if mode == "up":
        return away
    if mode == "ceiling":
        return floor + 1
    if mode == "floor":
        return floor
    if mode == "05up":
        return away if abs(toward_zero) % 5 == 0 else toward_zero
    if mode in ("half_even", "half_up", "half_down"):
        if distance != Fraction(1, 2):
            return away if distance > Fraction(1, 2) else toward_zero
        if mode == "half_up":
            return away
        if mode == "half_down":
            return toward_zero
        return toward_zero if toward_zero % 2 == 0 else away
    raise ValueError(f"unknown mode {mode}")


def expected(text: str, mode: str) -> tuple[list[str], bool]:
    """The four destination texts and the changed flag of one row."""
    if text in SPECIALS:
        return ["none"] * 4, False
    exact = Fraction(decimal.Decimal(text))
    result = rounded(exact, mode)
    texts = [str(result) if low <= result <= high else "none" for low, high in RANGES]
    return texts, result != exact


def check(source: str) -> list[str]:
    """The rows of `source` that disagree with the recomputation, as text; empty when all agree."""
    problems = []
    rows = ROW.findall(source)
    for text, mode, *destinations, changed in rows:
        texts, flag = expected(text, mode)
        if destinations != texts or (changed == "true") != flag:
            problems.append(f"{text} {mode}: file {destinations} {changed}, recomputed {texts} {flag}")
    if len(rows) != 550:
        problems.append(f"expected 550 rows, found {len(rows)}")
    return problems


def main() -> int:
    problems = check(SOURCE.read_text())
    for problem in problems:
        print(problem)
    print("check_decimal_to_integer_rows:", "FAIL" if problems else "550 rows agree")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
