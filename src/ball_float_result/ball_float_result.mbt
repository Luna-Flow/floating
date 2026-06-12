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
pub fn BallFloatResult::from_bigint(
  value : BigInt,
  precision? : Int = 16,
) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::from_bigint(value, precision~))
}

///|
pub fn BallFloatResult::from_double(
  value : Double,
  precision? : Int = 53,
) -> BallFloatResult {
  let bin = @bin_float.BinFloat::from_double(value, precision~)
  match bin.classify() {
    @arithmetic.FpClass::Finite =>
      BallFloatResult::ok(@ball_float.BallFloat::exact(bin, precision~))
    _ =>
      BallFloatResult::err(
        @arithmetic.ArithmeticError::domain_error("ball source must be finite"),
      )
  }
}

///|
pub fn BallFloatResult::from_float(
  value : Float,
  precision? : Int = 24,
) -> BallFloatResult {
  BallFloatResult::from_double(value.to_double(), precision~)
}

///|
pub fn BallFloatResult::exact(
  value : @bin_float.BinFloat,
  precision? : Int = value.precision(),
) -> BallFloatResult {
  match value.classify() {
    @arithmetic.FpClass::Finite =>
      BallFloatResult::ok(@ball_float.BallFloat::exact(value, precision~))
    _ =>
      BallFloatResult::err(
        @arithmetic.ArithmeticError::domain_error(
          "ball exact source must be finite",
        ),
      )
  }
}

///|
pub fn BallFloatResult::from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision? : Int = Int::max(lo.precision(), hi.precision()),
) -> BallFloatResult {
  match (lo.classify(), hi.classify()) {
    (@arithmetic.FpClass::NaN, _) | (_, @arithmetic.FpClass::NaN) =>
      return BallFloatResult::err(
        @arithmetic.ArithmeticError::domain_error("ball bounds must not be NaN"),
      )
    _ => ()
  }
  guard lo.compare(hi) <= 0 else {
    return BallFloatResult::err(
      @arithmetic.ArithmeticError::domain_error(
        "ball lower bound must not exceed upper bound",
      ),
    )
  }
  BallFloatResult::ok(@ball_float.BallFloat::from_bounds(lo, hi, precision~))
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
  match self.inner {
    Ok(value) => BallFloatResult::ok(f(value))
    Err(err) => BallFloatResult::err(err)
  }
}

///|
pub fn BallFloatResult::bind(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  match self.inner {
    Ok(value) => f(value)
    Err(err) => BallFloatResult::err(err)
  }
}

///|
pub fn BallFloatResult::flat_map(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  self.bind(f)
}

///|
fn lift2(
  a : BallFloatResult,
  b : BallFloatResult,
  f : (@ball_float.BallFloat, @ball_float.BallFloat) -> @ball_float.BallFloat,
) -> BallFloatResult {
  match a.inner {
    Err(err) => BallFloatResult::err(err)
    Ok(lhs) =>
      match b.inner {
        Err(err) => BallFloatResult::err(err)
        Ok(rhs) => BallFloatResult::ok(f(lhs, rhs))
      }
  }
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
  lift2(self, other, fn(lhs, rhs) { lhs + rhs })
}

///|
pub fn BallFloatResult::sub(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs - rhs })
}

///|
pub fn BallFloatResult::mul(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs * rhs })
}

///|
pub fn BallFloatResult::div(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  lift2(self, other, fn(lhs, rhs) { lhs / rhs })
}

///|
pub fn BallFloatResult::pow_nat(
  self : BallFloatResult,
  exponent : UInt,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @arithmetic.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @arithmetic.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BallFloatResult::pow_int(
  self : BallFloatResult,
  exponent : Int,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @arithmetic.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @arithmetic.PowIntChecked::pow_int_checked(value, exponent, ctx),
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
