#!/usr/bin/env python3
"""An oracle for powRev2 that shares no code with `interval`.

powRev2(a, c, x) is the hull of {beta in prior | exists a0 in a: a0^beta defined and in c},
a0^beta being defined for a0 > 0 (any beta) and for a0 = 0 with beta > 0 (value 0).

For a0 > 0, `a0^beta in c` is `beta * ln a0 in ln c`, so the set is the set division
`L /set M`, `L = ln(c ∩ (0, +inf))`, `M = ln(a ∩ (0, +inf))`, plus (0, +inf) when
`0 in a` and `0 in c`. The division is computed from the corner quotients of the ends
(an infinite end is a limit), with the part of `M` on each side of 0 taken apart when
`0 in M`; this is a different formulation from the case split of the implementation.

Each end `ln(c_end) / ln(a_end)` is enclosed with Python's `decimal` (260 digits) and
classified exactly: it is rational iff `c_end^q == a_end^p` for a small `p / q` found
from the enclosure by a continued fraction, verified with exact integers; every other
value is irrational, so it differs from every binary64 number. Comparisons and directed
roundings to binary64 are decided from the enclosures or exactly. `--report` lists the
statements that are not equal to the exact hull.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

import itl_refinements as refs
from itl_pow_reverse_oracle import FILE, REFINEMENTS, CORPUS, ln_enc
from itl_trig_reverse_oracle import Enc, _bound_text, compare as enc_compare, rounded_end

Bound = Fraction | float
INF = math.inf


@dataclass(frozen=True)
class Q:
    """An end: kind 'val' (the quotient ln(c)/ln(a) of positive rationals, a != 1),
    'zero' or 'inf' with a sign (+1 or -1)."""

    kind: str
    c: Fraction = Fraction(1)
    a: Fraction = Fraction(1)
    sign: int = 1


def _rational_value(end: Q) -> Fraction | None:
    """The exact value of ln(c)/ln(a) when it is rational, else None."""
    if end.c == 1:
        return Fraction(0)
    enc = quotient_enc(end)
    mid = (enc.lo + enc.hi) / 2
    for limit in (10**2, 10**3, 10**4):
        cand = mid.limit_denominator(limit)
        p, q = cand.numerator, cand.denominator
        # q ln c = p ln a  <=>  c^q = a^p
        lhs = end.c ** q
        rhs = end.a ** p
        if lhs == rhs:
            return cand
    return None


def quotient_enc(end: Q) -> Enc:
    lc, la = ln_enc(end.c), ln_enc(end.a)
    corners = [lc.lo / la.lo, lc.lo / la.hi, lc.hi / la.lo, lc.hi / la.hi]
    return Enc(min(corners), max(corners))


def compare_end(end: Q, d: Bound) -> int:
    """-1, 0, 1 for end < d, end == d, end > d; d may be infinite."""
    if isinstance(d, float):
        if end.kind == "inf":
            if end.sign > 0:
                return 0 if d == INF else 1
            return 0 if d == -INF else -1
        return -1 if d == INF else 1
    if end.kind == "inf":
        return end.sign
    if end.kind == "zero":
        value = Fraction(0)
    else:
        exact = _rational_value(end)
        if exact is None:
            return enc_compare(quotient_enc(end), d)
        value = exact
    return (value > d) - (value < d)


def rounded(end: Q, upper: bool) -> Bound:
    if end.kind == "inf":
        return end.sign * INF
    if end.kind == "zero":
        return Fraction(0)
    exact = _rational_value(end)
    if exact is not None:
        return refs.round_binary64(exact, up=upper) if exact != 0 else Fraction(0)
    return rounded_end(quotient_enc(end), upper)


@dataclass(frozen=True)
class Piece:
    lo: Q
    lo_open: bool
    hi: Q
    hi_open: bool


def _log_end(x: Bound) -> tuple[str, Fraction | None]:
    """('ninf', None) for ln -> -inf, ('pinf', None), ('zero', None) for ln = 0, or
    ('val', x) for a finite positive float other than 1."""
    if isinstance(x, float):
        return ("pinf", None) if x == INF else ("ninf", None)
    if x <= 0:
        return ("ninf", None)
    if x == 1:
        return ("zero", None)
    return ("val", Fraction(x))


def _sign_of(end: tuple[str, Fraction | None]) -> int:
    kind, value = end
    if kind == "ninf":
        return -1
    if kind == "pinf":
        return 1
    if kind == "zero":
        return 0
    assert value is not None
    return 1 if value > 1 else -1


def _quotient(lend: tuple[str, Fraction | None], mend: tuple[str, Fraction | None], l_sign_hint: int) -> tuple[Q, bool] | None:
    """The corner quotient l / m as (end, attained), or None for inf / inf."""
    lk, lv = lend
    mk, mv = mend
    lsign = _sign_of(lend)
    msign = _sign_of(mend)
    if lk in ("ninf", "pinf") and mk in ("ninf", "pinf"):
        return None
    if mk == "zero":
        # m -> 0 from the side given by the caller (l_sign_hint carries the side)
        return Q("inf", sign=lsign * l_sign_hint), False
    if lk in ("ninf", "pinf"):
        return Q("inf", sign=lsign * msign), False
    if mk in ("ninf", "pinf"):
        return Q("zero"), False
    if lk == "zero":
        return Q("zero"), True
    return Q("val", lv, mv), True


def _value_of(end: Q) -> tuple[int, Fraction]:
    """A sort key: (class, value) with class -1 for -inf, 0 for finite, 1 for +inf."""
    if end.kind == "inf":
        return (end.sign, Fraction(0))
    if end.kind == "zero":
        return (0, Fraction(0))
    enc = quotient_enc(end)
    return (0, (enc.lo + enc.hi) / 2)


def division_pieces(c: tuple[Bound, Bound], a: tuple[Bound, Bound]) -> list[Piece]:
    c1, c2 = c
    a1, a2 = a
    pieces: list[Piece] = []
    if c2 > 0 and a2 > 0:
        lo_l = ("ninf", None) if (isinstance(c1, float) or c1 <= 0) else _log_end(c1)
        hi_l = _log_end(c2)
        lo_m = ("ninf", None) if (isinstance(a1, float) or a1 <= 0) else _log_end(a1)
        hi_m = _log_end(a2)
        zero_l = c1 <= 1 <= c2
        zero_m = a1 <= 1 <= a2
        if zero_l and zero_m:
            pieces.append(Piece(Q("inf", sign=-1), True, Q("inf", sign=1), True))
        else:
            # M split into its parts of one sign; a part touching 0 is a limit
            parts: list[tuple[tuple, tuple, int]] = []
            if not zero_m:
                parts.append((lo_m, hi_m, 0))
            elif not (a1 == 1 and a2 == 1):
                if a1 < 1:
                    parts.append((lo_m, ("zero", None), -1))
                if a2 > 1:
                    parts.append((("zero", None), hi_m, +1))
            l_ends = (lo_l, hi_l)
            for m_lo, m_hi, near_zero in parts:
                corners = []
                for le in l_ends:
                    for me in (m_lo, m_hi):
                        if me[0] == "zero":
                            lsign = _sign_of(le)
                            if lsign == 0:
                                continue
                            corners.append((Q("inf", sign=lsign * near_zero), False))
                            continue
                        quotient = _quotient(le, me, 1)
                        if quotient is not None:
                            corners.append(quotient)
                if zero_l:
                    # 0 in L: the value 0 is attained for any m != 0
                    corners.append((Q("zero"), True))
                keyed = sorted(corners, key=lambda item: _value_of(item[0]))
                lo_end, lo_att = keyed[0]
                hi_end, hi_att = keyed[-1]
                # an extreme equal to 0 from an infinite corner: attained iff 0 in L
                lo_open = not lo_att and not (lo_end.kind == "zero" and zero_l)
                hi_open = not hi_att and not (hi_end.kind == "zero" and zero_l)
                if lo_end.kind == "inf":
                    lo_open = True
                if hi_end.kind == "inf":
                    hi_open = True
                pieces.append(Piece(lo_end, lo_open, hi_end, hi_open))
    # 0^beta = 0 for beta > 0
    if a1 <= 0 <= a2 and c1 <= 0 <= c2:
        pieces.append(Piece(Q("zero"), True, Q("inf", sign=1), True))
    return pieces


def hull(
    a: tuple[Bound, Bound],
    c: tuple[Bound, Bound],
    prior: tuple[Bound, Bound],
) -> tuple[Bound, Bound] | None:
    xl, xh = prior
    lower: Bound | None = None
    upper: Bound | None = None
    for piece in division_pieces(c, a):
        order_lo = compare_end(piece.lo, xh)
        order_hi = compare_end(piece.hi, xl)
        if order_lo > 0 or (order_lo == 0 and piece.lo_open):
            continue
        if order_hi < 0 or (order_hi == 0 and piece.hi_open):
            continue
        v: Bound = xl if compare_end(piece.lo, xl) <= 0 else rounded(piece.lo, upper=False)
        w: Bound = xh if compare_end(piece.hi, xh) >= 0 else rounded(piece.hi, upper=True)
        lower = v if lower is None or v < lower else lower
        upper = w if upper is None or w > upper else upper
    if lower is None or upper is None:
        return None
    return lower, upper


def operand(word: str) -> tuple[bool, Bound, Bound]:
    interval = refs.parse_interval(word)
    if interval.empty:
        return True, INF, -INF
    return False, interval.lo, interval.hi


def oracle_value(statement: refs.Statement, corpus_word: str) -> str | None:
    if statement.operation != "powRev2":
        return None
    words = refs.split_words(statement.lhs)[1:]
    a_empty, a1, a2 = operand(words[0])
    c_empty, c1, c2 = operand(words[1])
    x_empty, x1, x2 = operand(words[2])
    decoration = refs.parse_interval(corpus_word).decoration
    suffix = f"_{decoration}" if decoration else ""
    if a_empty or c_empty or x_empty:
        return "[empty]" + suffix
    result = hull((a1, a2), (c1, c2), (x1, x2))
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
    refined_ids: dict[str, str] = {}
    for statement in statements:
        if statement.operation != "powRev2":
            continue
        verdict, refined = classify(statement)
        counts[verdict] += 1
        if verdict == "refined":
            refined_ids[statement.id] = refined or ""
        if args.report and verdict != "equal":
            print(verdict, statement.id, statement.lhs, "|", statement.expected, "| oracle", refined)
    listed = {r.id: r for r in refs.load(REFINEMENTS) if r.operation == "powRev2"} if REFINEMENTS.exists() else {}
    print(counts, f"refinements listed: {len(listed)}")
    ok = counts["wrong"] == 0 and set(listed) == set(refined_ids)
    if ok:
        ok = all(listed[key].refined == value for key, value in refined_ids.items())
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
