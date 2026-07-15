///|
pub fn apply(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.apply_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.plus_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.minus_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn abs(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.abs_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
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
pub fn sqrt(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.sqrt_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
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
pub fn quantize(
  value : Decimal,
  quantum : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.quantize(quantum, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn rescale(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.rescale(scale, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn to_integral_exact(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.to_integral_exact(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn to_integral_value(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.to_integral_value(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn exp(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.exp_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn ln(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.ln_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn log10(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.log10_ctx(ctx.mathematical_decimal_context())
  complete_decimal_gda(result, ctx, flags)
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
pub fn reduce(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.reduce_ctx(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.next_plus(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.next_minus(ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_toward(
  value : Decimal,
  target : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.next_toward(target, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn scaleb(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.scaleb_ctx(scale, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn shift(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.shift_ctx(count, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn rotate(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
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
pub fn compare_total(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int] {
  let (result, flags) = lhs.compare_total_ctx(rhs, ctx.decimal_context())
  complete_gda(result, ctx, flags)
}

///|
pub fn compare_total_magnitude(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int] {
  let (result, flags) = lhs.compare_total_magnitude_ctx(
    rhs,
    ctx.decimal_context(),
  )
  complete_gda(result, ctx, flags)
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
pub fn min_mag(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.min_mag_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn max_mag(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.max_mag_ctx(rhs, ctx.decimal_context())
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn same_quantum(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Bool] {
  complete_gda(lhs.same_quantum(rhs), ctx, DecimalFlags::new())
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
