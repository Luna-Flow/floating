// The endpoints of a degenerate (point) enclosure for the rounding comparison of the
// certified decimal functions (`decimal_certified_endpoints`): a point stays exact.
// The test is `lower_bound.compare(upper_bound) == 0` of two `Binary`s (numerical
// since #643; before, the structural `==` took a point whose bounds differ in the sign
// of zero or in their label for an interval and rounded its endpoints outward, to at
// least target + 12 digits, which can lose a certification).
//
// ORACLE (level A): the expected endpoints are the exact decimal expansions of the
// binary value 1/3 rounded to 53 bits, written out: 0.333333333333333314829616256247390992939472198486328125.

///|
test "a point enclosure keeps its exact decimal endpoints" {
  let ctx = DecimalContext::new(precision=34)
  let third = @binary.Binary::from_double(1.0 / 3.0)
  let point = @interval.Interval::from_bounds(third, third, precision=53)
  let (lower, upper) = decimal_certified_endpoints(point, ctx)
  let expected = "0.333333333333333314829616256247390992939472198486328125"
  assert_true(lower.unwrap().to_string() == expected)
  assert_true(upper.unwrap().to_string() == expected)
}

///|
test "a point enclosure whose bounds are zeros of different sign is exact" {
  let ctx = DecimalContext::new(precision=34)
  let negative_zero = @binary.Binary::negative_zero(precision=53)
  let positive_zero = @binary.Binary::zero(precision=24)
  assert_true(negative_zero == positive_zero)
  assert_false(negative_zero.identical(positive_zero))
  let point = @interval.Interval::from_bounds(
    negative_zero,
    positive_zero,
    precision=53,
  )
  let (lower, upper) = decimal_certified_endpoints(point, ctx)
  assert_true(lower.unwrap().is_zero() && upper.unwrap().is_zero())
}
