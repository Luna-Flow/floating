///|
/// rootn(x, 1) = x and rootn(x, -1) = 1 / x are exact here in every rounding
/// mode; the certified loop cannot decide an exactly representable value.

///|
// oracle: A
// source: written out: rootn(x, 1) = x and rootn(x, -1) = 1 / x are exact in every direction (1/5 = 0.2, 1/8 = 0.125, 1/-0.04 = -25, 0.1 and -7.5 unchanged), no inexact and no invalid operation
// shares: Decimal::from_string reads the operands; rootn_ctx is the code under test; DecimalContext::decimal64, with_round and DecimalRound::from_arithmetic build the contexts; to_string and the flags read the result
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
    let ctx = DecimalContext::decimal64().with_round(
      DecimalRound::from_arithmetic(mode),
    )
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
