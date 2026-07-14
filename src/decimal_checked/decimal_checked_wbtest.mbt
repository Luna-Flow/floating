///|
test "decimal checked preserves IEEE defined results" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_int(1, context).div(
    @decimal.Decimal::zero(),
  )
  assert_true(result.value().is_infinite())
  assert_true(result.raised().contains(@decimal.DecimalSignal::DivisionByZero))
  assert_true(result.flags().contains(@decimal.DecimalSignal::DivisionByZero))
}

///|
test "decimal checked accumulates IEEE flags" {
  let context = @decimal.DecimalContext::new(precision=3)
  let parsed = DecimalChecked::parse("1.2345", context)
  assert_true(parsed.raised().contains(@decimal.DecimalSignal::Rounded))
  let result = parsed.add(@decimal.Decimal::zero())
  assert_false(result.raised().contains(@decimal.DecimalSignal::Rounded))
  assert_true(result.flags().contains(@decimal.DecimalSignal::Rounded))
  let cleared = result.clear_flags()
  assert_false(cleared.flags().contains(@decimal.DecimalSignal::Rounded))
  assert_false(cleared.flags().has_error())
}

///|
test "decimal checked parse keeps conversion result and flags" {
  let result = DecimalChecked::parse(
    "not-a-decimal",
    @decimal.DecimalContext::decimal64(),
  )
  assert_true(result.value().is_nan())
  assert_true(
    result.raised().contains(@decimal.DecimalSignal::ConversionSyntax),
  )
}
