///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.
test "a zero-quotient remainder is clamped only at its result" {
  let ctx = DecimalContext::new(precision=9, e_max=4)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (r, r_flags) = d("-80E-3").remainder_trunc_ctx(d("4442621E-4"), ctx)
  assert_eq(r.to_string(), "-0.0800")
  assert_true(r_flags == DecimalFlags::new())
  let (r2, r2_flags) = d("4736E-3").remainder_trunc_ctx(d("91945766E-7"), ctx)
  assert_eq(r2.to_string(), "4.7360000")
  assert_true(r2_flags == DecimalFlags::new())
  let (n, n_flags) = d("-73E-2").remainder_ctx(d("69846238E-6"), ctx)
  assert_eq(n.to_string(), "-0.730000")
  assert_true(n_flags == DecimalFlags::new())
}
