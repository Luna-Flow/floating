///|
test "GDA outcomes retain sticky status and defined trap results" {
  let operand = Decimal::one(precision=9)
  let divisor = Decimal::zero(precision=9)
  let disabled = divide(operand, divisor, GdaContext::basic())
  match disabled {
    GdaOutcome::Completed(value, context, raised) => {
      assert_true(value.is_infinite())
      assert_true(raised.contains(GdaSignal::DivisionByZero))
      assert_true(context.status().contains(GdaSignal::DivisionByZero))
    }
    GdaOutcome::Trapped(_, _, _, _) => fail("disabled traps must complete")
  }
  let trapped = divide(
    operand,
    divisor,
    GdaContext::basic().trap(GdaSignal::DivisionByZero),
  )
  match trapped {
    GdaOutcome::Trapped(signal, value, context, raised) => {
      assert_true(signal == GdaSignal::DivisionByZero)
      assert_true(value.is_infinite())
      assert_true(raised.contains(GdaSignal::DivisionByZero))
      assert_true(context.status().contains(GdaSignal::DivisionByZero))
    }
    GdaOutcome::Completed(_, _, _) => fail("enabled trap must trap")
  }
}

///|
test "GDA context exposes radix ten" {
  assert_eq(GdaContext::default().radix(), 10)
}
