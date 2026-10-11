///|
test "context exponent minimum near Int::min does not wrap etiny" {
  let context = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let (parsed, parse_flags) = Decimal::from_string_ctx("1", context)
  inspect(parsed.to_string(), content="1")
  inspect(parse_flags.inexact, content="false")
  let (sum, sum_flags) = Decimal::one().add_ctx(Decimal::one(), context)
  inspect(sum.to_string(), content="2")
  inspect(sum_flags.inexact, content="false")
}

///|
/// IEEE 754-2019 §§3.3 and 7.4: results beyond e_max overflow to infinity
/// with Overflow, Inexact, and Rounded. next_plus is exact.
test "extreme e_max reports overflow without adjusted exponent wrap" {
  let ctx = DecimalContext::new(
    precision=3,
    e_min=-999_999_999,
    e_max=999_999_999,
    clamp=true,
  ).unwrap()
  let max = Decimal::make(999N, 999_999_997, 3)

  let (sum, sum_flags) = max.add_ctx(max, ctx)
  assert_true(sum.is_infinite())
  assert_true(
    sum_flags ==
    { ..DecimalFlags::new(), overflow: true, inexact: true, rounded: true, },
  )

  let (next, next_flags) = max.next_plus(ctx)
  assert_true(next.is_infinite())
  assert_true(next_flags == DecimalFlags::new())

  let (quotient, quotient_flags) = max.div_ctx(Decimal::make(1N, -1, 3), ctx)
  assert_true(quotient.is_infinite())
  assert_true(quotient_flags.overflow)
  assert_true(quotient_flags.inexact)
  assert_true(quotient_flags.rounded)
  assert_false(quotient_flags.subnormal)
  assert_false(quotient_flags.clamped)
}

///|
/// IEEE 754-2019 §5.3.2: quantize returns NaN with InvalidOperation when its
/// result cannot be represented; exponent distance must not wrap or abort.
test "quantize with extreme exponent distance returns invalid operation" {
  let ctx = DecimalContext::new(
    precision=5,
    e_min=-999_999_999,
    e_max=999_999_999,
    clamp=true,
  ).unwrap()
  let value = Decimal::make(1N, 1_999_999_996, 5)
  let quantum = Decimal::make(1N, -2_000_000_003, 5)
  let (result, flags) = value.quantize(quantum, ctx)
  assert_true(result.is_qnan())
  assert_true(flags == { ..DecimalFlags::new(), invalid_operation: true, })
}

///|
test "decimal context rejects out of range fields without aborting" {
  assert_true(DecimalContext::try_new(precision=999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(e_min=-999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(e_max=999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(precision=1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_min=-1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_max=1_000_000_000) is Err(_))
  assert_true(DecimalContext::new(precision=1_000_000_000) is Err(_))
  assert_true(DecimalContext::new(e_min=-1_000_000_000) is Err(_))
  assert_true(DecimalContext::new(e_max=1_000_000_000) is Err(_))
}

///|
/// GDA 1.70, Finite numbers; decNumber `decContext.h`: the adopted
/// implementation bounds require `e_min <= 0 <= e_max`.  D-F1 keeps the GDA
/// balance rule itself optional, so an asymmetric range such as -10..=10 is
/// valid; only the signs at the two boundaries are constrained.
test "decimal context rejects exponent bounds with invalid signs" {
  assert_true(DecimalContext::try_new(e_min=0, e_max=0) is Ok(_))
  assert_true(
    DecimalContext::try_new(e_min=-999_999_999, e_max=999_999_999) is Ok(_),
  )
  assert_true(DecimalContext::try_new(e_min=-10, e_max=10) is Ok(_))
  assert_true(DecimalContext::try_new(e_min=1, e_max=10) is Err(_))
  assert_true(DecimalContext::try_new(e_min=-10, e_max=-1) is Err(_))
  match DecimalContext::try_new(e_min=1, e_max=10) {
    Err(error) =>
      assert_eq(error.message, "e_min must be within -999999999..=0")
    Ok(_) => fail("positive e_min must be rejected")
  }
  match DecimalContext::try_new(e_min=-10, e_max=-1) {
    Err(error) => assert_eq(error.message, "e_max must be within 0..=999999999")
    Ok(_) => fail("negative e_max must be rejected")
  }
}

///|
/// IEEE 754-2019 §9.2.1: fused multiply-add rounds the exact product-plus-sum
/// once. An out-of-range product cannot be rescued by this negligible addend.
test "fma with maximum context exponents reports overflow" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let (value, flags) = Decimal::make(1N, 999_999_999, 34).fma_ctx(
    Decimal::make(1N, 999_999_997, 34),
    Decimal::make(1N, -999_999_999, 34),
    ctx,
  )
  assert_true(value.is_infinite())
  assert_true(flags.overflow && flags.inexact && flags.rounded)
}

///|
/// GDA quantize and round-to-integral preserve their requested quantum. A
/// shift beyond Int is necessarily sticky and rounds to zero at that quantum.
test "huge quantize and to-integral shifts round to zero" {
  let ctx = DecimalContext::new(
    precision=1,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let tiny = Decimal::make(1N, -2_147_483_648, 1)
  let (quantized, quantize_flags) = tiny.quantize(
    Decimal::make(1N, 999_999_999, 1),
    ctx,
  )
  assert_true(quantized.is_zero())
  assert_eq(quantized.exponent10, 999_999_999)
  assert_true(quantize_flags.inexact && quantize_flags.rounded)
  assert_false(quantize_flags.invalid_operation)

  let (exact, exact_flags) = tiny.to_integral_exact(ctx)
  assert_true(exact.is_zero())
  assert_eq(exact.exponent10, 0)
  assert_true(exact_flags.inexact && exact_flags.rounded)
  let (silent, silent_flags) = tiny.to_integral_value(ctx)
  assert_true(silent.is_zero())
  assert_false(silent_flags.inexact || silent_flags.rounded)
}

///|
/// next* must handle an operand exponent at Int::min even when Etiny is zero.
test "next operations handle Int minimum with zero etiny" {
  let ctx = DecimalContext::new(precision=1, e_min=0, e_max=999_999_999).unwrap()
  let tiny = Decimal::make(1N, -2_147_483_648, 34)
  let (plus, plus_flags) = tiny.next_plus(ctx)
  assert_eq(plus.to_string(), "1")
  assert_true(plus_flags == DecimalFlags::new())
  let (minus, minus_flags) = tiny.next_minus(ctx)
  assert_true(minus.is_zero())
  assert_true(minus_flags == DecimalFlags::new())
  let (toward, toward_flags) = tiny.next_toward(Decimal::zero(), ctx)
  assert_true(toward.is_zero())
  assert_true(
    toward_flags.underflow && toward_flags.inexact && toward_flags.rounded,
  )
}

///|
test "fma far gap uses sticky addend without aborting" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let (value, flags) = Decimal::make(1N, -999_999_999, 34).fma_ctx(
    Decimal::make(1N, -999_999_999, 34),
    Decimal::make(1N, 999_999_999, 34),
    ctx,
  )
  inspect(
    value.to_string(),
    content="1.000000000000000000000000000000000E+999999999",
  )
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
  inspect(flags.rounded, content="true")
}

///|
test "fma exact product boundary honors negative addend" {
  let ctx = DecimalContext::new(
    precision=2,
    e_min=-999_999_999,
    e_max=0,
    rounding=RoundingMode::TowardZero,
    decimal_rounding=DecimalRoundingMode::Down,
  ).unwrap()
  let (value, flags) = Decimal::make(1N, 6, 2).fma_ctx(
    Decimal::make(1N, -5, 2),
    Decimal::make(-9N, -4, 2),
    ctx,
  )
  inspect(value.to_string(), content="9.9")
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
  inspect(flags.rounded, content="true")
}

///|
test "fma exact product boundary follows floor without overflow" {
  let ctx = DecimalContext::new(
    precision=2,
    e_min=-999_999_999,
    e_max=0,
    decimal_rounding=DecimalRoundingMode::Floor,
  ).unwrap()
  let (value, flags) = Decimal::make(1N, 6, 2).fma_ctx(
    Decimal::make(1N, -5, 2),
    Decimal::make(-9N, -4, 2),
    ctx,
  )
  inspect(value.to_string(), content="9.9")
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
  inspect(flags.rounded, content="true")
}

///|
test "fma product below Int range uses a bounded sticky alignment" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let (value, flags) = Decimal::make(1N, -2_147_483_648, 34).fma_ctx(
    Decimal::make(1N, -2_147_483_648, 34),
    Decimal::make(1N, 999_999_999, 34),
    ctx,
  )
  inspect(
    value.to_string(),
    content="1.000000000000000000000000000000000E+999999999",
  )
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
  inspect(flags.rounded, content="true")
}
