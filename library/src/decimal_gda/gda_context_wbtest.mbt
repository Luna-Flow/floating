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
      assert_true(context.flags().contains(GdaSignal::DivisionByZero))
    }
    GdaOutcome::Trapped(_, _, _, _) =>
      fail("explicitly disabled traps must complete")
  }
  let trapped = divide(
    operand,
    divisor,
    GdaContext::basic_default().trap(GdaSignal::DivisionByZero),
  )
  match trapped {
    GdaOutcome::Trapped(signal, value, context, raised) => {
      assert_true(signal == GdaSignal::DivisionByZero)
      assert_true(value.is_infinite())
      assert_true(raised.contains(GdaSignal::DivisionByZero))
      assert_true(context.flags().contains(GdaSignal::DivisionByZero))
    }
    GdaOutcome::Completed(_, _, _) => fail("enabled trap must trap")
  }
}

///|
test "GDA context exposes radix ten" {
  assert_eq(GdaContext::basic_default().radix(), 10)
}

///|
test "GDA try_new preserves validated context fields" {
  let traps = GdaTrapSet::new().with_signal(GdaSignal::Inexact)
  let context = GdaContext::try_new(
    precision=17,
    rounding=GdaRoundingMode::Floor,
    e_min=-34,
    e_max=34,
    clamp=true,
    extended=false,
    traps~,
  ).unwrap()
  assert_eq(context.precision(), 17)
  assert_true(context.rounding() == GdaRoundingMode::Floor)
  assert_eq(context.e_min(), -34)
  assert_eq(context.e_max(), 34)
  assert_true(context.clamp())
  assert_false(context.extended())
  assert_true(context.flags() == GdaFlags::new())
  assert_true(context.traps() == traps)
}

///|
test "GDA Decimal contextual conversion preserves exponent bounds and clamp" {
  let arithmetic = @lf_arith.ArithmeticContext::new(
    16,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  let context = DecimalContext::from_arithmetic_context(arithmetic).unwrap()
  assert_eq(context.precision(), 16)
  assert_eq(context.e_min(), -383)
  assert_eq(context.e_max(), 384)
  assert_true(context.clamp())
}

///|
test "GDA Decimal checked powers preserve arithmetic exponent bounds" {
  let context = @lf_arith.ArithmeticContext::new(7, e_min=-95, e_max=2)
  let result = @lf_arith.PowNatChecked::pow_nat_checked(
    Decimal::from_int(2, precision=7),
    10U,
    context,
  ).unwrap()
  assert_true(result.classify() == @lf_arith.FpClass::Infinity)
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
      assert_true(context.flags().contains(GdaSignal::DivisionByZero))
      assert_true(raised == GdaFlags::new())
    }
    GdaOutcome::Trapped(_, _, _, _) => fail("exact addition must complete")
  }
}

///|
test "GDA trap selection preserves signal precedence" {
  let raised = {
    ..GdaFlags::new(),
    invalid_operation: true,
    division_by_zero: true,
    inexact: true,
  }
  let traps = GdaTrapSet::new()
    .with_signal(GdaSignal::Inexact)
    .with_signal(GdaSignal::DivisionByZero)
    .with_signal(GdaSignal::InvalidOperation)
  assert_true(
    trapped_signal(raised, traps) == Some(GdaSignal::InvalidOperation),
  )
  assert_true(
    trapped_signal({ ..raised, invalid_operation: false, }, traps) ==
    Some(GdaSignal::DivisionByZero),
  )
}

///|
test "GDA cached presets do not share sticky status or traps" {
  let configured = GdaContext::basic_default().trap(GdaSignal::DivisionByZero)
  let outcome = divide(
    Decimal::one(precision=9),
    Decimal::zero(precision=9),
    configured,
  )
  assert_true(
    outcome.next_context().flags().contains(GdaSignal::DivisionByZero),
  )
  let fresh = GdaContext::basic_default()
  assert_true(!fresh.flags().contains(GdaSignal::DivisionByZero))
  assert_true(fresh.traps().contains(GdaSignal::DivisionByZero))
  assert_eq(GdaContext::decimal32().precision(), 7)
  assert_eq(GdaContext::decimal64().precision(), 16)
  assert_eq(GdaContext::decimal128().precision(), 34)
}

///|
test "GDA basic context matches the 1.70 defaults" {
  let ctx = GdaContext::basic_default()
  assert_eq(ctx.precision(), 9)
  assert_true(ctx.rounding() == GdaRoundingMode::HalfUp)
  assert_true(!ctx.extended())
  assert_true(ctx.flags() == GdaFlags::new())
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
  let outcome = to_number(
    "not-a-number",
    GdaContext::new().trap(GdaSignal::InvalidOperation),
  )
  match outcome {
    GdaOutcome::Trapped(signal, value, context, raised) => {
      assert_true(signal == GdaSignal::InvalidOperation)
      assert_true(value.is_qnan())
      assert_true(raised.conversion_syntax())
      assert_true(raised.contains(GdaSignal::InvalidOperation))
      assert_true(context.flags().conversion_syntax())
      assert_true(context.flags().contains(GdaSignal::InvalidOperation))
    }
    GdaOutcome::Completed(_, _, _) =>
      fail("ConversionSyntax must trigger the InvalidOperation trap")
  }
}

///|
test "GDA Decimal checked integer powers use the exact exponent" {
  // An exponent longer than the context precision must not be rounded
  // before use: rounding 12345679 to seven digits makes it even (#51).
  let context = @lf_arith.ArithmeticContext::new(7)
  let minus_one = Decimal::from_int(-1, precision=7)
  let int_power = fn(exponent : Int32) {
    @lf_arith.PowIntChecked::pow_int_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  let nat_power = fn(exponent : UInt32) {
    @lf_arith.PowNatChecked::pow_nat_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  assert_eq(int_power(12345679), "-1")
  assert_eq(int_power(-12345679), "-1")
  assert_eq(int_power(12345678), "1")
  assert_eq(int_power(2147483647), "-1")
  assert_eq(int_power(-2147483648), "1")
  assert_eq(nat_power(12345679U), "-1")
  assert_eq(nat_power(999999999U), "-1")
  assert_eq(nat_power(999999998U), "1")
}

///|
/// GDA 1.70, pages 51 and 52: Conversion syntax, Division impossible, Division
/// undefined and Invalid context each signal invalid-operation. The library
/// raises the specific condition (the decTest files name conditions, and
/// `Conversion_syntax` and `Invalid_context` come without the plain
/// `Invalid_operation`); the signal is read with `contains` and trapped with the
/// one trap-enabler of the signal.
test "the four conditions that signal invalid-operation are raised, read and trapped as InvalidOperation" {
  let plain = GdaContext::new(precision=5)
  let trapping = plain.trap(GdaSignal::InvalidOperation)
  let ten_to_ten = Decimal::from_string("1E+10").unwrap()
  let one = Decimal::from_int(1)
  let zero = Decimal::from_int(0)
  let cases : Array[(String, GdaOutcome[Decimal], GdaOutcome[Decimal], Bool)] = [
    // condition, untrapped outcome, trapped outcome, plain invalid_operation field
    (
      "conversion_syntax",
      to_number("abc", plain),
      to_number("abc", trapping),
      false,
    ),
    (
      "division_undefined",
      divide(zero, zero, plain),
      divide(zero, zero, trapping),
      true,
    ),
    (
      "division_impossible",
      divide_integer(ten_to_ten, one, plain),
      divide_integer(ten_to_ten, one, trapping),
      true,
    ),
    (
      "invalid_context",
      exp(one, GdaContext::new(precision=5_000_000)),
      exp(
        one,
        GdaContext::new(precision=5_000_000).trap(GdaSignal::InvalidOperation),
      ),
      false,
    ),
  ]
  for case in cases {
    let (name, untrapped, trapped, plain_field) = case
    let raised = untrapped.raised()
    let specific = match name {
      "conversion_syntax" => raised.conversion_syntax()
      "division_undefined" => raised.division_undefined()
      "division_impossible" => raised.division_impossible()
      _ => raised.invalid_context()
    }
    assert_true(specific)
    assert_true(raised.contains(GdaSignal::InvalidOperation))
    assert_eq(raised.invalid_operation(), plain_field)
    assert_true(
      untrapped.next_context().flags().contains(GdaSignal::InvalidOperation),
    )
    match trapped {
      Trapped(signal, _, _, _) =>
        assert_true(signal == GdaSignal::InvalidOperation)
      Completed(_, _, _) =>
        fail("\{name} must trigger the InvalidOperation trap")
    }
  }
}

///|
test "a trap-enabler exists for each of the nine signals and nothing else traps" {
  let all : Array[GdaSignal] = [
    Clamped,
    DivisionByZero,
    Inexact,
    InvalidOperation,
    LostDigits,
    Overflow,
    Rounded,
    Subnormal,
    Underflow,
  ]
  for signal in all {
    let only = GdaTrapSet::new().with_signal(signal)
    for other in all {
      assert_eq(only.contains(other), other == signal)
    }
    assert_true(!only.with_signal(signal, enabled=false).contains(signal))
  }
}

///|
test "the first trapped signal follows the handler order" {
  let traps = GdaTrapSet::new()
    .with_signal(GdaSignal::Inexact)
    .with_signal(GdaSignal::Rounded)
    .with_signal(GdaSignal::Overflow)
  let context = GdaContext::new(precision=3, e_min=-9, e_max=9, traps~)
  // overflow raises Inexact and Rounded too: Overflow is the trapped signal
  match
    multiply(
      Decimal::from_string("9.99E+9").unwrap(),
      Decimal::from_int(10),
      context,
    ) {
    Trapped(signal, _, _, _) => assert_true(signal == GdaSignal::Overflow)
    Completed(_, _, _) => fail("overflow must trap")
  }
}
