///|
fn complete_decimal_gda(
  value : Decimal,
  context : GdaContext,
  flags : DecimalFlags,
) -> GdaOutcome[Decimal] {
  complete_gda(value, context, flags)
}

///|
fn gda_exact_small_result(
  negative : Bool,
  coefficient : UInt64,
  ctx : GdaContext,
) -> Decimal? {
  guard ctx.extended_ &&
    coefficient > 0UL &&
    coefficient < gda_coeff_small_limit else {
    return None
  }
  let magnitude = GdaCoeff::Small(coefficient)
  let adjusted = magnitude.digits10() - 1
  guard magnitude.digits10() <= ctx.precision_ &&
    adjusted >= ctx.e_min_ &&
    adjusted <= ctx.e_max_ &&
    (!ctx.clamp_ || 0 <= ctx.e_max_ - ctx.precision_ + 1) else {
    return None
  }
  Some(finite_with_exponent_repr(negative, magnitude, 0, ctx.precision_))
}

///|
fn gda_exact_small_sum(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
  subtract_rhs : Bool,
) -> Decimal? {
  guard lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    lhs.exponent10 == 0 &&
    rhs.exponent10 == 0 &&
    gda_coeff_small_value(lhs.coefficient) is Some(left) &&
    gda_coeff_small_value(rhs.coefficient) is Some(right) else {
    return None
  }
  let rhs_negative = rhs.negative != subtract_rhs
  if lhs.negative == rhs_negative {
    let sum = left + right
    guard sum >= left else { return None }
    gda_exact_small_result(lhs.negative, sum, ctx)
  } else if left > right {
    gda_exact_small_result(lhs.negative, left - right, ctx)
  } else if right > left {
    gda_exact_small_result(rhs_negative, right - left, ctx)
  } else {
    None
  }
}

///|
fn gda_exact_small_product(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> Decimal? {
  guard lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    lhs.exponent10 == 0 &&
    rhs.exponent10 == 0 &&
    gda_coeff_small_value(lhs.coefficient) is Some(left) &&
    gda_coeff_small_value(rhs.coefficient) is Some(right) &&
    left > 0UL &&
    right > 0UL &&
    left <= (gda_coeff_small_limit - 1UL) / right else {
    return None
  }
  gda_exact_small_result(lhs.negative != rhs.negative, left * right, ctx)
}

///|
fn gda_exact_small_fma(
  lhs : Decimal,
  rhs : Decimal,
  addend : Decimal,
  ctx : GdaContext,
) -> Decimal? {
  guard lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    addend.class == FpClass::Finite &&
    lhs.exponent10 == 0 &&
    rhs.exponent10 == 0 &&
    addend.exponent10 == 0 &&
    gda_coeff_small_value(lhs.coefficient) is Some(left) &&
    gda_coeff_small_value(rhs.coefficient) is Some(right) &&
    gda_coeff_small_value(addend.coefficient) is Some(extra) &&
    left > 0UL &&
    right > 0UL &&
    left <= (gda_coeff_small_limit - 1UL) / right else {
    return None
  }
  let product = left * right
  let product_negative = lhs.negative != rhs.negative
  if product_negative == addend.negative {
    let sum = product + extra
    guard sum >= product else { return None }
    gda_exact_small_result(product_negative, sum, ctx)
  } else if product > extra {
    gda_exact_small_result(product_negative, product - extra, ctx)
  } else if extra > product {
    gda_exact_small_result(addend.negative, extra - product, ctx)
  } else {
    None
  }
}

///|
fn gda_exact_small_integer_parse(source : String, ctx : GdaContext) -> Decimal? {
  guard source.length() > 0 && source.length() <= 18 && source[0] != '0' else {
    return None
  }
  let magnitude = match gda_coeff_from_decimal_digits_repr(source) {
    Some(GdaCoeff::Small(value)) => value
    _ => return None
  }
  gda_exact_small_result(false, magnitude, ctx)
}

///|
fn gda_completed_exact(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  Completed(value, ctx, GdaFlags::none())
}

///|
pub fn context(
  precision? : Int = 34,
  rounding? : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
) -> GdaContext {
  GdaContext::new(precision~, rounding~, e_min~, e_max~, clamp~, extended~)
}

///|
pub fn decimal32_context() -> GdaContext {
  GdaContext::decimal32()
}

///|
pub fn decimal64_context() -> GdaContext {
  GdaContext::decimal64()
}

///|
pub fn decimal128_context() -> GdaContext {
  GdaContext::decimal128()
}

///|
pub fn parse(source : String, ctx : GdaContext) -> GdaOutcome[Decimal] {
  match gda_exact_small_integer_parse(source, ctx) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (value, flags) = Decimal::from_string_ctx(source, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn add(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  match gda_exact_small_sum(lhs, rhs, ctx, false) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (value, flags) = lhs.add_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn subtract(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  match gda_exact_small_sum(lhs, rhs, ctx, true) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (value, flags) = lhs.sub_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn multiply(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  match gda_exact_small_product(lhs, rhs, ctx) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (value, flags) = lhs.mul_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn divide(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, flags) = lhs.div_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}
