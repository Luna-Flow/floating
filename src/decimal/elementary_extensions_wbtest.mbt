///|
test "Decimal elementary extensions preserve exact identities" {
  let context = DecimalContext::decimal64().ieee754()
  let (power_two, power_two_flags) = Decimal::from_int(10).exp2_ctx(context)
  assert_eq(power_two.compare(Decimal::from_int(1024)), 0)
  assert_false(power_two_flags.inexact)
  let (power_ten, power_ten_flags) = Decimal::from_int(-2).exp10_ctx(context)
  assert_eq(power_ten.compare(Decimal::from_string("0.01").unwrap()), 0)
  assert_false(power_ten_flags.inexact)
  let (hypotenuse, hypot_flags) = Decimal::from_int(3).hypot_ctx(
    Decimal::from_int(4),
    context,
  )
  assert_eq(hypotenuse.compare(Decimal::from_int(5)), 0)
  assert_false(hypot_flags.inexact)
}

///|
test "Decimal pi-scaled functions follow IEEE exact special values" {
  let context = DecimalContext::decimal64().ieee754()
  let (negative_integer_sine, sine_flags) = Decimal::from_int(-1).sinpi_ctx(
    context,
  )
  assert_true(negative_integer_sine.is_negative_zero())
  assert_false(sine_flags.inexact)
  let half = Decimal::from_string("0.5").unwrap()
  let (half_sine, half_sine_flags) = half.sinpi_ctx(context)
  assert_eq(half_sine.compare(Decimal::one()), 0)
  assert_false(half_sine_flags.inexact)
  let (half_cosine, half_cosine_flags) = half.cospi_ctx(context)
  assert_true(half_cosine.is_zero())
  assert_false(half_cosine.is_negative_zero())
  assert_false(half_cosine_flags.inexact)
  let (half_tangent, half_tangent_flags) = half.tanpi_ctx(context)
  assert_true(half_tangent.is_infinite())
  assert_false(half_tangent.is_negative())
  assert_true(half_tangent_flags.division_by_zero)
}

///|
test "Decimal elementary domains and atan2 signed zeros are explicit" {
  let context = DecimalContext::decimal64().ieee754()
  let (invalid, invalid_flags) = Decimal::from_int(2).asin_ctx(context)
  assert_true(invalid.is_nan())
  assert_true(invalid_flags.invalid_operation)
  let (negative_axis_zero, zero_flags) = Decimal::negative_zero().atan2_ctx(
    Decimal::zero(),
    context,
  )
  assert_true(negative_axis_zero.is_negative_zero())
  assert_false(zero_flags.has_error())
}

///|
test "Decimal try power exposes certified evaluation as Result" {
  let context = DecimalContext::decimal64().ieee754()
  match
    Decimal::from_int(9).try_power_ctx(
      Decimal::from_string("0.5").unwrap(),
      context,
    ) {
    Ok((value, flags)) => {
      assert_eq(value.compare(Decimal::from_int(3)), 0)
      assert_false(flags.inexact)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "Decimal noninteger power preserves IEEE exact result semantics" {
  let ieee_context = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  ).ieee754()
  let base = Decimal::from_int(4, precision=32)
  let exponent = Decimal::from_string("0.5", precision=32).unwrap()
  let (ieee_value, ieee_flags) = base.power_ctx(exponent, ieee_context)
  assert_eq(ieee_value.to_string(), "2")
  assert_false(ieee_flags.rounded)
  assert_false(ieee_flags.inexact)
}

///|
test "Decimal elementary extensions honor context rounding" {
  let floor_context = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::Floor,
    e_min=-999,
    e_max=999,
  ).ieee754()
  let ceiling_context = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::Ceiling,
    e_min=-999,
    e_max=999,
  ).ieee754()
  let floor_result = Decimal::one().exp_ctx(floor_context)
  let ceiling_result = Decimal::one().exp_ctx(ceiling_context)
  assert_true(floor_result.0.compare(ceiling_result.0) < 0)
  assert_true(floor_result.1.inexact)
  assert_true(ceiling_result.1.inexact)
}

///|
test "Decimal extreme exp avoids unbounded dyadic endpoint expansion" {
  let input = Decimal::from_int(-100_000_000, precision=16)
  for
    mode in [
      DecimalRoundingMode::HalfEven,
      DecimalRoundingMode::HalfUp,
      DecimalRoundingMode::HalfDown,
      DecimalRoundingMode::Down,
      DecimalRoundingMode::Floor,
      DecimalRoundingMode::Ceiling,
      DecimalRoundingMode::Up,
      DecimalRoundingMode::ZeroFiveUp,
    ] {
    let context = DecimalContext::new(
      precision=7,
      decimal_rounding=mode,
      e_min=-383,
      e_max=384,
      extended=false,
    )
    let (value, flags) = input.exp_ctx(context)
    match mode {
      Ceiling | Up | ZeroFiveUp => {
        assert_eq(value.to_string(), "1E-389")
        assert_false(flags.clamped)
      }
      Down | Floor | HalfEven | HalfUp | HalfDown => {
        assert_true(value.is_zero())
        assert_true(flags.clamped)
      }
    }
    assert_true(flags.rounded)
    assert_true(flags.inexact)
    assert_true(flags.underflow)
    assert_true(flags.subnormal)
  }
}

///|
test "Decimal extreme exp honors before and after rounding tininess" {
  let input = Decimal::from_int(-1000, precision=16)
  let after = DecimalContext::new(
    precision=1,
    decimal_rounding=DecimalRoundingMode::Up,
    e_min=-2,
    e_max=2,
    tininess=DecimalTininessDetection::AfterRounding,
  )
  let before = after.with_tininess(DecimalTininessDetection::BeforeRounding)
  let (after_value, after_flags) = input.exp_ctx(after)
  let (before_value, before_flags) = input.exp_ctx(before)
  assert_eq(after_value.to_string(), "0.01")
  assert_eq(before_value.to_string(), "0.01")
  assert_true(after_flags.rounded && after_flags.inexact)
  assert_false(after_flags.underflow)
  assert_false(after_flags.subnormal)
  assert_true(before_flags.underflow)
  assert_true(before_flags.subnormal)
}
