///|
pub struct DecimalResult {
  priv inner : Result[@decimal.Decimal, @def.ArithmeticError]
}

///|
pub fn DecimalResult::from_result(
  inner : Result[@decimal.Decimal, @def.ArithmeticError],
) -> DecimalResult {
  { inner, }
}

///|
pub fn DecimalResult::ok(value : @decimal.Decimal) -> DecimalResult {
  { inner: Ok(value) }
}

///|
pub fn DecimalResult::err(err : @def.ArithmeticError) -> DecimalResult {
  { inner: Err(err) }
}

///|
pub fn DecimalResult::parse(
  src : String,
  precision? : Int = 34,
) -> DecimalResult {
  DecimalResult::from_result(@decimal.Decimal::parse(src, precision~))
}

///|
pub fn DecimalResult::from_int(
  value : Int,
  precision? : Int = 34,
) -> DecimalResult {
  DecimalResult::ok(@decimal.Decimal::from_int(value, precision~))
}

///|
pub fn DecimalResult::from_bigint(
  value : BigInt,
  precision? : Int = 34,
) -> DecimalResult {
  DecimalResult::ok(@decimal.Decimal::from_bigint(value, precision~))
}

///|
pub fn DecimalResult::from_double(
  value : Double,
  precision? : Int = 34,
) -> DecimalResult {
  DecimalResult::ok(@decimal.Decimal::from_double(value, precision~))
}

///|
pub fn DecimalResult::from_float(
  value : Float,
  precision? : Int = 34,
) -> DecimalResult {
  DecimalResult::ok(@decimal.Decimal::from_float(value, precision~))
}

///|
pub fn DecimalResult::result(
  self : DecimalResult,
) -> Result[@decimal.Decimal, @def.ArithmeticError] {
  self.inner
}

///|
pub fn DecimalResult::map(
  self : DecimalResult,
  f : (@decimal.Decimal) -> @decimal.Decimal,
) -> DecimalResult {
  match self.inner {
    Ok(value) => DecimalResult::ok(f(value))
    Err(err) => DecimalResult::err(err)
  }
}

///|
pub fn DecimalResult::bind(
  self : DecimalResult,
  f : (@decimal.Decimal) -> DecimalResult,
) -> DecimalResult {
  match self.inner {
    Ok(value) => f(value)
    Err(err) => DecimalResult::err(err)
  }
}

///|
pub fn DecimalResult::flat_map(
  self : DecimalResult,
  f : (@decimal.Decimal) -> DecimalResult,
) -> DecimalResult {
  self.bind(f)
}

///|
fn lift2(
  a : DecimalResult,
  b : DecimalResult,
  f : (@decimal.Decimal, @decimal.Decimal) -> @decimal.Decimal,
) -> DecimalResult {
  match a.inner {
    Err(err) => DecimalResult::err(err)
    Ok(lhs) =>
      match b.inner {
        Err(err) => DecimalResult::err(err)
        Ok(rhs) => DecimalResult::ok(f(lhs, rhs))
      }
  }
}

///|
fn lift2_checked(
  a : DecimalResult,
  b : DecimalResult,
  f : (@decimal.Decimal, @decimal.Decimal) -> Result[
    @decimal.Decimal,
    @def.ArithmeticError,
  ],
) -> DecimalResult {
  match a.inner {
    Err(err) => DecimalResult::err(err)
    Ok(lhs) =>
      match b.inner {
        Err(err) => DecimalResult::err(err)
        Ok(rhs) => DecimalResult::from_result(f(lhs, rhs))
      }
  }
}

///|
pub fn DecimalResult::normalized(self : DecimalResult) -> DecimalResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn DecimalResult::with_precision(
  self : DecimalResult,
  precision : Int,
  mode : @def.RoundingMode,
) -> DecimalResult {
  self.map(fn(value) { value.with_precision(precision, mode) })
}

///|
pub fn DecimalResult::neg(self : DecimalResult) -> DecimalResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn DecimalResult::abs(self : DecimalResult) -> DecimalResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn DecimalResult::add(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2(self, other, fn(lhs, rhs) { lhs + rhs })
}

///|
pub fn DecimalResult::sub(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2(self, other, fn(lhs, rhs) { lhs - rhs })
}

///|
pub fn DecimalResult::mul(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2(self, other, fn(lhs, rhs) { lhs * rhs })
}

///|
pub fn DecimalResult::div(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2_checked(self, other, fn(lhs, rhs) { lhs.div_checked(rhs) })
}

///|
pub fn DecimalResult::min(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2(self, other, fn(lhs, rhs) { lhs.min(rhs) })
}

///|
pub fn DecimalResult::max(
  self : DecimalResult,
  other : DecimalResult,
) -> DecimalResult {
  lift2(self, other, fn(lhs, rhs) { lhs.max(rhs) })
}

///|
pub fn DecimalResult::clamp(
  self : DecimalResult,
  min~ : DecimalResult,
  max~ : DecimalResult,
) -> DecimalResult {
  self.bind(fn(value) {
    min.bind(fn(lo) { max.map(fn(hi) { value.clamp(min=lo, max=hi) }) })
  })
}

///|
pub fn DecimalResult::sqrt(self : DecimalResult) -> DecimalResult {
  self.bind(fn(value) { DecimalResult::from_result(value.sqrt()) })
}

///|
pub fn DecimalResult::pow_nat(
  self : DecimalResult,
  exponent : UInt,
) -> DecimalResult {
  self.bind(fn(value) {
    let ctx = @arithmetic.ArithmeticContext::new(value.precision())
    DecimalResult::from_result(
      @arithmetic.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn DecimalResult::pow_int(
  self : DecimalResult,
  exponent : Int,
) -> DecimalResult {
  self.bind(fn(value) {
    let ctx = @arithmetic.ArithmeticContext::new(value.precision())
    DecimalResult::from_result(
      @arithmetic.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
}

///|
pub impl Add for DecimalResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for DecimalResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for DecimalResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for DecimalResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for DecimalResult with fn neg(self) {
  self.neg()
}
