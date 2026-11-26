///|
fn[A, B, E, C] interval_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
/// An `Interval` or the first `ArithmeticError` of a computation: a wrapper
/// around `Result[Interval, ArithmeticError]`. Invalid bounds, a precision out of
/// range and a failed certified function are errors; Entire, the empty interval
/// and other conservative enclosures are successful values. An operation on a
/// failed wrapper returns that failure, and a binary operation with two failed
/// operands keeps the left one. The wrapper stores no decorations and no
/// `IntervalFlags`.
pub struct IntervalChecked {
  priv inner : Result[@interval.Interval, @def.ArithmeticError]
}

///|
/// Wraps a `Result` as it is, with no check.
pub fn IntervalChecked::from_result(
  inner : Result[@interval.Interval, @def.ArithmeticError],
) -> IntervalChecked {
  { inner, }
}

///|
/// A successful wrapper around `value`, with no check.
pub fn IntervalChecked::ok(value : @interval.Interval) -> IntervalChecked {
  { inner: Ok(value), }
}

///|
/// A failed wrapper that carries `err`.
pub fn IntervalChecked::err(err : @def.ArithmeticError) -> IntervalChecked {
  { inner: Err(err), }
}

///|
/// The interval that contains the integer `value`, in a format of `precision`
/// bits (default 53; `Interval::from_int`). A `precision` outside the legal range
/// gives a failed wrapper.
///
/// ```mbt check
/// test {
///   let x = @interval_checked.IntervalChecked::from_int(7)
///   inspect(x.is_ok(), content="true")
///   inspect(
///     @interval_checked.IntervalChecked::from_int(7, precision=0).is_err(),
///     content="true",
///   )
/// }
/// ```
pub fn IntervalChecked::from_int(
  value : Int32,
  precision~ : Int32 = 53,
) -> IntervalChecked {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) =>
      IntervalChecked::ok(@interval.Interval::from_int(value, precision~))
    Err(error) => IntervalChecked::err(error)
  }
}

///|
/// The interval that contains the integer `value`, negated when `negative` is
/// true (`Interval::from_coefficient`), in a format of `precision` bits (default
/// 53). A `precision` outside the legal range gives a failed wrapper.
pub fn IntervalChecked::from_coefficient(
  value : @binary.BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> IntervalChecked {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) =>
      IntervalChecked::ok(
        @interval.Interval::from_coefficient(value, precision~, negative~),
      )
    Err(error) => IntervalChecked::err(error)
  }
}

///|
/// The interval that contains the `Double` `value`, in a format of `precision`
/// bits (default 53; `Interval::try_from_double`). NaN and the infinities give a
/// failed wrapper with a `DomainError`, as does a `precision` out of range.
pub fn IntervalChecked::from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> IntervalChecked {
  IntervalChecked::from_result(
    @interval.Interval::try_from_double(value, precision~),
  )
}

///|
/// The interval that contains the `Float` `value`, in a format of `precision`
/// bits (default 24; `Interval::try_from_float`). NaN and the infinities give a
/// failed wrapper with a `DomainError`, as does a `precision` out of range.
pub fn IntervalChecked::from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> IntervalChecked {
  IntervalChecked::from_result(
    @interval.Interval::try_from_float(value, precision~),
  )
}

///|
/// The singleton interval of the finite number `value` (`Interval::try_exact`),
/// in a format of `precision` bits (default the precision of `value`). An
/// infinite or NaN `value`, or a `precision` out of range, gives a failed wrapper
/// with a `DomainError`.
pub fn IntervalChecked::exact(
  value : @binary.Binary,
  precision~ : Int32 = value.precision(),
) -> IntervalChecked {
  IntervalChecked::from_result(@interval.Interval::try_exact(value, precision~))
}

///|
/// The interval `[lo, hi]` in a format of `precision` bits (default the larger
/// of the two precisions; `Interval::try_from_bounds`). A NaN bound, `lo` above
/// `hi`, `lo` positive infinity, `hi` negative infinity or a `precision` out of
/// range gives a failed wrapper with a `DomainError`.
pub fn IntervalChecked::from_bounds(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision~ : Int32 = Int32::max(lo.precision(), hi.precision()),
) -> IntervalChecked {
  IntervalChecked::from_result(
    @interval.Interval::try_from_bounds(lo, hi, precision~),
  )
}

///|
/// The whole real line in a format of `precision` bits (default 53). A
/// `precision` out of range gives a failed wrapper.
pub fn IntervalChecked::entire(precision~ : Int32 = 53) -> IntervalChecked {
  match @interval.IntervalContext::try_new(precision~) {
    Ok(_) => IntervalChecked::ok(@interval.Interval::entire(precision~))
    Err(error) => IntervalChecked::err(error)
  }
}

///|
/// The wrapped `Result`: the interval or the first error.
pub fn IntervalChecked::result(
  self : IntervalChecked,
) -> Result[@interval.Interval, @def.ArithmeticError] {
  self.inner
}

///|
/// Whether the wrapper holds an interval.
pub fn IntervalChecked::is_ok(self : IntervalChecked) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// Whether the wrapper holds an error.
pub fn IntervalChecked::is_err(self : IntervalChecked) -> Bool {
  !self.is_ok()
}

///|
/// The error of a failed wrapper, `None` for a success.
pub fn IntervalChecked::error(self : IntervalChecked) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
}

///|
/// Applies `f` to the interval of a successful wrapper; a failed one is returned
/// unchanged and `f` is not called. `f` cannot fail: use `bind` for that.
pub fn IntervalChecked::map(
  self : IntervalChecked,
  f : (@interval.Interval) -> @interval.Interval,
) -> IntervalChecked {
  IntervalChecked::from_result(self.inner.map(f))
}

///|
/// Passes the interval of a successful wrapper to `f`, which may return a failed
/// wrapper; a failed one is returned unchanged and `f` is not called.
pub fn IntervalChecked::bind(
  self : IntervalChecked,
  f : (@interval.Interval) -> IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
pub fn IntervalChecked::normalized(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn IntervalChecked::with_precision(
  self : IntervalChecked,
  precision : Int32,
) -> IntervalChecked {
  self.map(fn(value) { value.with_precision(precision) })
}

///|
/// `sqrt` of the interval part; a directed square root cannot fail.
pub fn IntervalChecked::sqrt(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.sqrt() })
}

///|
/// The square of the interval (`Interval::sqr`); it does not fail.
pub fn IntervalChecked::sqr(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.sqr() })
}

///|
/// `sign` of Table 9.1: a subset of [-1, 1]. Exact, it cannot fail.
pub fn IntervalChecked::sign(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.sign() })
}

///|
/// `ceil` of Table 9.1. Exact, it cannot fail.
pub fn IntervalChecked::ceil(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.ceil() })
}

///|
/// `floor` of Table 9.1. Exact, it cannot fail.
pub fn IntervalChecked::floor(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.floor() })
}

///|
/// `trunc` of Table 9.1. Exact, it cannot fail.
pub fn IntervalChecked::trunc(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.trunc() })
}

///|
/// `roundTiesToEven` of Table 9.1. Exact, it cannot fail.
pub fn IntervalChecked::round_ties_to_even(
  self : IntervalChecked,
) -> IntervalChecked {
  self.map(fn(value) { value.round_ties_to_even() })
}

///|
/// `roundTiesToAway` of Table 9.1. Exact, it cannot fail.
pub fn IntervalChecked::round_ties_to_away(
  self : IntervalChecked,
) -> IntervalChecked {
  self.map(fn(value) { value.round_ties_to_away() })
}

///|
/// `mulRev(b, c, x)` of Table 10.1 on the interval parts; an interval
/// operation never fails, so only an earlier failure is passed on. The prior
/// `x` is optional (default Entire).
pub fn IntervalChecked::mul_rev(
  self : IntervalChecked,
  c : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
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
pub fn IntervalChecked::mul_rev_to_pair(
  self : IntervalChecked,
  c : IntervalChecked,
) -> (IntervalChecked, IntervalChecked) {
  (
    self.bind(fn(b) { c.map(fn(cc) { b.mul_rev_to_pair(cc).0 }) }),
    self.bind(fn(b) { c.map(fn(cc) { b.mul_rev_to_pair(cc).1 }) }),
  )
}

///|
/// `sqrRev(c, x)` of Table 10.1 on the interval part; only an earlier failure
/// is passed on. The prior `x` is optional (default Entire).
pub fn IntervalChecked::sqr_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.sqr_rev(x=p) }) })
    None => self.map(fn(c) { c.sqr_rev() })
  }
}

///|
/// `absRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalChecked::abs_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.abs_rev(x=p) }) })
    None => self.map(fn(c) { c.abs_rev() })
  }
}

///|
/// `coshRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalChecked::cosh_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.cosh_rev(x=p) }) })
    None => self.map(fn(c) { c.cosh_rev() })
  }
}

///|
/// `pownRev(c, x, p)` of Table 10.1; see `sqr_rev`. The prior is the optional
/// last argument.
pub fn IntervalChecked::pown_rev(
  self : IntervalChecked,
  p : Int32,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(q) { c.pown_rev(p, x=q) }) })
    None => self.map(fn(c) { c.pown_rev(p) })
  }
}

///|
/// `sinRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalChecked::sin_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.sin_rev(x=p) }) })
    None => self.map(fn(c) { c.sin_rev() })
  }
}

///|
/// `cosRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalChecked::cos_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.cos_rev(x=p) }) })
    None => self.map(fn(c) { c.cos_rev() })
  }
}

///|
/// `tanRev(c, x)` of Table 10.1; see `sqr_rev`.
pub fn IntervalChecked::tan_rev(
  self : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
  match x {
    Some(prior) => self.bind(fn(c) { prior.map(fn(p) { c.tan_rev(x=p) }) })
    None => self.map(fn(c) { c.tan_rev() })
  }
}

///|
/// `powRev1(b, c, x)` of Table 10.1 on the interval parts; only an earlier failure is
/// passed on. The prior `x` is optional (default Entire).
pub fn IntervalChecked::pow_rev1(
  self : IntervalChecked,
  c : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
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
pub fn IntervalChecked::pow_rev2(
  self : IntervalChecked,
  c : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
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
pub fn IntervalChecked::atan2_rev1(
  self : IntervalChecked,
  c : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
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
pub fn IntervalChecked::atan2_rev2(
  self : IntervalChecked,
  c : IntervalChecked,
  x? : IntervalChecked,
) -> IntervalChecked {
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
pub fn IntervalChecked::from_string(
  s : String,
  precision~ : Int32 = 53,
) -> IntervalChecked {
  IntervalChecked::from_result(@interval.Interval::from_string(s, precision~))
}

///|
pub fn IntervalChecked::recip(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.recip() })
}

///|
pub fn IntervalChecked::min(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.min(rhs) }),
  )
}

///|
pub fn IntervalChecked::max(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.max(rhs) }),
  )
}

///|
/// `x * y + z` with one rounding of the interval operation.
pub fn IntervalChecked::fma(
  self : IntervalChecked,
  factor : IntervalChecked,
  addend : IntervalChecked,
) -> IntervalChecked {
  self.bind(fn(x) { factor.bind(fn(y) { addend.map(fn(z) { x.fma(y, z) }) }) })
}

///|
pub fn IntervalChecked::intersection(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.intersection(rhs)
    }),
  )
}

///|
pub fn IntervalChecked::convex_hull(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.convex_hull(rhs)
    }),
  )
}

///|
pub fn IntervalChecked::cancel_plus(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.cancel_plus(rhs)
    }),
  )
}

///|
pub fn IntervalChecked::cancel_minus(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) {
      lhs.cancel_minus(rhs)
    }),
  )
}

///|
pub fn IntervalChecked::neg(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.neg() })
}

///|
pub fn IntervalChecked::abs(self : IntervalChecked) -> IntervalChecked {
  self.map(fn(value) { value.abs() })
}

///|
/// The sum, rounded outward, at the larger of the two precisions
/// (`Interval::add`). A failed operand gives its error (the left one when both
/// fail); the operation itself does not fail. This is the `+` operator.
///
/// ```mbt check
/// test {
///   let a = @interval_checked.IntervalChecked::from_int(1)
///   let b = @interval_checked.IntervalChecked::from_int(2)
///   inspect((a + b).result().unwrap().to_string(), content="[3, 3]")
/// }
/// ```
pub fn IntervalChecked::add(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
/// The difference, as `add` is the sum (`Interval::sub`). This is the `-`
/// operator.
pub fn IntervalChecked::sub(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
/// The product, as `add` is the sum (`Interval::mul`). This is the `*`
/// operator.
pub fn IntervalChecked::mul(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
/// The quotient, as `add` is the sum (`Interval::div`). Division by zero is not
/// an error: `1 / [0, 0]` is the empty interval and `1 / [-1, 1]` is Entire.
/// This is the `/` operator.
pub fn IntervalChecked::div(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    interval_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs / rhs }),
  )
}

///|
/// The integer power `exponent` of the interval (`PowIntChecked::pow_int_checked`
/// at the precision of the interval). A failed wrapper stays failed.
pub fn IntervalChecked::pown(
  self : IntervalChecked,
  exponent : Int32,
) -> IntervalChecked {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    IntervalChecked::from_result(
      @lf_arith.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
}

///|
/// The root of degree `degree` (`Interval::try_rootn`). A degree of zero gives a
/// failed wrapper with a `DomainError`.
pub fn IntervalChecked::rootn(
  self : IntervalChecked,
  degree : Int32,
) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_rootn(degree)) })
}

///|
/// The exponential of the interval (`Interval::try_exp`). A failed certified
/// function gives a failed wrapper.
pub fn IntervalChecked::exp(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_exp()) })
}

///|
pub fn IntervalChecked::exp2(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_exp2()) })
}

///|
pub fn IntervalChecked::exp10(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_exp10()) })
}

///|
pub fn IntervalChecked::expm1(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_expm1()) })
}

///|
/// The natural logarithm of the interval (`Interval::try_ln`): the part of the
/// interval below zero is dropped, so `ln [-1, 1]` is `[-inf, 0]` and the
/// logarithm of an interval below zero is the empty interval, not an error.
pub fn IntervalChecked::ln(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_ln()) })
}

///|
pub fn IntervalChecked::log2(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_log2()) })
}

///|
pub fn IntervalChecked::log10(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_log10()) })
}

///|
pub fn IntervalChecked::log1p(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_log1p()) })
}

///|
/// The sine of the interval in radians (`Interval::try_sin`); the sine of Entire
/// is `[-1, 1]`.
pub fn IntervalChecked::sin(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_sin()) })
}

///|
pub fn IntervalChecked::cos(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_cos()) })
}

///|
pub fn IntervalChecked::tan(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_tan()) })
}

///|
pub fn IntervalChecked::sinpi(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_sinpi()) })
}

///|
pub fn IntervalChecked::cospi(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_cospi()) })
}

///|
pub fn IntervalChecked::tanpi(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_tanpi()) })
}

///|
pub fn IntervalChecked::asin(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_asin()) })
}

///|
pub fn IntervalChecked::acos(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_acos()) })
}

///|
pub fn IntervalChecked::atan(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_atan()) })
}

///|
pub fn IntervalChecked::sinh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_sinh()) })
}

///|
pub fn IntervalChecked::cosh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_cosh()) })
}

///|
pub fn IntervalChecked::tanh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_tanh()) })
}

///|
pub fn IntervalChecked::asinh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_asinh()) })
}

///|
pub fn IntervalChecked::acosh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_acosh()) })
}

///|
pub fn IntervalChecked::atanh(self : IntervalChecked) -> IntervalChecked {
  self.bind(fn(value) { IntervalChecked::from_result(value.try_atanh()) })
}

///|
pub fn IntervalChecked::hypot(
  self : IntervalChecked,
  other : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    self.inner.bind(fn(left) {
      other.inner.bind(fn(right) { left.try_hypot(right) })
    }),
  )
}

///|
/// `self` raised to `exponent` (`Interval::try_pow`); `[-2, -1]` raised to
/// `[1, 2]` is the empty interval, not an error. A failed
/// operand gives its error (the left one when both fail).
pub fn IntervalChecked::pow(
  self : IntervalChecked,
  exponent : IntervalChecked,
) -> IntervalChecked {
  self.bind(fn(base) {
    exponent.bind(fn(power) {
      IntervalChecked::from_result(base.try_pow(power))
    })
  })
}

///|
pub fn IntervalChecked::atan2(
  self : IntervalChecked,
  abscissa : IntervalChecked,
) -> IntervalChecked {
  IntervalChecked::from_result(
    self.inner.bind(fn(ordinate) {
      abscissa.inner.bind(fn(horizontal) { ordinate.try_atan2(horizontal) })
    }),
  )
}

///|
pub impl Add for IntervalChecked with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for IntervalChecked with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for IntervalChecked with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for IntervalChecked with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for IntervalChecked with fn neg(self) {
  self.neg()
}
