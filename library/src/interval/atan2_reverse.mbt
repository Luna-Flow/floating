///|
/// `atan2Rev1(b, c, x)` and `atan2Rev2(a, c, x)` of IEEE 1788-2015 Table 10.1, clause
/// 10.5.4, equations (6) and (7):
///
/// - `atan2Rev1(b, c, x)` is the hull of `{ y in x | exists b0 in b : atan2(y, b0) is
///   defined and in c }`: the unknown is the ordinate `y`, `b` the abscissa interval;
/// - `atan2Rev2(a, c, x)` is the hull of `{ x0 in x | exists a0 in a : atan2(a0, x0) is
///   defined and in c }`: the unknown is the abscissa, `a` the ordinate interval.
///
/// `atan2(y, x)` is defined on the plane minus the origin, with the range `(-pi, pi]`
/// (Table 9.1, footnote f: it is discontinuous on the half-line `y = 0, x < 0`, whose
/// angle is `pi`; the angle `-pi` is never attained). With `Theta = c inter (-pi, pi]`
/// the set is the projection of the sector `{ r (cos t, sin t) : r > 0, t in Theta }` on
/// the axis of the unknown, cut by the strip of the given operand; it is a union of at
/// most five pieces.
///
/// Rev1, with `b+ = b inter (0, inf)` and `b- = b inter (-inf, 0)`:
/// - right, angles in `(-pi/2, pi/2)`: `b+ * tan(Theta_r)`;
/// - upper-left, angles in `(pi/2, pi]`: `b- * tan(Theta_ul)`, `tan(pi) = 0` is attained;
/// - lower-left, angles in `(-pi, -pi/2)`: `b- * tan(Theta_ll)`, the end `tan(-pi) = 0`
///   is open;
/// - up, `pi/2 in Theta` and `0 in b`: `(0, +inf)`; down, `-pi/2 in Theta` and `0 in b`:
///   `(-inf, 0)`.
/// Rev2, with `a+` and `a-` likewise: `a+ * cot(Theta inter (0, pi))` (`cot` decreases
/// from `+inf` to `-inf`), `a- * cot(Theta inter (-pi, 0))` (the end at `-pi` is open),
/// `0 in Theta` and `0 in a`: `(0, +inf)`; `pi in Theta` and `0 in a`: `(-inf, 0)`.
///
/// Whether a float end of `c` is below or above a multiple of `pi/2` is decided exactly
/// (`pi` is irrational, so a float is never equal to such a multiple; only `0` is an exact
/// angle). The only exact piece ends are 0 and the infinities; every other end is
/// `b_end * tan(c_end)` (or `a_end * cot(c_end)`) of nonzero floats, which is irrational
/// (Lindemann-Weierstrass), so a comparison with a prior end is strict and the loop of
/// `pow_rev1` (the working precision doubles until the enclosure decides) terminates.

///|
priv enum ProdKind {
  Tan
  Cot
}

///|
/// An end of the factor interval (`b+`, `b-`, `a+` or `a-`): the limit 0 (not attained), an
/// infinite end (not attained), or a finite nonzero float (attained).
priv enum FactorEnd {
  FZero
  FInf(Int32)
  FFin(@binary.Binary)
}

///|
/// An end of the interval of the trigonometric value: an infinite end (not attained), the
/// value 0 (attained or not), or the tangent (cotangent) of a float angle, with its sign.
priv enum TrigEnd {
  TInf(Int32)
  TZero(Bool)
  TVal(@binary.Binary, Int32)
}

///|
fn trig_end_sign(end : TrigEnd) -> Int32 {
  match end {
    TInf(sign) => sign
    TZero(_) => 0
    TVal(_, sign) => sign
  }
}

///|
/// The position of an angle `e` against `-pi, -pi/2, 0, pi/2, pi`, exactly: 0 for
/// `e < -pi`, 1 for `-pi < e < -pi/2`, 2 for `-pi/2 < e < 0`, 3 for `e = 0`, 4 for
/// `0 < e < pi/2`, 5 for `pi/2 < e < pi`, 6 for `e > pi` (infinities included).
fn atan2_zone(e : @binary.Binary) -> Int32 {
  if is_neg_inf(e) {
    return 0
  }
  if is_pos_inf(e) {
    return 6
  }
  if e.is_zero() {
    return 3
  }
  let negative = e.sign() == Sign::Negative
  let magnitude = if negative { e.neg() } else { e }
  let half = Interval::exact(@binary.Binary::from_double(0.5))
  let mut w = Int32::max(64, e.precision() + 16)
  let mut position = -1
  while position < 0 {
    let pi = certified_pi_interval(w)
    let half_pi = pi * half
    if magnitude.compare(half_pi.lo_) < 0 {
      position = 0
    } else if magnitude.compare(half_pi.hi_) > 0 &&
      magnitude.compare(pi.lo_) < 0 {
      position = 1
    } else if magnitude.compare(pi.hi_) > 0 {
      position = 2
    } else {
      w = w * 2
    }
  }
  if negative {
    2 - position
  } else {
    4 + position
  }
}

///|
fn factor_positive(
  lo : @binary.Binary,
  hi : @binary.Binary,
) -> (FactorEnd, FactorEnd)? {
  // the part of [lo, hi] in (0, +inf)
  if hi.compare(@binary.Binary::zero()) <= 0 {
    return None
  }
  let low = if lo.compare(@binary.Binary::zero()) > 0 {
    FFin(lo)
  } else {
    FZero
  }
  let high = if is_pos_inf(hi) { FInf(1) } else { FFin(hi) }
  Some((low, high))
}

///|
fn factor_negative(
  lo : @binary.Binary,
  hi : @binary.Binary,
) -> (FactorEnd, FactorEnd)? {
  // the part of [lo, hi] in (-inf, 0)
  if lo.compare(@binary.Binary::zero()) >= 0 {
    return None
  }
  let low = if is_neg_inf(lo) { FInf(-1) } else { FFin(lo) }
  let high = if hi.compare(@binary.Binary::zero()) < 0 {
    FFin(hi)
  } else {
    FZero
  }
  Some((low, high))
}

///|
fn inf_end(sign : Int32) -> PowEnd {
  if sign > 0 {
    PInf
  } else {
    PNegInf
  }
}

///|
/// The corner `factor * trig` as a piece end and whether it is attained. The corner of an
/// infinite factor with an infinite value, or of the limit 0 with an infinite value, is
/// never selected as an extreme by `atan2_product`; it returns the infinite end of the
/// side asked (valid, loose).
fn atan2_corner(
  factor : FactorEnd,
  trig : TrigEnd,
  kind : ProdKind,
  upper : Bool,
) -> (PowEnd, Bool) {
  match trig {
    TZero(attained) => (PZero, attained)
    TInf(sign) =>
      match factor {
        FZero => (inf_end(if upper { 1 } else { -1 }), false)
        FInf(s) => (inf_end(s * sign), false)
        FFin(value) =>
          (
            inf_end(if value.sign() == Sign::Negative { -sign } else { sign }),
            false,
          )
      }
    TVal(angle, sign) =>
      match factor {
        FZero => (PZero, false)
        FInf(s) => (inf_end(s * sign), false)
        FFin(value) => (PProd(value, angle, kind), true)
      }
  }
}

///|
/// The set product `{ x * t }` of a factor interval of one sign (`positive` or negative)
/// with the interval `[tl, th]` of the trigonometric value. `x * t` is monotone in each
/// variable, so each extreme is the product of two ends, chosen by the signs of the ends
/// of `t`.
fn atan2_product(
  positive : Bool,
  xl : FactorEnd,
  xh : FactorEnd,
  tl : TrigEnd,
  th : TrigEnd,
  kind : ProdKind,
) -> PowPiece {
  let (lo_factor, lo_trig) = if positive {
    if trig_end_sign(tl) >= 0 {
      (xl, tl)
    } else {
      (xh, tl)
    }
  } else if trig_end_sign(th) >= 0 {
    (xl, th)
  } else {
    (xh, th)
  }
  let (hi_factor, hi_trig) = if positive {
    if trig_end_sign(th) >= 0 {
      (xh, th)
    } else {
      (xl, th)
    }
  } else if trig_end_sign(tl) <= 0 {
    (xl, tl)
  } else {
    (xh, tl)
  }
  let (lo, lo_attained) = atan2_corner(lo_factor, lo_trig, kind, false)
  let (hi, hi_attained) = atan2_corner(hi_factor, hi_trig, kind, true)
  pow_piece(lo, !lo_attained, hi, !hi_attained)
}

///|
/// The pieces of `atan2Rev1(b, c)`: the unknown is the ordinate.
fn atan2_rev1_pieces(b : Interval, c : Interval) -> Array[PowPiece] {
  let pieces : Array[PowPiece] = []
  let z1 = atan2_zone(c.lo_)
  let z2 = atan2_zone(c.hi_)
  // Theta = c inter (-pi, pi] is empty if c < -pi or c > pi
  if z2 == 0 || z1 == 6 {
    return pieces
  }
  let plus = factor_positive(b.lo_, b.hi_)
  let minus = factor_negative(b.lo_, b.hi_)
  let zero_in_b = b.lo_.compare(@binary.Binary::zero()) <= 0 &&
    b.hi_.compare(@binary.Binary::zero()) >= 0
  // right: angles in (-pi/2, pi/2): z1 <= 4 and z2 >= 2
  if z1 <= 4 && z2 >= 2 {
    if plus is Some((xl, xh)) {
      let tl = if z1 <= 1 {
        TInf(-1)
      } else if z1 == 2 {
        TVal(c.lo_, -1)
      } else if z1 == 3 {
        TZero(true)
      } else {
        TVal(c.lo_, 1)
      }
      let th = if z2 >= 5 {
        TInf(1)
      } else if z2 == 2 {
        TVal(c.hi_, -1)
      } else if z2 == 3 {
        TZero(true)
      } else {
        TVal(c.hi_, 1)
      }
      pieces.push(atan2_product(true, xl, xh, tl, th, Tan))
    }
  }
  // upper-left: angles in (pi/2, pi]: z2 >= 5 and z1 <= 5
  if z2 >= 5 && z1 <= 5 {
    if minus is Some((xl, xh)) {
      let tl = if z1 <= 4 { TInf(-1) } else { TVal(c.lo_, -1) }
      let th = if z2 == 6 { TZero(true) } else { TVal(c.hi_, -1) }
      pieces.push(atan2_product(false, xl, xh, tl, th, Tan))
    }
  }
  // lower-left: angles in (-pi, -pi/2): z1 <= 1 and z2 >= 1
  if z1 <= 1 && z2 >= 1 {
    if minus is Some((xl, xh)) {
      let tl = if z1 == 0 { TZero(false) } else { TVal(c.lo_, 1) }
      let th = if z2 >= 2 { TInf(1) } else { TVal(c.hi_, 1) }
      pieces.push(atan2_product(false, xl, xh, tl, th, Tan))
    }
  }
  // the axis angles +-pi/2 need the abscissa 0 (any radius)
  if zero_in_b {
    if z1 <= 4 && z2 >= 5 {
      pieces.push(pow_piece(PZero, true, PInf, true))
    }
    if z1 <= 1 && z2 >= 2 {
      pieces.push(pow_piece(PNegInf, true, PZero, true))
    }
  }
  pieces
}

///|
/// The pieces of `atan2Rev2(a, c)`: the unknown is the abscissa.
fn atan2_rev2_pieces(a : Interval, c : Interval) -> Array[PowPiece] {
  let pieces : Array[PowPiece] = []
  let z1 = atan2_zone(c.lo_)
  let z2 = atan2_zone(c.hi_)
  if z2 == 0 || z1 == 6 {
    return pieces
  }
  let plus = factor_positive(a.lo_, a.hi_)
  let minus = factor_negative(a.lo_, a.hi_)
  let zero_in_a = a.lo_.compare(@binary.Binary::zero()) <= 0 &&
    a.hi_.compare(@binary.Binary::zero()) >= 0
  // the value cot t decreases with t: the lower end of the interval is the cot of the
  // upper angle. Upper half-plane: angles in (0, pi): z2 >= 4 and z1 <= 5
  if z2 >= 4 && z1 <= 5 {
    if plus is Some((xl, xh)) {
      let tl = if z2 == 6 {
        TInf(-1)
      } else if z2 == 4 {
        TVal(c.hi_, 1)
      } else {
        TVal(c.hi_, -1)
      }
      let th = if z1 <= 3 {
        TInf(1)
      } else if z1 == 4 {
        TVal(c.lo_, 1)
      } else {
        TVal(c.lo_, -1)
      }
      pieces.push(atan2_product(true, xl, xh, tl, th, Cot))
    }
  }
  // lower half-plane: angles in (-pi, 0): z1 <= 2 and z2 >= 1
  if z1 <= 2 && z2 >= 1 {
    if minus is Some((xl, xh)) {
      let tl = if z2 >= 3 {
        TInf(-1)
      } else if z2 == 1 {
        TVal(c.hi_, 1)
      } else {
        TVal(c.hi_, -1)
      }
      let th = if z1 == 0 {
        TInf(1)
      } else if z1 == 1 {
        TVal(c.lo_, 1)
      } else {
        TVal(c.lo_, -1)
      }
      pieces.push(atan2_product(false, xl, xh, tl, th, Cot))
    }
  }
  // the angles 0 and pi need the ordinate 0 (any radius)
  if zero_in_a {
    if z1 <= 3 && z2 >= 3 {
      pieces.push(pow_piece(PZero, true, PInf, true))
    }
    if z2 == 6 && z1 <= 5 {
      pieces.push(pow_piece(PNegInf, true, PZero, true))
    }
  }
  pieces
}

///|
/// An enclosure of `factor * tan(angle)` (or `factor / tan(angle)`) at `w` bits.
fn prod_enclosure(
  factor : @binary.Binary,
  angle : @binary.Binary,
  kind : ProdKind,
  w : Int32,
) -> PowEnc {
  let tangent = Interval::exact(
    angle,
    precision=Int32::max(w, angle.precision()),
  ).tan()
  let f = Interval::exact(factor, precision=Int32::max(w, factor.precision()))
  let value = match kind {
    Tan => f * tangent
    Cot => f / tangent
  }
  {
    lo: value.lo_,
    lo_open: false,
    hi: value.hi_,
    hi_open: false,
    clamped: false,
  }
}

///|
/// The first working precision. The forward `tan` of a point has a relative error of about
/// `2^-w` also next to `pi/2`, `0` and `pi` (the argument reduction is done at the working
/// precision), and the loop needs the value to a relative `2^-(p + 2)`, so `p + 96` bits
/// start it; the loop doubles the precision when that is not enough, and the measured
/// maximum on the generated corpus is in the tests.
fn prod_start_work(
  _factor : @binary.Binary,
  _angle : @binary.Binary,
  _kind : ProdKind,
  precision : Int32,
) -> Int32 {
  precision + 96
}

///|
fn prod_end_compare(
  factor : @binary.Binary,
  angle : @binary.Binary,
  kind : ProdKind,
  d : @binary.Binary,
  precision : Int32,
  cap : Int32,
) -> RevOrder {
  pow_loop_compare(
    prod_start_work(factor, angle, kind, precision),
    fn(w) { prod_enclosure(factor, angle, kind, w) },
    d,
    cap,
  )
}

///|
fn prod_end_rounded(
  factor : @binary.Binary,
  angle : @binary.Binary,
  kind : ProdKind,
  upper : Bool,
  precision : Int32,
  cap : Int32,
) -> @binary.Binary {
  pow_loop_round(
    prod_start_work(factor, angle, kind, precision),
    fn(w) { prod_enclosure(factor, angle, kind, w) },
    upper,
    precision,
    cap,
  )
}

///|
/// `atan2_rev1` with the number of refinements allowed as a parameter.
fn Interval::atan2_rev1_capped(
  self : Interval,
  c : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision0, prior) = rev_prior_precision(c, x)
  let precision = Int32::max(precision0, self.precision_)
  if self.is_empty() || c.is_empty() || prior.is_empty() {
    return empty_interval(precision)
  }
  pow_reverse_hull(atan2_rev1_pieces(self, c), prior, precision, cap)
}

///|
/// `atan2_rev2` with the number of refinements allowed as a parameter.
fn Interval::atan2_rev2_capped(
  self : Interval,
  c : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision0, prior) = rev_prior_precision(c, x)
  let precision = Int32::max(precision0, self.precision_)
  if self.is_empty() || c.is_empty() || prior.is_empty() {
    return empty_interval(precision)
  }
  pow_reverse_hull(atan2_rev2_pieces(self, c), prior, precision, cap)
}

///|
/// `atan2Rev1(b, c, x)` of Table 10.1: the hull of
/// `{ y in x | exists b0 in b : atan2(y, b0) is defined and in c }` for the optional prior
/// `x` (default Entire); the receiver is `b`, the abscissa interval, and the unknown is the
/// ordinate `y`.
pub fn Interval::atan2_rev1(
  self : Interval,
  c : Interval,
  x? : Interval,
) -> Interval {
  self.atan2_rev1_capped(c, x, rev_refinements)
}

///|
/// `atan2Rev2(a, c, x)` of Table 10.1: the hull of
/// `{ x0 in x | exists a0 in a : atan2(a0, x0) is defined and in c }` for the optional prior
/// `x` (default Entire); the receiver is `a`, the ordinate interval, and the unknown is
/// the abscissa `x0`.
pub fn Interval::atan2_rev2(
  self : Interval,
  c : Interval,
  x? : Interval,
) -> Interval {
  self.atan2_rev2_capped(c, x, rev_refinements)
}

///|
/// The trivial decorated version of 11.7.1: NaI if any input is NaI, else the bare result
/// decorated `Trv`.
pub fn DecoratedInterval::atan2_rev1(
  self : DecoratedInterval,
  c : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return DecoratedInterval::nai(precision~)
  }
  let result = match x {
    Some(prior) => self.interval_.atan2_rev1(c.interval_, x=prior.interval_)
    None => self.interval_.atan2_rev1(c.interval_)
  }
  DecoratedInterval::new(result, decoration=Trv)
}

///|
/// The trivial decorated version of 11.7.1: NaI if any input is NaI, else the bare result
/// decorated `Trv`.
pub fn DecoratedInterval::atan2_rev2(
  self : DecoratedInterval,
  c : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return DecoratedInterval::nai(precision~)
  }
  let result = match x {
    Some(prior) => self.interval_.atan2_rev2(c.interval_, x=prior.interval_)
    None => self.interval_.atan2_rev2(c.interval_)
  }
  DecoratedInterval::new(result, decoration=Trv)
}
