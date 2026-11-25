///|
/// A tiny operand with a much smaller addend: the sum is inexact and tiny, so it
/// raises underflow. The shortcut for an addend far below the result grid must
/// not be taken when applying the context to the large operand already shows
/// a tiny (subnormal) value.
// oracle: A
// source: Python decimal (CPython, libmpdec, Context(prec=3, Emax=5, Emin=-4)): 2E-8 + 19E-6 and 2E-8 - (-19E-6) are 0.000019 with Inexact and Underflow (tiny: adjusted exponent -5 below emin -4)
// shares: Decimal::from_string, add_ctx, sub_ctx and DecimalFlags (the code under test)
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
