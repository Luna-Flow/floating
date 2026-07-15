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

///|
test "decimal checked elementary mirrors preserve results" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_int(10, context).exp2()
  assert_true(result.is_ok())
  assert_false(result.is_err())
  assert_eq(result.value().compare(@decimal.Decimal::from_int(1024)), 0)
  match result.result() {
    Ok((value, _)) =>
      assert_eq(value.compare(@decimal.Decimal::from_int(1024)), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "decimal checked pi-scaled and binary mirrors are additive" {
  let context = @decimal.DecimalContext::decimal64()
  let half = @decimal.Decimal::from_string("0.5").unwrap()
  let tangent = DecimalChecked::from_decimal(half, context).tanpi()
  assert_true(tangent.value().is_infinite())
  assert_true(tangent.raised().contains(@decimal.DecimalSignal::DivisionByZero))
  let hypot = DecimalChecked::from_int(3, context).hypot(
    @decimal.Decimal::from_int(4),
  )
  assert_eq(hypot.value().compare(@decimal.Decimal::from_int(5)), 0)
}
