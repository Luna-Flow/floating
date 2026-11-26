///|
/// IEEE 754-2019 6.3: an exact zero sum of operands with opposite signs is -0
/// under roundTowardNegative and +0 under every other direction.

///|
// oracle: A
// source: written out from IEEE Std 754-2019 6.3: an exact zero sum of operands with opposite signs is -0 under roundTowardNegative and +0 under every other direction, (-0) + (-0) is -0, abs of -0 is +0 and apply keeps -0, all without flag
// shares: Decimal::from_string reads the zeros; add_ctx, sub_ctx, abs_ctx and apply_ctx are the code under test; DecimalContext::new builds the contexts; to_string and the flags equality read the result
test "a zero sum follows the sign rule in every rounding direction" {
  let modes = [
    DecimalRoundingMode::RoundTiesToEven,
    DecimalRoundingMode::RoundTiesToAway,
    DecimalRoundingMode::RoundTowardZero,
    DecimalRoundingMode::RoundTowardPositive,
    DecimalRoundingMode::RoundTowardNegative,
  ]
  for mode in modes {
    let ctx = DecimalContext::new(precision=16, rounding=mode)
    let floor = mode == DecimalRoundingMode::RoundTowardNegative
    let zero = Decimal::from_string("0").unwrap()
    let negative_zero = Decimal::from_string("-0").unwrap()
    let (sum, sum_flags) = zero.add_ctx(negative_zero, ctx)
    assert_eq(sum.to_string(), if floor { "-0" } else { "0" })
    assert_true(sum_flags == DecimalFlags::new())
    let (difference, _) = zero.sub_ctx(zero, ctx)
    assert_eq(difference.to_string(), if floor { "-0" } else { "0" })
    let (same_sign, _) = negative_zero.add_ctx(negative_zero, ctx)
    assert_eq(same_sign.to_string(), "-0")
    // abs and apply keep or clear the sign without a flag
    let (magnitude, _) = negative_zero.abs_ctx(ctx)
    assert_eq(magnitude.to_string(), "0")
    let (applied, applied_flags) = negative_zero.apply_ctx(ctx)
    assert_eq(applied.to_string(), "-0")
    assert_true(applied_flags == DecimalFlags::new())
  }
}
