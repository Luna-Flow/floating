///|
test "GDA binary and ternary operations prioritize signaling nan payloads" {
  let context = DecimalContext::new(precision=9)
  let left = Decimal::quiet_nan(payload=95N, precision=12)
  let signal = Decimal::signaling_nan(payload=93N, precision=12)
  let (quotient, quotient_flags) = left.div_ctx(signal, context)
  assert_eq(quotient.to_string(), "nan93")
  assert_true(quotient_flags.invalid_operation)

  let first = Decimal::quiet_nan(payload=7N, precision=12)
  let addend = Decimal::signaling_nan(payload=19N, precision=12)
  let (fused, fused_flags) = Decimal::one().fma_ctx(first, addend, context)
  assert_eq(fused.to_string(), "nan19")
  assert_true(fused_flags.invalid_operation)

  let large_signal = Decimal::signaling_nan(payload=123456N, precision=16)
  let (scaled, scaled_flags) = Decimal::quiet_nan(payload=16N, precision=16).scaleb_ctx(
    large_signal,
    DecimalContext::new(precision=5, e_min=-9, e_max=9),
  )
  assert_eq(scaled.to_string(), "nan23456")
  assert_true(scaled_flags.invalid_operation)
}

///|
test "GDA unary operations use before-rounding tininess" {
  let context = DecimalContext::new(
    precision=3,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let (value, flags) = Decimal::from_string("0.999E-999", precision=64)
    .unwrap()
    .plus_ctx(context)
  assert_eq(value.to_string(), "1.00E-999")
  assert_true(flags.subnormal)
  assert_true(flags.underflow)
  assert_true(flags.inexact)
  assert_true(flags.rounded)
}

///|
test "GDA huge remainders report DivisionImpossible" {
  let context = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-999_999_999,
    e_max=999_999_999,
    extended=false,
  )
  let huge = Decimal::from_string("9E+999999999", precision=64).unwrap()
  let small = Decimal::from_string("0.23456789012345", precision=64).unwrap()
  let (remainder, remainder_flags) = huge.remainder(small, context)
  let (near, near_flags) = huge.remainder_near(small, context)
  assert_true(remainder.is_qnan())
  assert_true(remainder_flags.invalid_operation)
  assert_true(remainder_flags.division_impossible)
  assert_true(near.is_qnan())
  assert_true(near_flags.invalid_operation)
  assert_true(near_flags.division_impossible)
}

///|
test "GDA exp boundary cache stays bounded and preserves hits" {
  let saved_cache = decimal_exp_boundary_cache.copy()
  let saved_next = decimal_exp_boundary_cache_next.val
  defer {
    decimal_exp_boundary_cache.clear()
    for entry in saved_cache {
      decimal_exp_boundary_cache.push(entry)
    }
    decimal_exp_boundary_cache_next.val = saved_next
  }
  decimal_exp_boundary_cache.clear()
  decimal_exp_boundary_cache_next.val = 0
  let first_context = DecimalContext::new(precision=9, e_min=-100, e_max=100)
  let first = decimal_exp_boundary_entry(first_context)
  let repeated = decimal_exp_boundary_entry(first_context)
  assert_eq(decimal_exp_boundary_cache.length(), 1)
  assert_eq(first.lower.compare_total(repeated.lower), 0)
  assert_eq(first.upper.compare_total(repeated.upper), 0)
  for index in 0..<(decimal_exp_boundary_cache_capacity + 2) {
    ignore(
      decimal_exp_boundary_entry(
        DecimalContext::new(precision=9, e_min=-200 - index, e_max=200 + index),
      ),
    )
  }
  assert_eq(
    decimal_exp_boundary_cache.length(),
    decimal_exp_boundary_cache_capacity,
  )
  let mut first_present = false
  for entry in decimal_exp_boundary_cache {
    if entry.precision == first_context.precision() &&
      entry.e_min == first_context.e_min() &&
      entry.e_max == first_context.e_max() &&
      entry.clamp == first_context.clamp() {
      first_present = true
    }
  }
  assert_false(first_present)
}
