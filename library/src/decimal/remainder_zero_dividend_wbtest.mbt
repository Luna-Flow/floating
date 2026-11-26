///|
/// The quotient of a zero dividend is zero whatever the exponents, so the
/// remainder is the zero dividend, not an invalid operation.

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.1: the quotient of a zero dividend is zero, so the remainder is the zero dividend with its sign, at the smaller of the two exponents (0E+10 rem 3 is 0, -0E+10 rem 3 is -0, 0E+10 rem -3E-5 is 0.00000, 0.000 rem 7E+20 is 0.000, 0E-10 rem 3 is 0E-10), no flag
// shares: Decimal::from_string reads the operands; remainder_ctx is the code under test; DecimalContext::decimal32 builds the context; to_string and the flags equality read the result
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

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.1: a finite dividend over an infinite divisor is the dividend itself (1, -1 by +-Inf), no flag
// shares: Decimal::from_string reads the operands; remainder_ctx is the code under test; DecimalContext::new builds the context; to_string and the flags equality read the result
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
