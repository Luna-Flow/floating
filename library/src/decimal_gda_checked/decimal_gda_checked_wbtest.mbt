///|
// oracle: A
// source: spec: result inexact unless exact within precision; 0.01**0.5 = 0.1 padded to 0.1000
// shares: nothing
test "gda checked threads sticky status" {
  let context = @decimal_gda.GdaContext::new(precision=3)
  let parsed = GdaDecimalChecked::to_number("1.2345", context)
  assert_true(parsed.raised().contains(@decimal_gda.GdaSignal::Rounded))
  let result = parsed.add(
    GdaDecimalChecked::from_decimal(@decimal_gda.Decimal::zero(), context),
  )
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
  assert_true(result.flags().contains(@decimal_gda.GdaSignal::Rounded))
}

///|
// oracle: A
// source: literal operations; exponent gap over 2^31-1; operands equal to the large one after rounding
// shares: nothing
test "gda checked traps short circuit and preserve defined results" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let one = @decimal_gda.Decimal::one()
  let zero = @decimal_gda.Decimal::zero()
  let pipe = fn(v : @decimal_gda.Decimal) {
    GdaDecimalChecked::from_decimal(v, context)
  }
  let trapped = pipe(one).divide(pipe(zero))
  assert_true(trapped.is_err())
  assert_false(trapped.is_ok())
  assert_true(trapped.value().is_infinite())
  match trapped.error() {
    Some(signal) =>
      assert_true(signal == @decimal_gda.GdaSignal::DivisionByZero)
    None => fail("expected division-by-zero trap")
  }
  assert_true(trapped.result() is Err(@decimal_gda.GdaSignal::DivisionByZero))
  let still_trapped = trapped.add(pipe(one))
  assert_true(still_trapped.is_err())
  let resumed = trapped.resume_defined().add(pipe(one))
  assert_true(resumed.is_ok())
  assert_true(resumed.result() is Ok(_))
  assert_true(resumed.flags().contains(@decimal_gda.GdaSignal::DivisionByZero))
}

///|
// oracle: A
// source: hand derivation: to_number rounds 1.2345 at p3 to 1.23; 1 + 1.23 = 2.23; Python agrees (2.23); trap
//   short circuit rules of the pipeline
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
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
    let result = GdaDecimalChecked::from_decimal(base, context).power(
      GdaDecimalChecked::from_decimal(exponent, context),
    )
    assert_true(result.is_ok())
    assert_eq(result.value().to_string(), "0.000001000000000000000")
    assert_true(result.raised().contains(@decimal_gda.GdaSignal::Inexact))
    assert_true(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
    assert_false(
      result.raised().contains(@decimal_gda.GdaSignal::InvalidOperation),
    )
  }
}

///|
// oracle: A
// source: 10^-6 padded in 4 directed modes; value from spec; same row as the core test
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "gda checked power to a zero exponent is exactly 1 in a clamped context (issue 405)" {
  let context = @decimal_gda.GdaContext::new(
    precision=5,
    e_min=-1,
    e_max=0,
    clamp=true,
  )
  let base = @decimal_gda.Decimal::from_string("9.99").unwrap()
  let result = GdaDecimalChecked::from_decimal(base, context).power(
    GdaDecimalChecked::from_decimal(
      @decimal_gda.Decimal::zero(),
      @decimal_gda.GdaContext::new(),
    ),
  )
  assert_true(result.is_ok())
  assert_eq(result.value().to_string(), "1")
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Clamped))
}

///|
// oracle: A
// source: spec: x**0 is exactly 1; literal 1 and no Clamped
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "gda checked power to one half is the padded inexact result without Clamped (issue 397)" {
  let context = @decimal_gda.GdaContext::new(
    precision=4,
    rounding=@decimal_gda.GdaRoundingMode::Down,
    e_min=-1,
    e_max=0,
    clamp=true,
  )
  let base = @decimal_gda.Decimal::from_string("0.01").unwrap()
  let result = GdaDecimalChecked::from_decimal(base, context).power(
    GdaDecimalChecked::from_decimal(
      @decimal_gda.Decimal::from_string("0.5").unwrap(),
      @decimal_gda.GdaContext::new(),
    ),
  )
  assert_true(result.is_ok())
  assert_eq(result.value().to_string(), "0.1000")
  assert_true(result.raised().contains(@decimal_gda.GdaSignal::Inexact))
  assert_true(result.raised().contains(@decimal_gda.GdaSignal::Rounded))
  assert_false(result.raised().contains(@decimal_gda.GdaSignal::Clamped))
}

///|
/// S9: the right operand is a pipeline; its conditions join the result and its
/// trap short-circuits, the context of the left pipeline decides the operation.
// oracle: A
// source: literal strings for 17 checked operations (decTest-like values), hand derived
// shares: Decimal::to_string (printing the result)
test "gda checked merges the conditions and the trap of the right operand" {
  let left_context = @decimal_gda.GdaContext::new(precision=5)
  let right_context = @decimal_gda.GdaContext::new(precision=3)
  let left = GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::from_int(1),
    left_context,
  )
  // the right pipeline rounded while it was made: Inexact and Rounded
  let right = GdaDecimalChecked::to_number("1.2345", right_context)
  assert_true(right.raised().contains(@decimal_gda.GdaSignal::Inexact))
  let sum = left.add(right)
  // computed at the precision of the left context
  assert_eq(sum.value().to_string(), "2.23")
  assert_true(sum.raised().contains(@decimal_gda.GdaSignal::Inexact))
  assert_true(sum.flags().contains(@decimal_gda.GdaSignal::Inexact))
  assert_true(sum.context().precision() == 5)
  assert_true(sum.is_ok())
  // a trap of the right pipeline stops the operation and keeps the left value
  let trapping = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let bad = GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    trapping,
  ).divide(
    GdaDecimalChecked::from_decimal(@decimal_gda.Decimal::zero(), trapping),
  )
  assert_true(bad.is_err())
  let stopped = left.add(bad)
  assert_true(stopped.error() is Some(@decimal_gda.GdaSignal::DivisionByZero))
  assert_eq(stopped.value().to_string(), "1")
  assert_true(stopped.raised().contains(@decimal_gda.GdaSignal::DivisionByZero))
  // the left traps are not tested against the right conditions
  assert_true(stopped.context().traps() == left_context.traps())
  // a trapped left pipeline is returned as it is
  assert_true(
    bad.add(left).error() is Some(@decimal_gda.GdaSignal::DivisionByZero),
  )
  assert_eq(bad.add(left).value().to_string(), bad.value().to_string())
}

///|
test "gda checked covers the operations of the free functions that return a decimal" {
  let context = @decimal_gda.GdaContext::decimal64()
  let pipe = fn(text : String) { GdaDecimalChecked::to_number(text, context) }
  assert_eq(pipe("17").divide_integer(pipe("5")).value().to_string(), "3")
  assert_eq(pipe("17").remainder_near(pipe("5")).value().to_string(), "2")
  assert_eq(pipe("1.2345").rescale(pipe("-2")).value().to_string(), "1.23")
  assert_eq(pipe("2.5").round_to_integral_exact().value().to_string(), "2")
  assert_eq(pipe("2.5").round_to_integral_value().value().to_string(), "2")
  assert_eq(pipe("1.5").scaleb(pipe("3")).value().to_string(), "1.5E+3")
  assert_eq(pipe("12345").shift(pipe("2")).value().to_string(), "1234500")
  assert_eq(
    pipe("12345").rotate(pipe("-1")).value().to_string(),
    "5000000000001234",
  )
  assert_eq(pipe("0.00123").logb().value().to_string(), "-3")
  assert_eq(pipe("1100").logical_xor(pipe("1010")).value().to_string(), "110")
  assert_eq(pipe("1100").logical_and(pipe("1010")).value().to_string(), "1000")
  assert_eq(pipe("1100").logical_or(pipe("1010")).value().to_string(), "1110")
  assert_eq(
    pipe("1100").logical_invert().value().to_string(),
    "1111111111110011",
  )
  assert_eq(pipe("2.5").max(pipe("2.50")).value().to_string(), "2.5")
  assert_eq(pipe("2.5").min(pipe("3")).value().to_string(), "2.5")
  assert_eq(pipe("-3").max_magnitude(pipe("2")).value().to_string(), "-3")
  assert_eq(pipe("-3").min_magnitude(pipe("2")).value().to_string(), "2")
  assert_eq(pipe("1").compare(pipe("2")).value().to_string(), "-1")
  assert_true(
    pipe("NaN")
    .compare_signal(pipe("1"))
    .raised()
    .contains(@decimal_gda.GdaSignal::InvalidOperation),
  )
}
