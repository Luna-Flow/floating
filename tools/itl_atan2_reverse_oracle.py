#!/usr/bin/env python3
"""An oracle for atan2Rev1 and atan2Rev2 that shares no code with `ball_float`.

IEEE 1788-2015 10.5.4, equations (6) and (7), Table 10.1:

- atan2Rev1(b, c, x) = hull { y in x | exists b0 in b: atan2(y, b0) defined and in c },
  the unknown is the ordinate and `b` the abscissa interval;
- atan2Rev2(a, c, x) = hull { x0 in x | exists a0 in a: atan2(a0, x0) defined and in c },
  the unknown is the abscissa and `a` the ordinate interval.

`atan2` is defined on the plane minus the origin, with range (-pi, pi] (Table 9.1,
footnote f): the angle pi is attained on the half-line y = 0, x < 0, and -pi never.

Two formulations, which agree or the check fails:

1. `hull` (the exact hull), by polar rectangles. The angle range is cut at the angles where
   the trigonometric value is infinite (cos = 0 for Rev1, sin = 0 for Rev2); in each open
   region the image of `(factor, angle) -> factor * tan(angle)` (Rev1) or
   `factor * cot(angle)` (Rev2) over a rectangle (an angle interval and a factor interval
   of one sign) is monotone in each variable, so its extremes are values at corners (limits
   at the infinite and open corners, with the information whether a corner is attained);
   the singular angles are rays of their own (they need the factor 0). The angle and the
   corner values are compared numerically, from enclosures at 260 digits; the sign of an
   infinite end comes from a numerical evaluation next to the singular angle.

2. `member1` / `member2` (the forward definition, which shares nothing with the case
   analysis). For a fixed ordinate y, atan2(y, b0) is monotone and continuous in b0 on
   each side of the abscissa 0 (decreasing for y > 0, increasing for y < 0; for y = 0 it is
   0 for b0 > 0 and pi for b0 < 0), so its image over `b` is an interval (or two points)
   decided from the ends of `b`, and y is a member iff that image meets c. Rev2: the same
   with the roles exchanged. `validate` checks an exact hull by it: an attained end is a
   member; points a few geometric steps inside a piece end are members; a spread of points
   beyond each end of the hull, inside the prior, are not members.

`--write` writes `testdata/interval/generated/atan2_rev.itl` (byte-stable); `--check`
recomputes it, compares with the file, and validates every expected hull by the forward
definition.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path

import itl_refinements as refs
import itl_trig_reverse_oracle as trig
from itl_trig_reverse_oracle import Enc

DIGITS = 260
REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATED = REPO_ROOT / "testdata/interval/generated/atan2_rev.itl"
Bound = Fraction | float
INF = math.inf
ZERO = Fraction(0)


# ---------------------------------------------------------------------------
# enclosures: pi, sin, cos, tan
# ---------------------------------------------------------------------------

_PI: Enc | None = None


def pi_enc() -> Enc:
    global _PI
    if _PI is None:
        _PI = trig.pi()
    return _PI


def bp_enc(k: int) -> Enc:
    """k * pi / 2 for k in -2..2."""
    if k == 0:
        return Enc(ZERO, ZERO)
    p = pi_enc()
    lo, hi = p.lo * k / 2, p.hi * k / 2
    return Enc(min(lo, hi), max(lo, hi))


SIN_BP = {-2: 0, -1: -1, 0: 0, 1: 1, 2: 0}
COS_BP = {-2: -1, -1: 0, 0: 1, 1: 0, 2: -1}


def _dec(value: Fraction) -> Decimal:
    return Decimal(value.numerator) / Decimal(value.denominator)


def _sin_cos(x: Fraction) -> tuple[Decimal, Decimal]:
    """sin and cos of a rational |x| <= 4 by the Taylor series at 270 digits."""
    with localcontext() as context:
        context.prec = DIGITS + 10
        t = _dec(x)
        square = t * t
        threshold = Decimal(10) ** (-(DIGITS + 5))
        sin = Decimal(0)
        term = t
        k = 0
        while True:
            sin += term if k % 2 == 0 else -term
            if abs(term) < threshold:
                break
            term = term * square / ((2 * k + 2) * (2 * k + 3))
            k += 1
        cos = Decimal(0)
        term = Decimal(1)
        k = 0
        while True:
            cos += term if k % 2 == 0 else -term
            if abs(term) < threshold:
                break
            term = term * square / ((2 * k + 1) * (2 * k + 2))
            k += 1
        return sin, cos


_TAN_CACHE: dict[Fraction, Enc] = {}


def tan_enc(x: Fraction) -> Enc:
    """tan of a rational |x| <= 4, not a multiple of pi/2 (relative width below 1e-220)."""
    cached = _TAN_CACHE.get(x)
    if cached is not None:
        return cached
    if x == 0:
        result = Enc(ZERO, ZERO)
    else:
        sin, cos = _sin_cos(x)
        with localcontext() as context:
            context.prec = DIGITS + 10
            value = Fraction(sin / cos)
        slack = abs(value) * Fraction(1, 10**220) + Fraction(1, 10**240)
        result = Enc(value - slack, value + slack)
    _TAN_CACHE[x] = result
    return result


def cmp_bound_enc(c: Bound, enc: Enc) -> int:
    """-1, 0, 1 for c < enc, c = enc (exact only), c > enc; c may be infinite."""
    if isinstance(c, float):
        return -1 if c < 0 else 1
    if c < enc.lo:
        return -1
    if c > enc.hi:
        return 1
    if enc.lo == enc.hi == c:
        return 0
    raise ValueError("an angle too close to a singular angle for the enclosure")


# ---------------------------------------------------------------------------
# the exact hull
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Value:
    """An end of a piece: kind 'zero', 'inf' (with sign), or 'val' (an enclosure)."""

    kind: str
    sign: int = 0
    enc: Enc | None = None


def val_key(value: Value) -> tuple[int, Fraction]:
    if value.kind == "inf":
        return (value.sign, ZERO)
    if value.kind == "zero":
        return (0, ZERO)
    assert value.enc is not None
    return (0, (value.enc.lo + value.enc.hi) / 2)


@dataclass(frozen=True)
class Piece:
    lo: Value
    lo_attained: bool
    hi: Value
    hi_attained: bool


# a trigonometric end: kind 'inf' (sign), 'zero' (attained flag) or 'fin' (enclosure)
Trig = tuple[str, int, Enc | None, bool]


def _sign_of(enc: Enc) -> int:
    if enc.lo > 0:
        return 1
    if enc.hi < 0:
        return -1
    raise ValueError("the sign of an enclosure is not decided")


def _times(factor: Fraction | float | None, t: Trig) -> Value | None:
    """factor * t; a factor None is the limit 0 (not attained), an infinite float an
    infinite factor; None if the limit is undecided (0 * inf, inf * 0)."""
    kind, sign, enc, _ = t
    if factor is None:
        return None if kind == "inf" else Value("zero")
    if isinstance(factor, float):
        if kind == "zero":
            return None
        direction = sign if kind == "inf" else _sign_of(enc)
        return Value("inf", (1 if factor > 0 else -1) * direction)
    if kind == "zero":
        return Value("zero")
    if kind == "inf":
        return Value("inf", (1 if factor > 0 else -1) * sign)
    assert enc is not None
    lo, hi = factor * enc.lo, factor * enc.hi
    return Value("val", 0, Enc(min(lo, hi), max(lo, hi)))


def _attained(factor, t: Trig, result: Value) -> bool:
    if result.kind == "inf":
        return False
    if t[0] == "zero":
        return t[3]
    return isinstance(factor, Fraction)


def region_image(f_lo, f_hi, t_lo: Trig, t_hi: Trig) -> Piece | None:
    """The image of factor * t over the rectangle: its extremes are among the corners."""
    corners: list[tuple[Value, bool]] = []
    for factor in (f_lo, f_hi):
        for t in (t_lo, t_hi):
            value = _times(factor, t)
            if value is not None:
                corners.append((value, _attained(factor, t, value)))
    if not corners:
        return None
    ordered = sorted(corners, key=lambda item: val_key(item[0]))
    lo, lo_att = ordered[0]
    hi, hi_att = ordered[-1]
    if lo.kind == "zero":
        lo_att = any(v.kind == "zero" and a for v, a in corners)
    if hi.kind == "zero":
        hi_att = any(v.kind == "zero" and a for v, a in corners)
    return Piece(lo, lo_att, hi, hi_att)


def factor_parts(lo: Bound, hi: Bound) -> list[tuple[int, object, object]]:
    """The parts of [lo, hi] in (0, inf) and (-inf, 0) as (sign, lower end, upper end): an
    end None is the limit 0 (not attained), an infinite float an infinite end."""
    parts = []
    if hi > 0:
        parts.append((1, lo if lo > 0 else None, hi))
    if lo < 0:
        parts.append((-1, lo, hi if hi < 0 else None))
    return parts


def _g_at_angle(angle: Fraction, cot: bool) -> Trig:
    if angle == 0 and not cot:
        return ("zero", 0, None, True)
    t = tan_enc(angle)
    if cot:
        lo, hi = 1 / t.hi, 1 / t.lo
        t = Enc(min(lo, hi), max(lo, hi))
    return ("fin", 0, t, True)


def _g_at_breakpoint(k: int, side: int, cot: bool, attained: bool) -> Trig:
    """The value of tan (cot) at the breakpoint k pi/2 approached from `side` (+1: from
    above, -1: from below) inside the region: infinite if cos (sin) is 0, else 0. The sign
    of an infinite value is read from a numerical evaluation next to the breakpoint."""
    denominator = SIN_BP[k] if cot else COS_BP[k]
    if denominator != 0:
        return ("zero", 0, None, attained)
    centre = Fraction(float(bp_enc(k).lo + bp_enc(k).hi) / 2)
    near = centre + Fraction(side, 1000)
    sin, cos = _sin_cos(near)
    ratio_positive = (cos > 0) == (sin > 0) if not cot else (cos > 0) == (sin > 0)
    # tan = sin / cos and cot = cos / sin have the same sign
    return ("inf", 1 if ratio_positive else -1, None, False)


def hull_pieces(rev: int, factor: tuple[Bound, Bound], c: tuple[Bound, Bound]) -> list[Piece]:
    """The pieces of the exact set. rev = 1: unknown ordinate, `factor` = b (abscissa);
    rev = 2: unknown abscissa, `factor` = a (ordinate)."""
    c1, c2 = c
    f1, f2 = factor
    cot = rev == 2
    # the regions between the singular angles and the ends of the range (units of pi/2):
    # (lower k, upper k, is the upper end attained)
    if rev == 1:
        regions = [(-2, -1, False), (-1, 1, False), (1, 2, True)]
        singular = [-1, 1]
    else:
        regions = [(-2, 0, False), (0, 2, False)]
        singular = [0, 2]
    pieces: list[Piece] = []
    for lo_k, hi_k, hi_closed in regions:
        # Theta_r = [c1, c2] inter (lo_k pi/2, hi_k pi/2) (closed at the upper end if hi_closed)
        c1_vs_lo = cmp_bound_enc(c1, bp_enc(lo_k))
        c1_vs_hi = cmp_bound_enc(c1, bp_enc(hi_k))
        c2_vs_lo = cmp_bound_enc(c2, bp_enc(lo_k))
        c2_vs_hi = cmp_bound_enc(c2, bp_enc(hi_k))
        # the region is met iff c1 < hi (or c1 <= hi when closed) and c2 > lo
        if not (c1_vs_hi < 0 or (hi_closed and c1_vs_hi == 0)) or not c2_vs_lo > 0:
            continue
        lower_is_c = c1_vs_lo > 0
        upper_is_c = c2_vs_hi < 0
        if lower_is_c:
            t_lower = _g_at_angle(c1, cot)
        else:
            t_lower = _g_at_breakpoint(lo_k, +1, cot, attained=False)
        if upper_is_c:
            t_upper = _g_at_angle(c2, cot)
        else:
            t_upper = _g_at_breakpoint(hi_k, -1, cot, attained=hi_closed)
        # the sign of the factor in the region: that of cos (Rev1) or sin (Rev2) inside it
        middle = Fraction(lo_k + hi_k, 4) * Fraction(31415926535, 10000000000)
        sin, cos = _sin_cos(middle)
        region_sign = 1 if ((sin if cot else cos) > 0) else -1
        for sign, f_lo, f_hi in factor_parts(f1, f2):
            if sign != region_sign:
                continue
            image = region_image(f_lo, f_hi, t_lower, t_upper)
            if image is not None:
                pieces.append(image)
    # the singular angles: rays that need the factor 0 (a point of the factor interval)
    if f1 <= 0 <= f2:
        for k in singular:
            # the angle k pi/2 is in Theta iff c1 <= angle <= c2 (inside the range (-pi, pi])
            lower = cmp_bound_enc(c1, bp_enc(k))
            upper = cmp_bound_enc(c2, bp_enc(k))
            if lower <= 0 <= upper and not (k == -2):
                # the ray at angle k pi/2: the unknown is r sin (Rev1) or r cos (Rev2), r > 0
                direction = SIN_BP[k] if rev == 1 else COS_BP[k]
                if direction == 0:
                    continue
                if direction > 0:
                    pieces.append(Piece(Value("zero"), False, Value("inf", 1), False))
                else:
                    pieces.append(Piece(Value("inf", -1), False, Value("zero"), False))
    return pieces


# ---------------------------------------------------------------------------
# the hull of the pieces inside the prior, rounded to binary64
# ---------------------------------------------------------------------------


def compare_end(value: Value, d: Bound) -> int:
    """-1, 0, 1 for the end < d, = d, > d; d may be infinite."""
    if isinstance(d, float):
        if value.kind == "inf":
            return 0 if (value.sign > 0) == (d > 0) else (1 if value.sign > 0 else -1)
        return -1 if d == INF else 1
    if value.kind == "inf":
        return value.sign
    if value.kind == "zero":
        return (ZERO > d) - (ZERO < d)
    assert value.enc is not None
    return trig.compare(value.enc, d)


def rounded(value: Value, upper: bool) -> Bound:
    if value.kind == "inf":
        return value.sign * INF
    if value.kind == "zero":
        return ZERO
    assert value.enc is not None
    return trig.rounded_end(value.enc, upper)


@dataclass(frozen=True)
class Hull:
    lo: Bound
    hi: Bound
    lo_source: tuple  # ('prior', xl) or ('piece', Value, attained, piece index)
    hi_source: tuple


def hull(rev: int, factor: tuple[Bound, Bound], c: tuple[Bound, Bound], prior: tuple[Bound, Bound]) -> Hull | None:
    xl, xh = prior
    lower = upper = None
    lower_source = upper_source = ()
    for index, piece in enumerate(hull_pieces(rev, factor, c)):
        order_lo = compare_end(piece.lo, xh)
        order_hi = compare_end(piece.hi, xl)
        if order_lo > 0 or (order_lo == 0 and not piece.lo_attained):
            continue
        if order_hi < 0 or (order_hi == 0 and not piece.hi_attained):
            continue
        order_start = compare_end(piece.lo, xl)
        if order_start <= 0:
            v: Bound = xl
            # the prior end is a member if the piece starts before it, or at it and attains it
            v_source: tuple = ("prior", xl, order_start < 0 or piece.lo_attained)
        else:
            v = rounded(piece.lo, upper=False)
            v_source = ("piece", piece.lo, piece.lo_attained, index)
        order_stop = compare_end(piece.hi, xh)
        if order_stop >= 0:
            w: Bound = xh
            w_source: tuple = ("prior", xh, order_stop > 0 or piece.hi_attained)
        else:
            w = rounded(piece.hi, upper=True)
            w_source = ("piece", piece.hi, piece.hi_attained, index)
        if lower is None or v < lower:
            lower, lower_source = v, v_source
        if upper is None or w > upper:
            upper, upper_source = w, w_source
    if lower is None or upper is None:
        return None
    return Hull(lower, upper, lower_source, upper_source)


# ---------------------------------------------------------------------------
# the forward definition
# ---------------------------------------------------------------------------


def atan_enc(x: Fraction) -> Enc:
    return trig.atan(x)


def atan2_enc(y: Fraction, x: Fraction) -> Enc:
    """The angle of the point (x, y), not the origin."""
    p = pi_enc()
    half = Enc(p.lo / 2, p.hi / 2)
    if x > 0:
        return atan_enc(y / x)
    if x < 0:
        a = atan_enc(y / x)
        return a + p if y > 0 else (a - p)
    return half if y > 0 else Enc(-half.hi, -half.lo)


Angle = tuple[Enc, bool, Enc, bool]  # (lo, lo attained, hi, hi attained)


def _meets(image: Angle, c: tuple[Bound, Bound]) -> bool:
    lo, lo_att, hi, hi_att = image
    c1, c2 = c
    # image meets [c1, c2]: hi >= c1 and lo <= c2, strictly when the end is not attained
    order_hi = -cmp_bound_enc(c1, hi)  # hi vs c1
    order_lo = cmp_bound_enc(c2, lo)  # c2 vs lo
    return (order_hi > 0 or (order_hi == 0 and hi_att)) and (order_lo > 0 or (order_lo == 0 and lo_att))


def _point(angle: Enc) -> Angle:
    return (angle, True, angle, True)


def member1(y: Fraction, b: tuple[Bound, Bound], c: tuple[Bound, Bound]) -> bool:
    """Whether y is in { y | exists b0 in b: atan2(y, b0) in c }."""
    b1, b2 = b
    p = pi_enc()
    zero = Enc(ZERO, ZERO)
    if y == 0:
        images = []
        if b2 > 0:
            images.append(_point(zero))
        if b1 < 0:
            images.append(_point(p))
        return any(_meets(image, c) for image in images)
    if y > 0:
        # decreasing in b0: from pi (b0 -> -inf) to 0 (b0 -> +inf)
        low = (zero, False) if isinstance(b2, float) else (atan2_enc(y, b2), True)
        high = (p, False) if isinstance(b1, float) else (atan2_enc(y, b1), True)
    else:
        # increasing in b0: from -pi to 0
        low = (Enc(-p.hi, -p.lo), False) if isinstance(b1, float) else (atan2_enc(y, b1), True)
        high = (zero, False) if isinstance(b2, float) else (atan2_enc(y, b2), True)
    return _meets((low[0], low[1], high[0], high[1]), c)


def member2(x0: Fraction, a: tuple[Bound, Bound], c: tuple[Bound, Bound]) -> bool:
    """Whether x0 is in { x0 | exists a0 in a: atan2(a0, x0) in c }."""
    a1, a2 = a
    p = pi_enc()
    zero = Enc(ZERO, ZERO)
    half = Enc(p.lo / 2, p.hi / 2)
    neg_half = Enc(-half.hi, -half.lo)
    neg_p = Enc(-p.hi, -p.lo)
    images: list[Angle] = []
    if x0 > 0:
        # increasing in a0 over the whole line, from -pi/2 to pi/2
        low = (neg_half, False) if isinstance(a1, float) else (atan2_enc(a1, x0), True)
        high = (half, False) if isinstance(a2, float) else (atan2_enc(a2, x0), True)
        images.append((low[0], low[1], high[0], high[1]))
    elif x0 < 0:
        if a2 > 0:
            # a0 > 0: the angle pi - atan(a0 / |x0|) decreases from pi (a0 -> 0+) to pi/2
            low = (half, False) if isinstance(a2, float) else (atan2_enc(a2, x0), True)
            if a1 > 0:
                high = (atan2_enc(a1, x0), True)
            else:
                high = (p, False)
            images.append((low[0], low[1], high[0], high[1]))
        if a1 < 0:
            # a0 < 0: the angle atan(a0 / x0) - pi lies in (-pi, -pi/2): from -pi/2 (a0 -> -inf)
            # down to -pi (a0 -> 0-)
            high = (neg_half, False) if isinstance(a1, float) else (atan2_enc(a1, x0), True)
            if a2 < 0:
                low = (atan2_enc(a2, x0), True)
            else:
                low = (neg_p, False)
            images.append((low[0], low[1], high[0], high[1]))
        if a1 <= 0 <= a2:
            images.append(_point(p))
    else:
        if a2 > 0:
            images.append(_point(half))
        if a1 < 0:
            images.append(_point(neg_half))
    return any(_meets(image, c) for image in images)


def member(rev: int, point: Fraction, factor: tuple[Bound, Bound], c: tuple[Bound, Bound]) -> bool:
    return member1(point, factor, c) if rev == 1 else member2(point, factor, c)


# ---------------------------------------------------------------------------
# validation of a hull by the forward definition
# ---------------------------------------------------------------------------

INSIDE_STEPS = (Fraction(1, 10**9), Fraction(1, 10**15), Fraction(1, 10**30))
OUTSIDE_STEPS = (
    Fraction(1, 10**30),
    Fraction(1, 10**15),
    Fraction(1, 10**9),
    Fraction(1, 10**3),
    Fraction(1),
    Fraction(100),
)


def _centre(value: Value) -> Fraction | None:
    if value.kind == "zero":
        return ZERO
    if value.kind == "val":
        assert value.enc is not None
        return (value.enc.lo + value.enc.hi) / 2
    return None


def validate(
    rev: int,
    factor: tuple[Bound, Bound],
    c: tuple[Bound, Bound],
    prior: tuple[Bound, Bound],
    result: Hull | None,
    stats: dict[str, int],
) -> list[str]:
    """Checks the exact hull against the forward definition; returns the disagreements."""
    problems: list[str] = []
    pieces = hull_pieces(rev, factor, c)
    xl, xh = prior

    def in_prior(point: Fraction) -> bool:
        return xl <= point <= xh

    if result is None:
        # no point of the prior is a member: spot-check the prior ends and a few points
        stats["empty"] += 1
        samples = [p for p in (xl, xh) if isinstance(p, Fraction)]
        samples += [
            Fraction(k, 4) for k in (-8, -3, -1, 0, 1, 2, 5, 9) if in_prior(Fraction(k, 4))
        ]
        for point in samples:
            stats["points"] += 1
            if member(rev, point, factor, c):
                problems.append(f"empty hull but {point} is a member")
        return problems
    for side, end, source in (("lo", result.lo, result.lo_source), ("hi", result.hi, result.hi_source)):
        direction = 1 if side == "lo" else -1
        if source[0] == "prior":
            end_point = source[1]
            if isinstance(end_point, Fraction) and source[2]:
                stats["points"] += 1
                if not member(rev, end_point, factor, c):
                    problems.append(f"the prior end {side} {end_point} should be a member")
        else:
            value, attained = source[1], source[2]
            centre = _centre(value)
            index = source[3]
            piece = pieces[index]
            degenerate = piece.lo == piece.hi
            if centre is not None and not degenerate:
                if centre == 0 and attained:
                    stats["points"] += 1
                    if not member(rev, ZERO, factor, c):
                        problems.append(f"the attained end {side} 0 should be a member")
                width = _piece_width(piece)
                for step in INSIDE_STEPS:
                    delta = step * max(Fraction(1), abs(centre))
                    if width is not None:
                        delta = min(delta, width / 8)
                    point = centre + direction * delta
                    if in_prior(point):
                        stats["points"] += 1
                        if not member(rev, point, factor, c):
                            problems.append(f"{point} just inside the end {side} of the piece should be a member")
        # points beyond the end of the hull, inside the prior, are not members
        end_value = result.lo if side == "lo" else result.hi
        if isinstance(end_value, Fraction) and source[0] == "piece":
            exact_centre = _centre(source[1])
            base = exact_centre if exact_centre is not None else end_value
            for step in OUTSIDE_STEPS:
                delta = step * max(Fraction(1), abs(base))
                point = base - direction * delta
                if in_prior(point):
                    stats["points"] += 1
                    if member(rev, point, factor, c):
                        problems.append(f"{point} beyond the end {side} of the hull should not be a member")
    return problems


def _piece_width(piece: Piece) -> Fraction | None:
    if piece.lo.kind == "inf" or piece.hi.kind == "inf":
        return None
    low, high = _centre(piece.lo), _centre(piece.hi)
    if low is None or high is None:
        return None
    return abs(high - low)


# ---------------------------------------------------------------------------
# the generated corpus
# ---------------------------------------------------------------------------


def _floats(values: list[str]) -> list[Bound]:
    out: list[Bound] = []
    for text in values:
        if text == "inf":
            out.append(INF)
        elif text == "-inf":
            out.append(-INF)
        else:
            out.append(Fraction(float.fromhex(text)) if text.startswith(("0x", "-0x")) else Fraction(float(text)))
    return out


# c ends: far below and above the range, around -pi, -pi/2, 0, pi/2 and pi (the floats next to each)
C_ENDS = _floats(
    [
        "-inf",
        "-4.0",
        "-0x1.9221fp+1",  # -3.1416...: a float below -pi (|.| > pi)
        "-0x1.921fb54442d18p+1",  # RN(-pi), above -pi (|.| < pi)
        "-0x1.921fb54442d19p+1",  # the next float down: below -pi
        "-2.0",
        "-0x1.921fb54442d18p+0",  # RN(-pi/2): above -pi/2 (|.| < pi/2)
        "-0x1.921fb54442d19p+0",  # below -pi/2
        "0.0",
        "1.0",
        "0x1.921fb54442d18p+0",  # RN(pi/2): below pi/2
        "0x1.921fb54442d19p+0",  # above pi/2
        "2.0",
        "0x1.921fb54442d18p+1",  # RN(pi): below pi
        "0x1.921fb54442d19p+1",  # above pi
        "4.0",
        "inf",
    ]
)
C_ENDS = sorted(C_ENDS, key=lambda e: (-1e300 if e == -INF else (1e300 if e == INF else float(e))))
B_ENDS = _floats(["-inf", "-2.0", "-1.0", "-0.5", "0.0", "0.5", "1.0", "2.0", "inf"])
PRIORS = [
    (-INF, INF),
    (ZERO, INF),
    (-INF, ZERO),
    (Fraction(-1), Fraction(1)),
    (ZERO, ZERO),
    (Fraction(1), Fraction(2)),
    (Fraction(-2), Fraction(-1)),
    (Fraction(-4), Fraction(4)),
]


def intervals(ends: list[Bound]) -> list[tuple[Bound, Bound]]:
    out = []
    for i, low in enumerate(ends):
        for high in ends[i:]:
            if isinstance(low, float) and low > 0:
                continue
            if isinstance(high, float) and high < 0:
                continue
            out.append((low, high))
    return out


def text(value: Bound) -> str:
    if isinstance(value, float):
        return "infinity" if value > 0 else "-infinity"
    return float(value).hex()


def interval_text(interval: tuple[Bound, Bound] | None, decoration: str = "") -> str:
    if interval is None:
        return "[empty]" + decoration
    low, high = interval
    if low == -INF and high == INF:
        return "[entire]" + decoration
    return f"[{text(low)},{text(high)}]" + decoration


def cases() -> list[tuple[int, tuple, tuple, tuple]]:
    """The generated statements as (rev, factor, c, prior): the prior Entire for every
    combination, and a prior drawn deterministically for one in five."""
    out = []
    c_all = intervals(C_ENDS)
    f_all = intervals(B_ENDS)
    for rev in (1, 2):
        counter = 0
        for c in c_all:
            for f in f_all:
                out.append((rev, f, c, PRIORS[0]))
                counter += 1
                if counter % 5 == 0:
                    out.append((rev, f, c, PRIORS[1 + (counter // 5) % (len(PRIORS) - 1)]))
    return out


def statements() -> list[str]:
    lines: list[str] = []
    for rev in (1, 2):
        name = f"atan2Rev{rev}"
        lines.append(f"testcase atan2_rev{rev}_bare {{")
        for r, f, c, prior in cases():
            if r != rev:
                continue
            result = hull(r, f, c, prior)
            expected = None if result is None else (result.lo, result.hi)
            lines.append(
                f"    {name} {interval_text(f)} {interval_text(c)} {interval_text(prior)} = {interval_text(expected)};"
            )
        lines.append("}")
        lines.append("")
    # the decorated statements: every 23rd, the result decorated trv
    for rev in (1, 2):
        name = f"atan2Rev{rev}"
        lines.append(f"testcase atan2_rev{rev}_dec {{")
        picked = [item for item in cases() if item[0] == rev][::23]
        for r, f, c, prior in picked:
            result = hull(r, f, c, prior)
            expected = None if result is None else (result.lo, result.hi)
            lines.append(
                f"    {name} {interval_text(f, '_def')} {interval_text(c, '_def')} "
                f"{interval_text(prior, '_def')} = {interval_text(expected, '_trv')};"
            )
        lines.append("}")
        lines.append("")
    return lines


HEADER = (
    "// Generated by `python3 tools/itl_atan2_reverse_oracle.py --write`: atan2Rev1 and atan2Rev2,\n"
    "// IEEE 1788-2015 10.5.4. Not part of ITF1788: expected values are the exact hulls of tools/itl_atan2_reverse_oracle.py.\n"
)


def build_text() -> str:
    return HEADER + "\n" + "\n".join(statements()).rstrip("\n") + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    if args.write:
        GENERATED.parent.mkdir(parents=True, exist_ok=True)
        GENERATED.write_text(build_text(), encoding="utf-8")
        print(f"wrote {GENERATED.relative_to(REPO_ROOT)}")
        return 0
    text_now = build_text()
    ok = GENERATED.exists() and GENERATED.read_text(encoding="utf-8") == text_now
    if not ok:
        print("generated/atan2_rev.itl differs from the oracle; run --write and review")
    stats = {"cases": 0, "passed": 0, "points": 0, "empty": 0}
    failures = 0
    for rev, f, c, prior in cases():
        result = hull(rev, f, c, prior)
        problems = validate(rev, f, c, prior, result, stats)
        stats["cases"] += 1
        if problems:
            failures += 1
            print(f"DISAGREEMENT rev{rev} factor={interval_text(f)} c={interval_text(c)} prior={interval_text(prior)}")
            for problem in problems[:3]:
                print("   ", problem)
        else:
            stats["passed"] += 1
    print(stats, "forward-definition disagreements:", failures)
    return 0 if ok and failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
