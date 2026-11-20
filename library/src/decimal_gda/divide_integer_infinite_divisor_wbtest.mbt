///|
/// A finite dividend over an infinite divisor has the zero integer quotient
/// with preferred exponent 0; a clamped context folds that exponent down to
/// e_max - p + 1 and raises only `clamped`. (Moved from the `decimal` package.)
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
}
