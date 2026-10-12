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
