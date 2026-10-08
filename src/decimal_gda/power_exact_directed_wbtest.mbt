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
  // 2.25^1.5 = 3.375 is exact; at two digits it is a
  // midpoint for the half modes and lies inside a cell for the others.
  let check = (mode : GdaRoundingMode, expected : String) => {
    let ctx = GdaContext::new(
      precision=2,
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
  }
  check(GdaRoundingMode::HalfEven, "3.4")
  check(GdaRoundingMode::Down, "3.3")
  check(GdaRoundingMode::Up, "3.4")
}
