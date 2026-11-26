///|
pub fn apply(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return apply_subset(value, ctx)
  }
  let (result, flags) = value.apply_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Rounds the value to the context, as `0 + x`. The ideal exponent is that of
/// the operand. `plus(-0)` is -0 under `Floor` and +0 otherwise, and a zero
/// result is +0 in a subset context.
pub fn plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.plus_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Rounds the negated value to the context, as `0 - x`. The ideal exponent is
/// that of the operand. `minus(0)` is -0 under `Floor` and +0 otherwise, and a
/// zero result is +0 in a subset context.
pub fn minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.minus_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Rounds the absolute value to the context. The ideal exponent is that of the
/// operand; the absolute value of either zero is +0.
pub fn abs(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.abs_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Computes `a * b + c` with a single rounding: the product is exact and only
/// the sum is rounded. The ideal exponent is that of `add` applied to the exact
/// product and `c`. It is invalid in a subset context (`extended=false`).
pub fn fma(
  lhs : Decimal,
  rhs : Decimal,
  addend : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  match gda_exact_small_fma(lhs, rhs, addend, ctx) {
    Some(value) => return gda_completed_exact(value, ctx)
    None => ()
  }
  let (result, flags) = lhs.fma_ctx(rhs, addend, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Returns the square root, correctly rounded half even whatever the rounding of
/// the context. A perfect square is exact, with the ideal exponent `floor(q / 2)`.
/// A negative number is invalid; `sqrt(+inf)` is `+inf`.
pub fn sqrt(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ && gda_operand_is_long(value, ctx) {
    return sqrt_subset(value, ctx)
  }
  let (result, flags) = value.sqrt_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// `sqrt` in a subset context: the operand is rounded first with the algorithm of
/// the context, not that of the mathematical context (GDA 1.70, page 56).
fn sqrt_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.sqrt_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
pub fn divide_integer(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.divide_integer(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn remainder(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.remainder(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn remainder_near(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.remainder_near(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Returns the first value with the exponent of the second, rounded with the
/// rounding of the context; only the exponent of the second operand counts.
/// Dropped digits raise `Rounded`, and `Inexact` when one of them is not zero.
///
/// The result is NaN and invalid when the target exponent lies outside
/// `[e_min - precision + 1, e_max]`, when the coefficient would need more than
/// `precision` digits, or when exactly one operand is infinite. Two infinities
/// give the infinity. In a clamped context a target exponent above
/// `e_max - precision + 1` gives a result with exponent `e_max - precision + 1`.
/// A subnormal result raises `Subnormal` but not `Underflow`.
pub fn quantize(
  value : Decimal,
  quantum : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.quantize(quantum, ctx.decimal_context())
  complete_decimal_gda_keep_exponent(result, ctx, flags)
}

///|
pub fn rescale(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.rescale(scale, ctx.decimal_context())
  complete_decimal_gda_keep_exponent(result, ctx, flags)
}

///|
pub fn round_to_integral_exact(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return round_to_integral_exact_subset(value, ctx)
  }
  let (result, flags) = value.to_integral_exact(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn round_to_integral_value(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return round_to_integral_value_subset(value, ctx)
  }
  let (result, flags) = value.to_integral_value(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Returns `e` raised to the value. `exp(0)` is 1, `exp(+inf)` is `+inf` and `exp(-inf)`
/// is 0. Any other finite result is inexact. A computed result is correctly
/// rounded half even whatever the rounding of the context.
///
/// A context beyond the implementation limit of `exp`, `ln`, `log10` and `power`
/// (`precision` above 999999, `e_max` above 999999 or `e_min` below -999999)
/// gives NaN with `invalid_context`. When the refinement limit of the context
/// stops the evaluation, the result is NaN with `invalid_operation` and
/// `try_exp` returns `Err`.
pub fn exp(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ && gda_operand_is_long(value, ctx) {
    return exp_subset(value, ctx)
  }
  let (result, flags) = value.exp_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// `exp` in a subset context: the operand is rounded first with the algorithm of
/// the context, not that of the mathematical context (GDA 1.70, page 56).
fn exp_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.exp_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// Returns the natural logarithm, correctly rounded half even whatever the
/// rounding of the context when it is computed. `ln(1)` is 0, `ln(+inf)` is `+inf`, and `ln(0)` is
/// `-inf` in an extended context (it is invalid in a subset context) with no
/// condition raised. A negative number is invalid. The implementation limit of
/// `exp` applies (NaN with `invalid_context`); when the refinement limit stops
/// the evaluation the result is NaN with `invalid_operation` and `try_ln`
/// returns `Err`.
pub fn ln(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ && gda_operand_is_long(value, ctx) {
    return ln_subset(value, ctx)
  }
  let (result, flags) = value.ln_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// `ln` in a subset context: the operand is rounded first with the algorithm of
/// the context, not that of the mathematical context (GDA 1.70, page 56).
fn ln_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.ln_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
pub fn log10(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ && gda_operand_is_long(value, ctx) {
    return log10_subset(value, ctx)
  }
  let (result, flags) = value.log10_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// `log10` in a subset context: the operand is rounded first with the algorithm of
/// the context, not that of the mathematical context (GDA 1.70, page 56).
fn log10_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.log10_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
pub fn power(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.power_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Rounds the value to the context and removes its trailing zeros: `1200` gives
/// `1.2E+3`. A zero becomes 0 with exponent 0, keeping its sign in an extended
/// context. In a clamped context the exponent is not raised above
/// `e_max - precision + 1`.
pub fn reduce(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return reduce_subset(value, ctx)
  }
  let (result, flags) = value.reduce_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return next_plus_subset(value, ctx)
  }
  let (result, flags) = value.next_plus(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return next_minus_subset(value, ctx)
  }
  let (result, flags) = value.next_minus(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_toward(
  value : Decimal,
  target : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return next_toward_subset(value, target, ctx)
  }
  let (result, flags) = value.next_toward(target, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn scaleb(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return scaleb_subset(value, scale, ctx)
  }
  let (result, flags) = value.scaleb_ctx(scale, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn shift(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return shift_subset(value, count, ctx)
  }
  let (result, flags) = value.shift_ctx(count, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn rotate(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  if !ctx.extended_ {
    return rotate_subset(value, count, ctx)
  }
  let (result, flags) = value.rotate_ctx(count, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_and(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.logical_and(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_or(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.logical_or(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_xor(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.logical_xor(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_invert(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.logical_invert(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
/// Compares two values by value (`-0 = +0`, `2.50 = 2.5`) and returns the
/// decimal -1, 0 or 1. A NaN operand gives a quiet NaN; `InvalidOperation` is
/// raised only for a signaling NaN (`compare_signal` raises it for any NaN). Use
/// `compare_total` to order representations.
pub fn compare(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.compare_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn compare_signal(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.compare_signal_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logb(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.logb_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn min(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.min_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn max(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.max_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn min_magnitude(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.min_magnitude_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn max_magnitude(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.max_magnitude_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn class_name(value : Decimal, ctx : GdaContext) -> GdaOutcome[String] {
  complete_gda(
    value.class_name(ctx.decimal_context()),
    ctx,
    DecimalFlags::new(),
  )
}

///|
pub fn is_normal(value : Decimal, ctx : GdaContext) -> GdaOutcome[Bool] {
  complete_gda(value.is_normal(ctx.decimal_context()), ctx, DecimalFlags::new())
}

///|
pub fn is_subnormal(value : Decimal, ctx : GdaContext) -> GdaOutcome[Bool] {
  complete_gda(
    value.is_subnormal(ctx.decimal_context()),
    ctx,
    DecimalFlags::new(),
  )
}

///|
/// `exp` that returns `Err` when the library could not certify the result,
/// where `exp` reports `invalid_context`.
pub fn try_exp(
  value : Decimal,
  ctx : GdaContext,
) -> Result[GdaOutcome[Decimal], @def.ArithmeticError] {
  value
  .try_exp_ctx(ctx.mathematical_decimal_context())
  .map(fn(r) { complete_decimal_gda(r.0, ctx, r.1) })
}

///|
/// `ln` that returns `Err` when the library could not certify the result,
/// where `ln` reports `invalid_context`.
pub fn try_ln(
  value : Decimal,
  ctx : GdaContext,
) -> Result[GdaOutcome[Decimal], @def.ArithmeticError] {
  value
  .try_ln_ctx(ctx.mathematical_decimal_context())
  .map(fn(r) { complete_decimal_gda(r.0, ctx, r.1) })
}

///|
/// `log10` that returns `Err` when the library could not certify the result,
/// where `log10` reports `invalid_context`.
pub fn try_log10(
  value : Decimal,
  ctx : GdaContext,
) -> Result[GdaOutcome[Decimal], @def.ArithmeticError] {
  value
  .try_log10_ctx(ctx.mathematical_decimal_context())
  .map(fn(r) { complete_decimal_gda(r.0, ctx, r.1) })
}

///|
/// `power` that returns `Err` when the library could not certify the result,
/// where `power` reports `invalid_context`.
pub fn try_power(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> Result[GdaOutcome[Decimal], @def.ArithmeticError] {
  lhs
  .try_power_ctx(rhs, ctx.decimal_context())
  .map(fn(r) { complete_decimal_gda(r.0, ctx, r.1) })
}

///|
pub fn compare_total(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int32] {
  let (result, flags) = lhs.compare_total_ctx(rhs, ctx.decimal_context())
  complete_gda(result, ctx, flags)
}

///|
pub fn compare_total_magnitude(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int32] {
  let (result, flags) = lhs.compare_total_magnitude_ctx(
    rhs,
    ctx.decimal_context(),
  )
  complete_gda(result, ctx, flags)
}

///|
/// `apply` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn apply_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.apply_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `reduce` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn reduce_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.reduce_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `round_to_integral_exact` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn round_to_integral_exact_subset(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.to_integral_exact(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `round_to_integral_value` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn round_to_integral_value_subset(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.to_integral_value(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `next_plus` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn next_plus_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.next_plus(ctx.decimal_context())
  complete_decimal_gda_next(result, ctx, flags.combine(operand_flags))
}

///|
/// `next_minus` in a subset context: the operand is rounded first (GDA 1.70, page 56).
fn next_minus_subset(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = value.next_minus(ctx.decimal_context())
  complete_decimal_gda_next(result, ctx, flags.combine(operand_flags))
}

///|
/// `next_toward` in a subset context: the operands are rounded first (GDA 1.70, page 56).
fn next_toward_subset(
  value : Decimal,
  target : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, target, operand_flags) = gda_prepare_operands(value, target, ctx)
  let (result, flags) = value.next_toward(target, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `scaleb` in a subset context: the operands are rounded first (GDA 1.70, page 56).
fn scaleb_subset(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, scale, operand_flags) = gda_prepare_operands(value, scale, ctx)
  let (result, flags) = value.scaleb_ctx(scale, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `shift` in a subset context: the operands are rounded first (GDA 1.70, page 56).
fn shift_subset(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, count, operand_flags) = gda_prepare_operands(value, count, ctx)
  let (result, flags) = value.shift_ctx(count, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// `rotate` in a subset context: the operands are rounded first (GDA 1.70, page 56).
fn rotate_subset(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, count, operand_flags) = gda_prepare_operands(value, count, ctx)
  let (result, flags) = value.rotate_ctx(count, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
/// Whether a finite operand has more digits than the precision, so that a subset
/// context rounds it before use (GDA 1.70, page 56).
fn gda_operand_is_long(value : Decimal, ctx : GdaContext) -> Bool {
  value.class == FpClass::Finite &&
  ctx.precision_ > 0 &&
  value.coefficient.digits10() > ctx.precision_
}
