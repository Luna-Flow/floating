#!/usr/bin/env python3
"""Rows for decimal sin, cos, tan, sinpi, cospi and tanpi at huge and tiny operands (issue #377).

Writes two `mpfr-decimal-random-v1` tables (`decimal_row_table`):

* `testdata/decimal/ieee/rows/huge_trig.txt`, run by the full gate
  (`just gate decimal`) on every target: operands of 10^5 to 4 * 10^5 digits
  (a few seconds each), the exact and tiny rows of `sinpi`, `cospi`, `tanpi`
  and `cospi` next to zero;
* `testdata/decimal/ieee/rows/huge_trig_extreme.txt`, NOT in the gate: operands
  up to `1E+999999` (the whole operand range), 20 to 60 seconds each. Run it
  on demand:

      python3 tools/run_huge_trig_extreme.py [--target native]

No row comes from the library under test:

* sin, cos, tan: the rounding of an MPFR 4.2.2 enclosure of the value at the
  EXACT operand (`tools/mpfr_huge_trig.c`: the operand is set at a precision
  that holds it, evaluated at 768 bits with RNDD and RNDU); a row is kept only
  when both bounds round to one result under the row's context;
* sinpi, cospi, tanpi at an even integer: +-0, 1 and +-0 (IEEE 754-2019 9.2.1:
  sinPi(n) = +-0 with the sign of n, cosPi(n) = (-1)^n, tanPi(n) = sinPi(n) /
  cosPi(n)); the operand 1E+k, k >= 1, is an even integer;
* cospi next to zero: 0 < 1 - cospi(x) = 2 sin^2(pi x / 2) < 5 x^2, written as
  the exact enclosure [1 - 5 x^2, 1 - 4 x^2] (pi^2 / 2 = 4.93...), rounded by
  libmpdec (Python `decimal`).

    python3 tools/generate_decimal_huge_trig_rows.py
    python3 tools/generate_decimal_huge_trig_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import subprocess
import sys
import tempfile
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

import decimal_row_table as table
import generate_decimal_pm1_rows as pm1

sys.set_int_max_str_digits(0)
ROOT = Path(__file__).resolve().parents[1]
GATE_TABLE = "huge_trig"
EXTREME_TABLE = "huge_trig_extreme"
GENERATOR = "tools/generate_decimal_huge_trig_rows.py"
DECIMAL64 = pm1.DECIMAL64
DECIMAL128 = pm1.DECIMAL128
ROUNDINGS = pm1.ROUNDINGS

# (operation, operand, context spec, rounding)
GATE_CERTIFIED = [
    ("sin", "1E+20000", DECIMAL64, "half_even"),
    ("sin", "-1E+30000", DECIMAL64, "floor"),
    ("cos", "7.5E+30000", DECIMAL64, "ceiling"),
    ("tan", "1E+300000", DECIMAL64, "half_even"),
    ("sin", "1E+300000", DECIMAL64, "half_even"),
    ("tan", "-7.5E+400000", DECIMAL64, "half_up"),
]
EXTREME_CERTIFIED = [
    ("cos", "1E+300000", DECIMAL64, "down"),
    ("sin", "1E+300000", DECIMAL128, "floor"),
    ("sin", "1E+999999", DECIMAL64, "half_even"),
    ("cos", "1E+999999", DECIMAL64, "half_even"),
    ("tan", "1E+999999", DECIMAL64, "half_even"),
    ("sin", "-7.5E+999998", DECIMAL128, "ceiling"),
]
PI_OPERANDS = ["1E+20000", "-1E+300000", "7.5E+400000", "1E+999999", "-5E+999998"]
TINY_OPERANDS = ["1E-999999", "-3E-999999", "1E-1999996", "9E-1999997"]


def mpfr_binary() -> Path:
    out = Path(tempfile.gettempdir()) / f"mpfr_huge_trig_{Path.cwd().name}"
    source = ROOT / "tools/mpfr_huge_trig.c"
    cmd = ["cc", "-O2", "-I/opt/homebrew/include", "-L/opt/homebrew/lib", "-o", str(out), str(source), "-lmpfr", "-lgmp"]
    subprocess.run(cmd, check=True)
    return out


def enclosures(cases) -> list[tuple[str, str] | None]:
    binary = mpfr_binary()
    text = "".join(f"{op} {operand}\n" for op, operand, *_ in cases)
    output = subprocess.run([str(binary)], input=text, capture_output=True, text=True, check=True).stdout
    result = []
    for line in output.splitlines():
        parts = line.split()
        result.append(None if parts == ["skip"] else (parts[0], parts[1]))
    assert len(result) == len(cases)
    return result


def certified_rows(cases) -> list[table.TableRow]:
    rows = []
    for (op, operand, spec, rounding), bounds in zip(cases, enclosures(cases)):
        assert bounds is not None, (op, operand)
        context = pm1.ctx(spec, rounding)
        low = pm1.round_exact(Decimal(bounds[0]), context)
        high = pm1.round_exact(Decimal(bounds[1]), context)
        assert low == high, f"enclosure of {op} {operand} does not round to one result: {low} {high}"
        rows.append(row(op, rounding, spec, operand, low[0], low[1]))
    return rows


def row(op: str, rounding: str, spec, operand: str, expected: str, flags: str) -> table.TableRow:
    precision, emin, emax, clamp = spec
    return table.TableRow(op, rounding, precision, emin, emax, bool(clamp), "b", operand, None, 0, expected, flags)


def pi_scaled_rows() -> list[table.TableRow]:
    rows = []
    for operand in PI_OPERANDS:
        negative = operand.startswith("-")
        zero = "-0" if negative else "0"
        # Even integers: sinPi = +-0 with the sign of n, cosPi = 1, tanPi = sinPi.
        rows.append(row("sinpi", "half_even", DECIMAL64, operand, zero, "-"))
        rows.append(row("cospi", "half_even", DECIMAL64, operand, "1", "-"))
        rows.append(row("tanpi", "half_even", DECIMAL64, operand, zero, "-"))
    return rows


def tiny_cospi_rows() -> list[table.TableRow]:
    rows = []
    context = decimal.Context(prec=4_500_000, Emin=-999_999_999, Emax=999_999_999)
    for operand in TINY_OPERANDS:
        x = Decimal(operand).copy_abs()
        low = context.subtract(Decimal(1), context.multiply(Decimal(5), context.multiply(x, x)))
        high = context.subtract(Decimal(1), context.multiply(Decimal(4), context.multiply(x, x)))
        for spec in (DECIMAL64, DECIMAL128):
            for rounding in ROUNDINGS:
                c = pm1.ctx(spec, rounding)
                a = pm1.round_exact(low, c)
                b = pm1.round_exact(high, c)
                assert a == b, (operand, spec, rounding, a, b)
                rows.append(row("cospi", rounding, spec, operand, a[0], a[1]))
    return rows


BINARY_OUTPUT = ROOT / "src/bin_float/huge_argument_trig_wbtest.mbt"
# (operation, k, precision): sin, cos, tan of 2^k, rounded to nearest even.
BINARY_CASES = [
    (op, k, p)
    for k in (300, 5000, 70000, 100000)
    for op in ("sin", "cos", "tan")
    for p in (53, 113)
]


def round_binary(value: Fraction, precision: int) -> str:
    """`value` rounded to `precision` bits, ties to even, as `<odd>p<exp>`."""
    sign = value < 0
    magnitude = abs(value)
    exponent = magnitude.numerator.bit_length() - magnitude.denominator.bit_length() - precision
    while True:
        scaled = magnitude / Fraction(2) ** exponent if exponent >= 0 else magnitude * 2 ** (-exponent)
        if 2 ** (precision - 1) <= scaled < 2 ** precision:
            break
        exponent += 1 if scaled >= 2**precision else -1
    floor = scaled.numerator // scaled.denominator
    remainder = scaled - floor
    if remainder > Fraction(1, 2) or (remainder == Fraction(1, 2) and floor % 2 == 1):
        floor += 1
    while floor % 2 == 0:
        floor //= 2
        exponent += 1
    return f"{'-' if sign else ''}{floor}p{exponent}"


def binary_rows() -> list[tuple[str, int, int, str]]:
    rows = []
    bounds = enclosures([(op, f"2^{k}") for op, k, _ in BINARY_CASES])
    for (op, k, p), pair in zip(BINARY_CASES, bounds):
        assert pair is not None
        low = round_binary(Fraction(Decimal(pair[0])), p)
        high = round_binary(Fraction(Decimal(pair[1])), p)
        assert low == high, (op, k, p, low, high)
        rows.append((op, k, p, low))
    return rows


def render_binary(rows: list[tuple[str, int, int, str]]) -> str:
    lines = [
        "// Generated by tools/generate_decimal_huge_trig_rows.py; do not edit.",
        "// sin, cos and tan of 2^k (binary exponent above the old trigonometric cutoff and",
        "// the series-precision threshold of 256 bits), rounded to nearest even; the",
        "// expected values are the rounding of MPFR 4.2.2 enclosures at the exact argument",
        "// (tools/mpfr_huge_trig.c), kept only when both bounds round to one value.",
        "",
        "///|",
        "test \"sin, cos and tan of 2^k against MPFR at the exact argument\" {",
        "  let rows : Array[(String, Int32, Int32, String)] = [",
    ]
    for op, k, p, expected in rows:
        lines.append(f'    ("{op}", {k}, {p}, "{expected}"),')
    lines += [
        "  ]",
        "  for row in rows {",
        "    let (op, k, p, expected) = row",
        "    let x = BinFloat::make(BinCoeff::one(), k, 2)",
        "    let ctx = BinaryContext::unbounded(p)",
        "    let value = match op {",
        '      "sin" => x.try_sin_ctx(ctx).unwrap().0',
        '      "cos" => x.try_cos_ctx(ctx).unwrap().0',
        "      _ => x.try_tan_ctx(ctx).unwrap().0",
        "    }",
        '    assert_eq("\\{op}(2^\\{k}) p=\\{p} => \\{value}", "\\{op}(2^\\{k}) p=\\{p} => \\{expected}")',
        "  }",
        "}",
        "",
    ]
    return "\n".join(lines)


def build() -> tuple[str, str]:
    gate = certified_rows(GATE_CERTIFIED) + pi_scaled_rows() + tiny_cospi_rows()
    extreme = certified_rows(EXTREME_CERTIFIED)
    return (
        table.render_table(GATE_TABLE, GENERATOR, gate),
        table.render_table(EXTREME_TABLE, GENERATOR, extreme),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the committed tables differ")
    args = parser.parse_args(argv)
    gate, extreme = build()
    pairs = [
        (table.table_path(GATE_TABLE), gate),
        (table.table_path(EXTREME_TABLE), extreme),
        (BINARY_OUTPUT, render_binary(binary_rows())),
    ]
    if args.check:
        bad = [str(path) for path, text in pairs if not table.check_table(path, text)]
        if bad:
            print("stale tables:", *bad, file=sys.stderr)
            return 1
        return 0
    for path, text in pairs:
        path.write_text(text, encoding="utf-8")
        print(f"{path}: {table.count_rows(text)} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
