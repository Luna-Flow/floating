///|
test "GDA noninteger power preserves GDA cohort and flags" {
  let context = GdaContext::new(precision=9, e_min=-999_999, e_max=999_999)
  let base = Decimal::from_int(4, precision=32)
  let exponent = Decimal::from_string("0.5", precision=32).unwrap()
  let outcome = power(base, exponent, context)
  assert_eq(outcome.value().to_string(), "2.00000000")
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
}

///|
test "GDA transcendental operations finalize with half even" {
  let half_even = GdaContext::new(precision=3, e_min=-999_999, e_max=999_999)
  let upward = GdaContext::new(
    precision=3,
    rounding=GdaRoundingMode::Up,
    e_min=-999_999,
    e_max=999_999,
  )
  let value = Decimal::from_string("0.01").unwrap()
  let even = exp(value, half_even)
  let directed = exp(value, upward)
  assert_eq(even.value().to_string(), "1.01")
  assert_eq(directed.value().to_string(), "1.01")
  assert_true(even.raised().contains(GdaSignal::Rounded))
  assert_true(even.raised().contains(GdaSignal::Inexact))
  assert_eq(ln(Decimal::from_int(2), half_even).value().to_string(), "0.693")
  assert_eq(log10(Decimal::from_int(2), half_even).value().to_string(), "0.301")
}

///|
test "GDA extreme exp uses HalfEven without endpoint expansion" {
  let context = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Up,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let outcome = exp(Decimal::from_int(-100_000_000), context)
  assert_true(outcome.value().is_zero())
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_true(outcome.raised().contains(GdaSignal::Underflow))
  assert_true(outcome.raised().contains(GdaSignal::Subnormal))
  assert_true(outcome.raised().contains(GdaSignal::Clamped))
}

///|
test "GDA finite extreme-range exp certifies without full decimal expansion" {
  let context = GdaContext::new(precision=7, e_min=-999_999, e_max=999_999)
  let outcome = exp(Decimal::from_int(-1_000_000), context)
  assert_eq(outcome.value().to_string(), "3.296831E-434295")
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_false(outcome.raised().contains(GdaSignal::Underflow))
}

///|
test "GDA power certifies directed overflow and underflow cells" {
  let down = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Down,
    e_min=-99,
    e_max=99,
  )
  let finite = power(
    Decimal::from_int(17),
    Decimal::from_string("81.27115").unwrap(),
    down,
  )
  assert_eq(finite.value().to_string(), "9.999973E+99")
  let overflow = power(
    Decimal::from_int(17),
    Decimal::from_string("81.27116").unwrap(),
    down,
  )
  assert_eq(overflow.value().to_string(), "9.999999E+99")
  assert_true(overflow.raised().contains(GdaSignal::Overflow))
  let floor = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Floor,
    e_min=-95,
    e_max=96,
  )
  let underflow = power(
    Decimal::from_string("1e-101").unwrap(),
    Decimal::from_string("1.000001").unwrap(),
    floor,
  )
  assert_eq(underflow.value().to_string(), "0E-101")
  assert_true(underflow.raised().contains(GdaSignal::Underflow))
  assert_true(underflow.raised().contains(GdaSignal::Subnormal))
}

///|
test "GDA square-root power preserves zero and tiny-result conditions" {
  let zero = power(
    Decimal::from_string("0.000").unwrap(),
    Decimal::from_string("0.5").unwrap(),
    GdaContext::new(precision=9),
  )
  assert_eq(zero.value().to_string(), "0")
  assert_true(zero.raised() == GdaFlags::none())
  let tiny = power(
    Decimal::from_string("1E-20").unwrap(),
    Decimal::from_string("0.5").unwrap(),
    GdaContext::new(precision=12, e_min=-9, e_max=9),
  )
  assert_eq(tiny.value().to_string(), "1.0000000000E-10")
  assert_true(tiny.raised().contains(GdaSignal::Rounded))
  assert_true(tiny.raised().contains(GdaSignal::Inexact))
  assert_true(tiny.raised().contains(GdaSignal::Underflow))
  assert_true(tiny.raised().contains(GdaSignal::Subnormal))
}

///|
test "GDA classic subset retains legacy math flags and adjacent ln" {
  let subset = GdaContext::new(
    precision=17,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  let logarithm = ln(
    Decimal::from_string("0.99999991000000405").unwrap(),
    subset,
  )
  assert_eq(logarithm.value().to_string(), "-8.9999999999999879E-8")
  let exp_subset = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let tiny_exp = exp(Decimal::from_int(-1000), exp_subset)
  assert_true(tiny_exp.raised().contains(GdaSignal::Underflow))
  assert_true(tiny_exp.raised().contains(GdaSignal::Clamped))
  let power_subset = GdaContext::new(
    precision=9,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999_999_999,
    e_max=999_999_999,
    extended=false,
  )
  let invalid = power(
    Decimal::from_int(7),
    Decimal::from_int(1_000_000_001),
    power_subset,
  )
  assert_true(invalid.raised().contains(GdaSignal::InvalidContext))
  assert_true(invalid.raised().contains(GdaSignal::Rounded))
  assert_true(invalid.raised().contains(GdaSignal::Inexact))
  assert_true(invalid.raised().contains(GdaSignal::LostDigits))
}
