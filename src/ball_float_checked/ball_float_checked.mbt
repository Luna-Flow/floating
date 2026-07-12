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
  { inner: Ok(value) }
}

///|
pub fn BallFloatResult::err(err : @def.ArithmeticError) -> BallFloatResult {
  { inner: Err(err) }
}

///|
pub fn BallFloatResult::from_int(
  value : Int,
  precision? : Int = 16,
) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::from_int(value, precision~))
}

///|
pub fn BallFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision? : Int = 16,
  negative? : Bool = false,
) -> BallFloatResult {
  BallFloatResult::ok(
    @ball_float.BallFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BallFloatResult::from_double(
  value : Double,
  precision? : Int = 53,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_double(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_float(
  value : Float,
  precision? : Int = 24,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_float(value, precision~),
  )
}

///|
pub fn BallFloatResult::exact(
  value : @bin_float.BinFloat,
  precision? : Int = value.precision(),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_exact(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision? : Int = Int::max(lo.precision(), hi.precision()),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_bounds(lo, hi, precision~),
  )
}

///|
pub fn BallFloatResult::whole(precision? : Int = 53) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::whole(precision~))
}

///|
pub fn BallFloatResult::result(
  self : BallFloatResult,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  self.inner
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
#deprecated("Use bind instead")
pub fn BallFloatResult::flat_map(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  self.bind(f)
}

///|
pub fn BallFloatResult::normalized(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BallFloatResult::with_precision(
  self : BallFloatResult,
  precision : Int,
  mode : @def.RoundingMode,
) -> BallFloatResult {
  self.map(fn(value) { value.with_precision(precision, mode) })
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
pub fn BallFloatResult::pow_nat(
  self : BallFloatResult,
  exponent : UInt,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BallFloatResult::pow_int(
  self : BallFloatResult,
  exponent : Int,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @lf_arith.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
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
