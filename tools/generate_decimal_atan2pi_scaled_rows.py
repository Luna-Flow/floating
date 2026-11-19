#!/usr/bin/env python3
"""White-box rows for `atan2pi` with extreme operand exponents (#378).

Writes `src/decimal/atan2pi_scaled_rows_wbtest.mbt`, a table of
`(rounding, precision, e_min, e_max, clamp, y, x, expected, flags)` executed by
`atan2pi_scaled_wbtest.mbt`. The rows lie on both sides of the condition of the
scaled evaluation (`t = -(2 D + 2)` with `3 t >= 8 max(digits, p) + 400`, where
`D = adjusted(y) - adjusted(x)`), for both signs of `y` and of `x`, in all eight
rounding directions, for the context of issue #363, decimal32, decimal64 and
decimal128, and include `atan2pi(1E-1999996, 1)`.

No row comes from the library under test. `atan2pi(y, x) = sign(y) atan(|y/x|) / pi`
for `x > 0` and `sign(y) (1 - atan(|y/x|) / pi)` for `x < 0` (IEEE 754-2019 9.2
atan2Pi) is computed with Python `decimal` at 450 digits (the arctangent by
argument halving and its Taylor series, pi by Machin's formula) and rounded once
by libmpdec semantics for the format and direction. The oracle only cross-checks;
the standard decides. When the true value lies closer than 10^-440 to an integer
the ratio is replaced by one that is on the same side of the integer.

    python3 tools/generate_decimal_atan2pi_scaled_rows.py && moon fmt
    python3 tools/generate_decimal_atan2pi_scaled_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/decimal/atan2pi_scaled_rows_wbtest.mbt"
ROW_TYPE = "(String, String, Int32, Int32, Int32, Bool, String, String, String, String)"
PREC = 450
ROUNDINGS = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "half_up": decimal.ROUND_HALF_UP,
    "half_down": decimal.ROUND_HALF_DOWN,
    "down": decimal.ROUND_DOWN,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
    "up": decimal.ROUND_UP,
    "05up": decimal.ROUND_05UP,
}
CONTEXTS = [
    (51, -14, 11, False),
    (7, -95, 96, True),
    (16, -383, 384, True),
    (34, -6143, 6144, True),
]
W = decimal.Context(prec=PREC, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
decimal.setcontext(W)
EPS = Decimal(10) ** -(PREC - 10)


def atan_small(x: Decimal) -> Decimal:
    """Taylor series for |x| < 1/8."""
    x2 = x * x
    term = x
    total = x
    k = 1
    while abs(term) > EPS * abs(x):
        term = -term * x2
        k += 2
        total += term / k
    return total


def atan_pos(x: Decimal) -> Decimal:
    """arctan for x >= 0 by argument halving."""
    if x == 0:
        return Decimal(0)
    if x > 1:
        return PI / 2 - atan_pos(1 / x)
    halvings = 0
    while x > Decimal("0.1"):
        x = x / (1 + (1 + x * x).sqrt())
        halvings += 1
    return atan_small(x) * (2**halvings)


def machin_pi() -> Decimal:
    return 16 * atan_small(Decimal(1) / 5) - 4 * atan_small(Decimal(1) / 239)


PI = machin_pi()


def atan_ratio(r: Decimal) -> Decimal:
    """atan(r) for r > 0; for r < 1e-150 the value is r (1 - 10^-440), on the
    correct side (atan r < r) and far below any target precision."""
    if r < Decimal("1E-150"):
        exact = decimal.Context(prec=1200, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, traps=[])
        return exact.multiply(r, Decimal(1) - Decimal("1E-440"))
    return atan_pos(r)


def true_atan2(y: Decimal, x: Decimal) -> Decimal:
    """atan2(y, x) (not divided by pi) for y != 0, x != 0 with |y / x| >= 1e-300."""
    angle = atan_ratio(abs(y) / abs(x))
    magnitude = angle if x > 0 else PI - angle
    return -magnitude if y < 0 else magnitude


def true_value(y: Decimal, x: Decimal) -> Decimal:
    r = abs(y) / abs(x)
    angle = atan_pos(r) / PI
    behind = x < 0
    if behind:
        # 1 - angle: below 1 whenever the angle is not representable.
        magnitude = 1 - angle if angle > EPS else Decimal(1) - Decimal(10) ** -(PREC - 20)
    else:
        magnitude = angle
    return -magnitude if y < 0 else magnitude


def letters(flags: dict) -> str:
    out = ""
    for key, letter in (
        (decimal.Inexact, "x"),
        (decimal.Rounded, "r"),
        (decimal.Overflow, "o"),
        (decimal.Subnormal, "s"),
        (decimal.Underflow, "u"),
        (decimal.Clamped, "c"),
    ):
        if flags.get(key):
            out += letter
    return out or "-"


def rounded(value: Decimal, spec, rounding: str) -> tuple[str, str]:
    precision, e_min, e_max, clamp = spec
    ctx = decimal.Context(
        prec=precision,
        rounding=ROUNDINGS[rounding],
        Emin=e_min,
        Emax=e_max,
        clamp=1 if clamp else 0,
        traps=[],
    )
    result = ctx.plus(value)
    return str(result), letters(ctx.flags)


def threshold(precision: int) -> int:
    """The largest D for which the scaled path applies (digits <= precision)."""
    need = 8 * precision + 400
    t0 = -(-need // 3)  # smallest t with 3 t >= need
    return -((t0 + 2 + 1) // 2)  # 2 D + 2 <= -t0


def operands(spec) -> list[tuple[str, str]]:
    precision = spec[0]
    dmax = threshold(precision)
    exponents = [dmax - 40, dmax - 3, dmax - 1, dmax, dmax + 1, dmax + 3, dmax + 40,
                 -1999996, -5000, -300, -50, -20, -5, -2, 0]
    rows = []
    for d in exponents:
        for ymant, xmant in (("3", "1"), ("7.5", "2"), ("9.99", "1.01")):
            for ysign in ("", "-"):
                for xsign in ("", "-"):
                    rows.append((f"{ysign}{ymant}E{d}", f"{xsign}{xmant}"))
    # the regression case of #378 and the same ratio at two extreme exponents
    for ysign in ("", "-"):
        for xsign in ("", "-"):
            rows.append((f"{ysign}1E-1999996", f"{xsign}1"))
            rows.append((f"{ysign}3E-1999996", f"{xsign}2E-1999996"))
            rows.append((f"{ysign}5E-5000", f"{xsign}4E-5000"))
    return rows


def atan2_operands(spec) -> list[tuple[str, str]]:
    """Ratios on both sides of the gate `2 D < -(p + 4)` of the exact ratio of atan2."""
    precision = spec[0]
    rows = []
    for d in range(-(precision + 8) // 2 - 4, 3):
        for ymant, xmant in (("3", "1"), ("7.5", "2")):
            for ysign in ("", "-"):
                for xsign in ("", "-"):
                    rows.append((f"{ysign}{ymant}E{d}", f"{xsign}{xmant}"))
    for d in (-30, -300):
        for xsign in ("", "-"):
            rows.append((f"3E{d}", f"{xsign}1"))
    return rows


def all_rows() -> list[tuple]:
    rows = []
    for spec in CONTEXTS:
        for rounding in ROUNDINGS:
            for ytext, xtext in operands(spec):
                y, x = Decimal(ytext), Decimal(xtext)
                text, flags = rounded(true_value(y, x), spec, rounding)
                rows.append(("atan2pi", rounding, *spec, ytext, xtext, text, flags))
            for ytext, xtext in atan2_operands(spec):
                y, x = Decimal(ytext), Decimal(xtext)
                text, flags = rounded(true_atan2(y, x), spec, rounding)
                rows.append(("atan2", rounding, *spec, ytext, xtext, text, flags))
    return rows


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(rows: list[tuple]) -> str:
    out = [
        "///|",
        "// Generated by tools/generate_decimal_atan2pi_scaled_rows.py from Python decimal",
        "// (libmpdec) at 450 digits, a cross-check only; do not edit.",
        "// Columns: op, rounding, precision, e_min, e_max, clamp, y, x, expected",
        "// (compared with compare_total), flags.",
        "",
        "///|",
        f"fn atan2pi_scaled_rows() -> Array[{ROW_TYPE}] {{",
        "  [",
    ]
    for r in rows:
        op, rounding, p, lo, hi, clamp, y, x, expected, flags = r
        out.append(
            f"    ({quote(op)}, {quote(rounding)}, {p}, {lo}, {hi}, {'true' if clamp else 'false'}, "
            f"{quote(y)}, {quote(x)}, {quote(expected)}, {quote(flags)}),"
        )
    out += ["  ]", "}", ""]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.set_int_max_str_digits(0)
    text = render(all_rows())
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""

        def norm(s: str) -> str:
            squeezed = "".join(s.split())
            for closer in (")", "]", "}"):
                squeezed = squeezed.replace("," + closer, closer)
            return squeezed

        if norm(current) != norm(text):
            print(f"{OUTPUT} is stale: run tools/generate_decimal_atan2pi_scaled_rows.py")
            return 1
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(text)} bytes, {len(text.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
