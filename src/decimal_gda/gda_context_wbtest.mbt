///|
test "GDA outcomes retain sticky status and defined trap results" {
  let operand = Decimal::one(precision=9)
  let divisor = Decimal::zero(precision=9)
  let disabled = divide(
    operand,
    divisor,
    GdaContext::new(
      precision=9,
      rounding=GdaRoundingMode::HalfUp,
      extended=false,
    ),
  )
  match disabled {
    GdaOutcome::Completed(value, context, raised) => {
      assert_true(value.is_infinite())
      assert_true(raised.contains(GdaSignal::DivisionByZero))
      assert_true(context.status().contains(GdaSignal::DivisionByZero))
    }
    GdaOutcome::Trapped(_, _, _, _) =>
      fail("explicitly disabled traps must complete")
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

///|
test "GDA exact outcomes preserve sticky status without raising flags" {
  let sticky = divide(
    Decimal::one(precision=9),
    Decimal::zero(precision=9),
    GdaContext::new(),
  ).next_context()
  let outcome = add(
    Decimal::one(precision=9),
    Decimal::one(precision=9),
    sticky,
  )
  match outcome {
    GdaOutcome::Completed(value, context, raised) => {
      assert_eq(value.to_string(), "2")
      assert_true(context.status().contains(GdaSignal::DivisionByZero))
      assert_true(raised == GdaFlags::none())
    }
    GdaOutcome::Trapped(_, _, _, _) => fail("exact addition must complete")
  }
}

///|
test "GDA trap selection preserves signal precedence" {
  let raised = {
    ..GdaFlags::none(),
    invalid_operation: true,
    division_by_zero: true,
    inexact: true,
  }
  let traps = GdaTrapSet::none()
    .with_signal(GdaSignal::Inexact)
    .with_signal(GdaSignal::DivisionByZero)
    .with_signal(GdaSignal::InvalidOperation)
  assert_true(
    trapped_signal(raised, traps) == Some(GdaSignal::InvalidOperation),
  )
  assert_true(
    trapped_signal({ ..raised, invalid_operation: false }, traps) ==
    Some(GdaSignal::DivisionByZero),
  )
}

///|
test "GDA cached presets do not share sticky status or traps" {
  let configured = GdaContext::basic().trap(GdaSignal::DivisionByZero)
  let outcome = divide(
    Decimal::one(precision=9),
    Decimal::zero(precision=9),
    configured,
  )
  assert_true(
    outcome.next_context().status().contains(GdaSignal::DivisionByZero),
  )
  let fresh = GdaContext::basic()
  assert_true(!fresh.status().contains(GdaSignal::DivisionByZero))
  assert_true(fresh.traps().contains(GdaSignal::DivisionByZero))
  assert_eq(GdaContext::decimal32().precision(), 7)
  assert_eq(GdaContext::decimal64().precision(), 16)
  assert_eq(GdaContext::decimal128().precision(), 34)
}

///|
test "GDA basic context matches the 1.70 defaults" {
  let ctx = GdaContext::basic()
  assert_eq(ctx.precision(), 9)
  assert_true(ctx.rounding() == GdaRoundingMode::HalfUp)
  assert_true(!ctx.extended())
  assert_true(ctx.status() == GdaFlags::none())
  let traps = ctx.traps()
  assert_true(traps.contains(GdaSignal::Clamped))
  assert_true(traps.contains(GdaSignal::DivisionByZero))
  assert_true(traps.contains(GdaSignal::InvalidOperation))
  assert_true(traps.contains(GdaSignal::Overflow))
  assert_true(traps.contains(GdaSignal::Underflow))
  assert_true(!traps.contains(GdaSignal::Inexact))
  assert_true(!traps.contains(GdaSignal::Rounded))
  assert_true(!traps.contains(GdaSignal::Subnormal))
  assert_true(!traps.contains(GdaSignal::LostDigits))
}

///|
test "GDA invalid conditions signal InvalidOperation" {
  let outcome = parse(
    "not-a-number",
    GdaContext::new().trap(GdaSignal::InvalidOperation),
  )
  match outcome {
    GdaOutcome::Trapped(signal, value, context, raised) => {
      assert_true(signal == GdaSignal::InvalidOperation)
      assert_true(value.is_qnan())
      assert_true(raised.contains(GdaSignal::ConversionSyntax))
      assert_true(raised.contains(GdaSignal::InvalidOperation))
      assert_true(context.status().contains(GdaSignal::ConversionSyntax))
      assert_true(context.status().contains(GdaSignal::InvalidOperation))
    }
    GdaOutcome::Completed(_, _, _) =>
      fail("ConversionSyntax must trigger the InvalidOperation trap")
  }
}
