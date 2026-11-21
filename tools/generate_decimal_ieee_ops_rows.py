#!/usr/bin/env python3
"""White-box rows for the IEEE 754-2019 operations of `decimal` on legal contexts.

Writes `library/src/decimal/ieee_ops_rows_wbtest.mbt`, a table of
`(op, precision, e_max, rounding, a, b, c, expected, flags)` executed by
`ieee_ops_rows_wbtest.mbt`'s test: the operations that the General Decimal
Arithmetic tests of `decimal` used to exercise on contexts that no format has
(subnormal results, zero cohorts, next*, logB, scaleB, remainder, quantize,
roundToIntegral*, fma, NaN payloads), now on contexts of IEEE 754-2019 formats
only (`emin = 1 - emax`, clamp; checked by `corpus_common.check_ieee_decimal_context`).

No row comes from the library under test. The expected value is computed with
Python `decimal` (libmpdec, GDA 1.70 semantics): a cross-check oracle, not the
specification. Only the five IEEE flags are compared (inexact, underflow,
overflow, divideByZero, invalid); the executor compares the value with
`total_order_compare`, so the cohort, the sign of a zero and a NaN payload are
part of the check. A row where the oracle and the standard differ is not
emitted: the generator lists such operations in `EXCLUDED`.

    python3 tools/generate_decimal_ieee_ops_rows.py && moon fmt
    python3 tools/generate_decimal_ieee_ops_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import sys
from pathlib import Path

import corpus_common

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "library/src/decimal/ieee_ops_rows_wbtest.mbt"

ROUNDINGS = {
    "half_even": decimal.ROUND_HALF_EVEN,
    "half_up": decimal.ROUND_HALF_UP,
    "down": decimal.ROUND_DOWN,
    "ceiling": decimal.ROUND_CEILING,
    "floor": decimal.ROUND_FLOOR,
}
# (precision, emax): the smallest formats exercise the range limits at once,
# decimal32 and decimal64 the interchange formats.
FORMATS = [(1, 3), (2, 3), (3, 2), (3, 5), (5, 9), (9, 10), (7, 96), (16, 384)]
UNARY = ["next_up", "next_down", "logb", "sqrt", "to_integral_exact", "to_integral_value", "nan_payload"]
BINARY = ["add", "subtract", "multiply", "divide", "remainder", "quantize", "scaleb"]
TERNARY = ["fma"]
# sqrt is not directed here: Python `decimal` always rounds sqrt half-even, while
# IEEE 754-2019 5.4.1 rounds it with the attribute; the rounded half-even rows stay.
DIRECTED = {"add", "subtract", "multiply", "divide", "to_integral_exact", "to_integral_value", "scaleb", "fma", "quantize"}
EXCLUDED: set[str] = set()


def operands(p: int, emax: int) -> list[str]:
    emin = 1 - emax
    etiny = emin - p + 1
    etop = emax - p + 1
    nines = "9" * p
    out = [
        "0", "-0", f"0E{etiny}", f"-0E{etop}",
        "1", "-1", f"1E{etiny}", f"-1E{etiny}", f"{nines}E{etiny}", f"-{nines}E{etop}",
        f"1E{etop}", f"{nines}E{etop}", f"5E{etiny}", f"1E{emin}", f"{nines}E{emin - p}" if emin - p >= etiny else f"1E{emin}",
        f"1{'0' * (p - 1)}E{etiny}" if p > 1 else f"3E{etiny + 1}",
        "Infinity", "-Infinity", "NaN", "-NaN", "sNaN",
    ]
    if p > 1:
        out += [f"NaN{'7' * min(p - 1, 3)}", f"-sNaN{'4' * min(p - 1, 2)}"]
    seen, res = set(), []
    for text in out:
        v = decimal.Decimal(text)
        if not v.is_nan() and v.is_finite():
            digits = len(v.as_tuple().digits)
            exp = v.as_tuple().exponent
            if digits > p or exp < etiny or exp > etop:
                continue
        if text not in seen:
            seen.add(text)
            res.append(text)
    return res


def flags_text(ctx: decimal.Context) -> str:
    names = [(decimal.Inexact, "x"), (decimal.Underflow, "u"), (decimal.Overflow, "o"),
             (decimal.DivisionByZero, "z"), (decimal.InvalidOperation, "i")]
    return "".join(c if ctx.flags[s] else "." for s, c in names)


def evaluate(op: str, p: int, emax: int, mode: str, args: list[str]) -> tuple[str, str] | None:
    ctx = decimal.Context(prec=p, rounding=ROUNDINGS[mode], Emin=1 - emax, Emax=emax, clamp=1, traps=[], flags=[])
    a = [decimal.Decimal(x) for x in args]
    ctx.clear_flags()
    try:
        if op == "next_up": r = ctx.next_plus(a[0])
        elif op == "next_down": r = ctx.next_minus(a[0])
        elif op == "logb": r = ctx.logb(a[0])
        elif op == "scaleb": r = ctx.scaleb(a[0], a[1])
        elif op == "remainder": r = ctx.remainder_near(a[0], a[1])
        elif op == "quantize": r = ctx.quantize(a[0], a[1])
        elif op == "to_integral_exact": r = ctx.to_integral_exact(a[0])
        elif op == "to_integral_value": r = ctx.to_integral_value(a[0])
        elif op == "sqrt": r = ctx.sqrt(a[0])
        elif op == "add": r = ctx.add(a[0], a[1])
        elif op == "subtract": r = ctx.subtract(a[0], a[1])
        elif op == "multiply": r = ctx.multiply(a[0], a[1])
        elif op == "divide": r = ctx.divide(a[0], a[1])
        elif op == "fma": r = ctx.fma(a[0], a[1], a[2])
        elif op == "nan_payload": r = ctx.add(a[0], decimal.Decimal(1))
        else: return None
    except Exception:  # decimal raises for unsupported operands only
        return None
    return str(r), flags_text(ctx)


def build() -> list[tuple]:
    rows: list[tuple] = []
    for p, emax in FORMATS:
        corpus_common.check_ieee_decimal_context(p, "half_even", 1 - emax, emax, 1, "b")
        ops = operands(p, emax)
        finite = [x for x in ops if "N" not in x and "I" not in x]
        specials = [x for x in ops if x not in finite]
        for op in UNARY + BINARY + TERNARY:
            if op in EXCLUDED:
                continue
            modes = list(ROUNDINGS) if op in DIRECTED else ["half_even"]
            arity = 1 if op in UNARY else 2 if op in BINARY else 3
            if arity == 1:
                argsets = [[x] for x in ops]
            elif arity == 2:
                argsets = [[x, y] for x in ops for y in ops]
                if op == "scaleb":
                    argsets = [[x, n] for x in ops for n in ("-3", "-1", "0", "1", "2", str(2 * emax + p), str(-(2 * emax + p)))]
                if op == "quantize":
                    argsets = [[x, y] for x in ops for y in ops]
            else:
                trip = finite[:8] + specials[:3]
                argsets = [[x, y, z] for x in trip[::2] for y in trip[1::3] for z in trip[::3]]
            for index, args in enumerate(argsets):
                for mode_index, mode in enumerate(modes):
                    if len(modes) > 1 and (index + mode_index) % 3 != 0 and arity > 1:
                        continue
                    # Which NaN operand a binary/ternary operation propagates (and
                    # its sign) is implementation-defined (IEEE 754-2019 6.2.3).
                    if sum("N" in x for x in args) > 1:
                        continue
                    result = evaluate(op, p, emax, mode, args)
                    if result is None:
                        continue
                    # remainder is exact in IEEE 754-2019 5.3.1; Python `decimal`
                    # signals invalid when the integer quotient exceeds the precision.
                    if (op == "remainder" and result[0] == "NaN" and result[1][4] == "i"
                            and not any("N" in x or "I" in x for x in args)
                            and decimal.Decimal(args[1]) != 0):
                        continue
                    rows.append((op, p, emax, mode, *(args + ["-"] * (3 - len(args))), *result))
    return sample(rows)


# Rows kept per operation (the sampling stride of each operation follows from it,
# so removing an operation from the table does not change the rows of the others).
ROWS_PER_OPERATION = 500


def sample(rows: list[tuple]) -> list[tuple]:
    """Keep every k-th row of each operation so the table fits the quick gate.

    The full table (about 42,000 rows) passes as well; run it by setting
    `ROWS_PER_OPERATION` to a large number.
    """
    by_op: dict[str, list[tuple]] = {}
    for row in rows:
        by_op.setdefault(row[0], []).append(row)
    per_op = ROWS_PER_OPERATION
    out: list[tuple] = []
    for op_rows in by_op.values():
        stride = max(1, len(op_rows) // per_op)
        out += op_rows[::stride]
    return out


def render(rows: list[tuple]) -> str:
    lines = [
        "///|",
        "// Generated by tools/generate_decimal_ieee_ops_rows.py from Python `decimal`; do not edit.",
        "// Columns: op, precision, e_max, rounding, a, b, c, expected, flags (x u o z i).",
        "",
        "///|",
        "let ieee_ops_rows : Array[(String, Int32, Int32, String, String, String, String, String, String)] = [",
    ]
    for op, p, emax, mode, a, b, c, exp, fl in rows:
        lines.append(f'  ("{op}", {p}, {emax}, "{mode}", "{a}", "{b}", "{c}", "{exp}", "{fl}"),')
    lines.append("]")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = render(build())
    if args.check:
        import re
        norm = lambda s: re.sub(r"\s+", "", s).replace(",)", ")").replace(",]", "]")
        if not OUTPUT.is_file() or norm(OUTPUT.read_text(encoding="utf-8")) != norm(text):
            print(f"{OUTPUT} is stale", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT}: {text.count(chr(10)) - 7} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
