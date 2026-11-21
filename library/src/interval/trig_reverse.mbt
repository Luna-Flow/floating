///|
/// The reverse-mode trigonometric functions of IEEE 1788-2015 Table 10.1:
/// `sin_rev`, `cos_rev` and `tan_rev`. Each is the hull of
/// `{ x in x | f(x) in c }` for an optional prior `x` (default Entire).
///
/// The preimage of `c` is a periodic union of intervals. A piece end is
/// `t = (m2 / 2) pi + sigma * alpha(s)` with an integer `m2`, `sigma = +-1` and
/// `alpha` one of `asin`, `acos`, `atan` of an endpoint `s` of `c` (or no
/// `alpha` for a pole of `tan`). Every such end is irrational (indeed
/// transcendental) unless it is exactly 0, by the Lindemann-Weierstrass
/// theorem: `t = d` with `d` a float would make `e^(i d)` algebraic. The ends
/// that are 0 are `asin 0`, `acos 1` and `atan 0` with `m2 = 0`; they are
/// tested exactly. Every other end differs from every float, so its comparison
/// with a prior end has a strict answer, found by raising the working precision
/// until the enclosure of the end excludes the prior end. The value written as
/// a result end is the outward rounding of an enclosure of the end that
/// contains no float of the result precision, so it is exactly `RD(t)` or
/// `RU(t)`. The refinement is capped at 12 doublings; at the cap a piece is
/// treated as met and the rounding is that of the last enclosure (valid, and
/// possibly one unit wider). Beyond the working-precision limit of the forward
/// trigonometric functions the end of the prior is kept (valid, not tight).

///|
priv enum RevAlpha {
  AlphaZero
  AlphaAsin
  AlphaAcos
  AlphaAtan
}

///|
priv struct RevEnd {
  m2 : SignedBinCoeff
  sigma : Int32
  alpha : RevAlpha
  s : @bin_float.BinFloat
  // the enclosure of `alpha(s)` at the first working precision, shared by all
  // the ends of one template, and the enclosure of the end itself, found on
  // first use
  alpha_enc : Interval
  mut enc0 : Interval?
}

///|
/// The first working precision and the enclosure of pi / 2 at it, computed
/// once per call.
priv struct RevContext {
  w0 : Int32
  half_pi0 : Interval
  // the number of working-precision doublings allowed to decide a comparison or
  // a rounding; `rev_refinements` in use, smaller in the tests of the fallback
  cap : Int32
}

///|
/// The result of comparing a piece end `t` with a prior end `d`. `Undecided` is
/// the documented fallback when the enclosure of `t` still contains `d` after the
/// last refinement; every use of a comparison has to say what it does with it,
/// and a piece that might meet the prior is always treated as met.
priv enum RevOrder {
  Below
  Equal
  Above
  Undecided
}

///|
/// A family of pieces `[lo(k), hi(k)]`, `k` an integer: the ends have the form
/// of `RevEnd` with `m2 = offset + period * k`.
priv struct RevTemplate {
  lo_off : Int32
  lo_sigma : Int32
  lo_alpha : RevAlpha
  lo_s : @bin_float.BinFloat
  mut lo_enc : Interval?
  hi_off : Int32
  hi_sigma : Int32
  hi_alpha : RevAlpha
  hi_s : @bin_float.BinFloat
  mut hi_enc : Interval?
  period : Int32
}

///|
let rev_refinements : Int32 = 12

///|
fn rev_signed_to_bin(value : SignedBinCoeff) -> @bin_float.BinFloat {
  if signed_coeff_is_zero(value) {
    @bin_float.BinFloat::zero(precision=1)
  } else {
    exact_value(signed_coeff_magnitude(value), 0, negative=value.negative)
  }
}

///|
fn rev_end_of(
  template : RevTemplate,
  upper : Bool,
  k : SignedBinCoeff,
) -> RevEnd {
  let (off, sigma, alpha, s, alpha_enc) = if upper {
    (
      template.hi_off,
      template.hi_sigma,
      template.hi_alpha,
      template.hi_s,
      template.hi_enc.unwrap(),
    )
  } else {
    (
      template.lo_off,
      template.lo_sigma,
      template.lo_alpha,
      template.lo_s,
      template.lo_enc.unwrap(),
    )
  }
  let m2 = signed_coeff_add(
    signed_coeff_mul(k, signed_coeff_from_int(template.period)),
    signed_coeff_from_int(off),
  )
  { m2, sigma, alpha, s, alpha_enc, enc0: None, }
}

///|
/// `true` when the end is exactly 0, the only end that can be a float.
fn rev_end_is_zero(end : RevEnd) -> Bool {
  if !signed_coeff_is_zero(end.m2) {
    return false
  }
  match end.alpha {
    AlphaZero => true
    AlphaAsin | AlphaAtan => end.s.is_zero()
    AlphaAcos =>
      end.s.compare(@bin_float.BinFloat::from_int(1, precision=1)) == 0
  }
}

///|
/// An enclosure of `alpha(s)` at `w` bits.
fn rev_alpha_enclosure(
  alpha : RevAlpha,
  s : @bin_float.BinFloat,
  w : Int32,
) -> Interval {
  let point = Interval::exact(s, precision=Int32::max(w, s.precision()))
  match alpha {
    AlphaZero => Interval::exact(@bin_float.BinFloat::zero(precision=1))
    AlphaAsin => point.asin()
    AlphaAcos => point.acos()
    AlphaAtan => point.atan()
  }
}

///|
fn rev_combine(end : RevEnd, half_pi : Interval, alpha : Interval) -> Interval {
  let term = if signed_coeff_is_zero(end.m2) {
    Interval::exact(@bin_float.BinFloat::zero(precision=1))
  } else {
    Interval::exact(rev_signed_to_bin(end.m2)) * half_pi
  }
  if end.sigma > 0 {
    term + alpha
  } else {
    term - alpha
  }
}

///|
/// An enclosure of the end at `w` bits; at the first working precision it is
/// computed once from the shared pieces and kept.
fn rev_end_enclosure(end : RevEnd, w : Int32, rc : RevContext) -> Interval {
  if w == rc.w0 {
    match end.enc0 {
      Some(enclosure) => enclosure
      None => {
        let enclosure = rev_combine(end, rc.half_pi0, end.alpha_enc)
        end.enc0 = Some(enclosure)
        enclosure
      }
    }
  } else {
    let pi = certified_pi_interval(w)
    let half_pi = pi * Interval::exact(@bin_float.BinFloat::from_double(0.5))
    rev_combine(end, half_pi, rev_alpha_enclosure(end.alpha, end.s, w))
  }
}

///|
/// Compares the end `t` with the finite float `d`: `Below` for `t < d`, `Equal`
/// for `t = d` (only a zero end), `Above` for `t > d`, and `Undecided` when the
/// enclosure still contains `d` after `rc.cap` doublings (the documented fallback).
fn rev_end_compare(
  end : RevEnd,
  d : @bin_float.BinFloat,
  rc : RevContext,
) -> RevOrder {
  if rev_end_is_zero(end) {
    return if d.is_zero() {
      Equal
    } else if d.sign() == Sign::Positive {
      Below
    } else {
      Above
    }
  }
  let mut w = rc.w0
  for _ in 0..<rc.cap {
    let enclosure = rev_end_enclosure(end, w, rc)
    if enclosure.hi_.compare(d) < 0 {
      return Below
    }
    if enclosure.lo_.compare(d) > 0 {
      return Above
    }
    w = w * 2
  }
  Undecided
}

///|
/// `t >= d` for a piece that might meet the prior: an undecided comparison counts.
fn rev_may_be_at_least(order : RevOrder) -> Bool {
  match order {
    Below => false
    Equal | Above | Undecided => true
  }
}

///|
/// `t <= d`, an undecided comparison counting as met.
fn rev_may_be_at_most(order : RevOrder) -> Bool {
  match order {
    Above => false
    Below | Equal | Undecided => true
  }
}

///|
/// The directed rounding of the end to `precision` bits: `RD` for a lower end,
/// `RU` for an upper end, decided by refining until the enclosure of the end
/// contains no float of that precision.
fn rev_end_rounded(
  end : RevEnd,
  upper : Bool,
  precision : Int32,
  rc : RevContext,
) -> @bin_float.BinFloat {
  if rev_end_is_zero(end) {
    return @bin_float.BinFloat::zero(precision~)
  }
  let down = @bin_float.BinaryRoundingMode::RoundTowardNegative
  let up = @bin_float.BinaryRoundingMode::RoundTowardPositive
  let mut w = rc.w0
  let mut enclosure = rev_end_enclosure(end, w, rc)
  for _ in 0..<rc.cap {
    if enclosure.lo_.with_precision(precision, up).compare(enclosure.hi_) > 0 {
      break
    }
    w = w * 2
    enclosure = rev_end_enclosure(end, w, rc)
  }
  if upper {
    enclosure.hi_.with_precision(precision, up)
  } else {
    enclosure.lo_.with_precision(precision, down)
  }
}

///|
/// Bounds of `floor(2 x / pi)` and `ceil(2 x / pi)` from the enclosure of pi.
fn rev_quarter_window(
  x : @bin_float.BinFloat,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (SignedBinCoeff, SignedBinCoeff) {
  // |x| < 1 gives |2 x / pi| < 1 without any division (and without writing a
  // tiny x with a huge negative exponent as a rational)
  if x.is_zero() {
    return (signed_coeff_from_int(0), signed_coeff_from_int(0))
  }
  let adjusted = x.ilogb().unwrap().to_int64() + 1L
  if adjusted <= 0L {
    return if x.sign() == Sign::Negative {
      (signed_coeff_from_int(-1), signed_coeff_from_int(0))
    } else {
      (signed_coeff_from_int(0), signed_coeff_from_int(1))
    }
  }
  let (lower, upper) = trig_quotient_bounds(
    rat_from_finite_bin(x),
    pi_lower,
    pi_upper,
  )
  (rat_floor(lower), rat_ceil(upper))
}

///|
/// The indices `k` with `off + period * k` in `[low, high]`.
fn rev_index_range(
  low : SignedBinCoeff,
  high : SignedBinCoeff,
  off : Int32,
  period : Int32,
) -> (SignedBinCoeff, SignedBinCoeff) {
  let den = @bin_float.BinCoeff::from_uint64(period.to_uint64())
  let first = rat_ceil(
    certified_rat_coeff(signed_coeff_sub(low, signed_coeff_from_int(off)), den),
  )
  let last = rat_floor(
    certified_rat_coeff(signed_coeff_sub(high, signed_coeff_from_int(off)), den),
  )
  (first, last)
}

///|
/// The lower end of the hull of the pieces inside `[xl, xh]` (`xl` finite): the
/// minimum over the pieces that meet the prior of `xl` (when the piece starts
/// at or before `xl`) or of the rounded-down start of the piece. `None` when no
/// piece meets the prior.
fn rev_lower_end(
  templates : Array[RevTemplate],
  xl : @bin_float.BinFloat,
  xh : @bin_float.BinFloat,
  precision : Int32,
  rc : RevContext,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> @bin_float.BinFloat? {
  let (floor_u, ceil_u) = rev_quarter_window(xl, pi_lower, pi_upper)
  let xh_infinite = xh.classify() == FpClass::Infinity
  let mut best : @bin_float.BinFloat? = None
  for template in templates {
    // the first piece reaching xl has its upper end in this window
    let low = signed_coeff_sub(floor_u, signed_coeff_from_int(3))
    let high = signed_coeff_add(
      ceil_u,
      signed_coeff_from_int(2 + template.period),
    )
    let (first, last) = rev_index_range(
      low,
      high,
      template.hi_off,
      template.period,
    )
    let mut k = first
    while signed_coeff_compare(k, last) <= 0 {
      let lo_end = rev_end_of(template, false, k)
      let hi_end = rev_end_of(template, true, k)
      let reaches = rev_may_be_at_least(rev_end_compare(hi_end, xl, rc))
      let starts = xh_infinite ||
        rev_may_be_at_most(rev_end_compare(lo_end, xh, rc))
      if reaches && starts {
        // the lower end of a met piece inside the prior is xl or its own start;
        // when the comparison is undecided xl is a valid lower bound of both
        let value = match rev_end_compare(lo_end, xl, rc) {
          Below | Equal | Undecided => xl
          Above => rev_end_rounded(lo_end, false, precision, rc)
        }
        best = match best {
          Some(current) if current.compare(value) <= 0 => Some(current)
          _ => Some(value)
        }
      }
      k = signed_coeff_add(k, signed_coeff_from_int(1))
    }
  }
  best
}

///|
/// The upper end, symmetric to `rev_lower_end` (`xh` finite).
fn rev_upper_end(
  templates : Array[RevTemplate],
  xl : @bin_float.BinFloat,
  xh : @bin_float.BinFloat,
  precision : Int32,
  rc : RevContext,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> @bin_float.BinFloat? {
  let (floor_v, ceil_v) = rev_quarter_window(xh, pi_lower, pi_upper)
  let xl_infinite = xl.classify() == FpClass::Infinity
  let mut best : @bin_float.BinFloat? = None
  for template in templates {
    // the last piece starting at or below xh has its lower end in this window
    let low = signed_coeff_sub(
      floor_v,
      signed_coeff_from_int(3 + template.period),
    )
    let high = signed_coeff_add(ceil_v, signed_coeff_from_int(3))
    let (first, last) = rev_index_range(
      low,
      high,
      template.lo_off,
      template.period,
    )
    let mut k = first
    while signed_coeff_compare(k, last) <= 0 {
      let lo_end = rev_end_of(template, false, k)
      let hi_end = rev_end_of(template, true, k)
      let reaches = xl_infinite ||
        rev_may_be_at_least(rev_end_compare(hi_end, xl, rc))
      let starts = rev_may_be_at_most(rev_end_compare(lo_end, xh, rc))
      if reaches && starts {
        // symmetric: xh is a valid upper bound when the comparison is undecided
        let value = match rev_end_compare(hi_end, xh, rc) {
          Above | Equal | Undecided => xh
          Below => rev_end_rounded(hi_end, true, precision, rc)
        }
        best = match best {
          Some(current) if current.compare(value) >= 0 => Some(current)
          _ => Some(value)
        }
      }
      k = signed_coeff_add(k, signed_coeff_from_int(1))
    }
  }
  best
}

///|
/// `true` when the argument reduction at this end would need more working bits
/// than the forward trigonometric functions allow.
fn rev_end_beyond_limit(x : @bin_float.BinFloat, precision : Int32) -> Bool {
  if x.is_zero() {
    return false
  }
  let adjusted = x.ilogb().unwrap().to_int64()
  Int64::max(0L, adjusted) + precision.to_int64() + 96L > trig_work_limit
}

///|
/// The hull of the union of the `templates` inside the closed `prior`, with the
/// number of refinements allowed as a parameter (the tests of the fallback set it to 0
/// and 1).
///
/// The limit of the forward functions is decided first: an end of the prior at or
/// beyond it contributes no work and is kept, the working precision comes only
/// from the ends inside the limit, and when no end is inside it (the other being
/// infinite or beyond it too) the prior is returned at once.
fn trig_reverse_hull_capped(
  templates : Array[RevTemplate],
  prior : Interval,
  precision : Int32,
  cap : Int32,
) -> Interval {
  if prior.is_empty() {
    return empty_interval(precision)
  }
  let xl = prior.lo_
  let xh = prior.hi_
  let lower_infinite = is_neg_inf(xl)
  let upper_infinite = is_pos_inf(xh)
  if lower_infinite && upper_infinite {
    return Interval::entire(precision~)
  }
  let lower_works = !lower_infinite && !rev_end_beyond_limit(xl, precision)
  let upper_works = !upper_infinite && !rev_end_beyond_limit(xh, precision)
  if !lower_works && !upper_works {
    return Interval::from_bounds(xl, xh, precision~)
  }
  let w0 = if lower_works && upper_works {
    Int32::max(
      trig_initial_work(xl, precision),
      trig_initial_work(xh, precision),
    )
  } else if lower_works {
    trig_initial_work(xl, precision)
  } else {
    trig_initial_work(xh, precision)
  }
  let pi = certified_pi_interval(w0 + 48)
  let pi_lower = rat_from_finite_bin(pi.lo_)
  let pi_upper = rat_from_finite_bin(pi.hi_)
  let rc : RevContext = {
    w0,
    half_pi0: certified_pi_interval(w0) *
    Interval::exact(@bin_float.BinFloat::from_double(0.5)),
    cap,
  }
  for template in templates {
    template.lo_enc = Some(
      rev_alpha_enclosure(template.lo_alpha, template.lo_s, w0),
    )
    template.hi_enc = Some(
      rev_alpha_enclosure(template.hi_alpha, template.hi_s, w0),
    )
  }
  let lower = if lower_works {
    rev_lower_end(templates, xl, xh, precision, rc, pi_lower, pi_upper)
  } else if lower_infinite {
    Some(neg_inf(precision))
  } else {
    Some(xl)
  }
  let upper = if upper_works {
    rev_upper_end(templates, xl, xh, precision, rc, pi_lower, pi_upper)
  } else if upper_infinite {
    Some(pos_inf(precision))
  } else {
    Some(xh)
  }
  match (lower, upper) {
    (Some(l), Some(u)) =>
      if l.compare(u) <= 0 {
        Interval::from_bounds(l, u, precision~)
      } else {
        // not reachable for a nonempty set; the prior itself is a valid answer
        prior
      }
    (None, _) => empty_interval(precision)
    (_, None) => empty_interval(precision)
  }
}

///|
fn rev_template(
  lo : (Int32, Int32, RevAlpha, @bin_float.BinFloat),
  hi : (Int32, Int32, RevAlpha, @bin_float.BinFloat),
  period : Int32,
) -> RevTemplate {
  {
    lo_off: lo.0,
    lo_sigma: lo.1,
    lo_alpha: lo.2,
    lo_s: lo.3,
    lo_enc: None,
    hi_off: hi.0,
    hi_sigma: hi.1,
    hi_alpha: hi.2,
    hi_s: hi.3,
    hi_enc: None,
    period,
  }
}

///|
/// The part of `c` inside `[-1, 1]`, or `None` when it is empty; `full` when
/// `c` contains all of `[-1, 1]`.
fn rev_unit_part(
  c : Interval,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat, Bool)? {
  if c.is_empty() {
    return None
  }
  let one = @bin_float.BinFloat::from_int(1, precision~)
  let minus_one = @bin_float.BinFloat::from_int(-1, precision~)
  if c.hi_.compare(minus_one) < 0 || c.lo_.compare(one) > 0 {
    return None
  }
  let lo = if c.lo_.compare(minus_one) < 0 { minus_one } else { c.lo_ }
  let hi = if c.hi_.compare(one) > 0 { one } else { c.hi_ }
  Some((lo, hi, c.lo_.compare(minus_one) <= 0 && c.hi_.compare(one) >= 0))
}

///|
/// `sin_rev` with the number of refinements allowed as a parameter (the tests of the
/// fallback set it to 0 and 1).
fn Interval::sin_rev_capped(
  self : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision, prior) = rev_prior_precision(self, x)
  match rev_unit_part(self, precision) {
    None => empty_interval(precision)
    Some((s_lo, s_hi, full)) =>
      if full {
        if prior.is_empty() {
          empty_interval(precision)
        } else {
          Interval::from_bounds(prior.lo_, prior.hi_, precision~)
        }
      } else {
        // [asin lo + 2 pi k, asin hi + 2 pi k] and
        // [pi - asin hi + 2 pi k, pi - asin lo + 2 pi k]
        let first = rev_template(
          (0, 1, AlphaAsin, s_lo),
          (0, 1, AlphaAsin, s_hi),
          4,
        )
        let second = rev_template(
          (2, -1, AlphaAsin, s_hi),
          (2, -1, AlphaAsin, s_lo),
          4,
        )
        trig_reverse_hull_capped([first, second], prior, precision, cap)
      }
  }
}

///|
/// `sinRev(c, x)` of Table 10.1: the hull of `{ x in x | sin x in c }`. With the
/// default prior it is Entire for every `c` that meets `[-1, 1]`.
pub fn Interval::sin_rev(self : Interval, x? : Interval) -> Interval {
  self.sin_rev_capped(x, rev_refinements)
}

///|
/// `cos_rev` with the number of refinements allowed as a parameter (the tests of the
/// fallback set it to 0 and 1).
fn Interval::cos_rev_capped(
  self : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision, prior) = rev_prior_precision(self, x)
  match rev_unit_part(self, precision) {
    None => empty_interval(precision)
    Some((s_lo, s_hi, full)) =>
      if full {
        if prior.is_empty() {
          empty_interval(precision)
        } else {
          Interval::from_bounds(prior.lo_, prior.hi_, precision~)
        }
      } else {
        // [acos hi + 2 pi k, acos lo + 2 pi k] and
        // [-acos lo + 2 pi k, -acos hi + 2 pi k]
        let first = rev_template(
          (0, 1, AlphaAcos, s_hi),
          (0, 1, AlphaAcos, s_lo),
          4,
        )
        let second = rev_template(
          (0, -1, AlphaAcos, s_lo),
          (0, -1, AlphaAcos, s_hi),
          4,
        )
        trig_reverse_hull_capped([first, second], prior, precision, cap)
      }
  }
}

///|
/// `cosRev(c, x)` of Table 10.1: the hull of `{ x in x | cos x in c }`.
pub fn Interval::cos_rev(self : Interval, x? : Interval) -> Interval {
  self.cos_rev_capped(x, rev_refinements)
}

///|
/// `tan_rev` with the number of refinements allowed as a parameter (the tests of the
/// fallback set it to 0 and 1).
fn Interval::tan_rev_capped(
  self : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision, prior) = rev_prior_precision(self, x)
  if self.is_empty() || prior.is_empty() {
    return empty_interval(precision)
  }
  if is_neg_inf(self.lo_) && is_pos_inf(self.hi_) {
    return Interval::from_bounds(prior.lo_, prior.hi_, precision~)
  }
  // (atan lo + pi k, atan hi + pi k), the end of an unbounded c being a pole
  let zero = @bin_float.BinFloat::zero(precision~)
  let lo = if is_neg_inf(self.lo_) {
    (-1, 1, AlphaZero, zero)
  } else {
    (0, 1, AlphaAtan, self.lo_)
  }
  let hi = if is_pos_inf(self.hi_) {
    (1, 1, AlphaZero, zero)
  } else {
    (0, 1, AlphaAtan, self.hi_)
  }
  trig_reverse_hull_capped([rev_template(lo, hi, 2)], prior, precision, cap)
}

///|
/// `tanRev(c, x)` of Table 10.1: the hull of `{ x in x | tan x in c }`. The
/// poles `pi/2 + pi k` are not in the domain; no float is a pole.
pub fn Interval::tan_rev(self : Interval, x? : Interval) -> Interval {
  self.tan_rev_capped(x, rev_refinements)
}

///|
pub fn DecoratedInterval::sin_rev(
  self : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  self.rev_decorated_unary(x, fn(c, prior) { c.sin_rev(x?=prior) })
}

///|
pub fn DecoratedInterval::cos_rev(
  self : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  self.rev_decorated_unary(x, fn(c, prior) { c.cos_rev(x?=prior) })
}

///|
pub fn DecoratedInterval::tan_rev(
  self : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  self.rev_decorated_unary(x, fn(c, prior) { c.tan_rev(x?=prior) })
}
