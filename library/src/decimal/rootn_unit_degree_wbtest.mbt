///|
/// rootn(x, 1) = x and rootn(x, -1) = 1 / x are exact here in every rounding
/// mode; the certified loop cannot decide an exactly representable value.
test "rootn of degree 1 and -1 is exact" {
  let modes = [
    RoundingMode::ToNearestEven,
    TowardZero,
    TowardPositive,
    TowardNegative,
    AwayFromZero,
  ]
  let cases = [
    ("5", -1, "0.2"),
    ("0.1", 1, "0.1"),
    ("-0.04", -1, "-25"),
    ("8", -1, "0.125"),
    ("-7.5", 1, "-7.5"),
  ]
  for mode in modes {
    let ctx = DecimalContext::decimal64().with_rounding(mode)
    for entry in cases {
      let (text, degree, expected) = entry
      let (value, flags) = Decimal::from_string(text)
        .unwrap()
        .rootn_ctx(degree, ctx)
      assert_eq(value.to_string(), expected)
      assert_false(flags.inexact)
      assert_false(flags.invalid_operation)
    }
  }
}
