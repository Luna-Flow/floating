///|
fn[A, B, E, C] bin_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
fn[A, B, E, C] bin_result_lift2_checked(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> Result[C, E],
) -> Result[C, E] {
  left.bind(fn(lhs) { right.bind(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub struct BinFloatResult {
  priv inner : Result[@bin_float.BinFloat, @def.ArithmeticError]
}

///|
pub fn BinFloatResult::from_result(
  inner : Result[@bin_float.BinFloat, @def.ArithmeticError],
) -> BinFloatResult {
  { inner, }
}

///|
pub fn BinFloatResult::ok(value : @bin_float.BinFloat) -> BinFloatResult {
  { inner: Ok(value) }
}

///|
pub fn BinFloatResult::err(err : @def.ArithmeticError) -> BinFloatResult {
  { inner: Err(err) }
}

///|
pub fn BinFloatResult::from_int(
  value : Int,
  precision? : Int = 53,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_int(value, precision~))
}

///|
pub fn BinFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision? : Int = 53,
  negative? : Bool = false,
) -> BinFloatResult {
  BinFloatResult::ok(
    @bin_float.BinFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BinFloatResult::from_double(
  value : Double,
  precision? : Int = 53,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_double(value, precision~))
}

///|
pub fn BinFloatResult::from_float(
  value : Float,
  precision? : Int = 24,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_float(value, precision~))
}

///|
pub fn BinFloatResult::result(
  self : BinFloatResult,
) -> Result[@bin_float.BinFloat, @def.ArithmeticError] {
  self.inner
}

///|
pub fn BinFloatResult::map(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> @bin_float.BinFloat,
) -> BinFloatResult {
  BinFloatResult::from_result(self.inner.map(f))
}

///|
pub fn BinFloatResult::bind(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
#deprecated("Use bind instead")
pub fn BinFloatResult::flat_map(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  self.bind(f)
}

///|
pub fn BinFloatResult::normalized(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BinFloatResult::with_precision(
  self : BinFloatResult,
  precision : Int,
  mode : @def.RoundingMode,
) -> BinFloatResult {
  self.map(fn(value) { value.with_precision(precision, mode) })
}

///|
pub fn BinFloatResult::neg(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn BinFloatResult::abs(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn BinFloatResult::ulp(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.ulp() })
}

///|
pub fn BinFloatResult::add(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn BinFloatResult::sub(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn BinFloatResult::mul(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn BinFloatResult::div(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      lhs.div_checked(rhs)
    }),
  )
}

///|
pub fn BinFloatResult::min(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.min(rhs) }),
  )
}

///|
pub fn BinFloatResult::max(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.max(rhs) }),
  )
}

///|
pub fn BinFloatResult::clamp(
  self : BinFloatResult,
  min~ : BinFloatResult,
  max~ : BinFloatResult,
) -> BinFloatResult {
  self.bind(fn(value) {
    min.bind(fn(lo) {
      max.bind(fn(hi) {
        BinFloatResult::from_result(value.clamp_checked(min=lo, max=hi))
      })
    })
  })
}

///|
pub fn BinFloatResult::sqrt(self : BinFloatResult) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::from_result(value.sqrt()) })
}

///|
pub fn BinFloatResult::pow_nat(
  self : BinFloatResult,
  exponent : UInt,
) -> BinFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BinFloatResult::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BinFloatResult::pow_int(
  self : BinFloatResult,
  exponent : Int,
) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::from_result(value.pow_int(exponent)) })
}

///|
pub impl Add for BinFloatResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BinFloatResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BinFloatResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BinFloatResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for BinFloatResult with fn neg(self) {
  self.neg()
}
