#!/usr/bin/env python3
"""Rows for the encoders of the decimal interchange formats (`to_interchange_hex`, `from_decimal`).

Writes `tooling/src/consistency/interchange_rows_wbtest.mbt`, a table of
`(decimal text, format, expected word, inexact, overflow, underflow)`. The word is the
IEEE 754-2019 3.5.2 encoding (densely packed decimal) of the value rounded to the format
(ties to even, 4.3.1; overflow and underflow of 7.4 and 7.5) computed by
`tools/decimal_interchange_oracle.py`, which is written from the layout of the standard and
checked against the vector files `testdata/decimal/ieee/decimal*_dpd.json`. The library does
not run.

    python3 tools/generate_interchange_rows.py
    python3 tools/generate_interchange_rows.py --check
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import decimal_interchange_oracle as oracle

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tooling/src/consistency/interchange_rows_wbtest.mbt"
Row = tuple[str, str, str, bool, bool, bool]


def texts_for(fmt: oracle.Format) -> list[tuple[int, int]]:
    """(coefficient, exponent) pairs, the value being coefficient * 10^exponent."""
    p, qmax, qmin = fmt.precision, fmt.qmax, fmt.qmin
    nines = 10**p - 1
    rows = [
        (1, 0), (750, -2), (123, fmt.emax - 2), (123, fmt.emax - 3 - p), (nines, qmax), (1, qmax),
        (1, 1 - fmt.emax), (1, qmin), (nines, qmin), (0, 0), (0, qmin), (0, qmax + 3), (5, 0),
        # more digits than the format: below the tie, the tie to even (both parities), above the tie, carry
        (int("1" * (p + 1)), 0), (int("1" * p + "4"), 0), (int("1" * (p - 1) + "25"), 0),
        (int("1" * (p - 1) + "35"), 0), (int("1" * p + "6"), 0), (nines * 10 + 5, 0), (nines * 10 + 4, 0),
        # overflow: one decade above the largest, and a rounding up past it
        (1, fmt.emax + 1), (nines * 10 + 5, qmax), (nines, qmax + 1),
        # below the smallest: tie to zero, above the tie, and a value that rounds to the smallest
        (1, qmin - 1), (5, qmin - 1), (6, qmin - 1), (15, qmin - 1), (25, qmin - 1), (1, qmin - 5),
    ]
    return rows


def to_text(coefficient: int, exponent: int) -> str:
    return f"{coefficient}E{exponent}"


def all_rows() -> list[Row]:
    rows: list[Row] = []
    for fmt in (oracle.DECIMAL32, oracle.DECIMAL64, oracle.DECIMAL128):
        for coefficient, exponent in texts_for(fmt):
            for negative in (False, True):
                kind, c, e, flags = oracle.round_to_format(negative, coefficient, exponent, fmt)
                word = (
                    oracle.encode_infinity(negative, fmt) if kind == "inf" else oracle.encode_finite(negative, c, e, fmt)
                )
                text = ("-" if negative else "") + to_text(coefficient, exponent)
                rows.append(
                    (text, fmt.name, oracle.hex_word(word, fmt), "inexact" in flags, "overflow" in flags, "underflow" in flags)
                )
        width = fmt.precision - 1
        full = int("9" * width)
        distinct = int(("1234567890" * 4)[:width])
        for payload in (0, 12345, 54321, full, distinct):
            for negative in (False, True):
                for signaling in (False, True):
                    word = oracle.encode_nan(negative, signaling, payload, fmt)
                    text = ("-" if negative else "") + ("sNaN" if signaling else "NaN") + (str(payload) if payload else "")
                    rows.append((text, fmt.name, oracle.hex_word(word, fmt), False, False, False))
        for negative in (False, True):
            rows.append(
                (("-" if negative else "") + "Infinity", fmt.name, oracle.hex_word(oracle.encode_infinity(negative, fmt), fmt), False, False, False)
            )
    return rows


def render(rows: list[Row]) -> str:
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_interchange_rows.py with tools/decimal_interchange_oracle.py (the layout of IEEE 754-2019 3.5.2 in",
        "//   Python, checked against testdata/decimal/ieee/decimal*_dpd.json; rounding to the format by Python integers)",
        "// input: per format 29 finite values (exact, clamped, largest, smallest, zeros, more digits than the format with the ties and a",
        "//   carry, overflow, underflow), both signs, quiet and signaling NaN with payloads 0, 12345, 54321 and two of the full width of the format (6.2.3), infinities",
        "// Columns: decimal text, format, expected word, inexact, overflow, underflow.",
        "// library-ran: no",
        "",
        "///|",
        "fn interchange_rows() -> Array[(String, String, String, Bool, Bool, Bool)] {",
        "  [",
    ]
    for text, fmt, word, inexact, overflow, underflow in rows:
        out.append(
            f'    ("{text}", "{fmt}", "{word}", {str(inexact).lower()}, {str(overflow).lower()}, {str(underflow).lower()}),'
        )
    out += ["  ]", "}", ""]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""

        def norm(s: str) -> str:
            squeezed = "".join(s.split())
            for closer in (")", "]", "}"):
                squeezed = squeezed.replace("," + closer, closer)
            return squeezed

        if norm(current) != norm(text):
            print(f"{OUTPUT} is stale: run tools/generate_interchange_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(text)} bytes, {len(all_rows())} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
