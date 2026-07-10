///|
// Trait implementations for Decimal.

pub impl @lf_arith.ParseChecked for Decimal with fn parse_checked(src, ctx) {
  Decimal::parse(src, precision=ctx.precision)
}

///|
pub impl @lf_arith.DivChecked for Decimal with fn div_checked(self, other, ctx) {
  let dctx = DecimalContext::from_arithmetic_context(ctx)
  let (value, flags) = self.div_ctx(other, dctx)
  if flags.division_by_zero {
    Err(@def.ArithmeticError::division_by_zero("division by zero"))
  } else if flags.division_undefined || flags.invalid_operation {
    Err(@def.ArithmeticError::domain_error("invalid decimal division"))
  } else {
    Ok(value)
  }
}

///|
pub impl @lf_arith.CompareChecked for Decimal with fn compare_checked(
  self,
  other,
) {
  self.compare_checked(other)
}

///|
pub impl @lf_arith.SqrtChecked for Decimal with fn sqrt_checked(self, ctx) {
  let dctx = DecimalContext::from_arithmetic_context(ctx)
  let (value, flags) = self.sqrt_ctx(dctx)
  if flags.invalid_operation {
    Err(
      @def.ArithmeticError::domain_error("sqrt requires a non-negative value"),
    )
  } else {
    Ok(value)
  }
}

///|
pub impl @lf_arith.PowNatChecked for Decimal with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  let dctx = DecimalContext::new(
    precision=ctx.precision,
    rounding=ctx.rounding,
    e_min=-999_999,
    e_max=999_999,
  )
  let exponent_decimal = Decimal::from_int(
    exponent.reinterpret_as_int(),
    precision=ctx.precision,
  )
  let (value, flags) = self.power_ctx(exponent_decimal, dctx)
  if flags.division_by_zero {
    Err(
      @def.ArithmeticError::division_by_zero(
        "negative exponent requires a non-zero base",
      ),
    )
  } else if flags.invalid_operation || flags.invalid_context {
    Err(@def.ArithmeticError::domain_error("invalid decimal power"))
  } else {
    Ok(value)
  }
}

///|
pub impl @lf_arith.PowIntChecked for Decimal with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  if exponent < 0 && self.classify() == FpClass::Finite && self.is_zero() {
    return Err(
      @def.ArithmeticError::division_by_zero(
        "negative exponent requires a non-zero base",
      ),
    )
  }
  let dctx = DecimalContext::new(
    precision=ctx.precision,
    rounding=ctx.rounding,
    e_min=-999_999,
    e_max=999_999,
  )
  let exponent_decimal = Decimal::from_int(exponent, precision=ctx.precision)
  let (value, flags) = self.power_ctx(exponent_decimal, dctx)
  if flags.division_by_zero {
    Err(
      @def.ArithmeticError::division_by_zero(
        "negative exponent requires a non-zero base",
      ),
    )
  } else if flags.invalid_operation || flags.invalid_context {
    Err(@def.ArithmeticError::domain_error("invalid decimal power"))
  } else {
    Ok(value)
  }
}

///|
pub impl NatHomomorphism for Decimal

///|
pub impl IntegralHomomorphism for Decimal

///|
pub impl NatHomomorphism for Decimal with fn[S : @lf_alg.Nat] from_nat(
  value : S,
) -> Decimal {
  Decimal::from_bigint(@lf_alg.Integral::normalize(value)).normalized()
}

///|
pub impl IntegralHomomorphism for Decimal with fn[S : @lf_alg.Integral] from_integral(
  value : S,
) -> Decimal {
  Decimal::from_bigint(@lf_alg.Integral::normalize(value)).normalized()
}

///|
pub impl Eq for Decimal with fn equal(self, other) {
  match (self.class, other.class) {
    (FpClass::NaN, FpClass::NaN) => true
    (FpClass::NaN, _) | (_, FpClass::NaN) => false
    (FpClass::Infinity, FpClass::Infinity) => self.negative == other.negative
    (FpClass::Infinity, _) | (_, FpClass::Infinity) => false
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other) == 0
  }
}

///|
pub impl Zero for Decimal with fn zero() {
  Decimal::zero()
}

///|
pub impl One for Decimal with fn one() {
  Decimal::one()
}

///|
pub impl AddMonoid for Decimal

///|
pub impl MulMonoid for Decimal

///|
pub impl AddGroup for Decimal

///|
pub impl Semiring for Decimal

///|
pub impl Ring for Decimal

///|
pub impl Add for Decimal with fn add(self, other) {
  add_decimal_impl(self, other)
}

///|
pub impl Sub for Decimal with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for Decimal with fn mul(self, other) {
  mul_decimal_impl(self, other)
}

///|
pub impl Div for Decimal with fn div(self, other) {
  div_decimal_impl(self, other)
}

///|
pub impl Neg for Decimal with fn neg(self) {
  self.neg()
}

///|
pub impl Compare for Decimal with fn compare(self, other) {
  self.compare(other)
}

///|
pub impl @def.Floating for Decimal with fn classify(self) {
  self.classify()
}

///|
pub impl @def.Floating for Decimal with fn sign(self) {
  self.sign()
}

///|
pub impl @def.Floating for Decimal with fn precision(self) {
  self.precision()
}

///|
pub impl @def.Floating for Decimal with fn with_precision(self, precision, mode) {
  self.with_precision(precision, mode)
}

///|
pub impl @def.Floating for Decimal with fn normalized(self) {
  self.normalized()
}

///|
