///|
/// A tiny operand with a much smaller addend: the sum is inexact and tiny, so it
/// raises underflow. The shortcut for an addend far below the result grid must
/// not be taken when applying the context to the large operand already shows
/// a tiny (subnormal) value.
test "add of a tiny value and a far smaller addend raises underflow" {
  let ctx = DecimalContext::new(precision=3, e_max=5)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (sum, flags) = d("2E-8").add_ctx(d("19E-6"), ctx)
  assert_eq(sum.to_string(), "0.000019")
  assert_true(flags.inexact())
  assert_true(flags.underflow())
  let (difference, difference_flags) = d("2E-8").sub_ctx(d("-19E-6"), ctx)
  assert_eq(difference.to_string(), "0.000019")
  assert_true(difference_flags.underflow())
}
