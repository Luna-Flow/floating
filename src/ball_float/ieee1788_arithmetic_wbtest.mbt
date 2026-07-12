///|
fn arithmetic_interval(lo : Int, hi : Int) -> BallFloat {
  BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(lo, precision=53),
    @bin_float.BinFloat::from_int(hi, precision=53),
    precision=53,
  )
}

///|
test "IEEE 1788 multiplication is tight for zero and unbounded intervals" {
  let zero = arithmetic_interval(0, 0)
  let entire = BallFloat::whole(precision=53)
  assert_true((zero * entire).set_equal(zero))
  let positive_half = BallFloat::from_bounds(
    @bin_float.BinFloat::one(precision=53),
    @bin_float.BinFloat::inf(Sign::Positive, precision=53),
    precision=53,
  )
  let negative = arithmetic_interval(-5, -1)
  let product = positive_half * negative
  assert_true(product.lower_bound().classify() == FpClass::Infinity)
  assert_true(product.lower_bound().sign() == Sign::Negative)
  assert_eq(product.upper_bound().compare(negative.upper_bound()), 0)
}

///|
test "IEEE 1788 division keeps one-sided zero bounds tight" {
  let one = arithmetic_interval(1, 1)
  let nonnegative = arithmetic_interval(0, 1)
  let positive_result = one / nonnegative
  assert_eq(positive_result.lower_bound().compare(one.lower_bound()), 0)
  assert_true(positive_result.upper_bound().classify() == FpClass::Infinity)
  assert_true(positive_result.upper_bound().sign() == Sign::Positive)
  let nonpositive = arithmetic_interval(-1, 0)
  let negative_result = one / nonpositive
  assert_true(negative_result.lower_bound().classify() == FpClass::Infinity)
  assert_true(negative_result.lower_bound().sign() == Sign::Negative)
  assert_eq(negative_result.upper_bound().compare(one.lower_bound().neg()), 0)
}

///|
test "IEEE 1788 division handles zero numerator and zero denominator" {
  let zero = arithmetic_interval(0, 0)
  let spanning = arithmetic_interval(-1, 1)
  assert_true((zero / spanning).set_equal(zero))
  assert_true((spanning / zero).is_empty())
}

///|
test "binary64 context applies directed overflow bounds" {
  let ctx = BallContext::binary64()
  let max_finite = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one()
    .shift_left(53)
    .sub_checked(@bin_float.BinCoeff::one())
    .unwrap(),
    971,
    53,
  )
  let source = BallFloat::from_bounds(max_finite, max_finite, precision=53)
  let increment = arithmetic_interval(3, 4)
  let (result, flags) = source.add_ctx(increment, ctx)
  assert_eq(result.lower_bound().compare(max_finite), 0)
  assert_true(result.upper_bound().classify() == FpClass::Infinity)
  assert_true(flags.overflow)
  assert_true(flags.inexact)
}

///|
test "binary context applies gradual directed underflow" {
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=3)
  let below_subnormal = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -7,
    4,
  )
  let source = BallFloat::from_bounds(
    below_subnormal,
    below_subnormal,
    precision=8,
  )
  let (result, flags) = source.apply_ctx(ctx)
  let zero = @bin_float.BinFloat::zero(precision=4)
  let min_subnormal = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -5,
    4,
  )
  assert_eq(result.lower_bound().compare(zero), 0)
  assert_eq(result.upper_bound().compare(min_subnormal), 0)
  assert_true(flags.underflow)
  assert_true(flags.inexact)
}

///|
test "IEEE 1788 cancellation contracts compatible widths" {
  let left = arithmetic_interval(-5, 0)
  let right = arithmetic_interval(1, 5)
  assert_true(left.cancel_plus(right).set_equal(arithmetic_interval(0, 1)))
  let minuend = arithmetic_interval(-5, 0)
  let subtrahend = arithmetic_interval(-4, 0)
  assert_true(
    minuend.cancel_minus(subtrahend).set_equal(arithmetic_interval(-1, 0)),
  )
  assert_true(
    arithmetic_interval(-5, -1)
    .cancel_plus(arithmetic_interval(1, 6))
    .is_entire(),
  )
}

///|
test "IEEE 1788 fused multiply-add rounds only the final enclosure" {
  let left = arithmetic_interval(-2, 3)
  let multiplier = arithmetic_interval(4, 5)
  let addend = arithmetic_interval(1, 2)
  assert_true(
    left.fma(multiplier, addend).set_equal(arithmetic_interval(-9, 17)),
  )
  assert_true(left.fma(multiplier, BallFloat::empty(precision=53)).is_empty())
}

///|
test "BallFlags getters and combine accumulate endpoint status" {
  let left : BallFlags = { inexact: true, overflow: false, underflow: true }
  let right : BallFlags = { inexact: false, overflow: true, underflow: false }
  let combined = left.combine(right)
  assert_true(combined.inexact())
  assert_true(combined.overflow())
  assert_true(combined.underflow())
  assert_true(combined.combine(BallFlags::new()) == combined)
}
