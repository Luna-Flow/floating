///|
/// The integer quotient inside `remainder` is internal: only its digit count
/// matters. Its overflow or clamping must not reach the remainder's flags,
/// and the remainder must be taken with the exact quotient, not with one that
/// has overflowed to infinity. Expected values from Python `decimal`.
test "remainder keeps only the flags of the delivered remainder" {
  let x = Decimal::from_string("6E-6").unwrap()
  let y = Decimal::from_string("-9.99999999E-15").unwrap()
  for extended in [true, false] {
    for clamp in [false, true] {
      let ctx = DecimalContext::new(
        precision=9,
        e_min=-24,
        e_max=4,
        clamp~,
        extended~,
      )
      let (value, flags) = x.remainder(y, ctx)
      assert_eq(value.to_string(), "6.00000000E-15")
      assert_true(flags == DecimalFlags::new())
    }
  }
  // In a subset context the rounded quotient 17636684 overflows e_max = 4.
  let subset = DecimalContext::new(
    precision=9,
    e_min=-24,
    e_max=4,
    extended=false,
  )
  let (value, flags) = Decimal::from_string("123456789")
    .unwrap()
    .remainder(Decimal::from_string("7").unwrap(), subset)
  assert_eq(value.to_string(), "1")
  assert_true(flags == DecimalFlags::new())
}

///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.
test "a zero-quotient remainder is clamped only at its result" {
  let ctx = DecimalContext::new(precision=9, e_min=-24, e_max=4, clamp=true)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (r, r_flags) = d("-80E-3").remainder(d("4442621E-4"), ctx)
  assert_eq(r.to_string(), "-0.0800")
  assert_true(r_flags == DecimalFlags::new())
  let (r2, r2_flags) = d("4736E-3").remainder(d("91945766E-7"), ctx)
  assert_eq(r2.to_string(), "4.7360000")
  assert_true(r2_flags == DecimalFlags::new())
  let (n, n_flags) = d("-73E-2").remainder_near(d("69846238E-6"), ctx)
  assert_eq(n.to_string(), "-0.730000")
  assert_true(n_flags == DecimalFlags::new())
}
