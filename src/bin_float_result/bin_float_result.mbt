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
pub fn BinFloatResult::from_bigint(
  value : BigInt,
  precision? : Int = 53,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_bigint(value, precision~))
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
  match self.inner {
    Ok(value) => BinFloatResult::ok(f(value))
    Err(err) => BinFloatResult::err(err)
  }
}

///|
pub fn BinFloatResult::bind(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  match self.inner {
    Ok(value) => f(value)
    Err(err) => BinFloatResult::err(err)
  }
}

///|
pub fn BinFloatResult::flat_map(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  self.bind(f)
}

///|
fn lift2(
  a : BinFloatResult,
  b : BinFloatResult,
  f : (@bin_float.BinFloat, @bin_float.BinFloat) -> @bin_float.BinFloat,
) -> BinFloatResult {
  match a.inner {
    Err(err) => BinFloatResult::err(err)
    Ok(lhs) =>
      match b.inner {
        Err(err) => BinFloatResult::err(err)
        Ok(rhs) => BinFloatResult::ok(f(lhs, rhs))
      }
  }
}

///|
fn lift2_checked(
  a : BinFloatResult,
  b : BinFloatResult,
  f : (@bin_float.BinFloat, @bin_float.BinFloat) -> Result[
    @bin_float.BinFloat,
    @def.ArithmeticError,
  ],
) -> BinFloatResult {
  match a.inner {
    Err(err) => BinFloatResult::err(err)
    Ok(lhs) =>
      match b.inner {
        Err(err) => BinFloatResult::err(err)
        Ok(rhs) => BinFloatResult::from_result(f(lhs, rhs))
      }
  }
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
  lift2(self, other, fn(lhs, rhs) { lhs + rhs })
}

///|
pub fn BinFloatResult::sub(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs - rhs })
}

///|
pub fn BinFloatResult::mul(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs * rhs })
}

///|
pub fn BinFloatResult::div(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  lift2_checked(self, other, fn(lhs, rhs) { lhs.div_checked(rhs) })
}

///|
pub fn BinFloatResult::min(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs.min(rhs) })
}

///|
pub fn BinFloatResult::max(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs.max(rhs) })
}

///|
pub fn BinFloatResult::clamp(
  self : BinFloatResult,
  min~ : BinFloatResult,
  max~ : BinFloatResult,
) -> BinFloatResult {
  self.bind(fn(value) {
    min.bind(fn(lo) { max.map(fn(hi) { value.clamp(min=lo, max=hi) }) })
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
    let ctx = @arithmetic.ArithmeticContext::new(value.precision())
    BinFloatResult::from_result(
      @arithmetic.PowNatChecked::pow_nat_checked(value, exponent, ctx),
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
