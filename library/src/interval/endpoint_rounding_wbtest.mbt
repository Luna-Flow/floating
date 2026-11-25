///|
fn endpoint_rounding_value(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(coefficient),
    exponent,
    precision,
  )
}

///|
/// $[1, 1 + 2^{-52}]$ at 53 bits: both endpoints are representable, so
/// re-quantizing at 53 bits must not change the set.
fn endpoint_rounding_unit_interval() -> Interval {
  Interval::from_bounds(
    @binary.Binary::one(precision=53),
    endpoint_rounding_value((1UL << 52) + 1UL, -52, 53),
    precision=53,
  )
}

///|
// oracle: A
// source: written out by hand: the ends 1 and 1 + 2^-52 = (2^52 + 1) * 2^-52 of [1, 1 + 2^-52] are 53-bit numbers, so normalizing returns exactly those two ends at precision 53
// shares: endpoint_rounding_unit_interval (Interval::from_bounds on Binary::one and endpoint_rounding_value, a helper that builds m * 2^e) builds the input and the expected end; the operation under test is the code under test
test "normalized keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  let y = x.normalized()
  assert_true(y.equal(x))
  assert_eq(y.lower_bound().compare(@binary.Binary::one()), 0)
  assert_eq(
    y.upper_bound().compare(endpoint_rounding_value((1UL << 52) + 1UL, -52, 53)),
    0,
  )
  assert_eq(y.precision(), 53)
}

///|
// oracle: A
// source: written out by hand: the ends 1 and (2^52 + 1) * 2^-52 are 53-bit numbers, so re-quantizing at 53 bits returns exactly those two ends
// shares: endpoint_rounding_unit_interval (Interval::from_bounds on Binary::one and endpoint_rounding_value, a helper that builds m * 2^e) builds the input and the expected end; the operation under test is the code under test
test "with_precision at the same precision keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  let y = x.with_precision(53)
  assert_true(y.equal(x))
  assert_eq(y.lower_bound().compare(@binary.Binary::one()), 0)
  assert_eq(
    y.upper_bound().compare(endpoint_rounding_value((1UL << 52) + 1UL, -52, 53)),
    0,
  )
}

///|
// oracle: A
// source: worked by hand: at 8 bits 1 stays and 1 + 2^-52 rounds up to 1 + 2^-7 = 129 * 2^-7 (IEEE 1788-2015 12.12.7, outward rounding of the ends)
// shares: endpoint_rounding_unit_interval (Interval::from_bounds on Binary::one and endpoint_rounding_value, a helper that builds m * 2^e) builds the input; the operation under test is the code under test
test "with_precision rounds each endpoint outward" {
  let x = endpoint_rounding_unit_interval()
  // At 8 bits, 1 stays and 1 + 2^-52 rounds up to 1 + 2^-7.
  let y = x.with_precision(8)
  assert_eq(y.lower_bound().compare(@binary.Binary::one()), 0)
  assert_eq(y.upper_bound().compare(endpoint_rounding_value(129UL, -7, 8)), 0)
  assert_eq(y.precision(), 8)
}

///|
// oracle: A
// source: IEEE 1788-2015 10.5.7: convexHull(x, empty) = x, written out
// shares: endpoint_rounding_unit_interval (Interval::from_bounds on Binary::one and endpoint_rounding_value, a helper that builds m * 2^e) builds the input; the operation under test is the code under test
test "convex_hull with Empty is the other operand" {
  let x = endpoint_rounding_unit_interval()
  assert_true(Interval::empty().convex_hull(x).equal(x))
  assert_true(x.convex_hull(Interval::empty()).equal(x))
}

///|
// oracle: A
// source: x^1 = x for every x (IEEE 1788-2015 Table 9.1, pown with exponent 1), written out
// shares: endpoint_rounding_unit_interval (Interval::from_bounds on Binary::one and endpoint_rounding_value, a helper that builds m * 2^e) builds the input; the operation under test is the code under test; ArithmeticContext::new
test "pow_int_checked by one keeps the interval" {
  let x = endpoint_rounding_unit_interval()
  let ctx = @lf_arith.ArithmeticContext::new(53)
  assert_true(x.pow_int_checked(1, ctx).unwrap().equal(x))
  assert_true(x.pow_nat_checked(1U, ctx).unwrap().equal(x))
}

///|
// oracle: A
// source: the power of the empty set is the empty set for every exponent, including 0 (IEEE 1788-2015 Table 9.1, an extension is Empty on Empty), written out
// shares: Interval::empty and ArithmeticContext::new build the inputs; the checked powers are the code under test
test "pow_nat_checked of Empty is Empty" {
  let ctx = @lf_arith.ArithmeticContext::new(53)
  for n in [0U, 1U, 2U, 5U] {
    assert_true(Interval::empty().pow_nat_checked(n, ctx).unwrap().is_empty())
  }
  assert_true(Interval::empty().pow_int_checked(0, ctx).unwrap().is_empty())
}
