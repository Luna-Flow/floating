#!/usr/bin/env python3
"""An oracle for sinRev, cosRev and tanRev that shares no code with `ball_float`.

It evaluates asin, acos, atan and pi with Python's `decimal` at 260 digits and
encloses every value in an interval of width 2 * 10^-230, lists every piece of
the preimage for every period index in a window that covers the prior, and
decides each comparison and each directed rounding to binary64 from the
enclosures (it raises if one cannot be decided). Its results are the exact hull
in binary64 of `{x in prior | f(x) in c}`.

`--check` compares the corpus values with the oracle and checks that the
refinements file lists exactly the statements whose corpus value is wider than
the exact hull; `--write` rewrites the file.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path

import itl_refinements as refs

DIGITS = 260
ERROR = Fraction(1, 10**230)
REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS = REPO_ROOT / "testdata/interval/itf1788"
REFINEMENTS = REPO_ROOT / "testdata/interval/interpreter_refinements.json"
FILE = "libieeep1788_tests_rev.itl"
OPERATIONS = {
    "sinRev": ("sin", False),
    "sinRevBin": ("sin", True),
    "cosRev": ("cos", False),
    "cosRevBin": ("cos", True),
    "tanRev": ("tan", False),
    "tanRevBin": ("tan", True),
}


@dataclass(frozen=True)
class Enc:
    """A closed interval of rationals that contains a real number."""

    lo: Fraction
    hi: Fraction

    def __add__(self, other: Enc) -> Enc:
        return Enc(self.lo + other.lo, self.hi + other.hi)

    def __sub__(self, other: Enc) -> Enc:
        return Enc(self.lo - other.hi, self.hi - other.lo)

    def scale(self, factor: int) -> Enc:
        a, b = self.lo * factor, self.hi * factor
        return Enc(min(a, b), max(a, b))


def exact(value: Fraction) -> Enc:
    return Enc(value, value)


def _dec(value: Fraction) -> Decimal:
    return Decimal(value.numerator) / Decimal(value.denominator)


def _frac(value: Decimal) -> Fraction:
    return Fraction(value)


def _atan_series(t: Decimal) -> Decimal:
    """atan(t) for |t| <= 0.2 by the Taylor series (alternating, so the first
    omitted term bounds the error)."""
    threshold = Decimal(10) ** (-(DIGITS - 5))
    square = t * t
    power = t
    total = Decimal(0)
    k = 0
    while True:
        term = power / (2 * k + 1)
        total += -term if k % 2 else term
        if abs(term) < threshold:
            return total
        power *= square
        k += 1


def _atan_decimal(x: Decimal) -> Decimal:
    """atan(x) for |x| <= 1: three halvings atan(x) = 2 atan(x / (1 + sqrt(1 + x^2)))
    bring |x| below 0.1, then the series."""
    t = x
    for _ in range(3):
        t = t / (1 + (1 + t * t).sqrt())
    return 8 * _atan_series(t)


def _pi_decimal() -> Decimal:
    """Machin's formula."""
    return 16 * _atan_series(Decimal(1) / 5) - 4 * _atan_series(Decimal(1) / 239)


def pi() -> Enc:
    with localcontext() as context:
        context.prec = DIGITS
        value = _frac(_pi_decimal())
    return Enc(value - ERROR, value + ERROR)


def half_pi() -> Enc:
    p = pi()
    return Enc(p.lo / 2, p.hi / 2)


def atan(x: Fraction) -> Enc:
    if x == 0:
        return exact(Fraction(0))
    with localcontext() as context:
        context.prec = DIGITS
        magnitude = abs(x)
        if magnitude <= 1:
            value = _atan_decimal(_dec(magnitude))
        else:
            value = _pi_decimal() / 2 - _atan_decimal(_dec(1 / magnitude))
        result = _frac(value)
    enc = Enc(result - ERROR, result + ERROR)
    return enc if x > 0 else Enc(-enc.hi, -enc.lo)


def asin(x: Fraction) -> Enc:
    if x == 0:
        return exact(Fraction(0))
    if abs(x) == 1:
        h = half_pi()
        return h if x > 0 else Enc(-h.hi, -h.lo)
    with localcontext() as context:
        context.prec = DIGITS
        root = _dec(1 - x * x).sqrt()
        argument = _frac(_dec(x) / root)
    # the argument carries a relative error far below ERROR; widen to be safe
    inner = atan(argument)
    return Enc(inner.lo - ERROR, inner.hi + ERROR)


def acos(x: Fraction) -> Enc:
    if x == 1:
        return exact(Fraction(0))
    if x == -1:
        return pi()
    a = asin(x)
    h = half_pi()
    return Enc(h.lo - a.hi, h.hi - a.lo)


def compare(enc: Enc, d: Fraction) -> int:
    """-1, 0 or 1 for enc < d, enc = d (an exact value only) or enc > d."""
    if enc.lo > d:
        return 1
    if enc.hi < d:
        return -1
    if enc.lo == enc.hi == d:
        return 0
    raise ValueError("a comparison with the prior cannot be decided from the enclosure")


def rounded_end(enc: Enc, upper: bool) -> Fraction:
    """RD or RU to binary64 of the real number inside `enc`; raises if `enc`
    contains a binary64 value (then the rounding is not determined)."""
    if enc.lo == enc.hi:
        # an exact end (0): it must itself be a binary64 value
        if refs.round_binary64(enc.lo, up=True) != enc.lo:
            raise ValueError("an exact end is not a binary64 value")
        return enc.lo
    low, high = refs.round_binary64(enc.lo, up=True), refs.round_binary64(enc.hi, up=False)
    if low <= high:
        raise ValueError("the enclosure of an end contains a binary64 value")
    return refs.round_binary64(enc.hi, up=True) if upper else refs.round_binary64(enc.lo, up=False)


def operand(word: str) -> tuple[bool, Fraction | float, Fraction | float]:
    """A statement operand as a binary64 interval (a decimal bound is rounded
    outward by the parser); returns (is_empty, lower, upper), ignoring the
    decoration suffix."""
    interval = refs.parse_interval(word)
    if interval.empty:
        return True, math.inf, -math.inf
    return False, interval.lo, interval.hi


def _pieces(
    kind: str, c: tuple[Fraction | float, Fraction | float], kmin: int, kmax: int
) -> list[tuple[Enc, Enc]]:
    p = pi()
    two_pi = p.scale(2)
    out: list[tuple[Enc, Enc]] = []
    for k in range(kmin, kmax + 1):
        if kind == "tan":
            shift = p.scale(k)
            h = half_pi()
            lo = shift - h if c[0] == -math.inf else atan(Fraction(c[0])) + shift
            hi = shift + h if c[1] == math.inf else atan(Fraction(c[1])) + shift
            out.append((lo, hi))
            continue
        s_lo = max(Fraction(c[0]), Fraction(-1))
        s_hi = min(Fraction(c[1]), Fraction(1))
        shift = two_pi.scale(k)
        if kind == "sin":
            a, b = asin(s_lo), asin(s_hi)
            out.append((a + shift, b + shift))
            odd = p.scale(2 * k + 1)
            out.append((odd - b, odd - a))
        else:
            a, b = acos(s_hi), acos(s_lo)
            out.append((a + shift, b + shift))
            out.append((shift - b, shift - a))
    return out


def reverse_hull(
    kind: str,
    c: tuple[Fraction | float, Fraction | float],
    prior: tuple[Fraction | float, Fraction | float],
) -> tuple[Fraction | float, Fraction | float] | None:
    """The hull in binary64 of {x in prior | f(x) in c}, or None if it is empty.

    The prior must not be unbounded on both sides (the answer is then the whole
    line whenever the set is nonempty). An infinite end of the prior is an
    infinite end of the result, the set being periodic and unbounded."""
    xl, xh = prior
    if kind != "tan" and (c[1] < -1 or c[0] > 1):
        return None
    period = math.pi if kind == "tan" else 2 * math.pi
    if xl == -math.inf:
        first = math.floor(float(Fraction(xh)) / period) - 11
    else:
        first = math.floor(float(Fraction(xl)) / period) - 3
    if xh == math.inf:
        last = first + 11
    else:
        last = math.floor(float(Fraction(xh)) / period) + 3
    lower: Fraction | None = None
    upper: Fraction | None = None
    for lo, hi in _pieces(kind, c, first, last):
        reaches = xl == -math.inf or compare(hi, Fraction(xl)) >= 0
        starts = xh == math.inf or compare(lo, Fraction(xh)) <= 0
        if not (reaches and starts):
            continue
        if xl != -math.inf:
            v = Fraction(xl) if compare(lo, Fraction(xl)) <= 0 else rounded_end(lo, upper=False)
            lower = v if lower is None or v < lower else lower
        if xh != math.inf:
            w = Fraction(xh) if compare(hi, Fraction(xh)) >= 0 else rounded_end(hi, upper=True)
            upper = w if upper is None or w > upper else upper
    if xl != -math.inf and lower is None:
        return None
    if xh != math.inf and upper is None:
        return None
    return (-math.inf if xl == -math.inf else lower, math.inf if xh == math.inf else upper)  # type: ignore[return-value]


def _bound_text(value: Fraction | float) -> str:
    if isinstance(value, float):
        return "infinity" if value > 0 else "-infinity"
    return float(value).hex()


def oracle_value(statement: refs.Statement, corpus_word: str) -> str | None:
    """The oracle's expected value for one statement, in the corpus notation
    (the decoration suffix of the corpus value is kept), or None if the
    operation is not one of the reverse trigonometric functions."""
    if statement.operation not in OPERATIONS:
        return None
    kind, has_prior = OPERATIONS[statement.operation]
    words = refs.split_words(statement.lhs)[1:]
    c_empty, c_lo, c_hi = operand(words[0])
    x_empty, x_lo, x_hi = (False, -math.inf, math.inf)
    if has_prior:
        x_empty, x_lo, x_hi = operand(words[1])
    decoration = refs.parse_interval(corpus_word).decoration
    suffix = f"_{decoration}" if decoration else ""
    out_of_range = kind != "tan" and (c_hi < -1 or c_lo > 1)
    if c_empty or x_empty or out_of_range:
        return "[empty]" + suffix
    if x_lo == -math.inf and x_hi == math.inf:
        return "[entire]" + suffix
    hull = reverse_hull(kind, (c_lo, c_hi), (x_lo, x_hi))
    if hull is None:
        return "[empty]" + suffix
    return f"[{_bound_text(hull[0])},{_bound_text(hull[1])}]" + suffix


def ulps(value: Fraction, reference: Fraction) -> int:
    """How many binary64 steps `value` lies from `reference` (both binary64)."""
    return int(abs(value - reference) / refs.binary64_ulp(reference))


def classify(statement: refs.Statement) -> tuple[str, str | None]:
    """('equal' | 'refined' | 'wrong', refined value) for a trig reverse statement."""
    word = refs.split_words(statement.expected)[0]
    refined = oracle_value(statement, word)
    assert refined is not None
    corpus = refs.parse_interval(word)
    exact_value = refs.parse_interval(refined)
    if refs.same_set(corpus, exact_value):
        return "equal", None
    if refs.contains(corpus, exact_value):
        return "refined", refined
    return "wrong", refined


def reason(statement: refs.Statement, refined: str) -> str:
    corpus = refs.parse_interval(refs.split_words(statement.expected)[0])
    exact_value = refs.parse_interval(refined)
    parts: list[str] = []
    for name, got, want in (("lower", corpus.lo, exact_value.lo), ("upper", corpus.hi, exact_value.hi)):
        if got != want:
            parts.append(f"{name} end {ulps(Fraction(want), Fraction(got)) or 1} ulp from the exact hull end")
    return (
        "the corpus value is valid but wider than the exact hull in binary64 ("
        + ", ".join(parts)
        + "); IEEE 1788-2015 12.12.4 asks for an enclosure only"
    )


def build_entries() -> tuple[list[dict[str, str]], list[str]]:
    statements = refs.parse_statements((CORPUS / FILE).read_text(encoding="utf-8"))
    entries: list[dict[str, str]] = []
    problems: list[str] = []
    for statement in statements:
        if statement.operation not in OPERATIONS:
            continue
        verdict, refined = classify(statement)
        if verdict == "wrong":
            problems.append(f"{statement.id}: the corpus value is not a superset of the exact hull")
        elif verdict == "refined":
            assert refined is not None
            entries.append(
                {
                    "file": FILE,
                    "id": statement.id,
                    "operation": statement.operation,
                    "corpus": statement.expected,
                    "refined": refined,
                    "reason": reason(statement, refined),
                }
            )
    return entries, problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--write", action="store_true")
    args = parser.parse_args(argv)
    entries, problems = build_entries()
    if problems:
        print("\n".join(problems))
        return 1
    # the file also holds the entries of the other oracles (powRev2: `itl_pow2_reverse_oracle.py`
    # checks them); this oracle owns the entries of its own operations and keeps the rest
    existing = (
        json.loads(REFINEMENTS.read_text(encoding="utf-8")).get("refinements", [])
        if REFINEMENTS.exists()
        else []
    )
    others = [entry for entry in existing if entry["operation"] not in OPERATIONS]
    document = {"schemaVersion": 1, "corpus": "itf1788", "refinements": entries + others}
    text = json.dumps(document, indent=2) + "\n"
    if args.write:
        REFINEMENTS.write_text(text, encoding="utf-8")
        print(f"wrote {len(entries)} refinements ({len(others)} of other operations kept)")
        return 0
    own = [entry for entry in existing if entry["operation"] in OPERATIONS]
    if not REFINEMENTS.exists() or own != entries:
        print("interpreter_refinements.json differs from the oracle; run --write and review")
        return 1
    print(f"{len(entries)} refinements agree with the oracle")
    return 0


if __name__ == "__main__":
    sys.exit(main())
