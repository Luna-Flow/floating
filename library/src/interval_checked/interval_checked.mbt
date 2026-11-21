///|
fn[A, B, E, C] interval_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub struct IntervalResult {
  priv inner : Result[@interval.Interval, @def.ArithmeticError]
}

///|
pub fn IntervalResult::from_result(
  inner : Result[@interval.Interval, @def.ArithmeticError],
) -> IntervalResult {
  { inner, }
}

///|
pub fn IntervalResult::ok(value : @interval.Interval) -> IntervalResult {
  { inner: Ok(value), }
}

///|
pub fn IntervalResult::err(err : @def.ArithmeticError) -> IntervalResult {
  { inner: Err(err), }
}

///|
pub fn IntervalResult::from_int(
  value : Int32,
  precision~ : Int32 = 53,
) -> IntervalResult {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) => IntervalResult::ok(@interval.Interval::from_int(value, precision~))
    Err(error) => IntervalResult::err(error)
  }
}

///|
pub fn IntervalResult::from_coefficient(
  value : @binary.BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> IntervalResult {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) =>
      IntervalResult::ok(
        @interval.Interval::from_coefficient(value, precision~, negative~),
      )
    Err(error) => IntervalResult::err(error)
  }
}

///|
pub fn IntervalResult::from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> IntervalResult {
  IntervalResult::from_result(
    @interval.Interval::try_from_double(value, precision~),
  )
}

///|
pub fn IntervalResult::from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> IntervalResult {
  IntervalResult::from_result(
    @interval.Interval::try_from_float(value, precision~),
  )
}

///|
pub fn IntervalResult::exact(
  value : @binary.Binary,
  precision~ : Int32 = value.precision(),
) -> IntervalResult {
  IntervalResult::from_result(@interval.Interval::try_exact(value, precision~))
}

///|
pub fn IntervalResult::from_bounds(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision~ : Int32 = Int32::max(lo.precision(), hi.precision()),
) -> IntervalResult {
  IntervalResult::from_result(
    @interval.Interval::try_from_bounds(lo, hi, precision~),
  )
}

///|
pub fn IntervalResult::entire(precision~ : Int32 = 53) -> IntervalResult {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) => IntervalResult::ok(@interval.Interval::entire(precision~))
    Err(error) => IntervalResult::err(error)
  }
}

///|
pub fn IntervalResult::result(
  self : IntervalResult,
) -> Result[@interval.Interval, @def.ArithmeticError] {
  self.inner
}

///|
pub fn IntervalResult::is_ok(self : IntervalResult) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub fn IntervalResult::is_err(self : IntervalResult) -> Bool {
  !self.is_ok()
}

///|
pub fn IntervalResult::error(self : IntervalResult) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
}

///|
pub fn IntervalResult::map(
  self : IntervalResult,
  f : (@interval.Interval) -> @interval.Interval,
) -> IntervalResult {
  IntervalResult::from_result(self.inner.map(f))
}

///|
pub fn IntervalResult::bind(
  self : IntervalResult,
  f : (@interval.Interval) -> IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
pub fn IntervalResult::normalized(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn IntervalResult::with_precision(
  self : IntervalResult,
  precision : Int32,
) -> IntervalResult {
  self.map(fn(value) { value.with_precision(precision) })
}

///|
/// `sqrt` of the interval part; a directed square root cannot fail.
pub fn IntervalResult::sqrt(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.sqrt() })
}

///|
pub fn IntervalResult::sqr(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.sqr() })
}

///|
/// `sign` of Table 9.1: a subset of [-1, 1]. Exact, it cannot fail.
pub fn IntervalResult::sign(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.sign() })
}

///|
/// `ceil` of Table 9.1. Exact, it cannot fail.
pub fn IntervalResult::ceil(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.ceil() })
}

///|
/// `floor` of Table 9.1. Exact, it cannot fail.
pub fn IntervalResult::floor(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.floor() })
}

///|
/// `trunc` of Table 9.1. Exact, it cannot fail.
pub fn IntervalResult::trunc(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.trunc() })
}

///|
/// `roundTiesToEven` of Table 9.1. Exact, it cannot fail.
pub fn IntervalResult::round_ties_to_even(
  self : IntervalResult,
) -> IntervalResult {
  self.map(fn(value) { value.round_ties_to_even() })
}

///|
/// `roundTiesToAway` of Table 9.1. Exact, it cannot fail.
pub fn IntervalResult::round_ties_to_away(
  self : IntervalResult,
) -> IntervalResult {
  self.map(fn(value) { value.round_ties_to_away() })
}

///|
/// `mulRev(b, c, x)` of Table 10.1 on the interval parts; an interval
/// operation never fails, so only an earlier failure is passed on. The prior
/// `x` is optional (default Entire).
pub fn IntervalResult::mul_rev(
  self : IntervalResult,
  c : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) =>
      self.bind(fn(b) {
        c.bind(fn(cc) { prior.map(fn(p) { b.mul_rev(cc, x=p) }) })
      })
    None => self.bind(fn(b) { c.map(fn(cc) { b.mul_rev(cc) }) })
  }
}

///|
/// `mulRevToPair(b, c)` of 10.5.5: the two components, each an `Err` when
/// either input is.
pub fn IntervalResult::mul_rev_to_pair(
  self : IntervalResult,
  c : IntervalResult,
) -> (IntervalResult, IntervalResult) {
  (
    self.bind(fn(b) { c.map(fn(cc) { b.mul_rev_to_pair(cc).0 }) }),
    self.bind(fn(b) { c.map(fn(cc) { b.mul_rev_to_pair(cc).1 }) }),
  )
}

///|
/// `sqrRev(c, x)` of Table 10.1 on the interval part; only an earlier failure
/// is passed on. The prior `x` is optional (default Entire).
pub fn IntervalResult::sqr_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.sqr_rev(x=p) }) })
    None => self.map(fn(c) { c.sqr_rev() })
  }
}

///|
/// `absRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalResult::abs_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.abs_rev(x=p) }) })
    None => self.map(fn(c) { c.abs_rev() })
  }
}

///|
/// `coshRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalResult::cosh_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.cosh_rev(x=p) }) })
    None => self.map(fn(c) { c.cosh_rev() })
  }
}

///|
/// `pownRev(c, x, p)` of Table 10.1; see `sqr_rev`. The prior is the optional
/// last argument.
pub fn IntervalResult::pown_rev(
  self : IntervalResult,
  p : Int32,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(q) { c.pown_rev(p, x=q) }) })
    None => self.map(fn(c) { c.pown_rev(p) })
  }
}

///|
/// `sinRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalResult::sin_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.sin_rev(x=p) }) })
    None => self.map(fn(c) { c.sin_rev() })
  }
}

///|
/// `cosRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalResult::cos_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.cos_rev(x=p) }) })
    None => self.map(fn(c) { c.cos_rev() })
  }
}

///|
/// `tanRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalResult::tan_rev(
  self : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.tan_rev(x=p) }) })
    None => self.map(fn(c) { c.tan_rev() })
  }
}

///|
/// `powRev1(b, c, x)` of Table 10.1 on the interval parts; only an earlier failure is
/// passed on. The prior `x` is optional (default Entire).
pub fn IntervalResult::pow_rev1(
  self : IntervalResult,
  c : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) =>
      self.bind(fn(b) {
        c.bind(fn(cc) { prior.map(fn(p) { b.pow_rev1(cc, x=p) }) })
      })
    None => self.bind(fn(b) { c.map(fn(cc) { b.pow_rev1(cc) }) })
  }
}

///|
/// `powRev2(a, c, x)` of Table 10.1 on the interval parts; only an earlier failure is
/// passed on. The prior `x` is optional (default Entire).
pub fn IntervalResult::pow_rev2(
  self : IntervalResult,
  c : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) =>
      self.bind(fn(a) {
        c.bind(fn(cc) { prior.map(fn(p) { a.pow_rev2(cc, x=p) }) })
      })
    None => self.bind(fn(a) { c.map(fn(cc) { a.pow_rev2(cc) }) })
  }
}

///|
/// `atan2Rev1(b, c, x)` of Table 10.1 on the interval parts; only an earlier failure is
/// passed on. The prior `x` is optional (default Entire).
pub fn IntervalResult::atan2_rev1(
  self : IntervalResult,
  c : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) =>
      self.bind(fn(b) {
        c.bind(fn(cc) { prior.map(fn(p) { b.atan2_rev1(cc, x=p) }) })
      })
    None => self.bind(fn(b) { c.map(fn(cc) { b.atan2_rev1(cc) }) })
  }
}

///|
/// `atan2Rev2(a, c, x)` of Table 10.1 on the interval parts; only an earlier failure is
/// passed on. The prior `x` is optional (default Entire).
pub fn IntervalResult::atan2_rev2(
  self : IntervalResult,
  c : IntervalResult,
  x? : IntervalResult,
) -> IntervalResult {
  match x {
    Some(prior) =>
      self.bind(fn(a) {
        c.bind(fn(cc) { prior.map(fn(p) { a.atan2_rev2(cc, x=p) }) })
      })
    None => self.bind(fn(a) { c.map(fn(cc) { a.atan2_rev2(cc) }) })
  }
}

///|
/// `Interval::from_string` (IEEE 1788-2015 `textToInterval`): the failed call is the
/// failure of the result.
pub fn IntervalResult::from_string(
  s : String,
  precision~ : Int32 = 53,
) -> IntervalResult {
  IntervalResult::from_result(@interval.Interval::from_string(s, precision~))
}

///|
pub fn IntervalResult::recip(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.recip() })
}

///|
pub fn IntervalResult::min(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.min(rhs) }),
  )
}

///|
pub fn IntervalResult::max(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.max(rhs) }),
  )
}

///|
/// `x * y + z` with one rounding of the interval operation.
pub fn IntervalResult::fma(
  self : IntervalResult,
  factor : IntervalResult,
  addend : IntervalResult,
) -> IntervalResult {
  self.bind(fn(x) { factor.bind(fn(y) { addend.map(fn(z) { x.fma(y, z) }) }) })
}

///|
pub fn IntervalResult::intersection(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.intersection(rhs)
    }),
  )
}

///|
pub fn IntervalResult::convex_hull(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.convex_hull(rhs)
    }),
  )
}

///|
pub fn IntervalResult::cancel_plus(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.cancel_plus(rhs)
    }),
  )
}

///|
pub fn IntervalResult::cancel_minus(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.cancel_minus(rhs)
    }),
  )
}

///|
pub fn IntervalResult::neg(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn IntervalResult::abs(self : IntervalResult) -> IntervalResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn IntervalResult::add(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn IntervalResult::sub(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn IntervalResult::mul(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn IntervalResult::div(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs / rhs }),
  )
}

///|
pub fn IntervalResult::pown(
  self : IntervalResult,
  exponent : Int32,
) -> IntervalResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    IntervalResult::from_result(
      @lf_arith.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn IntervalResult::rootn(
  self : IntervalResult,
  degree : Int32,
) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_rootn(degree)) })
}

///|
pub fn IntervalResult::exp(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_exp()) })
}

///|
pub fn IntervalResult::exp2(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_exp2()) })
}

///|
pub fn IntervalResult::exp10(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_exp10()) })
}

///|
pub fn IntervalResult::expm1(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_expm1()) })
}

///|
pub fn IntervalResult::ln(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_ln()) })
}

///|
pub fn IntervalResult::log2(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_log2()) })
}

///|
pub fn IntervalResult::log10(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_log10()) })
}

///|
pub fn IntervalResult::log1p(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_log1p()) })
}

///|
pub fn IntervalResult::sin(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_sin()) })
}

///|
pub fn IntervalResult::cos(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_cos()) })
}

///|
pub fn IntervalResult::tan(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_tan()) })
}

///|
pub fn IntervalResult::sinpi(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_sinpi()) })
}

///|
pub fn IntervalResult::cospi(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_cospi()) })
}

///|
pub fn IntervalResult::tanpi(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_tanpi()) })
}

///|
pub fn IntervalResult::asin(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_asin()) })
}

///|
pub fn IntervalResult::acos(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_acos()) })
}

///|
pub fn IntervalResult::atan(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_atan()) })
}

///|
pub fn IntervalResult::sinh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_sinh()) })
}

///|
pub fn IntervalResult::cosh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_cosh()) })
}

///|
pub fn IntervalResult::tanh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_tanh()) })
}

///|
pub fn IntervalResult::asinh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_asinh()) })
}

///|
pub fn IntervalResult::acosh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_acosh()) })
}

///|
pub fn IntervalResult::atanh(self : IntervalResult) -> IntervalResult {
  self.bind(fn(value) { IntervalResult::from_result(value.try_atanh()) })
}

///|
pub fn IntervalResult::hypot(
  self : IntervalResult,
  other : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    self.inner.bind(fn(left) {
      other.inner.bind(fn(right) { left.try_hypot(right) })
    }),
  )
}

///|
pub fn IntervalResult::pow(
  self : IntervalResult,
  exponent : IntervalResult,
) -> IntervalResult {
  self.bind(fn(base) {
    exponent.bind(fn(power) { IntervalResult::from_result(base.try_pow(power)) })
  })
}

///|
pub fn IntervalResult::atan2(
  self : IntervalResult,
  abscissa : IntervalResult,
) -> IntervalResult {
  IntervalResult::from_result(
    self.inner.bind(fn(ordinate) {
      abscissa.inner.bind(fn(horizontal) { ordinate.try_atan2(horizontal) })
    }),
  )
}

///|
pub impl Add for IntervalResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for IntervalResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for IntervalResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for IntervalResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for IntervalResult with fn neg(self) {
  self.neg()
}
