#!/usr/bin/env python3
"""An oracle for powRev1 that shares no code with `ball_float`.

powRev1(b, c, x) is the hull of {x in prior | exists beta in b: x^beta defined and in c},
x^beta being defined for x > 0 (any beta) and for x = 0 with beta > 0 (value 0).

For x > 0, `x^beta in c` is `beta * ln x in ln(c)`, so the set is `exp(L /set b)` with
`L = ln(c ∩ (0, +inf))`, plus the point 0 when `0 in c` and `b` has a positive point.
The pieces are found by a case split on the signs of the ends of `L` (the sign of
`ln` of an end of `c` is its comparison with 1) and of `b`, every end being
`c_end^(1/b_end)`, 0, 1 or infinite, with the information whether it is attained.

Values are enclosed with Python's `decimal` (260 digits, enclosure of width 2e-230)
and each end is classified exactly: a rational value is found from the enclosure by a
continued fraction and verified by exact integer arithmetic (`x^u == c^v`); every
other value is irrational, so it differs from every binary64 number. Comparisons
and directed roundings to binary64 are decided from the enclosures or exactly.
`--check` compares the corpus with the oracle and the refinements file with the
oracle; `--write` regenerates the entries for powRev1.
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
from itl_trig_reverse_oracle import Enc, _bound_text, compare as enc_compare, rounded_end, ulps

DIGITS = 260
ERROR = Fraction(1, 10**230)
REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS = REPO_ROOT / "testdata/interval/itf1788"
REFINEMENTS = REPO_ROOT / "testdata/interval/interpreter_refinements.json"
FILE = "pow_rev.itl"
Bound = Fraction | float


@dataclass(frozen=True)
class End:
    """kind: 'zero', 'one', 'inf' or 'pow' (the value c^(1/beta))."""

    kind: str
    c: Fraction = Fraction(1)
    beta: Fraction = Fraction(1)


@dataclass(frozen=True)
class Piece:
    lo: End
    lo_open: bool
    hi: End
    hi_open: bool


def _dec(value: Fraction) -> Decimal:
    return Decimal(value.numerator) / Decimal(value.denominator)


def ln_enc(c: Fraction) -> Enc:
    with localcontext() as context:
        context.prec = DIGITS
        value = Fraction(_dec(c).ln())
    return Enc(value - ERROR, value + ERROR)


def exp_enc(t: Enc) -> Enc:
    with localcontext() as context:
        context.prec = DIGITS
        lo = Fraction(_dec(t.lo).exp())
        hi = Fraction(_dec(t.hi).exp())
    # exp is increasing; the relative error of each evaluation is far below 1e-250
    return Enc(lo * (1 - ERROR), hi * (1 + ERROR))


def _sign_value(end: End) -> int:
    """-1, 0 or 1 for end < 1, end == 1, end > 1 (the sign of ln c / beta, exactly)."""
    if end.c == 1:
        return 0
    return 1 if (end.c > 1) == (end.beta > 0) else -1


def _rational_value(end: End) -> Fraction | None:
    """The exact value of c^(1/beta) when it is rational, else None."""
    c, beta = end.c, end.beta
    if c == 1:
        return Fraction(1)
    bn, bd = beta.numerator, beta.denominator
    # x^beta = c with beta = bn / bd means x^bn = c^bd
    if abs(bn) > 64 or bd > 4096:
        # only a power of two c can be handled without huge integers: c = 2^g gives
        # x = 2^(g * bd / bn)
        n, d = c.numerator, c.denominator
        if n > 1 and d > 1:
            return None
        base = n if d == 1 else d
        sign = 1 if d == 1 else -1
        if base & (base - 1):
            return None
        g = sign * (base.bit_length() - 1)
        exponent = Fraction(g * bd, bn)
        if exponent.denominator != 1 or abs(exponent) > 10**6:
            return None
        return Fraction(2) ** int(exponent)
    enc = value_enc(end)
    mid = (enc.lo + enc.hi) / 2
    for limit in (10**6, 10**12, 10**30):
        cand = mid.limit_denominator(limit)
        if cand > 0 and cand**bn == c**bd:
            return cand
    return None


def value_enc(end: End) -> Enc:
    t = Enc(ln_enc(end.c).lo / end.beta, ln_enc(end.c).hi / end.beta)
    if end.beta < 0:
        t = Enc(ln_enc(end.c).hi / end.beta, ln_enc(end.c).lo / end.beta)
    return exp_enc(t)


def compare_end(end: End, d: Bound) -> int:
    """-1, 0, 1 for end < d, end == d, end > d; d may be infinite."""
    if isinstance(d, float):
        if end.kind == "inf":
            return 0 if d == math.inf else 1
        return -1 if d == math.inf else 1
    if end.kind == "inf":
        return 1
    if end.kind == "zero":
        value = Fraction(0)
    elif end.kind == "one":
        value = Fraction(1)
    else:
        exact = _rational_value(end)
        if exact is None:
            sign = _sign_value(end)
            enc = value_enc(end)
            if sign > 0:
                enc = Enc(max(enc.lo, Fraction(1)), enc.hi)
            else:
                enc = Enc(enc.lo, min(enc.hi, Fraction(1)))
            return enc_compare(enc, d)
        value = exact
    return (value > d) - (value < d)


def rounded(end: End, upper: bool) -> Fraction:
    """RD or RU to binary64 of the value of an end that is not infinite."""
    if end.kind == "zero":
        return Fraction(0)
    if end.kind == "one":
        return Fraction(1)
    exact = _rational_value(end)
    if exact is not None:
        return refs.round_binary64(exact, up=upper)
    sign = _sign_value(end)
    enc = value_enc(end)
    if sign > 0:
        enc = Enc(max(enc.lo, Fraction(1)), enc.hi)
    else:
        enc = Enc(enc.lo, min(enc.hi, Fraction(1)))
    return rounded_end_strict(enc, upper, sign)


def rounded_end_strict(enc: Enc, upper: bool, sign: int) -> Fraction:
    """As `rounded_end`, but the value is known to lie strictly on one side of 1, so
    the float 1 at the corresponding end of the enclosure does not count as inside."""
    if enc.lo == enc.hi:
        return enc.lo
    down = refs.round_binary64(enc.lo, up=False)
    up_lo = refs.round_binary64(enc.lo, up=True)
    down_hi = refs.round_binary64(enc.hi, up=False)
    up_hi = refs.round_binary64(enc.hi, up=True)
    if sign > 0 and enc.lo == 1:
        # value in (1, hi]: floats in the enclosure are those > 1
        first = refs.round_binary64(Fraction(1), up=True)
        first = first + refs.binary64_ulp(Fraction(1))  # the float after 1
        if first <= down_hi:
            raise ValueError("the enclosure of an end contains a binary64 value")
        return up_hi if upper else Fraction(1)
    if sign < 0 and enc.hi == 1:
        # value in [lo, 1): floats in the enclosure are those < 1
        before = Fraction(1) - refs.binary64_ulp(Fraction(1, 2)) 
        if before >= up_lo:
            raise ValueError("the enclosure of an end contains a binary64 value")
        return Fraction(1) if upper else down
    return rounded_end(enc, upper)


def _symbols(c: tuple[Bound, Bound], b: tuple[Bound, Bound]) -> list[Piece]:
    """The pieces of S_pos = exp(L /set b), and the zero part."""
    c1, c2 = c
    b1, b2 = b
    pieces: list[Piece] = []
    zero = End("zero")
    one = End("one")
    inf = End("inf")
    if c2 > 0:
        # L = ln(c ∩ (0, inf)); an end of L is -inf (c1 <= 0), +inf, or ln of c_end
        l_lo_inf = c1 <= 0
        l_hi_inf = c2 == math.inf
        zero_l = c1 <= 1 <= c2
        zero_b = b1 <= 0 <= b2
        pow_end = lambda ce, be: End("pow", Fraction(ce), Fraction(be))  # noqa: E731
        if zero_l and zero_b:
            pieces.append(Piece(zero, True, inf, True))
        elif zero_l:
            if b1 > 0:
                lo = zero if l_lo_inf else pow_end(c1, b1)
                hi = inf if l_hi_inf else pow_end(c2, b1)
                pieces.append(Piece(lo, l_lo_inf, hi, l_hi_inf))
            else:
                lo = zero if l_hi_inf else pow_end(c2, b2)
                hi = inf if l_lo_inf else pow_end(c1, b2)
                pieces.append(Piece(lo, l_hi_inf, hi, l_lo_inf))
        elif not zero_b:
            positive_l = c1 > 1
            if positive_l and b1 > 0:
                lo, lo_open = (one, True) if b2 == math.inf else (pow_end(c1, b2), False)
                hi, hi_open = (inf, True) if l_hi_inf else (pow_end(c2, b1), False)
            elif positive_l:
                lo, lo_open = (zero, True) if l_hi_inf else (pow_end(c2, b2), False)
                hi, hi_open = (one, True) if b1 == -math.inf else (pow_end(c1, b1), False)
            elif b1 > 0:
                lo, lo_open = (zero, True) if l_lo_inf else (pow_end(c1, b1), False)
                hi, hi_open = (one, True) if b2 == math.inf else (pow_end(c2, b2), False)
            else:
                lo, lo_open = (one, True) if b1 == -math.inf else (pow_end(c2, b1), False)
                hi, hi_open = (inf, True) if l_lo_inf else (pow_end(c1, b2), False)
            pieces.append(Piece(lo, lo_open, hi, hi_open))
        elif not (b1 == 0 and b2 == 0):
            positive_l = c1 > 1
            n = c1 if positive_l else c2
            has_negative = b1 < 0
            has_positive = b2 > 0
            neg_piece = pos_piece = None
            if has_negative:
                if positive_l:
                    # t <= n / b1 : x in (0, n^(1/b1)]
                    hi, hi_open = (one, True) if b1 == -math.inf else (pow_end(n, b1), False)
                    neg_piece = Piece(zero, True, hi, hi_open)
                else:
                    # t >= n / b1 : x in [n^(1/b1), inf)
                    lo, lo_open = (one, True) if b1 == -math.inf else (pow_end(n, b1), False)
                    neg_piece = Piece(lo, lo_open, inf, True)
            if has_positive:
                if positive_l:
                    lo, lo_open = (one, True) if b2 == math.inf else (pow_end(n, b2), False)
                    pos_piece = Piece(lo, lo_open, inf, True)
                else:
                    hi, hi_open = (one, True) if b2 == math.inf else (pow_end(n, b2), False)
                    pos_piece = Piece(zero, True, hi, hi_open)
            ordered = [neg_piece, pos_piece] if positive_l else [pos_piece, neg_piece]
            pieces.extend(piece for piece in ordered if piece is not None)
    if b2 > 0 and c1 <= 0 <= c2:
        pieces.append(Piece(zero, False, zero, False))
    return pieces


def hull(
    b: tuple[Bound, Bound],
    c: tuple[Bound, Bound],
    prior: tuple[Bound, Bound],
) -> tuple[Bound, Bound] | None:
    """The hull in binary64 of the set inside the prior, or None if it is empty."""
    xl, xh = prior
    lower: Bound | None = None
    upper: Bound | None = None
    for piece in _symbols(c, b):
        # the piece meets the closed prior iff lo <= xh and xl <= hi (an open end that
        # equals a prior end does not meet it)
        order_lo = compare_end(piece.lo, xh)
        order_hi = compare_end(piece.hi, xl)
        if order_lo > 0 or (order_lo == 0 and piece.lo_open):
            continue
        if order_hi < 0 or (order_hi == 0 and piece.hi_open):
            continue
        # the lower end of the part inside the prior: xl, or the start of the piece
        v: Bound = xl if compare_end(piece.lo, xl) <= 0 else rounded(piece.lo, upper=False)
        if piece.hi.kind == "inf":
            w: Bound = xh
        elif compare_end(piece.hi, xh) >= 0:
            w = xh
        else:
            w = rounded(piece.hi, upper=True)
        lower = v if lower is None or v < lower else lower
        upper = w if upper is None or w > upper else upper
    if lower is None or upper is None:
        return None
    return lower, upper


def operand(word: str) -> tuple[bool, Bound, Bound]:
    interval = refs.parse_interval(word)
    if interval.empty:
        return True, math.inf, -math.inf
    return False, interval.lo, interval.hi


def oracle_value(statement: refs.Statement, corpus_word: str) -> str | None:
    if statement.operation != "powRev1":
        return None
    words = refs.split_words(statement.lhs)[1:]
    b_empty, b1, b2 = operand(words[0])
    c_empty, c1, c2 = operand(words[1])
    x_empty, x1, x2 = operand(words[2])
    decoration = refs.parse_interval(corpus_word).decoration
    suffix = f"_{decoration}" if decoration else ""
    if b_empty or c_empty or x_empty:
        return "[empty]" + suffix
    result = hull((b1, b2), (c1, c2), (x1, x2))
    if result is None:
        return "[empty]" + suffix
    return f"[{_bound_text(result[0])},{_bound_text(result[1])}]" + suffix


def classify(statement: refs.Statement) -> tuple[str, str | None]:
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)
    statements = refs.parse_statements((CORPUS / FILE).read_text(encoding="utf-8"))
    counts = {"equal": 0, "refined": 0, "wrong": 0}
    for statement in statements:
        if statement.operation != "powRev1":
            continue
        verdict, refined = classify(statement)
        counts[verdict] += 1
        if args.report and verdict != "equal":
            print(verdict, statement.id, statement.lhs, "|", statement.expected, "| oracle", refined)
    listed = [r for r in refs.load(REFINEMENTS) if r.operation == "powRev1"] if REFINEMENTS.exists() else []
    print(counts, f"refinements listed: {len(listed)}")
    # every corpus statement equals the exact hull, so no refinement is listed
    return 0 if counts["wrong"] == 0 and counts["refined"] == 0 and not listed else 1


if __name__ == "__main__":
    sys.exit(main())
