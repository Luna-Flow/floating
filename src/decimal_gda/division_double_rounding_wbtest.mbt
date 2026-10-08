///|
/// 1/2222 = 0.00045004..., so one digit rounds to 0.0005. Rounding the guarded
/// quotient with the target mode made the discarded tail look like an exact
/// 50...0 tie, and the final HalfEven then rounded down to 0.0004.
test "gda divide rounds once near a manufactured midpoint" {
  let one = Decimal::from_string("1").unwrap()
  let divisor = Decimal::from_string("2222").unwrap()
  let none = GdaTrapSet::none()
  for
    mode in [
      GdaRoundingMode::HalfEven,
      GdaRoundingMode::HalfUp,
      GdaRoundingMode::HalfDown,
    ] {
    let ctx = GdaContext::new(precision=1, rounding=mode, traps=none)
    inspect(divide(one, divisor, ctx).value(), content="0.0005")
  }
}

///|
test "gda divide stays exact when the quotient terminates" {
  let none = GdaTrapSet::none()
  let ctx = GdaContext::new(
    precision=9,
    rounding=GdaRoundingMode::HalfEven,
    traps=none,
  )
  let cases = [
    ("1", "2", "0.5"),
    ("1", "4", "0.25"),
    ("6", "3", "2"),
    ("1", "8", "0.125"),
  ]
  for row in cases {
    let (left, right, want) = row
    let a = Decimal::from_string(left).unwrap()
    let b = Decimal::from_string(right).unwrap()
    assert_eq(divide(a, b, ctx).value().to_string(), want)
  }
}
