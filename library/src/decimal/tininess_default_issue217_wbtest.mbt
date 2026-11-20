///|
/// IEEE 754-2019 §7.5: "For decimal formats, tininess is detected before
/// rounding". Every public way of building a `DecimalContext` therefore
/// defaults to `BeforeRounding`; `AfterRounding` is an explicit non-standard
/// option. `0.99951` is below `10^e_min = 1` before rounding (tiny, and
/// inexact, so `underflow`) but rounds to `1.00` at three digits.
test "decimal contexts detect tininess before rounding by default (#217)" {
  let ctx = DecimalContext::new(precision=3, e_min=0, e_max=10).unwrap()
  assert_true(ctx.tininess() == DecimalTininessDetection::BeforeRounding)
  assert_true(
    DecimalContext::try_new(precision=3).unwrap().tininess() ==
    DecimalTininessDetection::BeforeRounding,
  )
  for
    preset in [
      DecimalContext::decimal32(),
      DecimalContext::decimal64(),
      DecimalContext::decimal128(),
      DecimalContext::exact(),
    ] {
    assert_true(preset.tininess() == DecimalTininessDetection::BeforeRounding)
  }
  for text in ["0.9951", "0.99951"] {
    let (value, flags) = Decimal::from_string(text).unwrap().plus_ctx(ctx)
    assert_eq(value.to_string(), "1.00")
    assert_true(flags.underflow && flags.subnormal && flags.inexact, msg=text)
  }
  let after = ctx.with_tininess(DecimalTininessDetection::AfterRounding)
  let (_, flags_after) = Decimal::from_string("0.99951")
    .unwrap()
    .plus_ctx(after)
  assert_false(flags_after.underflow || flags_after.subnormal)
  let (_, flags_after_tiny) = Decimal::from_string("0.9951")
    .unwrap()
    .plus_ctx(after)
  assert_true(flags_after_tiny.underflow && flags_after_tiny.subnormal)
}
