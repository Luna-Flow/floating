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
  let context = @decimal.DecimalContext::new(precision=3).unwrap()
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

///|
test "decimal checked atan2 accepts infinite operands" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_decimal(
    @decimal.Decimal::from_string("Inf").unwrap(),
    context,
  ).atan2(@decimal.Decimal::from_string("-Inf").unwrap())
  inspect(result.value(), content="2.356194490192345")
  assert_false(result.flags().has_error())
}

///|
test "decimal checked exp2m1 exp10m1 log2p1 log10p1 mirror the try forms" {
  // IEEE 754-2019 9.2: the checked methods record the result and the flags of
  // Decimal::try_*_ctx; log2p1(-1) and log10p1(-1) are poles (9.2.1).
  let context = @decimal.DecimalContext::decimal64()
  inspect(DecimalChecked::from_int(4, context).exp2m1().value(), content="15")
  inspect(DecimalChecked::from_int(2, context).exp10m1().value(), content="99")
  inspect(
    DecimalChecked::from_int(1023, context).log2p1().value(),
    content="10",
  )
  inspect(DecimalChecked::from_int(999, context).log10p1().value(), content="3")
  let half = DecimalChecked::from_decimal(
    @decimal.Decimal::from_string("0.5").unwrap(),
    context,
  ).exp2m1()
  inspect(half.value(), content="0.4142135623730950")
  assert_true(half.raised().contains(@decimal.DecimalSignal::Inexact))
  let pole = DecimalChecked::from_int(-1, context).log2p1()
  assert_true(pole.value().is_infinite())
  assert_true(pole.raised().contains(@decimal.DecimalSignal::DivisionByZero))
  let ten_pole = DecimalChecked::from_int(-1, context).log10p1()
  assert_true(
    ten_pole.raised().contains(@decimal.DecimalSignal::DivisionByZero),
  )
}

///|
test "decimal checked rsqrt compound powr mirror the try forms" {
  // IEEE 754-2019 9.2: the checked methods record the result and flags of
  // Decimal::try_*_ctx; rSqrt(+-0) and compound(-1, n < 0) are poles (9.2.1).
  let context = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(
    DecimalChecked::from_decimal(d("0.25"), context).rsqrt().value(),
    content="2",
  )
  inspect(
    DecimalChecked::from_decimal(d("0.1"), context).compound(2).value(),
    content="1.21",
  )
  inspect(
    DecimalChecked::from_int(8, context).powr(d("0.5")).value(),
    content="2.828427124746190",
  )
  let pole = DecimalChecked::from_int(0, context).rsqrt()
  assert_true(pole.raised().contains(@decimal.DecimalSignal::DivisionByZero))
  let compound_pole = DecimalChecked::from_int(-1, context).compound(-2)
  assert_true(
    compound_pole.raised().contains(@decimal.DecimalSignal::DivisionByZero),
  )
  let invalid = DecimalChecked::from_int(0, context).powr(d("0"))
  assert_true(
    invalid.raised().contains(@decimal.DecimalSignal::InvalidOperation),
  )
}
