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
test "IEEE 1788 division reduces sign-definite quotients to two corners" {
  let quarter = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2, 53)
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53)
  let positive = arithmetic_interval(1, 1) / arithmetic_interval(2, 4)
  assert_eq(positive.lower_bound().compare(quarter), 0)
  assert_eq(positive.upper_bound().compare(half), 0)
  let negative = arithmetic_interval(1, 1) / arithmetic_interval(-4, -2)
  assert_eq(negative.lower_bound().compare(half.neg()), 0)
  assert_eq(negative.upper_bound().compare(quarter.neg()), 0)
  let crossing = arithmetic_interval(-2, 4) / arithmetic_interval(2, 4)
  assert_true(crossing.set_equal(arithmetic_interval(-1, 2)))
  let one_sided = BallFloat::from_bounds(
    @bin_float.BinFloat::one(precision=53),
    @bin_float.BinFloat::inf(Sign::Positive, precision=53),
    precision=53,
  )
  let unbounded = arithmetic_interval(1, 1) / one_sided
  assert_true(unbounded.lower_bound().is_zero())
  assert_eq(
    unbounded.upper_bound().compare(@bin_float.BinFloat::one(precision=53)),
    0,
  )
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
test "IEEE 1788 finite multiplication keeps sign-partition bounds" {
  let nonnegative = arithmetic_interval(0, 3)
  let nonpositive = arithmetic_interval(-2, 0)
  assert_true(
    nonnegative.mul(nonpositive).set_equal(arithmetic_interval(-6, 0)),
  )
  assert_true(
    arithmetic_interval(-3, -1)
    .mul(arithmetic_interval(2, 4))
    .set_equal(arithmetic_interval(-12, -2)),
  )
}

///|
test "IEEE 1788 pown uses directed endpoints across zero and poles" {
  assert_true(
    arithmetic_interval(-2, 3).pown(3).set_equal(arithmetic_interval(-8, 27)),
  )
  assert_true(
    arithmetic_interval(-2, 3).pown(2).set_equal(arithmetic_interval(0, 9)),
  )
  let zero = arithmetic_interval(0, 0)
  assert_true(zero.pown(-2).is_empty())
  let nonnegative = arithmetic_interval(0, 4).pown(-2)
  let one_sixteenth = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -4,
    53,
  )
  assert_eq(nonnegative.lower_bound().compare(one_sixteenth), 0)
  assert_true(nonnegative.upper_bound().classify() == FpClass::Infinity)
  let crossing = arithmetic_interval(-4, 4).pown(-2)
  assert_eq(crossing.lower_bound().compare(one_sixteenth), 0)
  assert_true(crossing.upper_bound().classify() == FpClass::Infinity)
  assert_true(arithmetic_interval(-2, 3).pown(-3).is_entire())
}

///|
test "IEEE 1788 pown preserves negative-half-axis monotonicity" {
  let negative = arithmetic_interval(-3, -2)
  assert_true(negative.pown(2).set_equal(arithmetic_interval(4, 9)))
  let reciprocal = negative.pown(-2)
  assert_true(reciprocal.lower_bound().compare(reciprocal.upper_bound()) <= 0)
  assert_true(reciprocal.lower_bound().sign() == Sign::Positive)
  assert_true(
    reciprocal
    .upper_bound()
    .compare(@bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2, 53)) >=
    0,
  )
}

///|
test "IEEE 1788 pown preserves infinity, signed zero, and Int min" {
  let negative_zero = @bin_float.BinFloat::negative_zero(precision=53)
  let signed_zero = BallFloat::from_bounds(
    negative_zero,
    negative_zero,
    precision=53,
  )
  assert_true(signed_zero.pown(3).lower_bound().is_negative_zero())
  let negative_unbounded = BallFloat::from_bounds(
    @bin_float.BinFloat::inf(Sign::Negative, precision=53),
    @bin_float.BinFloat::from_int(-1, precision=53),
    precision=53,
  ).pown(-1)
  assert_true(
    negative_unbounded
    .lower_bound()
    .compare(@bin_float.BinFloat::from_int(-1, precision=53)) ==
    0,
  )
  assert_true(negative_unbounded.upper_bound().is_negative_zero())
  let minimum_exponent = -2147483647 - 1
  assert_true(
    BallFloat::from_int(1, precision=53)
    .pown(minimum_exponent)
    .set_equal(BallFloat::from_int(1, precision=53)),
  )
  assert_true(
    BallFloat::from_int(-1, precision=53)
    .pown(minimum_exponent)
    .set_equal(BallFloat::from_int(1, precision=53)),
  )
  let exact_tiny = BallFloat::from_int(2, precision=53).pown(minimum_exponent)
  assert_true(exact_tiny.lower_bound().is_zero() == false)
  assert_eq(exact_tiny.lower_bound().exponent2(), -2147483648)
  assert_eq(exact_tiny.upper_bound().exponent2(), -2147483648)
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
