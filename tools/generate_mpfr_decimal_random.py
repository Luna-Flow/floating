#!/usr/bin/env python3
"""Seeded random rows for the IEEE decimal elementary functions, certified by MPFR.

Row format `mpfr-decimal-random-v1` (executed by `frontend/mpfr_expr`)::

    id op rounding precision emin emax clamp tininess a b n expected flags

Case ``I`` of operation ``F`` under seed ``S`` is a pure function of
``(S, F, I)``. The expected value is never one MPFR result: it is the rounding
of a rigorous enclosure (`tools/mpfr_decimal_enclosure.c`: 2048-bit operand
bounds, 768-bit directed results, one ulp of slack). A candidate becomes a row
only if

* both enclosure endpoints round to the same decimal with the same flags, and
* the rounded value lies outside the enclosure (so the true value is not
  representable: exact results are not sampled here, they are the subject of
  the white-box tests), and
* for the tininess rule of the row, both endpoints agree on "tiny".

Underflow and Subnormal follow the library's convention (Subnormal = tiny,
Underflow = tiny and inexact) and are computed here for both tininess rules
because Python's `decimal` knows only one: before rounding is the rule of IEEE
754-2019 7.5 for decimal formats; after rounding is the library's non-standard
`AfterRounding` option, which applies the rule that 7.5 states for binary
formats (the result computed with an unbounded exponent range and precision p). Rounded, Clamped and
Overflow come from libmpdec. MPFR and libmpdec are oracles, not authorities.

A candidate that does not certify is replaced by the next attempt of the same
index (at most ``MAX_ATTEMPTS``), so the sequence stays a function of the index.
"""

from __future__ import annotations

import argparse
import decimal
import os
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal
from fractions import Fraction
from pathlib import Path

import generate_libmpdec_random as base

sys.set_int_max_str_digits(0)

REPO_ROOT = Path(__file__).resolve().parent.parent
C_SOURCE = REPO_ROOT / "tools/mpfr_decimal_enclosure.c"
ENCLOSURE_BINARY = REPO_ROOT / ".tmp/random-diff/bin/mpfr_decimal_enclosure"

MAX_ATTEMPTS = 8
# Exponent range of the "wide" contexts. `decimal_exact_dyadic_endpoint` expands
# every in-range endpoint to its exact decimal, so a result near 10^E costs
# O(E^1.6) and ranges beyond 20,000 make a random campaign impractical
# (`doc/manual/verification.md`); the boundary sweeps probe the wide ones.
WIDE_EXPONENT = 20_000
CHUNK = 20_000
HEADER = "# mpfr-decimal-random-v1"
COLUMNS = "# id op rounding precision emin emax clamp tininess a b n expected flags"

# Operand profiles: how the operands of an operation are drawn.
EXP = "exp"  # growth like exp: |x| up to the overflow threshold
EXP2 = "exp2_growth"  # growth like 2^x: overflow near x = 3.32 (emax + 1)
EXP10 = "exp10_growth"  # growth like 10^x: overflow near x = emax + 1
POSITIVE = "positive"  # x > 0
LOG1P = "log1p"  # x > -1
UNIT = "unit"  # |x| <= 1
AT_LEAST_ONE = "at_least_one"  # x >= 1
REAL = "real"  # any real, moderate to tiny
ARITY = {
    "exp": (EXP,), "exp2": (EXP,), "exp10": (EXP,), "expm1": (EXP,),
    "sinh": (EXP,), "cosh": (EXP,),
    "ln": (POSITIVE,), "log2": (POSITIVE,), "log10": (POSITIVE,),
    "log1p": (LOG1P,),
    "sin": (REAL,), "cos": (REAL,), "tan": (REAL,),
    "sinpi": (REAL,), "cospi": (REAL,), "tanpi": (REAL,),
    "atan": (REAL,), "tanh": (REAL,), "asinh": (REAL,),
    "asin": (UNIT,), "acos": (UNIT,), "atanh": (UNIT,),
    "acosh": (AT_LEAST_ONE,),
    "pow": ("pow_base", "pow_exponent"),
    "hypot": (REAL, REAL),
    "atan2": (REAL, REAL),
    "rootn": ("root_base",),
    "pown": ("root_base",),
    # IEEE 754-2019 9.2 functions added by #236 (after the first campaign's
    # entries, so the rows of every earlier operation are unchanged).
    "exp2m1": (EXP2,), "exp10m1": (EXP10,),
    "log2p1": (LOG1P,), "log10p1": (LOG1P,),
    # rSqrt, compound and powr (#236 PR 2). compound is not enclosed by MPFR
    # (mpfr_compound_si 4.2.2 is wrong for n < 0 in the directed modes): its
    # value is the exact rational (1 + x)^n, bracketed to 900 digits.
    "rsqrt": (POSITIVE,), "compound": (LOG1P,), "powr": ("pow_base", "pow_exponent"),
}
INTEGER_OPERATIONS = ("rootn", "pown", "compound")
OPERATIONS = tuple(ARITY)
IEEE_CONTEXTS = base.IEEE_CONTEXTS


@dataclass(frozen=True)
class Context:
    precision: int
    rounding: str
    emin: int
    emax: int
    clamp: int
    tininess: str  # "a" or "b"

    @property
    def etiny(self) -> int:
        return self.emin - self.precision + 1

    def python(self) -> decimal.Context:
        return decimal.Context(
            prec=self.precision,
            rounding=dict(base.ROUNDINGS)[self.rounding],
            Emin=self.emin,
            Emax=self.emax,
            clamp=self.clamp,
            capitals=1,
            flags=[],
            traps=[],
        )

    def unbounded(self) -> decimal.Context:
        return decimal.Context(
            prec=self.precision,
            rounding=dict(base.ROUNDINGS)[self.rounding],
            Emin=-(10**17),
            Emax=10**17,
            clamp=0,
            capitals=1,
            flags=[],
            traps=[],
        )


@dataclass(frozen=True)
class Candidate:
    index: int
    op: str
    context: Context
    operands: tuple[Decimal, ...]
    integer: int


# ---------------------------------------------------------------- operands ---


def pick_context(rng: base.Rng) -> Context:
    rounding = base.ROUNDINGS[rng.range(0, 7)][0]
    kind = rng.range(0, 99)
    if kind < 30:
        precision, emin, emax = IEEE_CONTEXTS[rng.range(0, 2)]
        clamp = 1 if rng.chance(4, 5) else 0
    elif kind < 50:
        precision = rng.range(1, 6)
        emax = rng.range(0, 20)
        emin = -rng.range(0, 30)
        clamp = rng.range(0, 1)
    elif kind < 75:
        precision = rng.log(1, 120)
        emax = rng.choice((0, 9, 99, 999, 9999))
        emax = max(0, emax + rng.range(-3, 3))
        emin = -emax - rng.range(-3, 5)
        emin = min(emin, 0)
        clamp = rng.range(0, 1)
    elif kind < 90:
        precision = rng.range(1, 40)
        emax = rng.range(0, WIDE_EXPONENT)
        emin = -rng.range(0, WIDE_EXPONENT)
        clamp = rng.range(0, 1)
    else:
        precision = rng.choice((9, 9, 3, 28, 100))
        emax, emin, clamp = 999, -999, 0
    return Context(precision, rounding, emin, emax, clamp, "a" if rng.chance(1, 2) else "b")


def digits(rng: base.Rng, length: int) -> str:
    text = str(rng.range(1, 9))
    style = rng.range(0, 9)
    for _ in range(length - 1):
        if style == 0:
            text += "9"
        elif style == 1:
            text += "0" if rng.chance(3, 4) else str(rng.range(0, 9))
        else:
            text += str(rng.range(0, 9))
    return text


def adjusted_target(rng: base.Rng, context: Context, profile: str) -> int:
    """The adjusted exponent (decimal order of magnitude) of an operand."""
    precision = context.precision
    kind = rng.range(0, 99)
    if profile in (EXP, EXP2, EXP10):
        # The overflow threshold of exp is x ~ 2.4 * (emax + 2) (3.33 for
        # 2^x, 1 for 10^x); 10% of the samples sit there, 15% near zero where
        # the result is near 1.
        scale = {EXP: 2.4, EXP2: 3.33, EXP10: 1.0}[profile]
        limit = max(1, int((context.emax + 2) * scale))
        order = len(str(limit)) - 1
        if kind < 25:
            return rng.range(-(precision + 3), 0)
        if kind < 55:
            return rng.range(0, min(3, order))
        if kind < 75:
            return order - rng.range(0, 1)
        if kind < 90:
            return rng.range(-(precision + 8) - 20, -(precision + 3))
        return rng.range(context.etiny - 2, context.emin + precision)
    if profile in (POSITIVE, "pow_base", "root_base"):
        span = 3 if profile != POSITIVE else 300
        if kind < 30:
            return rng.range(-3, 3)
        if kind < 70:
            return rng.range(-min(-context.emin, span), min(context.emax, span))
        if kind < 85:
            return context.emax - rng.range(0, 4)
        return context.emin + rng.range(0, 4)
    if profile == LOG1P:
        if kind < 25:
            return rng.range(-(precision + 8), -1)
        if kind < 60:
            return rng.range(-3, 3)
        if kind < 80:
            return rng.range(3, 30)
        return rng.range(context.etiny - 2, context.emin + precision)
    if profile in (UNIT, "pow_exponent"):
        if kind < 40:
            return rng.range(-3, -1)
        if kind < 70:
            return rng.range(-(precision + 8), -3)
        if kind < 85:
            return rng.range(-1, 0)
        return rng.range(context.etiny - 2, context.emin + precision)
    if profile == AT_LEAST_ONE:
        if kind < 40:
            return rng.range(0, 2)
        if kind < 70:
            return rng.range(2, 40)
        return context.emax - rng.range(0, 4)
    # REAL
    if kind < 25:
        return rng.range(-(precision + 3), 0)
    if kind < 60:
        return rng.range(0, 6)
    if kind < 70:
        return rng.range(6, 40)
    if kind < 85:
        return rng.range(-(precision + 8) - 20, -(precision + 3))
    return rng.range(context.etiny - 2, context.emin + precision)


def make_operand(rng: base.Rng, context: Context, profile: str, negative_ok: bool) -> Decimal | None:
    """An operand representable in the context, or None if the draw is unusable."""
    precision = context.precision
    length = rng.range(1, min(precision, 40)) if rng.chance(3, 4) else precision
    length = max(1, min(length, 400))
    coefficient = digits(rng, length)
    adjusted = adjusted_target(rng, context, profile)
    exponent = adjusted - (length - 1)
    sign = 1 if negative_ok and rng.chance(1, 2) else 0
    if profile in (POSITIVE, AT_LEAST_ONE, "pow_base"):
        sign = 0
    value = Decimal((sign, tuple(int(d) for d in coefficient), exponent))
    fraction = Decimal((sign, tuple(int(d) for d in coefficient), -length))
    if profile == AT_LEAST_ONE:
        # 1 + t with t >= 0 drawn like a magnitude (exact: wide context).
        value = decimal.Context(prec=2000, Emax=10**9, Emin=-(10**9)).add(Decimal(1), value)
    if profile == LOG1P and sign == 1 and value.adjusted() >= 0:
        value = fraction  # a negative operand must stay above -1
    if profile == UNIT and value.copy_abs() > 1:
        value = fraction
    return value


def representable(value: Decimal, context: Context) -> Decimal | None:
    """`value` as a member of the context's format (same value, no flags)."""
    if not value.is_finite() or value.is_zero():
        return None
    python = context.python()
    rounded = python.create_decimal(value)
    flags = {signal for signal, raised in python.flags.items() if raised}
    if flags or rounded != value or not rounded.is_finite() or rounded.is_zero():
        return None
    return rounded


def make_candidate(op: str, seed: int, index: int, attempt: int) -> Candidate | None:
    rng = base.Rng(seed, f"decm.{op}.{attempt}", index)
    context = pick_context(rng)
    profiles = ARITY[op]
    operands: list[Decimal] = []
    for position, profile in enumerate(profiles):
        negative_ok = profile not in (POSITIVE, AT_LEAST_ONE, "pow_base")
        value = None
        for _ in range(6):
            draw = make_operand(rng, context, profile, negative_ok)
            if draw is None:
                continue
            value = representable(draw, context)
            if value is not None:
                break
        if value is None:
            return None
        if profile == "root_base":
            # rootn of a negative needs an odd degree: decided below.
            pass
        operands.append(value)
    integer = 0
    if op == "rootn":
        integer = rng.range(1, 40)
        if operands[0] < 0 and integer % 2 == 0:
            integer += 1
    elif op == "pown":
        integer = rng.range(1, 40) * (-1 if rng.chance(1, 3) else 1)
    elif op == "compound":
        integer = rng.range(1, 40) if rng.chance(4, 5) else rng.range(41, 400)
        integer *= -1 if rng.chance(1, 3) else 1
    return Candidate(index, op, context, tuple(operands), integer)


# ----------------------------------------------------------------- oracle ---


def build_enclosure(mpfr_prefix: str | None = None, force: bool = False) -> Path:
    if ENCLOSURE_BINARY.is_file() and not force:
        if ENCLOSURE_BINARY.stat().st_mtime >= C_SOURCE.stat().st_mtime:
            return ENCLOSURE_BINARY
    prefix = None
    for candidate in (mpfr_prefix, os.environ.get("MPFR_PREFIX"), "/opt/homebrew", "/usr/local", "/usr"):
        if candidate and (Path(candidate) / "include/mpfr.h").is_file():
            prefix = Path(candidate)
            break
    if prefix is None:
        raise RuntimeError("mpfr.h not found; set MPFR_PREFIX")
    ENCLOSURE_BINARY.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [os.environ.get("CC", "cc"), "-O2", f"-I{prefix}/include", f"-L{prefix}/lib",
         "-o", str(ENCLOSURE_BINARY), str(C_SOURCE), "-lmpfr", "-lgmp"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError("cannot build the MPFR enclosure helper:\n" + result.stderr)
    return ENCLOSURE_BINARY


def enclose(candidates: list[Candidate], binary: Path) -> list[tuple[int, int, int, int] | None]:
    """Dyadic enclosures `(m_lo, e_lo, m_hi, e_hi)` or None (skip), in order."""
    lines = []
    for candidate in candidates:
        second = str(candidate.operands[1]) if len(candidate.operands) > 1 else "-"
        lines.append(f"{candidate.op} {candidate.operands[0]} {second} {candidate.integer}")
    result = subprocess.run([str(binary)], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("MPFR enclosure helper failed:\n" + result.stderr)
    outputs = [line for line in result.stdout.splitlines() if not line.startswith("#")]
    if len(outputs) != len(candidates):
        raise RuntimeError("MPFR enclosure helper returned a different number of lines")
    parsed: list[tuple[int, int, int, int] | None] = []
    for line in outputs:
        if line == "skip":
            parsed.append(None)
        else:
            m_lo, e_lo, m_hi, e_hi = line.split()
            parsed.append((int(m_lo), int(e_lo), int(m_hi), int(e_hi)))
    return parsed


WORK_DIGITS = 900


def dyadic_bound(mantissa: int, exponent: int, upper: bool, context: Context) -> Decimal:
    """A decimal with 900 digits that is >= (upper) or <= m * 2^e, to 10^-899."""
    if mantissa == 0:
        return Decimal(0)
    negative = mantissa < 0
    magnitude = -mantissa if negative else mantissa
    # Round the magnitude up for an upper bound of a positive value or a lower
    # bound of a negative one.
    round_up = upper != negative
    top = int((magnitude.bit_length() + exponent) * 0.30103) + 1
    # Far outside the exponent range every endpoint overflows (or underflows)
    # alike; a representative of the same sign and result spares expanding an
    # integer of millions of digits (rounding is monotone).
    if top > context.emax + 10:
        return Decimal((1 if negative else 0, (1,), context.emax + 10))
    if top < context.etiny - 10:
        return Decimal((1 if negative else 0, (1,), context.etiny - 10))
    shift = top - WORK_DIGITS  # value = q * 10^shift
    numerator = magnitude
    denominator = 1
    if exponent >= 0:
        numerator <<= exponent
    else:
        denominator <<= -exponent
    if shift >= 0:
        denominator *= 10**shift
    else:
        numerator *= 10 ** (-shift)
    quotient, remainder = divmod(numerator, denominator)
    if round_up and remainder:
        quotient += 1
    text = str(quotient)
    result = Decimal((1 if negative else 0, tuple(int(c) for c in text), shift))
    return result


def flag_names(context: decimal.Context) -> set[str]:
    return {signal.__name__ for signal, raised in context.flags.items() if raised}


def certify(candidate: Candidate, enclosure: tuple[int, int, int, int]) -> str | None:
    lower = dyadic_bound(enclosure[0], enclosure[1], False, candidate.context)
    upper = dyadic_bound(enclosure[2], enclosure[3], True, candidate.context)
    return certify_bounds(candidate, lower, upper)


def rational_bound(value: Fraction, upper: bool, context: Context) -> Decimal:
    """A 900-digit decimal >= (upper) or <= the rational `value`."""
    if value == 0:
        return Decimal(0)
    negative = value < 0
    magnitude = -value if negative else value
    round_up = upper != negative
    top = len(str(magnitude.numerator)) - len(str(magnitude.denominator)) + 1
    if top > context.emax + 10:
        return Decimal((1 if negative else 0, (1,), context.emax + 10))
    if top < context.etiny - 10:
        return Decimal((1 if negative else 0, (1,), context.etiny - 10))
    shift = top - WORK_DIGITS
    numerator, denominator = magnitude.numerator, magnitude.denominator
    if shift >= 0:
        denominator *= 10**shift
    else:
        numerator *= 10 ** (-shift)
    quotient, remainder = divmod(numerator, denominator)
    if round_up and remainder:
        quotient += 1
    return Decimal((1 if negative else 0, tuple(int(c) for c in str(quotient)), shift))


def certify_exact_compound(candidate: Candidate) -> str | None:
    """compound(x, n) from exact rational arithmetic on (1 + x)^n.

    Far outside the range both bounds are the range representative; for
    |x| < 10^-150, 1 + n x +- 2 (n x)^2 encloses the value (|n x| < 10^-147:
    |n log1p(x) - n x| <= |n| x^2 and |e^u - 1 - u| <= 0.6 u^2);
    otherwise the rational (1 + x)^n itself is bracketed."""
    x = candidate.operands[0]
    n = candidate.integer
    context = candidate.context
    with decimal.localcontext() as local:
        local.prec = 40
        local.Emax = decimal.MAX_EMAX
        local.Emin = decimal.MIN_EMIN
        local.traps[decimal.Inexact] = False
        local.traps[decimal.Rounded] = False
        estimate = n * (1 + x).log10()
    if estimate > context.emax + 12:
        top = Decimal((0, (1,), context.emax + 10))
        return certify_bounds(candidate, top, top)
    if estimate < context.etiny - 12:
        bottom = Decimal((0, (1,), context.etiny - 10))
        return certify_bounds(candidate, bottom, bottom)
    if x.adjusted() < -150:
        # Exact decimal arithmetic: a 900-digit bracket would swallow a
        # deviation below 10^-900 and reject the row.
        with decimal.localcontext() as exact:
            exact.prec = decimal.MAX_PREC
            exact.Emax = decimal.MAX_EMAX
            exact.Emin = decimal.MIN_EMIN
            exact.traps[decimal.Inexact] = True
            linear = 1 + n * x
            error = 2 * (n * x) * (n * x)
            lower = linear - error
            upper = linear + error
        return certify_bounds(candidate, lower, upper)
    if abs(n) > 2000 or abs(x.adjusted()) > 150:
        # exp(n ln(1 + x)) by libmpdec at P digits (its ln and exp are
        # correctly rounded); u = n ln(1 + x) carries an absolute error below
        # |u| 10^(1-P) and 1 + x is exact, so the value is within a relative
        # (|u| + 2) 10^(2-P) of the computed one.
        digits = 3 * context.precision + 60
        with decimal.localcontext() as local:
            local.prec = digits
            local.Emax = decimal.MAX_EMAX
            local.Emin = decimal.MIN_EMIN
            local.traps[decimal.Inexact] = False
            local.traps[decimal.Rounded] = False
            u = n * decimal.Context(prec=decimal.MAX_PREC, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN).add(1, x).ln(local)
            value = u.exp()
            slack = (abs(u) + 2) * Decimal((0, (1,), 2 - digits))
            lower = value * (1 - slack)
            upper = value * (1 + slack)
        return certify_bounds(candidate, lower, upper)
    value = (1 + Fraction(x)) ** n
    lower = rational_bound(value, False, context)
    upper = rational_bound(value, True, context)
    return certify_bounds(candidate, lower, upper)


def certify_bounds(candidate: Candidate, lower: Decimal, upper: Decimal) -> str | None:
    if lower > upper or lower.is_zero() or upper.is_zero() or (lower < 0) != (upper < 0):
        return None
    context = candidate.context
    results = []
    for endpoint in (lower, upper):
        python = context.python()
        result = python.create_decimal(endpoint)
        flags = flag_names(python)
        unbounded = context.unbounded()
        rounded_unbounded = unbounded.create_decimal(endpoint)
        tiny_after = (not rounded_unbounded.is_zero()) and rounded_unbounded.adjusted() < context.emin
        tiny_before = endpoint.adjusted() < context.emin
        results.append((result, flags, tiny_after, tiny_before))
    (low_result, low_flags, low_after, low_before), (high_result, high_flags, high_after, high_before) = results
    if low_result.compare_total(high_result) != 0:
        return None
    for name in ("Rounded", "Clamped", "Overflow"):
        if (name in low_flags) != (name in high_flags):
            return None
    tiny = (low_after, high_after) if context.tininess == "a" else (low_before, high_before)
    if tiny[0] != tiny[1]:
        return None
    # The rounded value must lie outside the enclosure: the true value is then
    # certainly not representable, and every endpoint flag is the value's own.
    if low_result.is_finite() and lower <= low_result <= upper:
        return None
    letters = "x"
    if "Rounded" in low_flags:
        letters += "r"
    if "Overflow" in low_flags:
        letters += "o"
    is_tiny = tiny[0] and not low_result.is_infinite()
    if is_tiny:
        letters += "su"
    if "Clamped" in low_flags:
        letters += "c"
    order = "xrosucvz"
    letters = "".join(sorted(set(letters), key=order.index))
    operands = candidate.operands
    return " ".join(
        [
            candidate_id(candidate),
            candidate.op,
            context.rounding,
            str(context.precision),
            str(context.emin),
            str(context.emax),
            str(context.clamp),
            context.tininess,
            str(operands[0]),
            str(operands[1]) if len(operands) > 1 else "-",
            str(candidate.integer),
            str(low_result),
            letters or "-",
        ]
    )


_SEED = 0


def candidate_id(candidate: Candidate) -> str:
    return f"m{_SEED}.{candidate.op}.{candidate.index}"


def generate(op: str, seed: int, start: int, count: int, mpfr_prefix: str | None = None) -> list[str]:
    """The rows of cases `start .. start + count - 1` of `op` (fewer if some never certify)."""
    global _SEED
    _SEED = seed
    binary = build_enclosure(mpfr_prefix)
    rows: dict[int, str] = {}
    pending = list(range(start, start + count))
    for attempt in range(MAX_ATTEMPTS):
        if not pending:
            break
        candidates = []
        for index in pending:
            candidate = make_candidate(op, seed, index, attempt)
            if candidate is not None:
                candidates.append(candidate)
        if op == "compound":
            for candidate in candidates:
                row = certify_exact_compound(candidate)
                if row is not None:
                    rows[candidate.index] = row
            candidates = []
        for offset in range(0, len(candidates), CHUNK):
            chunk = candidates[offset : offset + CHUNK]
            for candidate, enclosure in zip(chunk, enclose(chunk, binary)):
                if enclosure is None:
                    continue
                row = certify(candidate, enclosure)
                if row is not None:
                    rows[candidate.index] = row
        pending = [index for index in pending if index not in rows]
    return [rows[index] for index in sorted(rows)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("op", choices=OPERATIONS)
    parser.add_argument("--seed", type=int, default=20261118)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--mpfr-prefix")
    args = parser.parse_args(argv)
    rows = generate(args.op, args.seed, args.start, args.count, args.mpfr_prefix)
    print(f"{HEADER} seed={args.seed} op={args.op}")
    print(COLUMNS)
    for row in rows:
        print(row)
    print(f"# {len(rows)} of {args.count} cases certified", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
