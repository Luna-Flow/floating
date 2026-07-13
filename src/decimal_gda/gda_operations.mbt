///|
pub fn apply(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.apply_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.plus_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.minus_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn abs(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.abs_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn fma(
  lhs : Decimal,
  rhs : Decimal,
  addend : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.fma_ctx(rhs.inner, addend.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn sqrt(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.sqrt_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn divide_integer(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.divide_integer(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn remainder(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.remainder(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn remainder_near(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.remainder_near(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn quantize(
  value : Decimal,
  quantum : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.quantize(quantum.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn rescale(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.rescale(scale.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn to_integral_exact(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.to_integral_exact(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn to_integral_value(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.to_integral_value(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn exp(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.exp_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn ln(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.ln_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn log10(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.log10_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn power(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.power_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn reduce(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.reduce_ctx(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_plus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.next_plus(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_minus(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.next_minus(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn next_toward(
  value : Decimal,
  target : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.next_toward(target.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn scaleb(
  value : Decimal,
  scale : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.scaleb_ctx(scale.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn shift(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.shift_ctx(count.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn rotate(
  value : Decimal,
  count : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.rotate_ctx(count.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_and(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.logical_and(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_or(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.logical_or(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_xor(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.logical_xor(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn logical_invert(value : Decimal, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (result, flags) = value.inner.logical_invert(ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn compare(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.compare_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn compare_signal(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (result, flags) = lhs.inner.compare_signal_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(result, ctx, flags)
}

///|
pub fn compare_total(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int] {
  let (result, flags) = lhs.inner.compare_total_ctx(rhs.inner, ctx.inner)
  complete_gda(result, ctx, flags)
}

///|
pub fn compare_total_magnitude(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Int] {
  let (result, flags) = lhs.inner.compare_total_magnitude_ctx(
    rhs.inner,
    ctx.inner,
  )
  complete_gda(result, ctx, flags)
}
