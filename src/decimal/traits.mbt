///|
// Trait implementations for Decimal.

fn contextual_diagnostics(
  flags : DecimalFlags,
) -> @lf_arith.ArithmeticDiagnostics {
  @lf_arith.ArithmeticDiagnostics::new(
    inexact=flags.inexact,
    rounded=flags.rounded,
    overflow=flags.overflow,
    underflow=flags.underflow,
    subnormal=flags.subnormal,
    clamped=flags.clamped,
  )
}

///|
fn contextual_outcome(
  value : Decimal,
  flags : DecimalFlags,
) -> Result[@lf_arith.ArithmeticOutcome[Decimal], @lf_arith.ArithmeticError] {
  if flags.division_by_zero {
    Err(@lf_arith.ArithmeticError::division_by_zero("division by zero"))
  } else if flags.has_error() {
    Err(@lf_arith.ArithmeticError::domain_error("invalid decimal operation"))
  } else {
    Ok(
      @lf_arith.ArithmeticOutcome::with_diagnostics(
        value,
        contextual_diagnostics(flags),
      ),
    )
  }
}

///|
pub impl @lf_arith.AddContextual for Decimal with fn add_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.add_ctx(
    other,
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.SubContextual for Decimal with fn sub_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.sub_ctx(
    other,
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.MulContextual for Decimal with fn mul_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.mul_ctx(
    other,
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.DivContextual for Decimal with fn div_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.div_ctx(
    other,
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.AbsContextual for Decimal with fn abs_contextual(
  self,
  context,
) {
  let (value, flags) = self.abs_ctx(
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.SqrtContextual for Decimal with fn sqrt_contextual(
  self,
  context,
) {
  let (value, flags) = self.sqrt_ctx(
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.ExpContextual for Decimal with fn exp_contextual(
  self,
  context,
) {
  let (value, flags) = self.exp_ctx(
    DecimalContext::from_arithmetic_context(context),
  )
  contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn zero_contextual(
  context,
) {
  Decimal::zero(precision=context.precision)
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn one_contextual(
  context,
) {
  Decimal::one(precision=context.precision)
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn epsilon_contextual(
  context,
) {
  let decimal_context = DecimalContext::from_arithmetic_context(context)
  let one = Decimal::one(precision=context.precision)
  one.next_plus(decimal_context).0.sub_ctx(one, decimal_context).0
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn min_normal_contextual(
  context,
) {
  let exponent = context.e_min.unwrap_or(-999_999_999)
  Decimal::from_string("1E" + exponent.to_string(), precision=context.precision).unwrap()
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn max_finite_contextual(
  context,
) {
  let decimal_context = DecimalContext::from_arithmetic_context(context)
  Decimal::inf(Sign::Positive, precision=context.precision).next_minus(
    decimal_context,
  ).0
}

///|
pub impl @lf_arith.NumericFormatContextual for Decimal with fn classify_contextual(
  self,
) {
  self.classify()
}

///|
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
  guard exponent <= 999_999_999U else {
    return Err(
      @def.ArithmeticError::unsupported(
        "natural exponent exceeds Decimal power range",
      ),
    )
  }
  let dctx = DecimalContext::new(
    precision=ctx.precision,
    rounding=ctx.rounding,
    e_min=-999_999,
    e_max=999_999,
  )
  let exponent_decimal = Decimal::from_bigint(
    BigInt::from_uint(exponent),
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
