#!/usr/bin/env python3
"""Rows for the plain paths of `add_ctx`, `sub_ctx`, `mul_ctx` and `div_ctx` of `decimal` (round 2 of #438).

Writes `library/src/decimal/plain_ctx_rows_wbtest.mbt`, tables only: `plain_ctx_table`, the contexts
`(precision, e_min, e_max, rounding, clamp)`, and three row tables `(context, lhs, rhs, lhs + rhs, lhs - rhs,
lhs * rhs, lhs / rhs)` (short operands, long operands, and the end of the range with a rounding carry).
Every expected value is `text flags` computed by CPython `decimal` (libmpdec) in the row's context
(Emin, Emax, clamp as in the table, all eight rounding directions), with the flags inexact (x), underflow (u)
and overflow (o); the text is the `Decimal::to_string` form (`inf` for an infinity).

    python3 tools/generate_decimal_plain_ctx_rows.py && moon fmt
    python3 tools/generate_decimal_plain_ctx_rows.py --check
"""

from __future__ import annotations

import argparse
import decimal
import random
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/decimal/plain_ctx_rows_wbtest.mbt"
E_TINY = -2147483645
E_MAX = 2147483646
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
SHORT_ROWS = 450
LONG_ROWS = 150
SHORT_DIGITS = 40
LONG_DIGITS = 130
SHORT_SEED = 0x9E3779B97F4A7C15
LONG_SEED = 0xD1B54A32D192ED03


class Spec(NamedTuple):
    precision: int
    e_min: int
    e_max: int
    rounding: str
    clamp: bool


def context_table() -> list[Spec]:
    """The contexts of the plain-path tests: the three IEEE formats, then four ranges per precision and direction."""
    specs = [
        Spec(7, -95, 96, "half_even", True),
        Spec(16, -383, 384, "half_even", True),
        Spec(34, -6143, 6144, "half_even", True),
    ]
    for precision in (1, 2, 3, 7, 16, 34, 60):
        for rounding in ROUNDINGS:
            specs.append(Spec(precision, E_TINY + precision - 1, E_MAX, rounding, False))
            specs.append(Spec(precision, -30, 40, rounding, False))
            specs.append(Spec(precision, -30, 40, rounding, True))
            specs.append(Spec(precision, -5, 7, rounding, True))
    return specs


def python_context(spec: Spec) -> decimal.Context:
    return decimal.Context(
        prec=spec.precision,
        rounding=ROUNDINGS[spec.rounding],
        Emin=spec.e_min,
        Emax=spec.e_max,
        clamp=1 if spec.clamp else 0,
        traps=[],
    )


def library_text(value: decimal.Decimal) -> str:
    text = str(value)
    return {"Infinity": "inf", "-Infinity": "-inf", "NaN": "nan"}.get(text, text)


def flag_letters(context: decimal.Context) -> str:
    return "".join(
        letter if context.flags[signal] else "."
        for signal, letter in ((decimal.Inexact, "x"), (decimal.Underflow, "u"), (decimal.Overflow, "o"))
    )


def evaluate(spec: Spec, operation: str, lhs: decimal.Decimal, rhs: decimal.Decimal) -> str:
    context = python_context(spec)
    function = {
        "add": context.add,
        "sub": context.subtract,
        "mul": context.multiply,
        "div": context.divide,
    }[operation]
    value = function(lhs, rhs)
    return f"{library_text(value)} {flag_letters(context)}"


def in_storage(text: str) -> bool:
    """The operand is a finite number of the stored range of `decimal` (otherwise the library reads an infinity)."""
    value = decimal.Decimal(text)
    exponent = value.as_tuple().exponent
    return exponent >= E_TINY and value.adjusted() <= E_MAX


def digits_text(generator: random.Random, count: int) -> str:
    """Runs of nines and zeros make carries and cancellations frequent."""
    style = generator.randrange(5)
    out = []
    for index in range(count):
        if style == 0:
            digit = 9
        elif style == 1 and generator.randrange(3) != 0:
            digit = 0
        else:
            digit = generator.randrange(10)
        out.append("1" if index == 0 and digit == 0 else str(digit))
    return "".join(out)


def operand(generator: random.Random, spec: Spec, max_digits: int) -> str:
    digits = digits_text(generator, generator.randint(1, max_digits))
    place = generator.randrange(4)
    if place == 0:
        adjusted = spec.e_min + generator.randint(-3, 6)
    elif place == 1:
        adjusted = spec.e_max + generator.randint(-6, 3)
    else:
        adjusted = generator.randint(-12, 12)
    exponent = adjusted - len(digits) + 1
    sign = "-" if generator.randrange(2) == 0 else ""
    return f"{sign}{digits}E{exponent}"


def second_operand(generator: random.Random, spec: Spec, first: str, max_digits: int) -> str:
    kind = generator.randrange(6)
    value = decimal.Decimal(first)
    digits = "".join(map(str, value.as_tuple().digits))
    exponent = value.as_tuple().exponent
    if kind == 0:
        cut = min(len(digits), generator.randint(1, 3))
        tail = digits_text(generator, cut)
        sign = "" if value < 0 else "-"
        return f"{sign}{digits[: len(digits) - cut]}{tail}E{exponent}"
    if kind == 1:
        digits2 = digits_text(generator, generator.randint(1, max_digits))
        sign = "-" if generator.randrange(2) == 0 else ""
        return f"{sign}{digits2}E{exponent + generator.randint(-40, 40)}"
    return operand(generator, spec, max_digits)


def row(spec_index: int, spec: Spec, lhs: str, rhs: str) -> tuple | None:
    if not (in_storage(lhs) and in_storage(rhs)):
        return None
    a, b = decimal.Decimal(lhs), decimal.Decimal(rhs)
    if a == 0 or b == 0:
        return None
    return (
        spec_index,
        lhs,
        rhs,
        evaluate(spec, "add", a, b),
        evaluate(spec, "sub", a, b),
        evaluate(spec, "mul", a, b),
        evaluate(spec, "div", a, b),
    )


def random_rows(count: int, max_digits: int, seed: int) -> list[tuple]:
    generator = random.Random(seed)
    specs = context_table()
    rows: list[tuple] = []
    iteration = 0
    while len(rows) < count:
        index = iteration % len(specs)
        iteration += 1
        spec = specs[index]
        lhs = operand(generator, spec, max_digits)
        rhs = second_operand(generator, spec, lhs, max_digits)
        made = row(index, spec, lhs, rhs)
        if made is not None:
            rows.append(made)
    return rows


# the contexts and the operands of the rows at the end of the range
CARRY_CONTEXTS = (
    Spec(7, -95, 96, "half_even", True),
    Spec(16, -383, 384, "half_even", True),
    Spec(3, -30, 40, "half_even", False),
    Spec(3, -30, 40, "half_up", True),
    Spec(3, -5, 7, "half_even", True),
    Spec(3, -5, 7, "ceiling", True),
    Spec(3, -5, 7, "floor", True),
    Spec(1, -5, 7, "half_even", True),
    Spec(2, -30, 40, "down", False),
    Spec(7, -30, 40, "up", False),
    Spec(34, -6143, 6144, "half_down", True),
    Spec(3, E_TINY + 2, E_MAX, "half_even", False),
)
CARRY_TEXTS = ("1", "5", "50", "99")


def carry_rows() -> tuple[list[tuple], list[tuple]]:
    """A result whose adjusted exponent is e_max before rounding is e_max or, after a carry into 10^p, beyond it;
    the sums and products of p + 2 nines at six adjusted exponents around both ends of the range."""
    specs = context_table()
    rows: list[tuple] = []
    top_rows: list[tuple] = []
    for spec in CARRY_CONTEXTS:
        index = specs.index(spec) if spec in specs else None
        if index is None:
            specs.append(spec)
            index = len(specs) - 1
        p = spec.precision
        for adjusted in (spec.e_max - 2, spec.e_max - 1, spec.e_max, spec.e_min, spec.e_min + 1, spec.e_min - 1):
            nines = "9" * (p + 2)
            exponent = adjusted - (p + 2) + 1
            lhs = f"{nines}E{exponent}"
            for text in CARRY_TEXTS:
                for shift in (0, -1, 1):
                    rhs = f"{text}E{exponent + shift}"
                    for left, right in ((lhs, rhs), (lhs, "-" + rhs)):
                        made = row(index, spec, left, right)
                        if made is None:
                            continue
                        # issue 806: at e_max = 2147483646 a left operand at the adjusted exponent e_max
                        if spec.e_max == E_MAX and decimal.Decimal(left).adjusted() >= spec.e_max:
                            top_rows.append(made)
                        else:
                            rows.append(made)
    return rows, top_rows


def all_specs() -> list[Spec]:
    specs = context_table()
    for spec in CARRY_CONTEXTS:
        if spec not in specs:
            specs.append(spec)
    return specs


def quote(text: str) -> str:
    return '"' + text + '"'


def render_rows(name: str, rows: list[tuple]) -> list[str]:
    out = ["///|", f"let {name} : Array[(Int32, String, String, String, String, String, String)] = ["]
    for index, lhs, rhs, add, sub, mul, div in rows:
        fields = ", ".join(quote(x) for x in (lhs, rhs, add, sub, mul, div))
        out.append(f"  ({index}, {fields}),")
    out += ["]", ""]
    return out


def render() -> str:
    specs = all_specs()
    out = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/generate_decimal_plain_ctx_rows.py (CPython `decimal`, libmpdec)",
        "// input: contexts (precision, e_min, e_max, rounding, clamp) with the IEEE formats and four ranges per precision and direction; seeded random operands near both ends of the range (450 short, 150 long rows) and the operands of a rounding carry at both ends of the range",
        "// library-ran: no",
        "// shares: nothing in the tables; the tests parse the operands with Decimal::from_string_ctx and compare to_string text and three flags",
        "// check: python3 tools/generate_decimal_plain_ctx_rows.py --check",
        "",
        "///|",
        "let plain_ctx_table : Array[(Int32, Int32, Int32, String, Bool)] = [",
    ]
    for spec in specs:
        out.append(
            f"  ({spec.precision}, {spec.e_min}, {spec.e_max}, {quote(spec.rounding)}, {'true' if spec.clamp else 'false'}),"
        )
    out += ["]", ""]
    out += render_rows("plain_short_rows", random_rows(SHORT_ROWS, SHORT_DIGITS, SHORT_SEED))
    out += render_rows("plain_long_rows", random_rows(LONG_ROWS, LONG_DIGITS, LONG_SEED))
    carry, carry_top = carry_rows()
    out += render_rows("plain_carry_rows", carry)
    out += render_rows("plain_carry_top_rows", carry_top)
    return "\n".join(out)


def squeeze(text: str) -> str:
    squeezed = "".join(text.split())
    for closer in (")", "]", "}"):
        squeezed = squeezed.replace("," + closer, closer)
    return squeezed


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args(argv)
    sys.set_int_max_str_digits(0)
    text = render()
    if arguments.check:
        committed = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if squeeze(committed) == squeeze(text):
            print("rows match")
            return 0
        print(f"{OUTPUT} differs from the generator", file=sys.stderr)
        return 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
