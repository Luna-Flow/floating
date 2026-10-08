///|
fn endpoint_rounding_value(
  coefficient : UInt64,
  exponent : Int,
  precision : Int,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(coefficient),
    exponent,
    precision,
  )
}

///|
/// $[1, 1 + 2^{-52}]$ at 53 bits: both endpoints are representable, so
/// re-quantizing at 53 bits must not change the set.
fn endpoint_rounding_unit_interval() -> BallFloat {
  BallFloat::from_bounds(
    @bin_float.BinFloat::one(precision=53),
    endpoint_rounding_value((1UL << 52) + 1UL, -52, 53),
    precision=53,
  )
}

///|
let endpoint_rounding_modes : Array[RoundingMode] = [
  RoundingMode::ToNearestEven,
  RoundingMode::TowardPositive,
  RoundingMode::TowardNegative,
  RoundingMode::TowardZero,
  RoundingMode::AwayFromZero,
]

///|
test "normalized keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  assert_true(x.normalized().set_equal(x))
  assert_eq(x.normalized().precision(), 53)
  assert_true(@def.Floating::normalized(x).set_equal(x))
}

///|
test "with_precision at the same precision keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  for mode in endpoint_rounding_modes {
    assert_true(x.with_precision(53, mode).set_equal(x))
  }
}

///|
test "with_precision rounds each endpoint outward" {
  let x = endpoint_rounding_unit_interval()
  // At 8 bits, 1 stays and 1 + 2^-52 rounds up to 1 + 2^-7.
  let y = x.with_precision(8, RoundingMode::ToNearestEven)
  assert_eq(y.lower_bound().compare(@bin_float.BinFloat::one()), 0)
  assert_eq(y.upper_bound().compare(endpoint_rounding_value(129UL, -7, 8)), 0)
  assert_eq(y.precision(), 8)
}

///|
test "convex_hull with Empty is the other operand" {
  let x = endpoint_rounding_unit_interval()
  assert_true(BallFloat::empty().convex_hull(x).set_equal(x))
  assert_true(x.convex_hull(BallFloat::empty()).set_equal(x))
}

///|
test "pow_int_checked by one keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  let ctx = @lf_arith.ArithmeticContext::new(53)
  assert_true(x.pow_int_checked(1, ctx).unwrap().set_equal(x))
  assert_true(x.pow_nat_checked(1U, ctx).unwrap().set_equal(x))
}

///|
test "pow_nat_checked of Empty is Empty" {
  let ctx = @lf_arith.ArithmeticContext::new(53)
  for n in [0U, 1U, 2U, 5U] {
    assert_true(BallFloat::empty().pow_nat_checked(n, ctx).unwrap().is_empty())
  }
  assert_true(BallFloat::empty().pow_int_checked(0, ctx).unwrap().is_empty())
}
