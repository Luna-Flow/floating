///|
fn complete_decimal_gda(
  value : Decimal,
  context : GdaContext,
  flags : DecimalFlags,
) -> GdaOutcome[Decimal] {
  if context.extended_ {
    complete_gda(value, context, flags)
  } else {
    complete_gda_subset(value, context, flags, false)
  }
}

///|
/// Operand rounding of a subset context (GDA 1.70, page 56, Appendix A,
/// "Operation differences", first item): an operand with more digits than the
/// precision is rounded to precision digits before use, with the conditions that
/// the rounding raises (Lost digits when non-zero digits go). An extended
/// context returns the operand as it is.
fn gda_prepare_operand(
  value : Decimal,
  ctx : GdaContext,
) -> (Decimal, DecimalFlags) {
  if ctx.extended_ {
    (value, DecimalFlags::new())
  } else {
    prepare_operand_for_context(value, ctx.decimal_context())
  }
}

///|
fn gda_prepare_operands(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> (Decimal, Decimal, DecimalFlags) {
  if ctx.extended_ {
    (lhs, rhs, DecimalFlags::new())
  } else {
    prepare_binary_operands_for_context(lhs, rhs, ctx.decimal_context())
  }
}

///|
fn complete_gda_subset(
  value : Decimal,
  context : GdaContext,
  flags : DecimalFlags,
  keep_exponent : Bool,
) -> GdaOutcome[Decimal] {
  let (value, flags) = gda_subset_result(value, flags, context, keep_exponent)
  complete_gda(value, context, flags)
}

///|
/// `complete_decimal_gda` for `quantize`, `rescale` and `to_number`: the result
/// keeps the exponent of a zero and a positive exponent (GDA 1.70, page 55:
/// "unless the operation is quantize"); a zero is still of sign 0.
fn complete_decimal_gda_keep_exponent(
  value : Decimal,
  context : GdaContext,
  flags : DecimalFlags,
) -> GdaOutcome[Decimal] {
  if context.extended_ {
    complete_gda(value, context, flags)
  } else {
    complete_gda_subset(value, context, flags, true)
  }
}

///|
/// The last step of every operation in a subset context (`extended=false`), the
/// three result rules of GDA 1.70, page 55 (Appendix A, The X3.274 subset):
/// a subnormal result is not permitted and becomes the zero of the subset with
/// the conditions of an underflow (as `multiply` has always given), a zero has
/// sign 0 and exponent 0, and a positive exponent is reduced to 0 when the
/// coefficient then has at most precision digits. With `keep_exponent` (quantize)
/// the last two stop at the sign of a zero. The functions that apply the rules
/// in the operation itself (`add`, `divide`) meet the rules again here and
/// leave their result as it is.
fn gda_subset_result(
  value : Decimal,
  flags : DecimalFlags,
  context : GdaContext,
  keep_exponent : Bool,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else { return (value, flags) }
  if !value.coefficient.is_zero() &&
    adjusted_exponent64(value) < context.e_min_.to_int64() {
    let zero = Decimal::zero_raw(precision=value.precision_)
    let underflow = {
      ..flags,
      underflow: true,
      subnormal: true,
      inexact: true,
      rounded: true,
      clamped: false,
    }
    return (zero, underflow)
  }
  if keep_exponent {
    if value.coefficient.is_zero() && value.negative {
      (
        finite_with_exponent_repr(
          false,
          value.coefficient,
          value.exponent10,
          value.precision_,
        ),
        flags,
      )
    } else {
      (value, flags)
    }
  } else {
    (finish_subset_finite_result(value, context.decimal_, false), flags)
  }
}

///|
/// `complete_decimal_gda` for `next_plus` and `next_minus` in a subset context: rule S of
/// page 55 still turns a subnormal next number into 0, but the flags of the operation stay
/// as they were, because page 34 says that no flags are set for a numeric operand.
fn complete_decimal_gda_next(
  value : Decimal,
  context : GdaContext,
  flags : DecimalFlags,
) -> GdaOutcome[Decimal] {
  let (result, _) = gda_subset_result(value, flags, context, false)
  complete_gda(result, context, flags)
}

///|
fn gda_exact_small_result(
  negative : Bool,
  coefficient : UInt64,
  ctx : GdaContext,
) -> Decimal? {
  guard ctx.extended_ &&
    coefficient > 0UL &&
    coefficient < dec_coeff_small_limit else {
    return None
  }
  let magnitude = DecCoeff::Small(coefficient)
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
    dec_coeff_small_value(lhs.coefficient) is Some(left) &&
    dec_coeff_small_value(rhs.coefficient) is Some(right) else {
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
    dec_coeff_small_value(lhs.coefficient) is Some(left) &&
    dec_coeff_small_value(rhs.coefficient) is Some(right) &&
    left > 0UL &&
    right > 0UL &&
    left <= (dec_coeff_small_limit - 1UL) / right else {
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
    dec_coeff_small_value(lhs.coefficient) is Some(left) &&
    dec_coeff_small_value(rhs.coefficient) is Some(right) &&
    dec_coeff_small_value(addend.coefficient) is Some(extra) &&
    left > 0UL &&
    right > 0UL &&
    left <= (dec_coeff_small_limit - 1UL) / right else {
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
  let magnitude = match dec_coeff_from_decimal_digits_repr(source) {
    Some(DecCoeff::Small(value)) => value
    _ => return None
  }
  gda_exact_small_result(false, magnitude, ctx)
}

///|
fn gda_completed_exact(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  Completed(value, ctx, GdaFlags::new())
}

///|
pub fn to_number(source : String, ctx : GdaContext) -> GdaOutcome[Decimal] {
  match gda_exact_small_integer_parse(source, ctx) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (value, flags) = Decimal::from_string_ctx(source, ctx.decimal_context())
  complete_decimal_gda_keep_exponent(value, ctx, flags)
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
  match gda_fast_sum(lhs, rhs, ctx, false) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_fast_wide_sum(lhs, rhs, ctx, false) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_add_plain(lhs, rhs, ctx, false) {
    Some(outcome) => return outcome
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
  match gda_fast_sum(lhs, rhs, ctx, true) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_fast_wide_sum(lhs, rhs, ctx, true) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_add_plain(lhs, rhs, ctx, true) {
    Some(outcome) => return outcome
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
  match gda_fast_product(lhs, rhs, ctx) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_mul_plain(lhs, rhs, ctx) {
    Some(outcome) => return outcome
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
  match gda_fast_quotient(lhs, rhs, ctx) {
    Some(outcome) => return outcome
    None => ()
  }
  match gda_div_plain(lhs, rhs, ctx) {
    Some(outcome) => return outcome
    None => ()
  }
  let (value, flags) = lhs.div_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(value, ctx, flags)
}
