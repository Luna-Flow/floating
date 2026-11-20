///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.

///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.
test "a zero-quotient remainder is clamped only at its result" {
  let ctx = DecimalContext::new(precision=9, e_max=4)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (n, n_flags) = d("-73E-2").remainder_ctx(d("69846238E-6"), ctx)
  assert_eq(n.to_string(), "-0.730000")
  assert_true(n_flags == DecimalFlags::new())
}
