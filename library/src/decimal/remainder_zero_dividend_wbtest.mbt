///|
/// The quotient of a zero dividend is zero whatever the exponents, so the
/// remainder is the zero dividend, not an invalid operation.
test "remainder accepts a zero dividend" {
  let context = DecimalContext::decimal32()
  let cases = [
    ("0E+10", "3", "0"),
    ("-0E+10", "3", "-0"),
    ("0E+10", "-3E-5", "0.00000"),
    ("0.000", "7E+20", "0.000"),
    ("0E-10", "3", "0E-10"),
  ]
  for entry in cases {
    let (left, right, remainder) = entry
    let x = Decimal::from_string(left).unwrap()
    let y = Decimal::from_string(right).unwrap()
    let (n, n_flags) = x.remainder_ctx(y, context)
    assert_eq(n.to_string(), remainder)
    assert_true(n_flags == DecimalFlags::new())
  }
}

///|
/// A finite dividend over an infinite divisor is the dividend itself (IEEE
/// 754-2019 5.3.1), at the exponent the format allows.
test "remainder of a finite value by an infinity is the value" {
  let ctx = DecimalContext::new(precision=9, e_max=8)
  let cases = [
    ("1", "Inf", "1"),
    ("-1", "Inf", "-1"),
    ("1", "-Inf", "1"),
    ("-1", "-Inf", "-1"),
  ]
  for entry in cases {
    let (left, right, expected) = entry
    let x = Decimal::from_string(left).unwrap()
    let y = Decimal::from_string(right).unwrap()
    let (r, flags) = x.remainder_ctx(y, ctx)
    assert_eq(r.to_string(), expected)
    assert_true(flags == DecimalFlags::new())
  }
}
