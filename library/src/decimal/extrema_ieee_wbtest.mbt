///|
test "IEEE 754 extrema distinguish NaN propagation variants" {
  let ctx = DecimalContext::decimal64()
  let finite = Decimal::from_int(2, precision=16)
  let qnan = Decimal::quiet_nan(payload=7N, precision=16)
  let snan = Decimal::signaling_nan(payload=9N, precision=16)

  let (minimum, minimum_flags) = qnan.minimum_ctx(finite, ctx)
  let (minimum_number, minimum_number_flags) = qnan.minimum_number_ctx(
    finite, ctx,
  )
  let (snan_minimum, snan_minimum_flags) = snan.minimum_ctx(finite, ctx)
  let (snan_number, snan_number_flags) = snan.minimum_number_ctx(finite, ctx)

  assert_eq(minimum.to_string(), "nan7")
  assert_false(minimum_flags.invalid_operation)
  assert_eq(minimum_number.to_string(), "2")
  assert_false(minimum_number_flags.invalid_operation)
  assert_eq(snan_minimum.to_string(), "nan9")
  assert_true(snan_minimum_flags.invalid_operation)
  assert_eq(snan_number.to_string(), "2")
  assert_true(snan_number_flags.invalid_operation)
}

///|
test "IEEE 754 magnitude extrema retain signed zero tie ordering" {
  let ctx = DecimalContext::decimal64()
  let negative_zero = Decimal::negative_zero(precision=16)
  let positive_zero = Decimal::zero(precision=16)
  let (minimum, _) = negative_zero.minimum_magnitude_ctx(positive_zero, ctx)
  let (maximum, _) = negative_zero.maximum_magnitude_ctx(positive_zero, ctx)
  assert_true(minimum.is_negative_zero())
  assert_false(maximum.is_negative_zero())
}

///|
test "IEEE NaN payload accessors preserve quiet and signaling state" {
  let quiet = Decimal::quiet_nan(payload=12N, negative=true, precision=16)
  let signaling = quiet.set_payload_signaling(34N)
  let replaced = signaling.set_payload(56N)
  assert_eq(quiet.get_payload().to_string(), "12")
  assert_true(signaling.is_signaling_nan())
  assert_eq(signaling.get_payload().to_string(), "34")
  assert_true(replaced.is_quiet_nan())
  assert_eq(replaced.nan_payload().to_string(), "56")
  assert_eq(Decimal::from_string("1.2300").unwrap().quantum(), -4)
}
