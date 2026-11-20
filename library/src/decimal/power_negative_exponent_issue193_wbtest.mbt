///|
test "decimal power handles large negative exponents for fractional bases" {
  let base = Decimal::from_string("0.5").unwrap()
  let exponent = Decimal::from_string("-999999998").unwrap()
  let expected = [
    (DecimalRoundingMode::HalfEven, "inf"),
    (DecimalRoundingMode::HalfUp, "inf"),
    (DecimalRoundingMode::HalfDown, "inf"),
    (DecimalRoundingMode::Down, "9.999999999999999E+384"),
    (DecimalRoundingMode::Floor, "9.999999999999999E+384"),
    (DecimalRoundingMode::Ceiling, "inf"),
    (DecimalRoundingMode::Up, "inf"),
    (DecimalRoundingMode::ZeroFiveUp, "9.999999999999999E+384"),
  ]
  for (mode, expected_value) in expected {
    let context = DecimalContext::{
      ..DecimalContext::decimal64(),
      decimal_rounding: mode,
    }
    let (value, flags) = base.power_ctx(exponent, context)
    assert_eq(value.to_string(), expected_value)
    assert_true(flags.overflow && flags.inexact && flags.rounded)
  }
}

///|
test "decimal power bounds extreme negative exponent work" {
  let base = Decimal::from_string("0.5").unwrap()
  for exponent_text in ["-500000000", "-1999999997"] {
    let (value, flags) = base.power_ctx(
      Decimal::from_string(exponent_text).unwrap(),
      DecimalContext::decimal64(),
    )
    assert_eq(value.to_string(), "inf")
    assert_true(flags.overflow && flags.inexact && flags.rounded)
  }
}

///|
test "decimal power preserves negative overflow sign" {
  let base = Decimal::from_string("-0.5").unwrap()
  let odd = Decimal::from_string("-999999999").unwrap()
  let even = Decimal::from_string("-1000000000").unwrap()
  assert_eq(
    base.power_ctx(odd, DecimalContext::decimal64()).0.to_string(),
    "-inf",
  )
  assert_eq(
    base.power_ctx(even, DecimalContext::decimal64()).0.to_string(),
    "inf",
  )
}

///|
test "decimal power large fractional bases cover interchange formats and modes" {
  let bases = ["0.5", "-0.5", "-5E-1"]
  let exponents = [
    "-999999998", "-999999999", "-1000000000", "-1000000001", "-1E+9", "-1000000000.0",
    "-1000000001.0",
  ]
  let modes = [
    DecimalRoundingMode::HalfEven,
    DecimalRoundingMode::HalfUp,
    DecimalRoundingMode::HalfDown,
    DecimalRoundingMode::Down,
    DecimalRoundingMode::Floor,
  ]
  let contexts = [
    DecimalContext::decimal32(),
    DecimalContext::decimal64(),
    DecimalContext::decimal128(),
  ]
  for context in contexts {
    for mode in modes {
      let context = { ..context, decimal_rounding: mode, }
      for base_text in bases {
        for exponent_text in exponents {
          let (value, flags) = Decimal::from_string(base_text)
            .unwrap()
            .power_ctx(Decimal::from_string(exponent_text).unwrap(), context)
          assert_true(!value.is_nan() && flags.overflow)
        }
      }
    }
  }
}

///|
test "decimal power keeps finite values below overflow boundaries" {
  let cases = [
    ("0.9", "-1000", "5.721245194772949E+45"),
    ("0.9", "-2000", "3.273264657871256E+91"),
    ("0.99", "-10000", "4.446865812651755E+43"),
    ("0.19", "-500", "4.199518739829564E+360"),
    ("0.95", "-5000", "2.409758693747040E+111"),
    ("0.5", "-1270", "2.032799256770390E+382"),
  ]
  let context = DecimalContext::decimal64()
  for (base, exponent, expected) in cases {
    let (value, flags) = Decimal::from_string(base)
      .unwrap()
      .power_ctx(Decimal::from_string(exponent).unwrap(), context)
    assert_eq(value.to_string(), expected)
    assert_true(!flags.overflow)
  }
}

///|
test "decimal power checks both sides across all rounding modes" {
  let modes = [
    DecimalRoundingMode::HalfEven,
    DecimalRoundingMode::HalfUp,
    DecimalRoundingMode::HalfDown,
    DecimalRoundingMode::Down,
    DecimalRoundingMode::Floor,
    DecimalRoundingMode::Ceiling,
    DecimalRoundingMode::Up,
    DecimalRoundingMode::ZeroFiveUp,
  ]
  let p9 = DecimalContext::new(precision=9, e_min=-383, e_max=384).unwrap()
  for mode in modes {
    let context = { ..p9, decimal_rounding: mode, }
    let (finite, finite_flags) = Decimal::from_string("0.9")
      .unwrap()
      .power_ctx(Decimal::from_string("-1000").unwrap(), context)
    assert_true(finite.is_finite() && !finite_flags.overflow)
    if mode == DecimalRoundingMode::HalfEven {
      assert_eq(finite.to_string(), "5.72124519E+45")
      let (negative, negative_flags) = Decimal::from_string("-0.9")
        .unwrap()
        .power_ctx(Decimal::from_string("-999").unwrap(), context)
      assert_eq(negative.to_string(), "-5.14912068E+45")
      assert_true(!negative_flags.overflow)
    }
    let (near_limit, near_flags) = Decimal::from_string("0.5")
      .unwrap()
      .power_ctx(Decimal::from_string("-1270").unwrap(), context)
    assert_true(near_limit.is_finite() && !near_flags.overflow)
    let (overflow, overflow_flags) = Decimal::from_string("0.5")
      .unwrap()
      .power_ctx(Decimal::from_string("-1280").unwrap(), context)
    assert_true(overflow_flags.overflow && !overflow.is_nan())
  }
  let default_context = DecimalContext::new().unwrap()
  let (default_value, default_flags) = Decimal::from_string("0.5")
    .unwrap()
    .power_ctx(Decimal::from_string("-1999999997").unwrap(), default_context)
  assert_eq(
    default_value.to_string(),
    "2.659943448420222263365646200686070E+602059990",
  )
  assert_true(!default_flags.overflow)
}
