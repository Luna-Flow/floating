///|
fn assert_gda_fast_matches_generic(
  fast : GdaOutcome[Decimal],
  generic : (Decimal, DecimalFlags),
  context : GdaContext,
) -> Unit raise {
  assert_true(fast.value() == generic.0)
  assert_true(fast.raised() == gda_flags_from_decimal(generic.1))
  assert_true(
    fast.next_context().status() == context.status().combine(fast.raised()),
  )
}

///|
test "GDA exact small wrapper paths match generic finalization" {
  let context = GdaContext::new(precision=40, e_min=-999999, e_max=999999)
  let decimal_context = context.decimal_context()
  let left = Decimal::from_string("314159265358979328").unwrap()
  let right = Decimal::from_string("2").unwrap()
  let addend = Decimal::from_string("3").unwrap()
  assert_gda_fast_matches_generic(
    add(left, right, context),
    left.add_ctx(right, decimal_context),
    context,
  )
  assert_gda_fast_matches_generic(
    subtract(left, right, context),
    left.sub_ctx(right, decimal_context),
    context,
  )
  assert_gda_fast_matches_generic(
    multiply(left, right, context),
    left.mul_ctx(right, decimal_context),
    context,
  )
  assert_gda_fast_matches_generic(
    fma(left, right, addend, context),
    left.fma_ctx(right, addend, decimal_context),
    context,
  )
  assert_gda_fast_matches_generic(
    parse("314159265358979328", context),
    Decimal::from_string_ctx("314159265358979328", decimal_context),
    context,
  )
}

///|
test "GDA small wrapper paths fall back at semantic boundaries" {
  let tiny_context = GdaContext::new(precision=9, e_min=-2, e_max=2)
  let left = Decimal::from_string("999999999999999999").unwrap()
  let right = Decimal::from_string("2").unwrap()
  assert_gda_fast_matches_generic(
    add(left, right, tiny_context),
    left.add_ctx(right, tiny_context.decimal_context()),
    tiny_context,
  )
  let clamped = GdaContext::new(precision=18, e_min=-2, e_max=2, clamp=true)
  assert_gda_fast_matches_generic(
    parse("314159265358979328", clamped),
    Decimal::from_string_ctx("314159265358979328", clamped.decimal_context()),
    clamped,
  )
}
