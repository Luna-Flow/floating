///|
// oracle: A
// source: arithmetic: 1 parses to 1 exactly and 1 + 1 = 2 exactly, with no inexact flag, in a 34-digit context with e_max 999999999 (Etiny = -1999999965)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "context exponent minimum near Int::min does not wrap etiny" {
  let context = DecimalContext::new(precision=34, e_max=999_999_999)
  let (parsed, parse_flags) = Decimal::from_string_ctx("1", context)
  inspect(parsed.to_string(), content="1")
  inspect(parse_flags.inexact, content="false")
  let (sum, sum_flags) = Decimal::one().add_ctx(Decimal::one(), context)
  inspect(sum.to_string(), content="2")
  inspect(sum_flags.inexact, content="false")
}

///|
/// IEEE 754-2019 §§3.3 and 7.4: results beyond e_max overflow to infinity
/// with Overflow, Inexact, and Rounded. next_up_ctx is exact.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) and IEEE 754-2019 7.4: 999E+999999997 + 999E+999999997 and 999E+999999997 / 0.1 overflow to infinity with overflow and inexact, and next_up of the largest finite number is exact infinity with no flag (5.3.1)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "extreme e_max reports overflow without adjusted exponent wrap" {
  let ctx = DecimalContext::new(precision=3, e_max=999_999_999)
  let max = Decimal::make(999N, 999_999_997, 3)

  let (sum, sum_flags) = max.add_ctx(max, ctx)
  assert_true(sum.is_infinite())
  assert_true(
    sum_flags == { ..DecimalFlags::new(), overflow: true, inexact: true, },
  )

  let (next, next_flags) = max.next_up_ctx(ctx)
  assert_true(next.is_infinite())
  assert_true(next_flags == DecimalFlags::new())

  let (quotient, quotient_flags) = max.div_ctx(Decimal::make(1N, -1, 3), ctx)
  assert_true(quotient.is_infinite())
  assert_true(quotient_flags.overflow)
  assert_true(quotient_flags.inexact)
}

///|
/// IEEE 754-2019 §5.3.2: quantize returns NaN with InvalidOperation when its
/// result cannot be represented; exponent distance must not wrap or abort.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) and IEEE 754-2019 5.3.2: quantizing 1E+1999999996 to the quantum 1E-2000000003 needs more than the precision digits, so NaN with invalid operation (CPython agrees)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "quantize with extreme exponent distance returns invalid operation" {
  let ctx = DecimalContext::new(precision=5, e_max=999_999_999)
  let value = Decimal::make(1N, 1_999_999_996, 5)
  let quantum = Decimal::make(1N, -2_000_000_003, 5)
  let (result, flags) = value.quantize_ctx(quantum, ctx)
  assert_true(result.is_quiet_nan())
  assert_true(flags == { ..DecimalFlags::new(), invalid_operation: true, })
}

///|
/// IEEE 754-2019 §9.2.1: fused multiply-add rounds the exact product-plus-sum
/// once. An out-of-range product cannot be rescued by this negligible addend.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26): 1E+999999999 * 1E+999999997 + 1E-999999999 overflows to infinity with overflow and inexact (IEEE 754-2019 7.4)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "fma with maximum context exponents reports overflow" {
  let ctx = DecimalContext::new(precision=34, e_max=999_999_999)
  let (value, flags) = Decimal::make(1N, 999_999_999, 34).fma_ctx(
    Decimal::make(1N, 999_999_997, 34),
    Decimal::make(1N, -999_999_999, 34),
    ctx,
  )
  assert_true(value.is_infinite())
  assert_true(flags.overflow && flags.inexact)
}

///|
/// GDA quantize and round-to-integral preserve their requested quantum. A
/// shift beyond Int is necessarily sticky and rounds to zero at that quantum.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26): 1E-2147483645 quantized to 1E+999999999 at one digit is 0E+999999999 with inexact, to_integral_exact gives 0 with inexact and to_integral_value 0 with no inexact (IEEE 754-2019 5.3.1, 5.9)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "huge quantize and to-integral shifts round to zero" {
  let ctx = DecimalContext::new(precision=1, e_max=999_999_999)
  let tiny = Decimal::make(1N, -2_147_483_645, 1)
  let (quantized, quantize_flags) = tiny.quantize_ctx(
    Decimal::make(1N, 999_999_999, 1),
    ctx,
  )
  assert_true(quantized.is_zero())
  assert_eq(quantized.exponent10, 999_999_999)
  assert_true(quantize_flags.inexact)
  assert_false(quantize_flags.invalid_operation)

  let (exact, exact_flags) = tiny.to_integral_exact_ctx(ctx)
  assert_true(exact.is_zero())
  assert_eq(exact.exponent10, 0)
  assert_true(exact_flags.inexact)
  let (silent, silent_flags) = tiny.to_integral_value_ctx(ctx)
  assert_true(silent.is_zero())
  assert_false(silent_flags.inexact)
}

///|
/// next* must handle an operand exponent at Int::min even when Etiny is zero.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) (precision 1, Emax 1, so Etiny = 0): next_plus of 1E-2147483645 is 1 and next_minus is 0, no flag (IEEE 754-2019 5.3.1)
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "next operations handle Int minimum with zero etiny" {
  let ctx = DecimalContext::new(precision=1, e_max=1)
  let tiny = Decimal::make(1N, -2_147_483_645, 34)
  let (plus, plus_flags) = tiny.next_up_ctx(ctx)
  assert_eq(plus.to_string(), "1")
  assert_true(plus_flags == DecimalFlags::new())
  let (minus, minus_flags) = tiny.next_down_ctx(ctx)
  assert_true(minus.is_zero())
  assert_true(minus_flags == DecimalFlags::new())
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26): 1E-999999999 * 1E-999999999 + 1E+999999999 rounds to 1.000000000000000000000000000000000E+999999999 (34 digits, exponent emax - p + 1, not an overflow) with inexact
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "fma far gap uses sticky addend without aborting" {
  let ctx = DecimalContext::new(precision=34, e_max=999_999_999)
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
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) (precision 2, Emax 1, toward zero): 1E+7 * 1E-5 + -9E-3 = 99.991 rounds to 99 with inexact and no overflow
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "fma exact product boundary honors negative addend" {
  let ctx = DecimalContext::new(
    precision=2,
    e_max=1,
    rounding=DecimalRoundingMode::RoundTowardZero,
  )
  let (value, flags) = Decimal::make(1N, 7, 2).fma_ctx(
    Decimal::make(1N, -5, 2),
    Decimal::make(-9N, -3, 2),
    ctx,
  )
  inspect(value.to_string(), content="99")
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) (precision 2, Emax 1, toward negative): 99.991 rounds down to 99 with inexact and no overflow; toward positive it overflows
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "fma exact product boundary follows floor without overflow" {
  let ctx = DecimalContext::new(
    precision=2,
    e_max=1,
    rounding=DecimalRoundingMode::RoundTowardNegative,
  )
  let (value, flags) = Decimal::make(1N, 7, 2).fma_ctx(
    Decimal::make(1N, -5, 2),
    Decimal::make(-9N, -3, 2),
    ctx,
  )
  inspect(value.to_string(), content="99")
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26): 1E-2147483645 * 1E-2147483645 + 1E+999999999 rounds to 1.000000000000000000000000000000000E+999999999 with inexact and no overflow
// shares: Decimal::make and from_string_ctx (build the operands), to_string (prints the result), add_ctx, next_up_ctx, next_down_ctx, div_ctx, fma_ctx, quantize_ctx and to_integral_*_ctx (the code under test)
test "fma product below Int range uses a bounded sticky alignment" {
  let ctx = DecimalContext::new(precision=34, e_max=999_999_999)
  let (value, flags) = Decimal::make(1N, -2_147_483_645, 34).fma_ctx(
    Decimal::make(1N, -2_147_483_645, 34),
    Decimal::make(1N, 999_999_999, 34),
    ctx,
  )
  inspect(
    value.to_string(),
    content="1.000000000000000000000000000000000E+999999999",
  )
  inspect(flags.overflow, content="false")
  inspect(flags.inexact, content="true")
}
