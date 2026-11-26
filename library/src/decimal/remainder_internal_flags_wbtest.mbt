///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.

///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.1: the quotient of -0.73 by 69.846238 rounds to the integer 0, so the remainder is the dividend, delivered at the smaller exponent -6 as -0.730000 with no flag
// shares: Decimal::from_string reads the operands; remainder_ctx is the code under test; DecimalContext::new builds the context; to_string and the flags equality read the result
test "a zero-quotient remainder is clamped only at its result" {
  let ctx = DecimalContext::new(precision=9, e_max=4)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (n, n_flags) = d("-73E-2").remainder_ctx(d("69846238E-6"), ctx)
  assert_eq(n.to_string(), "-0.730000")
  assert_true(n_flags == DecimalFlags::new())
}
