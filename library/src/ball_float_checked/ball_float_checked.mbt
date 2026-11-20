///|
fn[A, B, E, C] ball_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub struct BallFloatResult {
  priv inner : Result[@ball_float.BallFloat, @def.ArithmeticError]
}

///|
pub fn BallFloatResult::from_result(
  inner : Result[@ball_float.BallFloat, @def.ArithmeticError],
) -> BallFloatResult {
  { inner, }
}

///|
pub fn BallFloatResult::ok(value : @ball_float.BallFloat) -> BallFloatResult {
  { inner: Ok(value), }
}

///|
pub fn BallFloatResult::err(err : @def.ArithmeticError) -> BallFloatResult {
  { inner: Err(err), }
}

///|
pub fn BallFloatResult::from_int(
  value : Int32,
  precision~ : Int32 = 16,
) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::from_int(value, precision~))
}

///|
pub fn BallFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision~ : Int32 = 16,
  negative~ : Bool = false,
) -> BallFloatResult {
  BallFloatResult::ok(
    @ball_float.BallFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BallFloatResult::from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_double(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_float(value, precision~),
  )
}

///|
pub fn BallFloatResult::exact(
  value : @bin_float.BinFloat,
  precision~ : Int32 = value.precision(),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_exact(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision~ : Int32 = Int32::max(lo.precision(), hi.precision()),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_bounds(lo, hi, precision~),
  )
}

///|
pub fn BallFloatResult::entire(precision~ : Int32 = 53) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::entire(precision~))
}

///|
pub fn BallFloatResult::result(
  self : BallFloatResult,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  self.inner
}

///|
pub fn BallFloatResult::is_ok(self : BallFloatResult) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub fn BallFloatResult::is_err(self : BallFloatResult) -> Bool {
  !self.is_ok()
}

///|
pub fn BallFloatResult::error(self : BallFloatResult) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
}

///|
pub fn BallFloatResult::map(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> @ball_float.BallFloat,
) -> BallFloatResult {
  BallFloatResult::from_result(self.inner.map(f))
}

///|
pub fn BallFloatResult::bind(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
pub fn BallFloatResult::normalized(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BallFloatResult::with_precision(
  self : BallFloatResult,
  precision : Int32,
) -> BallFloatResult {
  self.map(fn(value) { value.with_precision(precision) })
}

///|
pub fn BallFloatResult::neg(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn BallFloatResult::abs(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn BallFloatResult::add(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn BallFloatResult::sub(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn BallFloatResult::mul(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn BallFloatResult::div(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs / rhs }),
  )
}

///|
pub fn BallFloatResult::pown(
  self : BallFloatResult,
  exponent : Int32,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @lf_arith.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BallFloatResult::rootn(
  self : BallFloatResult,
  degree : Int32,
) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_rootn(degree)) })
}

///|
pub fn BallFloatResult::exp(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_exp()) })
}

///|
pub fn BallFloatResult::exp2(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_exp2()) })
}

///|
pub fn BallFloatResult::exp10(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_exp10()) })
}

///|
pub fn BallFloatResult::expm1(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_expm1()) })
}

///|
pub fn BallFloatResult::ln(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_ln()) })
}

///|
pub fn BallFloatResult::log2(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_log2()) })
}

///|
pub fn BallFloatResult::log10(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_log10()) })
}

///|
pub fn BallFloatResult::log1p(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_log1p()) })
}

///|
pub fn BallFloatResult::sin(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_sin()) })
}

///|
pub fn BallFloatResult::cos(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_cos()) })
}

///|
pub fn BallFloatResult::tan(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_tan()) })
}

///|
pub fn BallFloatResult::sinpi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_sinpi()) })
}

///|
pub fn BallFloatResult::cospi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_cospi()) })
}

///|
pub fn BallFloatResult::tanpi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_tanpi()) })
}

///|
pub fn BallFloatResult::asin(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_asin()) })
}

///|
pub fn BallFloatResult::acos(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_acos()) })
}

///|
pub fn BallFloatResult::atan(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_atan()) })
}

///|
pub fn BallFloatResult::sinh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_sinh()) })
}

///|
pub fn BallFloatResult::cosh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_cosh()) })
}

///|
pub fn BallFloatResult::tanh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_tanh()) })
}

///|
pub fn BallFloatResult::asinh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_asinh()) })
}

///|
pub fn BallFloatResult::acosh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_acosh()) })
}

///|
pub fn BallFloatResult::atanh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_atanh()) })
}

///|
pub fn BallFloatResult::hypot(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    self.inner.bind(fn(left) {
      other.inner.bind(fn(right) { left.try_hypot(right) })
    }),
  )
}

///|
pub fn BallFloatResult::pow(
  self : BallFloatResult,
  exponent : BallFloatResult,
) -> BallFloatResult {
  self.bind(fn(base) {
    exponent.bind(fn(power) {
      BallFloatResult::from_result(base.try_pow(power))
    })
  })
}

///|
pub fn BallFloatResult::atan2(
  self : BallFloatResult,
  abscissa : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    self.inner.bind(fn(ordinate) {
      abscissa.inner.bind(fn(horizontal) { ordinate.try_atan2(horizontal) })
    }),
  )
}

///|
pub impl Add for BallFloatResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BallFloatResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BallFloatResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BallFloatResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for BallFloatResult with fn neg(self) {
  self.neg()
}
