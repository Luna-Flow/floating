///|
/// hypot(+-inf, y) is +inf for every y, even a quiet NaN, but a signaling NaN
/// signals invalid and the result is a quiet NaN (IEEE 754-2019 6.2, 9.2.1).
test "hypot of an infinity and a signaling NaN is a quiet NaN" {
  let ctx = DecimalContext::decimal64()
  let infinity = Decimal::from_string("Infinity").unwrap()
  let negative_infinity = Decimal::from_string("-Infinity").unwrap()
  let quiet = Decimal::from_string("NaN").unwrap()
  let signaling = Decimal::signaling_nan()
  for
    pair in [
      (infinity, signaling),
      (signaling, infinity),
      (negative_infinity, signaling),
    ] {
    let (value, flags) = pair.0.hypot_ctx(pair.1, ctx)
    assert_true(value.is_nan())
    assert_false(value.is_signaling_nan())
    assert_true(flags.invalid_operation)
  }
  for pair in [(infinity, quiet), (quiet, negative_infinity)] {
    let (value, flags) = pair.0.hypot_ctx(pair.1, ctx)
    assert_eq(value.to_string(), "inf")
    assert_false(flags.invalid_operation)
  }
}
