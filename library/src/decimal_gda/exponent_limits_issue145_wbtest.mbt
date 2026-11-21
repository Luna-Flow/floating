///|
/// GDA context exponent bounds use widened arithmetic. Exact parsing and
/// addition retain their values and raise no conditions.
// oracle: A
// source: hand: 1 and 1+1 = 2 with no flags (CPython agrees)
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "extreme e_min preserves exact parse and addition" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let (one, parse_flags) = Decimal::from_string_ctx("1", ctx)
  assert_eq(one.to_string(), "1")
  assert_true(parse_flags == DecimalFlags::new())
  let (two, add_flags) = one.add_ctx(one, ctx)
  assert_eq(two.to_string(), "2")
  assert_true(add_flags == DecimalFlags::new())
}

///|
/// GDA context bounds and IEEE 754-2019 §7.4 require exact overflow flags.
// oracle: A
// source: CPython prec 3 Emax 999999999 clamp 1: 999E+999999997 doubled -> Infinity xr..o...; next_plus ->
//   Infinity no flags; /1E-1 -> Infinity xr..o
// shares: nothing
test "extreme e_max reports overflow without adjusted exponent wrap" {
  let ctx = DecimalContext::new(
    precision=3,
    e_min=-999_999_999,
    e_max=999_999_999,
    clamp=true,
  )
  let max = Decimal::make(999N, 999_999_997, 3)

  let (sum, sum_flags) = max.add_ctx(max, ctx)
  assert_true(sum.is_infinite())
  assert_true(sum_flags.overflow)
  assert_true(sum_flags.inexact)
  assert_true(sum_flags.rounded)
  assert_false(sum_flags.subnormal)
  assert_false(sum_flags.clamped)

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
/// IEEE 754-2019 §5.3.2: an unrepresentable quantize result is NaN with
/// InvalidOperation, without wrapping the exponent distance or aborting.
// oracle: A
// source: CPython quantize prec 5: NaN with InvalidOperation only
// shares: nothing
test "quantize with extreme exponent distance returns invalid operation" {
  let ctx = DecimalContext::new(
    precision=5,
    e_min=-999_999_999,
    e_max=999_999_999,
    clamp=true,
  )
  let value = Decimal::make(1N, 1_999_999_996, 5)
  let quantum = Decimal::make(1N, -2_000_000_003, 5)
  let (result, flags) = value.quantize(quantum, ctx)
  assert_true(result.is_qnan())
  assert_true(flags == { ..DecimalFlags::new(), invalid_operation: true, })
}

///|
// oracle: A
// source: hand: GDA limits 1..999,999,999 and +-999,999,999, both sides of each bound
// shares: nothing
test "GDA decimal context rejects out of range fields without aborting" {
  assert_true(DecimalContext::try_new(precision=999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(e_min=-999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(e_max=999_999_999) is Ok(_))
  assert_true(DecimalContext::try_new(precision=1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_min=-1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_max=1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(precision=1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_min=-1_000_000_000) is Err(_))
  assert_true(DecimalContext::try_new(e_max=1_000_000_000) is Err(_))
}

///|
/// GDA division must not wrap the distance from a p=1 quotient to Etiny.
// oracle: A
// source: CPython divide prec 1: 9E+999999999 / 5E-999999999 = Infinity xr..o
// shares: nothing
test "p=1 extreme division overflows without aborting" {
  let ctx = DecimalContext::new(
    precision=1,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let (value, flags) = Decimal::make(9N, 999_999_999, 1).div_ctx(
    Decimal::make(5N, -999_999_999, 1),
    ctx,
  )
  assert_true(value.is_infinite())
  assert_true(flags.overflow && flags.inexact && flags.rounded)
}

///|
/// GDA integral and quantize conversions with an unrepresentable shift use a
/// sticky zero result at the requested quantum, with the specified flags.
// oracle: A
// source: CPython prec 1 Emin/Emax +-999,999,999 with operand 1E-2147483648: quantize to 1E+999999999 =
//   0E+999999999 xr; to_integral_exact 0 xr; to_integral_value 0 no flags
// shares: nothing
test "huge quantize and to-integral shifts round to zero" {
  let ctx = DecimalContext::new(
    precision=1,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let tiny = decimal_unchecked(false, 1N, -2_147_483_648, 1)
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
/// Adjacent-value operations handle Int::min when the context Etiny is zero.
// oracle: A
// source: decNumber 3.68 (tools/decnumber_probe.c, extended=1, precision 1, Emin 0, Emax 999999999) on the operand
//   1E-9, the nearest operand decNumber can read (its exponent limit is -999999999): next_plus gives 1 and next_minus
//   0 with no flag, next_toward 0 gives 0 with Inexact, Rounded, Underflow (and Subnormal, Clamped, which the test
//   does not assert); CPython agrees on next_plus and next_minus and differs on the next_toward flags (none)
// shares: nothing
test "next operations handle Int minimum with zero etiny" {
  let ctx = DecimalContext::new(precision=1, e_min=0, e_max=999_999_999)
  let tiny = decimal_unchecked(false, 1N, -2_147_483_648, 34)
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
// oracle: A
// source: CPython fma prec 34 Emin/Emax +-999,999,999: 1.000000000000000000000000000000000E+999999999 xr
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA fma far gap uses sticky addend without aborting" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
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
// oracle: A
// source: CPython fma prec 2 Emax 0 ROUND_DOWN: 9.9 xr
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA fma exact product boundary honors negative addend" {
  let ctx = DecimalContext::new(
    precision=2,
    e_min=-999_999_999,
    e_max=0,
    rounding=RoundingMode::TowardZero,
    decimal_rounding=DecimalRoundingMode::Down,
  )
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
// oracle: A
// source: CPython fma prec 2 Emax 0 ROUND_FLOOR: 9.9 xr
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA fma exact product boundary follows floor without overflow" {
  let ctx = DecimalContext::new(
    precision=2,
    e_min=-999_999_999,
    e_max=0,
    decimal_rounding=DecimalRoundingMode::Floor,
  )
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
// oracle: A
// source: CPython fma with 1E-2147483648 operands (64-bit libmpdec): same value, xr
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA fma product below Int range uses a bounded sticky alignment" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let (value, flags) = decimal_unchecked(false, 1N, -2_147_483_648, 34).fma_ctx(
    decimal_unchecked(false, 1N, -2_147_483_648, 34),
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
/// GdaContext validates through the same adopted context bounds before constructing
/// a DecimalContext for stateful operations.
// oracle: A
// source: hand: adopted limits (precision 1..999,999,999, e_min and e_max within +-999,999,999; decNumber limits,
//   not GDA 1.70 text) and the Emin = -Emax +- 1 balance rule (GDA 1.70 page 10), both sides of each bound
// shares: nothing
test "GdaContext rejects precision and exponent bounds outside adopted limits" {
  assert_true(GdaContext::try_new(precision=999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(e_min=-999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(e_max=999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(precision=999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(e_min=-999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(e_max=999_999_999) is Ok(_))
  assert_true(GdaContext::try_new(precision=2_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(precision=-1) is Err(_))
  assert_true(GdaContext::try_new(e_min=-2_147_483_648) is Err(_))
  assert_true(GdaContext::try_new(e_min=-1_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(e_max=2_147_483_647) is Err(_))
  assert_true(GdaContext::try_new(e_max=1_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(precision=0) is Err(_))
  assert_true(GdaContext::try_new(e_min=1, e_max=0) is Err(_))
  assert_true(GdaContext::try_new(precision=2_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(precision=-1) is Err(_))
  assert_true(GdaContext::try_new(e_min=-2_147_483_648) is Err(_))
  assert_true(GdaContext::try_new(e_min=-1_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(e_max=2_147_483_647) is Err(_))
  assert_true(GdaContext::try_new(e_max=1_000_000_000) is Err(_))
  assert_true(GdaContext::try_new(precision=0) is Err(_))
  assert_true(GdaContext::try_new(e_min=1, e_max=0) is Err(_))
}

///|
/// GDA 1.70, Finite numbers; decNumber `decContext.h`: the adopted
/// implementation bounds require `e_min <= 0 <= e_max` without enforcing the
/// separate balanced-range rule.
// oracle: A
// source: hand: e_min <= 0 <= e_max of the adopted bounds; message strings are the library own text
// shares: nothing
test "GdaContext rejects exponent bounds with invalid signs" {
  assert_true(GdaContext::try_new(e_min=0, e_max=0) is Ok(_))
  assert_true(
    GdaContext::try_new(e_min=-999_999_999, e_max=999_999_999) is Ok(_),
  )
  assert_true(GdaContext::try_new(e_min=-10, e_max=10) is Ok(_))
  assert_true(GdaContext::try_new(e_min=1, e_max=10) is Err(_))
  assert_true(GdaContext::try_new(e_min=-10, e_max=-1) is Err(_))
  match GdaContext::try_new(e_min=1, e_max=10) {
    Err(error) =>
      assert_eq(error.message, "GdaContext e_min must be within -999999999..=0")
    Ok(_) => fail("positive e_min must be rejected")
  }
  match GdaContext::try_new(e_min=-10, e_max=-1) {
    Err(error) =>
      assert_eq(error.message, "GdaContext e_max must be within 0..=999999999")
    Ok(_) => fail("negative e_max must be rejected")
  }
}
