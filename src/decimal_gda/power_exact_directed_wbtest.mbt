///|
test "power decides exact non-integral results in every rounding mode" {
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::ZeroFiveUp,
  ]
  let cases = [
    ("4", "1.5", "8.0000"),
    ("9", "1.5", "27.000"),
    ("16", "0.25", "2.0000"),
    ("0.25", "1.5", "0.12500"),
    ("4", "-1.5", "0.12500"),
  ]
  for mode in modes {
    let ctx = GdaContext::new(
      precision=5,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    for entry in cases {
      let (left, right, expected) = entry
      let outcome = power(
        Decimal::from_string(left).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().to_string(), expected)
      assert_true(outcome.raised().contains(GdaSignal::Inexact))
      assert_true(outcome.raised().contains(GdaSignal::Rounded))
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}

///|
test "power rounds an exact result longer than the precision" {
  // 2.25^1.5 = 3.375 is exact. At three digits it is the midpoint of
  // 3.37 and 3.38; at two digits it lies inside the cell (3.3, 3.4).
  let check = (precision : Int, mode : GdaRoundingMode, expected : String) => {
    let ctx = GdaContext::new(
      precision~,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    let outcome = power(
      Decimal::from_string("2.25").unwrap(),
      Decimal::from_string("1.5").unwrap(),
      ctx,
    )
    assert_eq(outcome.value().to_string(), expected)
    assert_true(outcome.raised().contains(GdaSignal::Inexact))
    assert_true(outcome.raised().contains(GdaSignal::Rounded))
  }
  check(3, GdaRoundingMode::HalfEven, "3.38")
  check(3, GdaRoundingMode::HalfUp, "3.38")
  check(3, GdaRoundingMode::HalfDown, "3.37")
  check(3, GdaRoundingMode::Down, "3.37")
  check(3, GdaRoundingMode::Up, "3.38")
  check(2, GdaRoundingMode::HalfEven, "3.4")
  check(2, GdaRoundingMode::Down, "3.3")
  check(2, GdaRoundingMode::Up, "3.4")
}

///|
/// `(2^1200 * 10^-1200)^1.5 = 2^1800 * 10^-1800` is exact at precision 1000
/// although `base^3` needs 1084 digits; so is `(5^1200)^-1.5`. Both are
/// decided in every mode instead of failing certification after minutes.
test "power decides exact non-integral results past base^p's size (#138)" {
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::ZeroFiveUp,
  ]
  let two_1200 = (BigInt::from_int(1) << 1200).to_string()
  let two_1800 = (BigInt::from_int(1) << 1800).to_string()
  let expected = Decimal::from_string("\{two_1800}E-1800", precision=1000).unwrap()
  let cases = [("\{two_1200}E-1200", "1.5"), (pow5(1200).to_string(), "-1.5")]
  for mode in modes {
    let ctx = GdaContext::new(
      precision=1000,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    for entry in cases {
      let (left, right) = entry
      let outcome = power(
        Decimal::from_string(left, precision=1000).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().compare(expected), 0)
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}

///|
test "power decides exact powers with large reduced exponents" {
  let cases = [
    (pow5(1024).to_string(), "0.0009765625", 720, "5"),
    ("0.25", "4096.5", 5800, "\{pow5(8193)}E-8193"),
  ]
  for entry in cases {
    let (left, right, precision, expected) = entry
    let want = Decimal::from_string(expected, precision~).unwrap()
    for
      mode in [
        GdaRoundingMode::HalfEven,
        GdaRoundingMode::Floor,
        GdaRoundingMode::Up,
      ] {
      let ctx = GdaContext::new(
        precision~,
        rounding=mode,
        e_min=-999_999,
        e_max=999_999,
      )
      let outcome = power(
        Decimal::from_string(left, precision~).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().compare(want), 0)
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}
