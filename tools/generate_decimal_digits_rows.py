#!/usr/bin/env python3
"""Rows for `library/src/binary/decimal_format_range_issue677_wbtest.mbt`.

Each row is (coefficient, binary exponent, digits, expected text): the value
`coefficient * 2^exponent` rounded once to `digits` significant decimal digits,
to nearest with ties to even, written as `d.ddde+x`. The expected text comes from
CPython `decimal` (libmpdec): the power of two is computed with `digits + 60`
digits and the result is rounded once; a row whose discarded digits lie within
10^-29 of a tie is refused, so the double rounding cannot matter. Nothing comes
from the library under test.

    python3 tools/generate_decimal_digits_rows.py            # rewrite the rows
    python3 tools/generate_decimal_digits_rows.py --check    # compare with the committed rows
"""

from __future__ import annotations

import argparse
import decimal
import sys
from decimal import Decimal, localcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "library/src/binary/decimal_format_range_issue677_wbtest.mbt"
BEGIN = "// BEGIN ROWS"
END = "// END ROWS"

IMPLEMENTATION_E_MIN = -(2**30) + 2
IMPLEMENTATION_E_MAX = 2**30 - 1
COEFFICIENTS = (1, 3, (1 << 53) - 1)
DIGIT_COUNTS = (1, 7, 34, 100)
GUARD_DIGITS = 60
TIE_WINDOW = 29

Row = tuple[int, int, int, str]

# `binary_ten_power_applied` splits a power of ten above this count
# (`decimal_format_split_power` in decimal_format.mbt).
SPLIT_POWER = 1 << 28
THRESHOLD_COEFFICIENT = 3
THRESHOLD_DIGITS = (7, 34)
THRESHOLD_COUNTS = (SPLIT_POWER - 1, SPLIT_POWER, SPLIT_POWER + 1)


def exponents_for(coefficient: int) -> list[int]:
    """The exponents probed for one coefficient: both ends of the range and some inside."""
    highest = IMPLEMENTATION_E_MAX - coefficient.bit_length() + 1
    inside = [-2000, -1, 0, 5, 1000]
    low_end = [IMPLEMENTATION_E_MIN + step for step in (0, 1, 100, 122)]
    high_end = [highest - step for step in (0, 1, 122, 1000)]
    return sorted(set(low_end + inside + high_end))


def decimal_exponent(coefficient: int, exponent: int) -> int:
    """The exponent of the first decimal digit of `coefficient * 2^exponent`."""
    with localcontext() as context:
        context.prec = GUARD_DIGITS
        context.Emax = decimal.MAX_EMAX
        context.Emin = decimal.MIN_EMIN
        return (Decimal(coefficient) * (Decimal(2) ** exponent)).adjusted()


def scale_of(coefficient: int, exponent: int, digits: int) -> int:
    """The power of ten `binary_scaled_decimal_integer` is asked for: exponent - digits + 1."""
    return decimal_exponent(coefficient, exponent) - digits + 1


def exponent_for_scale(coefficient: int, digits: int, scale: int) -> int:
    """A binary exponent whose value has `scale_of(...) == scale` at `digits` digits."""
    wanted = scale + digits - 1
    guess = round(wanted * 3.321928094887362)
    for exponent in sorted(range(guess - 4, guess + 5), key=lambda e: abs(e - guess)):
        if decimal_exponent(coefficient, exponent) == wanted:
            return exponent
    raise ValueError(f"no exponent for scale {scale} at {digits} digits")


def threshold_rows() -> list[tuple[int, int, int]]:
    """Rows whose |scale| is one below, at and one above the split threshold, both signs."""
    rows: list[tuple[int, int, int]] = []
    for count in THRESHOLD_COUNTS:
        for scale in (count, -count):
            for digits in THRESHOLD_DIGITS:
                exponent = exponent_for_scale(THRESHOLD_COEFFICIENT, digits, scale)
                rows.append((THRESHOLD_COEFFICIENT, exponent, digits))
    return rows


def sides_covered(rows: list[tuple[int, int, int]]) -> bool:
    """Whether every sign of the scale has a row at or below the threshold and one above it."""
    scales = [scale_of(c, e, d) for c, e, d in rows]
    return all(
        any(0 < sign * scale <= SPLIT_POWER for scale in scales)
        and any(sign * scale > SPLIT_POWER for scale in scales)
        for sign in (1, -1)
    )


def decimal_text(coefficient: int, exponent: int, digits: int) -> str:
    """`coefficient * 2^exponent` rounded once to `digits` digits as `d.ddde+x`."""
    with localcontext() as context:
        context.prec = digits + GUARD_DIGITS
        context.Emax = decimal.MAX_EMAX
        context.Emin = decimal.MIN_EMIN
        exact = Decimal(coefficient) * (Decimal(2) ** exponent)
        tail = "".join(map(str, exact.as_tuple().digits))[digits : digits + TIE_WINDOW]
        near_tie = tail.startswith("5" + "0" * (TIE_WINDOW - 1)) or tail.startswith(
            "4" + "9" * (TIE_WINDOW - 1)
        )
        if near_tie:
            raise ValueError(f"row ({coefficient}, {exponent}, {digits}) is within 10^-{TIE_WINDOW} of a tie")
        context.prec = digits
        rounded = +exact
    parts = rounded.as_tuple()
    digit_string = "".join(map(str, parts.digits)).ljust(digits, "0")
    decimal_exponent = int(parts.exponent) + len(parts.digits) - 1
    mantissa = digit_string[0] + ("." + digit_string[1:] if digits > 1 else "")
    sign = "+" if decimal_exponent >= 0 else "-"
    return f"{mantissa}e{sign}{abs(decimal_exponent)}"


def build_rows() -> list[Row]:
    probes = [
        (coefficient, exponent, digits)
        for coefficient in COEFFICIENTS
        for exponent in exponents_for(coefficient)
        for digits in DIGIT_COUNTS
    ]
    edges = threshold_rows()
    if not sides_covered(edges):
        raise ValueError("the threshold rows do not cover both sides for both signs")
    return [(c, e, d, decimal_text(c, e, d)) for c, e, d in probes + edges]


def render_block(rows: list[Row], python_version: str, libmpdec_version: str) -> str:
    lines = [
        BEGIN,
        f"// generated by tools/generate_decimal_digits_rows.py: {len(rows)} rows,",
        f"// Python {python_version}, libmpdec {libmpdec_version}",
        "let binary_decimal_digits_range_rows : Array[(UInt64, Int32, Int32, String)] = [",
    ]
    lines += [f'  ({c}UL, {e}, {d}, "{text}"),' for c, e, d, text in rows]
    lines += ["]", END]
    return "\n".join(lines)


def row_lines(block: str) -> list[str]:
    """The lines of a block that carry data: everything but the version comments."""
    return [line for line in block.splitlines() if not line.startswith("//")]


def normalized_rows(block: str) -> str:
    """The data lines of a block without the layout `moon fmt` gives them: whitespace removed and the
    trailing commas before a closing bracket dropped, so a one-line row and a wrapped row compare equal."""
    squeezed = "".join("".join(row_lines(block)).split())
    for closer in (")", "]"):
        squeezed = squeezed.replace("," + closer, closer)
    return squeezed


def committed_block(text: str) -> str:
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    return text[start:end]


def current_block() -> str:
    return render_block(build_rows(), sys.version.split()[0], decimal.__libmpdec_version__)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare with the committed rows")
    args = parser.parse_args(argv)
    text = TARGET.read_text(encoding="utf-8")
    block = current_block()
    if args.check:
        if normalized_rows(block) != normalized_rows(committed_block(text)):
            print(f"{TARGET.relative_to(ROOT)}: the committed rows differ from the regenerated ones", file=sys.stderr)
            return 1
        print(f"{TARGET.relative_to(ROOT)}: {len(build_rows())} rows match")
        return 0
    TARGET.write_text(text.replace(committed_block(text), block), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
