///|
test "GDA sqrt rounds directly at subnormal precision" {
  let ctx = context(precision=2, e_min=-9, e_max=9)
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
test "GDA inexact sqrt always uses half-even" {
  let ctx = GdaContext::new(precision=1, rounding=GdaRoundingMode::HalfUp)
  let operand = Decimal::from_string("6.25", precision=3).unwrap()
  let outcome = sqrt(operand, ctx)
  assert_eq(outcome.value().to_string(), "2")
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
}
