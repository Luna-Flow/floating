///|
/// The integer quotient of a zero dividend is zero whatever the exponents, so
/// it always fits the precision: divide_integer and the GDA remainders return
/// zeros instead of rejecting the division as impossible.
test "divide_integer and remainder accept a zero dividend" {
  let context = DecimalContext::decimal32()
  let cases = [
    ("0E+10", "3", "0", "0"),
    ("-0E+10", "3", "-0", "-0"),
    ("0E+10", "-3E-5", "-0", "0.00000"),
    ("0.000", "7E+20", "0", "0.000"),
    ("0E-10", "3", "0", "0E-10"),
  ]
  for entry in cases {
    let (left, right, quotient, remainder) = entry
    let x = Decimal::from_string(left).unwrap()
    let y = Decimal::from_string(right).unwrap()
    let (q, q_flags) = x.divide_integer(y, context)
    assert_eq(q.to_string(), quotient)
    assert_true(q_flags == DecimalFlags::new())
    let (r, r_flags) = x.remainder(y, context)
    assert_eq(r.to_string(), remainder)
    assert_true(r_flags == DecimalFlags::new())
    let (n, n_flags) = x.remainder_near(y, context)
    assert_eq(n.to_string(), remainder)
    assert_true(n_flags == DecimalFlags::new())
  }
}
