///|
fn certified_target_rounding(
  value : BallFloat,
  context : @bin_float.BinaryContext,
) -> (@bin_float.BinFloat, Bool, @bin_float.BinaryFlags) {
  if value.is_empty() {
    return (
      @bin_float.BinFloat::nan(precision=context.precision()),
      false,
      @bin_float.BinaryFlags::new(),
    )
  }
  let (lower, lower_flags) = value.lo_.round_ctx(context)
  let (upper, upper_flags) = value.hi_.round_ctx(context)
  (lower, lower == upper, lower_flags.combine(upper_flags))
}

///|
fn certified_rounding_value(
  coefficient : UInt64,
  exponent : Int,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(coefficient),
    exponent,
    8,
  )
}

///|
test "certified target rounding accepts only one rounded value" {
  let context = @bin_float.BinaryContext::unbounded(3)
  let accepted = BallFloat::from_bounds(
    certified_rounding_value(16UL, -4),
    certified_rounding_value(17UL, -4),
    precision=8,
  )
  let (accepted_value, accepted_unique, _) = certified_target_rounding(
    accepted, context,
  )
  assert_true(accepted_unique)
  assert_eq(accepted_value, @bin_float.BinFloat::one(precision=3))
  let rejected = BallFloat::from_bounds(
    certified_rounding_value(16UL, -4),
    certified_rounding_value(19UL, -4),
    precision=8,
  )
  let (_, rejected_unique, _) = certified_target_rounding(rejected, context)
  assert_false(rejected_unique)
}

///|
test "certified target rounding respects directed modes" {
  let interval = BallFloat::from_bounds(
    certified_rounding_value(16UL, -4),
    certified_rounding_value(17UL, -4),
    precision=8,
  )
  let downward = @bin_float.BinaryContext::unbounded(
    3,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    3,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  assert_true(certified_target_rounding(interval, downward).1)
  assert_false(certified_target_rounding(interval, upward).1)
}

///|
test "expm1 and log1p preserve certified containment" {
  let source = BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(-0.125, precision=53),
    @bin_float.BinFloat::from_double(0.25, precision=53),
    precision=53,
  )
  let expm1 = source.expm1_interval()
  assert_true(expm1.contains(@bin_float.BinFloat::from_double(0.0)))
  let log1p = source.log1p_interval()
  assert_true(log1p.contains(@bin_float.BinFloat::from_double(0.0)))
}

///|
test "decorated log1p uses its shifted IEEE domain" {
  let inside = BallFloatDecorated::new(
    BallFloat::from_double(-0.5, precision=53),
  ).log1p_interval()
  assert_eq(inside.decoration(), Com)
  let crossing = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_double(-2.0, precision=53),
      @bin_float.BinFloat::from_double(0.0, precision=53),
      precision=53,
    ),
  ).log1p_interval()
  assert_eq(crossing.decoration(), Trv)
}
