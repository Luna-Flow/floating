///|
test "gda checked threads sticky status" {
  let context = @decimal_gda.GdaContext::new(precision=3)
  let parsed = GdaDecimalChecked::parse("1.2345", context)
  assert_true(parsed.raised().contains(@decimal_gda.GdaSignal::Rounded))
  let result = parsed.add(@decimal_gda.Decimal::zero())
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
  assert_true(result.status().contains(@decimal_gda.GdaSignal::Rounded))
}

///|
test "gda checked traps short circuit and preserve defined results" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let one = @decimal_gda.Decimal::one()
  let zero = @decimal_gda.Decimal::zero()
  let trapped = GdaDecimalChecked::from_decimal(one, context).divide(zero)
  assert_true(trapped.is_trapped())
  assert_true(trapped.value().is_infinite())
  match trapped.trapped_signal() {
    Some(signal) =>
      assert_true(signal == @decimal_gda.GdaSignal::DivisionByZero)
    None => fail("expected division-by-zero trap")
  }
  let still_trapped = trapped.add(one)
  assert_true(still_trapped.is_trapped())
  let resumed = trapped.resume_defined().add(one)
  assert_false(resumed.is_trapped())
  assert_true(resumed.status().contains(@decimal_gda.GdaSignal::DivisionByZero))
}
