///|
/// GDA context exponent bounds use widened arithmetic. Exact parsing and
/// addition retain their values and raise no conditions.
test "extreme e_min preserves exact parse and addition" {
  let ctx = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=999_999_999,
  ).unwrap()
  let (one, parse_flags) = Decimal::from_string_ctx("1", ctx)
  assert_eq(one.to_string(), "1")
  assert_true(parse_flags == DecimalFlags::new())
  let (two, add_flags) = one.add_ctx(one, ctx)
  assert_eq(two.to_string(), "2")
  assert_true(add_flags == DecimalFlags::new())
}

///|
/// GDA context bounds and IEEE 754-2019 §7.4 require exact overflow flags.
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
test "GDA decimal context rejects out of range fields without aborting" {
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
