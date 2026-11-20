///|
fn extrema_test_operand(source : String) -> Decimal {
  match Decimal::from_string(source, precision=64) {
    Some(value) => value
    None => abort("expected decimal parse to succeed: " + source)
  }
}

///|
test "GDA min and max keep the preferred NaN diagnostics" {
  let ctx = DecimalContext::new(precision=4)
  let finite = Decimal::from_int(2, precision=8)
  let left_qnan = Decimal::quiet_nan(payload=11N, precision=8)
  let right_qnan = Decimal::quiet_nan(payload=54N, negative=true, precision=8)
  let left_snan = Decimal::signaling_nan(payload=7N, precision=8)
  let right_snan = Decimal::signaling_nan(
    payload=93N,
    negative=true,
    precision=8,
  )
  let (max_snan, max_snan_flags) = left_snan.max_ctx(finite, ctx)
  let (min_two_nan, min_two_nan_flags) = left_qnan.min_ctx(right_qnan, ctx)
  let (max_qnan_snan, max_qnan_snan_flags) = left_qnan.max_ctx(right_snan, ctx)
  assert_eq(max_snan.to_string(), "nan7")
  assert_eq(max_snan.nan_payload(), 7N)
  assert_true(max_snan_flags.invalid_operation)
  assert_eq(min_two_nan.to_string(), "nan11")
  assert_eq(min_two_nan.nan_payload(), 11N)
  assert_false(min_two_nan_flags.invalid_operation)
  assert_eq(max_qnan_snan.to_string(), "-nan93")
  assert_true(max_qnan_snan.is_signed())
  assert_eq(max_qnan_snan.nan_payload(), 93N)
  assert_true(max_qnan_snan_flags.invalid_operation)
}

///|
test "GDA subset min and max clean the selected zero" {
  let ctx = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  let negative_zero = extrema_test_operand("-0")
  let positive_zero = extrema_test_operand("0")
  let (minimum, min_flags) = negative_zero.min_ctx(positive_zero, ctx)
  let (maximum, max_flags) = negative_zero.max_ctx(positive_zero, ctx)
  let (minimum_mag, min_mag_flags) = negative_zero.min_magnitude_ctx(
    positive_zero, ctx,
  )
  let (maximum_mag, max_mag_flags) = negative_zero.max_magnitude_ctx(
    positive_zero, ctx,
  )
  assert_true(minimum.is_zero() && !minimum.is_signed())
  assert_true(maximum.is_zero() && !maximum.is_signed())
  assert_true(minimum_mag.is_zero() && !minimum_mag.is_signed())
  assert_true(maximum_mag.is_zero() && !maximum_mag.is_signed())
  assert_true(min_flags == DecimalFlags::new())
  assert_true(max_flags == DecimalFlags::new())
  assert_true(min_mag_flags == DecimalFlags::new())
  assert_true(max_mag_flags == DecimalFlags::new())
}

///|
test "GDA min and max order signed zeros by the total order in the extended mode" {
  let ctx = DecimalContext::new(
    precision=16,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  let negative_zero = extrema_test_operand("-0")
  let positive_zero = extrema_test_operand("0")
  let (min_value, min_flags) = positive_zero.min_ctx(negative_zero, ctx)
  let (max_value, max_flags) = positive_zero.max_ctx(negative_zero, ctx)
  assert_true(min_value.is_zero() && min_value.is_signed())
  assert_true(max_value.is_zero() && !max_value.is_signed())
  assert_true(min_flags == DecimalFlags::new())
  assert_true(max_flags == DecimalFlags::new())
}
