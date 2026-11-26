///|
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3, 7.4: 0.5^(-999999998) = 2^999999998 is about 10^300000000, far above the largest decimal64 number, so overflow with inexact: infinity when rounding to nearest or up (half-even, half-up, half-down, ceiling, up) and 9.999999999999999E+384 when rounding toward zero or down (down, floor, 05up, which discards toward zero); CPython decimal plus of 1E+500 in the eight modes agrees
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
test "decimal power handles large negative exponents for fractional bases" {
  let base = Decimal::from_string("0.5").unwrap()
  let exponent = Decimal::from_string("-999999998").unwrap()
  let expected = [
    (DecimalRound::HalfEven, "inf"),
    (DecimalRound::HalfUp, "inf"),
    (DecimalRound::HalfDown, "inf"),
    (DecimalRound::Down, "9.999999999999999E+384"),
    (DecimalRound::Floor, "9.999999999999999E+384"),
    (DecimalRound::Ceiling, "inf"),
    (DecimalRound::Up, "inf"),
    (DecimalRound::ZeroFiveUp, "9.999999999999999E+384"),
  ]
  for (mode, expected_value) in expected {
    let context = DecimalContext::{
      ..DecimalContext::decimal64(),
      decimal_rounding: mode,
    }
    let (value, flags) = base.pow_ctx(exponent, context)
    assert_eq(value.to_string(), expected_value)
    assert_true(flags.overflow && flags.inexact)
  }
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 7.4: 0.5^(-500000000) and 0.5^(-1999999997) are 2^500000000 and 2^1999999997, far above 10^385, so +infinity with overflow and inexact (to nearest)
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
test "decimal power bounds extreme negative exponent work" {
  let base = Decimal::from_string("0.5").unwrap()
  for exponent_text in ["-500000000", "-1999999997"] {
    let (value, flags) = base.pow_ctx(
      Decimal::from_string(exponent_text).unwrap(),
      DecimalContext::decimal64(),
    )
    assert_eq(value.to_string(), "inf")
    assert_true(flags.overflow && flags.inexact)
  }
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 and 7.4: (-0.5)^(-999999999) = -(2^999999999) overflows to -infinity (odd exponent) and (-0.5)^(-1000000000) to +infinity (even exponent)
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
test "decimal power preserves negative overflow sign" {
  let base = Decimal::from_string("-0.5").unwrap()
  let odd = Decimal::from_string("-999999999").unwrap()
  let even = Decimal::from_string("-1000000000").unwrap()
  assert_eq(
    base.pow_ctx(odd, DecimalContext::decimal64()).0.to_string(),
    "-inf",
  )
  assert_eq(
    base.pow_ctx(even, DecimalContext::decimal64()).0.to_string(),
    "inf",
  )
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 7.4: 2^999999998 and larger powers of two exceed the largest number of decimal32, decimal64 and decimal128 (10^97, 10^385, 10^6145), so every combination of base 0.5 or -0.5, exponent from -999999998 to -1000000001 (also spelled -1E+9 and -1000000000.0), format and the five directions raises overflow and returns a number (infinity or the largest finite number); the block asserts that property only
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
test "decimal power large fractional bases cover interchange formats and modes" {
  let bases = ["0.5", "-0.5", "-5E-1"]
  let exponents = [
    "-999999998", "-999999999", "-1000000000", "-1000000001", "-1E+9", "-1000000000.0",
    "-1000000001.0",
  ]
  let modes = [
    DecimalRound::HalfEven,
    DecimalRound::HalfUp,
    DecimalRound::HalfDown,
    DecimalRound::Down,
    DecimalRound::Floor,
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
            .pow_ctx(Decimal::from_string(exponent_text).unwrap(), context)
          assert_true(!value.is_nan() && flags.overflow)
        }
      }
    }
  }
}

///|
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline) (Context(prec=16, Emax=384)): 0.9^-1000, 0.9^-2000, 0.99^-10000, 0.19^-500, 0.95^-5000 and 0.5^-1270 (2^1270 = 1.4E+382, below 10^385) as written out, no overflow
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
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
      .pow_ctx(Decimal::from_string(exponent).unwrap(), context)
    assert_eq(value.to_string(), expected)
    assert_true(!flags.overflow)
  }
}

///|
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): 0.9^-1000 = 5.72124519E+45 and (-0.9)^-999 = -5.14912068E+45 at nine digits, 0.5^-1999997 at 34 digits in a context with e_max 999999999 = 2.659943448420222263365646200686070E+602059990; 0.5^-1270 is finite (2^1270 = 1.4E+382) and 0.5^-1280 overflows (2^1280 = 1.9E+385) at e_max 384 in each of the eight directions; written out
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx (the code under test)
test "decimal power checks both sides across all rounding modes" {
  let modes = [
    DecimalRound::HalfEven,
    DecimalRound::HalfUp,
    DecimalRound::HalfDown,
    DecimalRound::Down,
    DecimalRound::Floor,
    DecimalRound::Ceiling,
    DecimalRound::Up,
    DecimalRound::ZeroFiveUp,
  ]
  let p9 = DecimalContext::new(precision=9, e_max=384)
  for mode in modes {
    let context = { ..p9, decimal_rounding: mode, }
    let (finite, finite_flags) = Decimal::from_string("0.9")
      .unwrap()
      .pow_ctx(Decimal::from_string("-1000").unwrap(), context)
    assert_true(finite.is_finite() && !finite_flags.overflow)
    if mode == DecimalRound::HalfEven {
      assert_eq(finite.to_string(), "5.72124519E+45")
      let (negative, negative_flags) = Decimal::from_string("-0.9")
        .unwrap()
        .pow_ctx(Decimal::from_string("-999").unwrap(), context)
      assert_eq(negative.to_string(), "-5.14912068E+45")
      assert_true(!negative_flags.overflow)
    }
    let (near_limit, near_flags) = Decimal::from_string("0.5")
      .unwrap()
      .pow_ctx(Decimal::from_string("-1270").unwrap(), context)
    assert_true(near_limit.is_finite() && !near_flags.overflow)
    let (overflow, overflow_flags) = Decimal::from_string("0.5")
      .unwrap()
      .pow_ctx(Decimal::from_string("-1280").unwrap(), context)
    assert_true(overflow_flags.overflow && !overflow.is_nan())
  }
  let default_context = DecimalContext::new(e_max=999_999_999)
  let (default_value, default_flags) = Decimal::from_string("0.5")
    .unwrap()
    .pow_ctx(Decimal::from_string("-1999999997").unwrap(), default_context)
  assert_eq(
    default_value.to_string(),
    "2.659943448420222263365646200686070E+602059990",
  )
  assert_true(!default_flags.overflow)
}
