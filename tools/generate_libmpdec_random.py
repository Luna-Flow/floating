#!/usr/bin/env python3
"""Seeded random differential rows for the decimal cores against libmpdec.

    generate_libmpdec_random.py <family> <seed> <start> <count>

writes a General Decimal Arithmetic `.decTest` file whose expected results and
conditions come from Python's `decimal` module (libmpdec). The rows run through
`just conformance`'s GDA interpreter (`floating-conformance --backend gda`).

Case I of family F under seed S is a pure function of (S, F, I): the stream is
a SplitMix64 generator seeded from the triple, so `family seed I 1` reproduces
one row of a million-row run. The row id is `S.F.I` with a `d` prefix.

libmpdec is an implementation of the General Decimal Arithmetic specification,
not the specification itself. A row that disagrees with it is not a defect
until the GDA text (or IEEE 754-2019 for the decimal32/64/128 contexts) has
been read; the oracle is only a strong lead.
"""

from __future__ import annotations

import decimal
import sys
from dataclasses import dataclass, field
from decimal import Context, Decimal
from fractions import Fraction
from typing import Callable, Iterator, Sequence

MASK = (1 << 64) - 1
FAMILIES = (
    "add",
    "subtract",
    "multiply",
    "divide",
    "squareroot",
    "fma",
    "apply",
    "tosci",
    "toeng",
    "exp",
    "ln",
    "log10",
    "power",
    "expwide",
    "lnwide",
    "log10wide",
    "powerwide",
)
ELEMENTARY = ("exp", "ln", "log10", "power")
ROUNDINGS = (
    ("half_even", decimal.ROUND_HALF_EVEN),
    ("half_up", decimal.ROUND_HALF_UP),
    ("half_down", decimal.ROUND_HALF_DOWN),
    ("down", decimal.ROUND_DOWN),
    ("ceiling", decimal.ROUND_CEILING),
    ("floor", decimal.ROUND_FLOOR),
    ("up", decimal.ROUND_UP),
    ("05up", decimal.ROUND_05UP),
)
CONDITIONS = (
    (decimal.Clamped, "Clamped"),
    (decimal.DivisionByZero, "Division_by_zero"),
    (decimal.Inexact, "Inexact"),
    (decimal.InvalidOperation, "Invalid_operation"),
    (decimal.Overflow, "Overflow"),
    (decimal.Rounded, "Rounded"),
    (decimal.Subnormal, "Subnormal"),
    (decimal.Underflow, "Underflow"),
)
IEEE_CONTEXTS = ((7, -95, 96), (16, -383, 384), (34, -6143, 6144))


def fnv1a(text: str) -> int:
    value = 0xCBF29CE484222325
    for byte in text.encode():
        value ^= byte
        value = (value * 0x100000001B3) & MASK
    return value


def splitmix(state: int) -> tuple[int, int]:
    state = (state + 0x9E3779B97F4A7C15) & MASK
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
    return state, z ^ (z >> 31)


class Rng:
    """SplitMix64 seeded by (seed, family, index); integer arithmetic only."""

    def __init__(self, seed: int, family: str, index: int) -> None:
        _, state = splitmix(seed & MASK)
        _, state = splitmix(state ^ ((fnv1a(family) * 0xD6E8FEB86659FD93) & MASK))
        _, state = splitmix(
            state ^ ((index * 0xA0761D6478BD642F + 0x1234567) & MASK)
        )
        self.state = state

    def next(self) -> int:
        self.state, value = splitmix(self.state)
        return value

    def range(self, low: int, high: int) -> int:
        if high <= low:
            return low
        return low + self.next() % (high - low + 1)

    def chance(self, numerator: int, denominator: int) -> bool:
        return self.next() % denominator < numerator

    def log(self, low: int, high: int) -> int:
        bits = self.range(low.bit_length(), high.bit_length())
        lower = 1 if bits == 1 else 1 << (bits - 1)
        upper = (1 << bits) - 1
        return self.range(max(lower, low), min(upper, high))

    def choice(self, items: Sequence[int]) -> int:
        return items[self.range(0, len(items) - 1)]


@dataclass(frozen=True)
class Ctx:
    precision: int
    rounding: str
    emin: int
    emax: int
    clamp: int

    def python(self) -> Context:
        mode = dict(ROUNDINGS)[self.rounding]
        context = Context(
            prec=self.precision,
            rounding=mode,
            Emin=self.emin,
            Emax=self.emax,
            clamp=self.clamp,
            capitals=1,
            flags=[],
            traps=[],
        )
        return context

    def directives(self) -> list[str]:
        return [
            f"precision: {self.precision}",
            f"rounding: {self.rounding}",
            f"maxexponent: {self.emax}",
            f"minexponent: {self.emin}",
            f"clamp: {self.clamp}",
        ]


@dataclass(frozen=True)
class Case:
    case_id: str
    op: str
    context: Ctx
    operands: tuple[str, ...]


@dataclass(frozen=True)
class Row:
    case: Case
    result: str
    conditions: tuple[str, ...]
    # An expected difference from libmpdec (see `power_of_ten_difference`):
    # the libmpdec result and conditions, written as a comment before the row.
    libmpdec: str = ""


# ---------------------------------------------------------------- operands ---


@dataclass
class Number:
    sign: int
    digits: str
    exponent: int

    def text(self) -> str:
        return str(Decimal((self.sign, tuple(int(d) for d in self.digits), self.exponent)))

    def value(self) -> Decimal:
        return Decimal((self.sign, tuple(int(d) for d in self.digits), self.exponent))


def digits_of(rng: Rng, length: int, style: int | None = None) -> str:
    length = max(length, 1)
    style = rng.range(0, 7) if style is None else style
    if style == 1:  # sparse
        chars = ["0"] * length
        chars[0] = str(rng.range(1, 9))
        for _ in range(rng.range(0, 3)):
            chars[rng.range(0, length - 1)] = str(rng.range(1, 9))
        return "".join(chars)
    if style == 2:  # all nines
        return "9" * length
    if style == 3:  # 10...01 or 99..9 then zeros
        if length == 1:
            return str(rng.range(1, 9))
        if rng.chance(1, 2):
            return "1" + "0" * (length - 2) + "1"
        run = rng.range(1, length)
        return "9" * run + "0" * (length - run)
    if style == 4:  # trailing zeros
        core = digits_of(rng, max(1, length - rng.range(0, length - 1)), 0)
        return (core + "0" * length)[:length] if length > 1 else core
    first = str(rng.range(1, 9))
    rest = "".join(str(rng.range(0, 9)) for _ in range(length - 1))
    return first + rest


def format_operand(rng: Rng, number: Number) -> str:
    """The same value written in one of the legal layouts."""
    canonical = number.text()
    kind = rng.range(0, 9)
    if kind < 6 or number.digits == "0" and False:
        return canonical
    sign = "-" if number.sign else ("+" if rng.chance(1, 4) else "")
    digits = number.digits
    exponent = number.exponent
    marker = "E" if rng.chance(2, 3) else "e"
    if kind == 6:
        return f"{sign}{digits}{marker}{exponent:+d}" if exponent else f"{sign}{digits}"
    if kind == 7 and len(digits) > 1:
        split = rng.range(1, len(digits) - 1)
        return f"{sign}{digits[:split]}.{digits[split:]}{marker}{exponent + len(digits) - split:+d}"
    if kind == 8:
        zeros = "0" * rng.range(1, 4)
        return f"{sign}{zeros}{digits}{marker}{exponent:+d}"
    return f"{sign}{digits}.{marker}{exponent:+d}"


def special_operand(rng: Rng) -> str:
    return (
        "NaN",
        "sNaN",
        "Infinity",
        "-Infinity",
        "Inf",
        "0",
        "-0",
        "0E+5",
        "-0E-7",
    )[rng.range(0, 8)]


# ----------------------------------------------------------------- context ---


def base_family(family: str) -> str:
    return family.removesuffix("wide")


def pick_context(rng: Rng, family: str) -> Ctx:
    rounding = ROUNDINGS[rng.range(0, 7)][0]
    if base_family(family) in ELEMENTARY:
        # libmpdec guarantees correctly rounded results of these functions
        # only to nearest-even.
        rounding = "half_even"
    kind = rng.range(0, 99)
    if kind < 30:
        precision, emin, emax = IEEE_CONTEXTS[rng.range(0, 2)]
        clamp = 1 if rng.chance(4, 5) else 0
    elif kind < 45:
        precision = rng.range(1, 5)
        emax = rng.range(0, 20)
        emin = -emax - rng.range(-3, 10)
        emin = min(emin, 0)
        clamp = rng.range(0, 1)
    elif kind < 75:
        precision = rng.log(1, 300)
        emax = rng.choice((0, 9, 99, 999, 9999, 999999))
        emax = max(0, emax + rng.range(-3, 3))
        emin = -emax if rng.chance(1, 2) else -emax + rng.range(0, min(emax, 5))
        emin = min(emin, 0)
        clamp = rng.range(0, 1)
    elif kind < 90:
        precision = rng.log(1, 5000) if rng.chance(1, 2) else rng.range(1, 60)
        emax = rng.range(0, 999999999)
        emin = -rng.range(0, 999999999)
        clamp = rng.range(0, 1)
    else:
        precision = rng.choice((9, 9, 3, 28, 100))
        emax, emin, clamp = 999, -999, 0
    if base_family(family) in ELEMENTARY:
        precision = min(precision, rng.range(1, 120))
        # libmpdec reports Subnormal and Underflow for a result such as
        # exp(-1E-9) = 0.999999999 -> 1 only after rounding, GDA 1.70
        # ("Subnormal", "Underflow") before rounding. That differs only when
        # Emin = 0, so elementary rows keep Emin below zero.
        emin = min(emin, -1)
        if not family.endswith("wide"):
            # exp, ln, log10 and power answer NaN with Invalid_context once the
            # exponent range reaches 10^6 (the decNumber DEC_MAX_MATH limit the
            # decimal package adopts); the `...wide` families sample those
            # contexts, the plain ones stay below.
            emax = min(emax, 999999)
            emin = max(emin, -999999)
    return Ctx(precision, rounding, emin, emax, clamp)


def target_exponent(rng: Rng, context: Ctx) -> int:
    """Adjusted exponent aimed at by a result."""
    emin, emax = context.emin, context.emax
    etiny = emin - context.precision + 1
    kind = rng.range(0, 99)
    if kind < 18:
        return emax + rng.range(-3, 3)
    if kind < 40:
        pick = rng.range(0, 9)
        if pick < 4:
            return emin + rng.range(-3, 3)
        if pick < 7:
            return etiny + rng.range(-3, 3)
        return rng.range(etiny - 2, emin + 1)
    if rng.chance(7, 10):
        return max(emin, min(emax, rng.range(-30, 30)))
    return rng.range(emin, emax)


def gap_between(rng: Rng, precision: int, la: int, lb: int) -> int:
    kind = rng.range(0, 99)
    if kind < 20:
        return rng.range(0, 3)
    if kind < 35:
        return precision + rng.range(-3, 3)
    if kind < 45:
        return la + rng.range(-2, 2)
    if kind < 55:
        return lb + rng.range(-2, 2)
    if kind < 65:
        return 2 * precision + rng.range(-3, 3)
    if kind < 90:
        return rng.range(0, 2 * precision + 8)
    return rng.log(1, 10**9)


def operand_length(rng: Rng, precision: int) -> int:
    kind = rng.range(0, 99)
    if kind < 25:
        length = precision
    elif kind < 35:
        length = precision + rng.range(-3, 3)
    elif kind < 55:
        length = rng.range(1, 20)
    elif kind < 70:
        length = rng.log(1, 3000)
    elif kind < 85:
        length = precision + rng.range(1, 40)
    elif kind < 93:
        length = precision * 2
    else:
        length = rng.range(1, 3)
    return max(1, min(length, 6000))


def clamp_exponent(exponent: int) -> int:
    return max(-(10**9) - 5000, min(10**9 + 5000, exponent))


# -------------------------------------------------------------- generation ---


def make_number(rng: Rng, length: int, lead: int, sign: int | None = None) -> Number:
    """A number with `length` digits whose adjusted exponent is `lead`."""
    digits = digits_of(rng, length)
    exponent = clamp_exponent(lead - (len(digits) - 1))
    return Number(rng.range(0, 1) if sign is None else sign, digits, exponent)


def exact_value(operation: Callable[[Context], Decimal], digits: int) -> Decimal | None:
    wide = Context(prec=digits, Emin=decimal.MIN_EMIN, Emax=decimal.MAX_EMAX, traps=[], flags=[])
    result = operation(wide)
    if wide.flags[decimal.Inexact]:
        return None
    return result


def last_digit_five(number: Number) -> Number:
    digits = number.digits
    if len(digits) == 1 and digits == "0":
        return number
    return Number(number.sign, digits[:-1] + "5", number.exponent)


def with_tie_precision(context: Ctx, value: Decimal | None) -> Ctx:
    """The context that turns an exact result ending in 5 into a tie."""
    if value is None or not value.is_finite() or value == 0:
        return context
    digits = value.as_tuple().digits
    stripped = list(digits)
    while len(stripped) > 1 and stripped[-1] == 0:
        stripped.pop()
    if len(stripped) >= 2 and stripped[-1] == 5:
        return Ctx(len(stripped) - 1, context.rounding, context.emin, context.emax, context.clamp)
    return context


def maybe_special(rng: Rng, operands: list[str]) -> list[str]:
    if rng.chance(4, 100):
        index = rng.range(0, len(operands) - 1)
        operands[index] = special_operand(rng)
    return operands


def gen_add(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    pa, pb = operand_length(rng, p), operand_length(rng, p)
    gap = gap_between(rng, p, pa, pb) * (-1 if rng.chance(1, 2) else 1)
    la = target - rng.range(0, 1)
    a = make_number(rng, pa, la)
    b = make_number(rng, pb, la - gap)
    tie = rng.chance(30, 100)
    if rng.chance(12, 100):  # cancellation
        b = Number(1 - a.sign, a.digits, a.exponent)
        if rng.chance(3, 4):
            tail = digits_of(rng, rng.range(1, 6), 0)
            b = Number(b.sign, (b.digits + tail)[: len(b.digits) + len(tail)], b.exponent - len(tail))
    if tie:
        # The addend with the smaller exponent decides the last digit.
        low_first = a.exponent <= b.exponent
        if low_first:
            a = last_digit_five(a)
        else:
            b = last_digit_five(b)

        def sum_(ctx: Context) -> Decimal:
            return ctx.add(a.value(), b.value()) if family == "add" else ctx.subtract(a.value(), b.value())

        wide = max(len(a.digits), len(b.digits)) + abs(a.exponent - b.exponent) + 5
        if wide < 20000:
            context = with_tie_precision(context, exact_value(sum_, wide))
    operands = [format_operand(rng, a), format_operand(rng, b)]
    return context, maybe_special(rng, operands)


def gen_multiply(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    pa, pb = operand_length(rng, p), operand_length(rng, p)
    la = target // 2 + rng.range(-20, 20)
    a = make_number(rng, pa, la)
    b = make_number(rng, pb, target - la - rng.range(0, 1))
    if rng.chance(30, 100):
        a = last_digit_five(a)
        b = Number(b.sign, b.digits[:-1] + str(rng.choice((1, 3, 7, 9))), b.exponent)
        value = exact_value(lambda c: c.multiply(a.value(), b.value()), len(a.digits) + len(b.digits) + 2)
        context = with_tie_precision(context, value)
    return context, maybe_special(rng, [format_operand(rng, a), format_operand(rng, b)])


def gen_divide(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    pb = operand_length(rng, p)
    nq = operand_length(rng, p) if rng.chance(1, 2) else p
    lb = rng.range(-30, 30) + (rng.range(-500000, 500000) if rng.chance(1, 5) else 0)
    b = make_number(rng, pb, lb)
    q = make_number(rng, nq, target)
    if rng.chance(30, 100):
        q = last_digit_five(q)
    exact_a = exact_value(lambda c: c.multiply(q.value(), b.value()), len(q.digits) + len(b.digits) + 2)
    if exact_a is None or rng.chance(1, 4):
        a = make_number(rng, operand_length(rng, p), target + lb)
    else:
        sign, digits, exponent = exact_a.as_tuple()
        a = Number(sign, "".join(map(str, digits)), int(exponent))
        context = with_tie_precision(context, exact_value(lambda c: c.divide(a.value(), b.value()), len(q.digits) + 3))
        if rng.chance(25, 100):
            tail = digits_of(rng, rng.range(1, 30), 0)
            a = Number(a.sign, a.digits + tail, a.exponent - len(tail))
    operands = [format_operand(rng, a), format_operand(rng, b)]
    if rng.chance(3, 100):
        operands[1] = ("0", "-0", "0E+3", "0.00")[rng.range(0, 3)]
    return context, maybe_special(rng, operands)


def gen_sqrt(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    nr = max(1, min(operand_length(rng, p) // 2 + 1, 3000))
    root = make_number(rng, nr, target // 2, sign=0)
    if rng.chance(30, 100):
        root = last_digit_five(root)
    square = exact_value(lambda c: c.multiply(root.value(), root.value()), 2 * nr + 4)
    if square is None or rng.chance(1, 3):
        number = make_number(rng, operand_length(rng, p), 2 * target + rng.range(0, 1), sign=0)
    else:
        sign, digits, exponent = square.as_tuple()
        number = Number(0, "".join(map(str, digits)), int(exponent))
        if rng.chance(30, 100):
            context = with_tie_precision(context, root.value())
        if rng.chance(25, 100):
            tail = digits_of(rng, rng.range(1, 30), 0)
            number = Number(0, number.digits + tail, number.exponent - len(tail))
    if rng.chance(3, 100):
        number = Number(1, number.digits, number.exponent)
    return context, maybe_special(rng, [format_operand(rng, number)])


def gen_fma(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    pa, pb, pc = (operand_length(rng, p) for _ in range(3))
    la = target // 2 + rng.range(-20, 20)
    a = make_number(rng, pa, la)
    b = make_number(rng, pb, target - la - rng.range(0, 1))
    gap = gap_between(rng, p, pa + pb, pc) * (-1 if rng.chance(1, 2) else 1)
    c = make_number(rng, pc, target - gap)
    if rng.chance(12, 100):  # cancellation against the product
        exact = exact_value(lambda x: x.multiply(a.value(), b.value()), len(a.digits) + len(b.digits) + 2)
        if exact is not None:
            sign, digits, exponent = exact.as_tuple()
            c = Number(1 - sign, "".join(map(str, digits)), int(exponent))
            if rng.chance(3, 4):
                tail = digits_of(rng, rng.range(1, 6), 0)
                c = Number(c.sign, c.digits + tail, c.exponent - len(tail))
    if rng.chance(30, 100):
        c = last_digit_five(c)
        if a.exponent + b.exponent > c.exponent:
            wide = len(a.digits) + len(b.digits) + len(c.digits) + abs(a.exponent + b.exponent - c.exponent) + 5
            if wide < 20000:
                context = with_tie_precision(
                    context, exact_value(lambda x: x.fma(a.value(), b.value(), c.value()), wide)
                )
    return context, maybe_special(rng, [format_operand(rng, a), format_operand(rng, b), format_operand(rng, c)])


def gen_apply(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    target = target_exponent(rng, context)
    length = operand_length(rng, p) if rng.chance(1, 2) else p + rng.range(0, 6)
    number = make_number(rng, length, target)
    if rng.chance(35, 100) and length >= 2:
        # an exact halfway point: one digit more than the precision, ending 5
        number = make_number(rng, p + 1, target)
        number = last_digit_five(number)
        if rng.chance(40, 100):
            tail = digits_of(rng, rng.range(1, 30), 0)
            number = Number(number.sign, number.digits + tail, number.exponent - len(tail))
        elif rng.chance(1, 2):
            number = Number(number.sign, number.digits[:-1] + str(rng.choice((4, 6))), number.exponent)
    operands = maybe_special(rng, [format_operand(rng, number)])
    # `apply` is a conversion, not a GDA operation: whether a signaling NaN
    # stays signaling is left to the implementation, so it is not tested.
    operands = ["NaN" if text == "sNaN" else text for text in operands]
    return context, operands


def gen_string(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    kind = rng.range(0, 99)
    if kind < 30:
        lead = rng.range(-30, 30)
    elif kind < 60:
        lead = rng.range(-3000, 3000)
    else:
        lead = rng.range(-999999999, 999999999)
    number = make_number(rng, operand_length(rng, 16), lead)
    return context, maybe_special(rng, [format_operand(rng, number)])


def gen_unary_function(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    p = context.precision
    lead = rng.range(-6, 6) if rng.chance(8, 10) else rng.range(-60, 30)
    if family == "exp" and rng.chance(1, 20):
        lead = rng.range(2, 12)
    length = min(max(1, operand_length(rng, p)), 40)
    number = make_number(rng, length, lead)
    if family in ("ln", "log10"):
        number = Number(0, number.digits, number.exponent)
        if rng.chance(1, 5):
            # near 1: 1 plus or minus a few figures far below the last one
            depth = rng.range(2, 40)
            tiny = Decimal(
                (rng.range(0, 1), tuple(int(d) for d in digits_of(rng, 3)), -depth - 2)
            )
            value = Context(prec=400, traps=[]).add(Decimal(1), tiny)
            sign, figures, exponent = value.as_tuple()
            number = Number(0, "".join(map(str, figures)), int(exponent))
    return context, maybe_special(rng, [format_operand(rng, number)])


def gen_power(rng: Rng, family: str) -> tuple[Ctx, list[str]]:
    context = pick_context(rng, family)
    base = make_number(rng, rng.range(1, 30), rng.range(-4, 4))
    if rng.chance(3, 4):
        exponent = Number(rng.range(0, 1), digits_of(rng, rng.range(1, 3)), 0)
        exponent = Number(exponent.sign, exponent.digits, 0)
    else:
        exponent = make_number(rng, rng.range(1, 20), rng.range(-4, 2))
    if rng.chance(1, 15):
        base = Number(0, base.digits, base.exponent)
    operands = maybe_special(rng, [format_operand(rng, base), format_operand(rng, exponent)])
    # Drawn after everything above, so every other row of a case keeps its value.
    if base_family(family) == "power" and not family.endswith("wide") and rng.chance(1, 25):
        return power_of_ten_case(rng, context)
    return context, operands


# `k` of the powers of ten `10^k` whose non-integral powers have an integral
# exponent: `|k|` has no prime factor besides 2 and 5, so `n / |k|` terminates.
POWER_OF_TEN_EXPONENTS = (2, 4, 5, 8, 10, 16, 20, 25, 40, 50)


def power_of_ten_case(rng: Rng, context: Ctx) -> tuple[Ctx, list[str]]:
    """`power(10^k, y)` with a non-integral `y` and an integral `k*y` (issue 351),
    in any rounding mode: the class in which this library returns the exact value
    and libmpdec may be one unit in the last place away in a directed mode. The
    base is written in one of several cohorts."""
    k = POWER_OF_TEN_EXPONENTS[rng.range(0, len(POWER_OF_TEN_EXPONENTS) - 1)]
    sign = -1 if rng.chance(1, 2) else 1
    k *= sign
    n = rng.range(1, 3 * abs(k) - 1)
    if 2 * n == abs(k):
        # y = 0.5 takes the square-root path, which raises an extra Clamped in
        # a clamped context (issue 397); it is not the path of issue 351.
        n += 1
    if n % abs(k) == 0:
        n += 1
    y = Decimal(n) / Decimal(abs(k))
    y = -y if rng.chance(1, 2) else y
    zeros = rng.range(0, 2)
    base = Decimal((0, (1,) + (0,) * zeros, k - zeros))
    rounding = ROUNDINGS[rng.range(0, 7)][0]
    return Ctx(context.precision, rounding, context.emin, context.emax, context.clamp), [str(base), str(y)]


GENERATORS: dict[str, Callable[[Rng, str], tuple[Ctx, list[str]]]] = {
    "expwide": lambda rng, family: gen_unary_function(rng, family),
    "lnwide": lambda rng, family: gen_unary_function(rng, family),
    "log10wide": lambda rng, family: gen_unary_function(rng, family),
    "powerwide": lambda rng, family: gen_power(rng, family),
    "add": gen_add,
    "subtract": gen_add,
    "multiply": gen_multiply,
    "divide": gen_divide,
    "squareroot": gen_sqrt,
    "fma": gen_fma,
    "apply": gen_apply,
    "tosci": gen_string,
    "toeng": gen_string,
    "exp": gen_unary_function,
    "ln": gen_unary_function,
    "log10": gen_unary_function,
    "power": gen_power,
}


# --------------------------------------------------------------- evaluation ---


def condition_names(context: Context) -> list[str]:
    return [name for signal, name in CONDITIONS if context.flags[signal]]


def undefined_division(operands: Sequence[Decimal]) -> bool:
    """GDA 0/0 (and Inf/Inf) is Division_undefined only for zero by zero."""
    left, right = operands
    return left.is_zero() and right.is_zero() and left.is_finite() and right.is_finite()


# Largest precision and exponent magnitude of the contexts in which `exp`, `ln`,
# `log10` and non-integral `power` are defined (decNumber's DEC_MAX_MATH).
MATH_LIMIT = 999999
POWER_OF_TEN_MARKER = "expected-difference power-of-ten #351"


def power_of_ten_exponent(base: Decimal, exponent: Decimal) -> int | None:
    """`k*y` when `base` is a positive power of ten `10^k` (`k != 0`, any cohort)
    and `exponent` a non-integral finite `y` with `k*y` an integer, else None."""
    if not (base.is_finite() and exponent.is_finite()) or base <= 0 or exponent == exponent.to_integral_value():
        return None
    if base.adjusted() == 0 or base.scaleb(-base.adjusted()) != 1:
        return None
    product = Fraction(exponent) * base.adjusted()
    return int(product) if product.denominator == 1 else None


def power_of_ten_result(context: Ctx, exponent: int) -> tuple[Decimal, tuple[str, ...]]:
    """The result this library gives for `10^exponent` as a non-integral power
    (GDA 1.70, power: the result "will be inexact", and an inexact finite result
    should be correctly rounded; the correctly rounded value of a representable
    number is that number in every rounding mode). The exact value is rounded
    to the context by libmpdec only as an arithmetic helper; a value inside the
    exponent range is written with `precision` digits, a subnormal one down to
    Etiny, with Inexact and Rounded (and Underflow when subnormal), and the
    full-precision form never raises Clamped (issue 305)."""
    python = context.python()
    rounded = python.plus(Decimal((0, (1,), exponent)))
    raised = {name for signal, name in CONDITIONS if python.flags[signal]}
    if "Inexact" not in raised:
        etiny = context.emin - context.precision + 1
        padded = max(exponent - (context.precision - 1), etiny)
        if padded <= exponent:
            rounded = Decimal((0, (1,) + (0,) * (exponent - padded), padded))
        raised.discard("Clamped")
        raised |= {"Inexact", "Rounded"}
        if "Subnormal" in raised:
            raised.add("Underflow")
    return rounded, tuple(name for _, name in CONDITIONS if name in raised)


def power_of_ten_difference(case: Case, libmpdec: Decimal) -> tuple[str, tuple[str, ...]] | None:
    """The result and conditions this library gives for `power(10^k, y)` with a
    non-integral `y` and an integral `k*y` (issue 351), when libmpdec's result
    `libmpdec` differs from them.

    libmpdec returns the exact value or a neighbour of it in a directed mode
    (`power 1E-5 1.2` in ceiling is `0.000001000000000000001`), which GDA 1.70
    allows ("may be up to 1 ulp in error"); this library returns the exact value
    in every mode (the maintainer's decision on issue 351). The class is
    checked, not skipped: the row expects this library's result, and the
    generator refuses a row whose libmpdec result is farther than 1 ulp from it.
    Contexts beyond decNumber's elementary limit answer Invalid_context and are
    the business of the `...wide` families."""
    context = case.context
    if case.op != "power" or max(context.precision, context.emax, -context.emin) > MATH_LIMIT:
        return None
    base, exponent = (Decimal(text) for text in case.operands)
    product = power_of_ten_exponent(base, exponent)
    if product is None:
        return None
    expected, conditions = power_of_ten_result(context, product)
    if expected.is_finite() and libmpdec.is_finite():
        ulp = Decimal((0, (1,), max(expected.as_tuple().exponent, libmpdec.as_tuple().exponent)))
        if abs(expected - libmpdec) > ulp:
            raise ValueError(f"{case.case_id}: libmpdec result {libmpdec} is more than 1 ulp from {expected}")
    return str(expected), conditions


def evaluate(case: Case) -> Row:
    context = case.context.python()
    values = [Decimal(text) for text in case.operands]
    op = base_family(case.op)
    if op == "add":
        result = context.add(values[0], values[1])
    elif op == "subtract":
        result = context.subtract(values[0], values[1])
    elif op == "multiply":
        result = context.multiply(values[0], values[1])
    elif op == "divide":
        result = context.divide(values[0], values[1])
    elif op == "squareroot":
        result = context.sqrt(values[0])
    elif op == "fma":
        result = context.fma(values[0], values[1], values[2])
    elif op == "apply":
        # create_decimal applies the context to a literal: GDA `apply`.
        result = context.create_decimal(case.operands[0])
    elif op in ("tosci", "toeng"):
        # decTest applies the precision directive to the operand of toSci and
        # toEng (dtfile.html, "Processing of a test case line").
        converted = context.create_decimal(case.operands[0])
        text = str(converted) if op == "tosci" else converted.to_eng_string()
        return Row(case, text, tuple(condition_names(context)))
    elif op == "exp":
        result = context.exp(values[0])
    elif op == "ln":
        result = context.ln(values[0])
    elif op == "log10":
        result = context.log10(values[0])
    elif op == "power":
        result = context.power(values[0], values[1])
    else:
        raise ValueError(f"unsupported operation {op}")
    names = condition_names(context)
    if op == "divide" and "Invalid_operation" in names and undefined_division(values):
        names.append("Division_undefined")
    text = str(result)
    if op == "power":
        difference = power_of_ten_difference(case, result)
        if difference is not None and (difference[0], difference[1]) != (text, tuple(names)):
            return Row(case, difference[0], difference[1], f"{text} {' '.join(names)}".strip())
    return Row(case, text, tuple(names))


def fit_operand(text: str, emax: int) -> str:
    """An operand whose adjusted exponent exceeds Emax, moved down to Emax.

    decTest converts operands subject to the exponent limits of the directives
    (dtfile.html, "Processing of a test case line"), so such an operand would
    overflow on conversion before the operation sees it. Rows test the
    operation, not the conversion, so the operand is brought into range."""
    value = Decimal(text)
    if not value.is_finite() or value == 0 or value.adjusted() <= emax:
        return text
    sign, figures, _ = value.as_tuple()
    exponent = emax - (len(figures) - 1)
    return str(Decimal((sign, figures, exponent)))


def generate_case(family: str, seed: int, index: int) -> Case:
    rng = Rng(seed, family, index)
    context, operands = GENERATORS[family](rng, family)
    if base_family(family) not in ("apply", "tosci", "toeng"):
        operands = [fit_operand(text, context.emax) for text in operands]
    return Case(f"d{seed}.{family}.{index}", base_family(family), context, tuple(operands))


def format_row(row: Row) -> list[str]:
    lines = row.case.context.directives()
    if row.libmpdec:
        lines.append(f"-- {POWER_OF_TEN_MARKER}: libmpdec gives {row.libmpdec}")
    conditions = " ".join(row.conditions)
    operands = " ".join(quote(text) for text in row.case.operands)
    suffix = f" {conditions}" if conditions else ""
    lines.append(f"{row.case.case_id} {row.case.op} {operands} -> {quote(row.result)}{suffix}")
    return lines


def quote(text: str) -> str:
    return text


def header(family: str, seed: int, start: int, count: int) -> list[str]:
    return [
        f"-- libmpdec-random-v1 libmpdec={decimal.__libmpdec_version__} "
        f"family={family} seed={seed} start={start} count={count}",
        "-- Expected results and conditions: Python decimal (libmpdec). The oracle",
        "-- is not the specification; see doc/manual/verification.md.",
        "version: 2.62",
        "extended: 1",
    ]


def generate(family: str, seed: int, start: int, count: int) -> Iterator[str]:
    yield from header(family, seed, start, count)
    for index in range(start, start + count):
        yield from format_row(evaluate(generate_case(family, seed, index)))


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "families":
        print("\n".join(FAMILIES))
        return 0
    if len(argv) != 5 or argv[1] not in FAMILIES:
        sys.stderr.write(f"usage: {argv[0]} <{'|'.join(FAMILIES)}> <seed> <start> <count>\n")
        return 2
    family, seed, start, count = argv[1], int(argv[2]), int(argv[3]), int(argv[4])
    for line in generate(family, seed, start, count):
        sys.stdout.write(line + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
