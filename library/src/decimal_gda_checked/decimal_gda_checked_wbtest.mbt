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

///|
test "gda checked power of a power of ten with an integral k*y is exact in the directed modes (issue 351)" {
  for
    mode in [
      @decimal_gda.GdaRoundingMode::Floor,
      @decimal_gda.GdaRoundingMode::Ceiling,
      @decimal_gda.GdaRoundingMode::Down,
      @decimal_gda.GdaRoundingMode::Up,
    ] {
    let context = @decimal_gda.GdaContext::new(
      precision=16,
      rounding=mode,
      e_min=-383,
      e_max=384,
      clamp=true,
    )
    let base = @decimal_gda.Decimal::from_string("1E-5").unwrap()
    let exponent = @decimal_gda.Decimal::from_string("1.2").unwrap()
    let result = GdaDecimalChecked::from_decimal(base, context).power(exponent)
    assert_false(result.is_trapped())
    assert_eq(result.value().to_string(), "0.000001000000000000000")
    assert_true(result.raised().contains(@decimal_gda.GdaSignal::Inexact))
    assert_true(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
    assert_false(
      result.raised().contains(@decimal_gda.GdaSignal::InvalidOperation),
    )
  }
}

///|
test "gda checked power to a zero exponent is exactly 1 in a clamped context (issue 405)" {
  let context = @decimal_gda.GdaContext::new(
    precision=5,
    e_min=-10,
    e_max=0,
    clamp=true,
  )
  let base = @decimal_gda.Decimal::from_string("9.99").unwrap()
  let result = GdaDecimalChecked::from_decimal(base, context).power(
    @decimal_gda.Decimal::zero(),
  )
  assert_false(result.is_trapped())
  assert_eq(result.value().to_string(), "1")
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Clamped))
}

///|
test "gda checked power to one half is the padded inexact result without Clamped (issue 397)" {
  let context = @decimal_gda.GdaContext::new(
    precision=4,
    rounding=@decimal_gda.GdaRoundingMode::Down,
    e_min=-4,
    e_max=0,
    clamp=true,
  )
  let base = @decimal_gda.Decimal::from_string("0.01").unwrap()
  let result = GdaDecimalChecked::from_decimal(base, context).power(
    @decimal_gda.Decimal::from_string("0.5").unwrap(),
  )
  assert_false(result.is_trapped())
  assert_eq(result.value().to_string(), "0.1000")
  assert_true(result.raised().contains(@decimal_gda.GdaSignal::Inexact))
  assert_true(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Clamped))
}
