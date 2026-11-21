///|
// oracle: A
// source: hand-derived: sqrt(1.2E-19) = 3.46E-10, Etiny -10 at p2 emin -9 -> 3E-10 with Underflow Subnormal
//   Inexact Rounded; CPython agrees
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA sqrt rounds directly at subnormal precision" {
  let ctx = GdaContext::try_new(precision=2, e_min=-9, e_max=9).unwrap()
  let operand = Decimal::from_string("1.2E-19", precision=2).unwrap()
  let outcome = sqrt(operand, ctx)
  let result = outcome.value()
  assert_eq(result.to_string(), "3E-10")
  let flags = outcome.raised()
  assert_true(flags.contains(GdaSignal::Underflow))
  assert_true(flags.contains(GdaSignal::Subnormal))
  assert_true(flags.contains(GdaSignal::Inexact))
  assert_true(flags.contains(GdaSignal::Rounded))
}

///|
// oracle: A
// source: hand-derived: sqrt(6.25) = 2.5 exact tie at p1 -> half-even 2 (not the configured HalfUp, which would
//   give 3); CPython at p1 HalfUp gives 2 with Inexact Rounded
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA inexact sqrt always uses half-even" {
  let ctx = GdaContext::new(precision=1, rounding=GdaRoundingMode::HalfUp)
  let operand = Decimal::from_string("6.25", precision=3).unwrap()
  let outcome = sqrt(operand, ctx)
  assert_eq(outcome.value().to_string(), "2")
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
}
