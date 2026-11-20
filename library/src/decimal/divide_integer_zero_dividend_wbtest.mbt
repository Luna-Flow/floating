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

///|
test "divide_integer clamps a zero quotient exponent" {
  let ctx = DecimalContext::new(precision=9, e_min=0, e_max=1, clamp=true)
  let lhs = Decimal::from_string("-8.95E-6").unwrap()
  let rhs = Decimal::from_string("2.40E-5").unwrap()
  let (value, flags) = lhs.divide_integer(rhs, ctx)
  inspect(value.to_string(), content="-0E-7")
  inspect(flags.clamped, content="true")
}

///|
/// A finite dividend over an infinite divisor has the zero integer quotient
/// with preferred exponent 0; a clamped context folds that exponent down to
/// e_max - p + 1 and raises only `clamped`.
test "divide_integer clamps a zero quotient over an infinite divisor" {
  let ctx = DecimalContext::new(precision=9, e_min=0, e_max=1, clamp=true)
  let cases = [
    ("1", "Inf", "0E-7", "1.0000000"),
    ("-1", "Inf", "-0E-7", "-1.0000000"),
    ("1", "-Inf", "-0E-7", "1.0000000"),
    ("-1", "-Inf", "0E-7", "-1.0000000"),
  ]
  for entry in cases {
    let (left, right, expected, remainder) = entry
    let x = Decimal::from_string(left).unwrap()
    let y = Decimal::from_string(right).unwrap()
    let (q, flags) = x.divide_integer(y, ctx)
    assert_eq(q.to_string(), expected)
    assert_true(flags == { ..DecimalFlags::new(), clamped: true, })
    // x rem Inf is x itself, whose exponent 0 the clamp folds to -7.
    let (r, r_flags) = x.remainder(y, ctx)
    assert_eq(r.to_string(), remainder)
    assert_true(r_flags == { ..DecimalFlags::new(), clamped: true, })
  }
  let unclamped = DecimalContext::new(precision=9, e_min=0, e_max=1)
  let (q, flags) = Decimal::from_string("-1")
    .unwrap()
    .divide_integer(Decimal::from_string("Inf").unwrap(), unclamped)
  inspect(q.to_string(), content="-0")
  assert_true(flags == DecimalFlags::new())
}
