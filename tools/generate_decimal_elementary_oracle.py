#!/usr/bin/env python3
"""Convert MPFR directed dyadic bounds into certified Decimal oracle rows."""

from __future__ import annotations

import argparse
import decimal
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / ".tmp/mpfr-decimal-interval.txt"
DEFAULT_OUTPUT = ROOT / "testdata/decimal/ieee/elementary_mpfr_oracle.json"
HEX = re.compile(r"^(?P<sign>-?)0x(?P<coefficient>[0-9a-f]+)p(?P<exponent>-?[0-9]+)$")
FORMATS = {
    "decimal32": (7, -95, 96, 1),
    "decimal64": (16, -383, 384, 1),
    "decimal128": (34, -6143, 6144, 1),
}
ROUNDINGS = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "half_up": decimal.ROUND_HALF_UP,
    "half_down": decimal.ROUND_HALF_DOWN,
    "down": decimal.ROUND_DOWN,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
    "up": decimal.ROUND_UP,
    "zero_five_up": decimal.ROUND_05UP,
}
SIGNALS = {
    decimal.InvalidOperation: "InvalidOperation",
    decimal.DivisionByZero: "DivisionByZero",
    decimal.Overflow: "Overflow",
    decimal.Underflow: "Underflow",
    decimal.Subnormal: "Subnormal",
    decimal.Inexact: "Inexact",
    decimal.Rounded: "Rounded",
    decimal.Clamped: "Clamped",
}


def exact_decimal(sign: int, coefficient: int, exponent: int) -> decimal.Decimal:
    if coefficient == 0:
        return decimal.Decimal((sign, (0,), 0))
    if exponent >= 0:
        decimal_coefficient = coefficient << exponent
        decimal_exponent = 0
    else:
        shift = -exponent
        decimal_coefficient = coefficient * 5**shift
        decimal_exponent = -shift
    while decimal_coefficient % 10 == 0:
        decimal_coefficient //= 10
        decimal_exponent += 1
    digits = tuple(int(character) for character in str(decimal_coefficient))
    return decimal.Decimal((sign, digits, decimal_exponent))


def parse_dyadic(source: str) -> decimal.Decimal:
    match = HEX.fullmatch(source)
    if match is None:
        raise ValueError(f"invalid dyadic hexadecimal value: {source}")
    return exact_decimal(
        int(bool(match.group("sign"))),
        int(match.group("coefficient"), 16),
        int(match.group("exponent")),
    )


def decimal_context(format_name: str, rounding: str) -> decimal.Context:
    precision, e_min, e_max, clamp = FORMATS[format_name]
    context = decimal.Context(
        prec=precision,
        Emin=e_min,
        Emax=e_max,
        rounding=ROUNDINGS[rounding],
        clamp=clamp,
    )
    for signal in context.traps:
        context.traps[signal] = False
    return context


def rounded_endpoint(
    endpoint: decimal.Decimal, format_name: str, rounding: str
) -> tuple[decimal.Decimal, frozenset[str]]:
    context = decimal_context(format_name, rounding)
    context.clear_flags()
    result = context.create_decimal(endpoint)
    flags = frozenset(
        name for signal, name in SIGNALS.items() if context.flags.get(signal, False)
    )
    return result, flags


def parse_intervals(path: Path) -> list[dict[str, object]]:
    intervals = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tokens = line.split()
        if len(tokens) != 7:
            raise ValueError(f"line {line_number}: expected seven fields")
        operation, left, right, integer, lower, upper, exact = tokens
        lower_value = parse_dyadic(lower)
        upper_value = parse_dyadic(upper)
        if lower_value > upper_value:
            raise ValueError(f"line {line_number}: reversed MPFR enclosure")
        intervals.append(
            {
                "operation": operation,
                "left": parse_dyadic(left),
                "right": None if right == "-" else parse_dyadic(right),
                "integer": int(integer),
                "lower": lower_value,
                "upper": upper_value,
                "exact": exact == "1",
                "line": line_number,
            }
        )
    return intervals


def generate_rows(intervals: list[dict[str, object]]) -> list[dict[str, object]]:
    rows = []
    for interval_index, interval in enumerate(intervals):
        lower = interval["lower"]
        upper = interval["upper"]
        assert isinstance(lower, decimal.Decimal)
        assert isinstance(upper, decimal.Decimal)
        for format_name in FORMATS:
            for rounding in ROUNDINGS:
                lower_result, lower_flags = rounded_endpoint(lower, format_name, rounding)
                upper_result, upper_flags = rounded_endpoint(upper, format_name, rounding)
                if lower_result != upper_result or lower_flags != upper_flags:
                    raise ValueError(
                        f"line {interval['line']}: MPFR enclosure does not uniquely round "
                        f"for {format_name}/{rounding}"
                    )
                if interval["exact"]:
                    if lower != upper:
                        raise ValueError(f"line {interval['line']}: invalid exact enclosure")
                elif lower <= lower_result <= upper:
                    raise ValueError(
                        f"line {interval['line']}: enclosure cannot certify inexact status"
                    )
                row: dict[str, object] = {
                    "id": f"mpfr-{interval_index:04d}-{format_name}-{rounding}",
                    "operation": interval["operation"],
                    "format": format_name,
                    "rounding": rounding,
                    "left": str(interval["left"]),
                    "integer": interval["integer"],
                    "result": str(lower_result),
                    "flags": sorted(lower_flags),
                }
                if interval["right"] is not None:
                    row["right"] = str(interval["right"])
                rows.append(row)
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv)
    intervals = parse_intervals(args.input)
    rows = generate_rows(intervals)
    payload = {
        "schemaVersion": 1,
        "standard": "IEEE 754-2019",
        "oracle": "MPFR 4.2.2 directed dyadic enclosure plus exact decimal endpoint rounding",
        "inputSha256": hashlib.sha256(args.input.read_bytes()).hexdigest(),
        "rows": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"generated {len(rows)} certified Decimal elementary rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
