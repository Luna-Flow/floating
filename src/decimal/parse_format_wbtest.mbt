///|
test "decimal parsing preserves coefficient-native finite and NaN payloads" {
  let ctx = DecimalContext::new(precision=34)
  let digits = "1234567890123456789012345678901234"
  let (finite, finite_flags) = Decimal::from_string_ctx(
    "000" + digits + "E-12",
    ctx,
  )
  assert_true(finite.class == FpClass::Finite)
  assert_eq(finite.coefficient.to_string(), digits)
  assert_eq(finite.exponent10, -12)
  assert_false(finite_flags.rounded)
  assert_false(finite_flags.inexact)

  let (nan, nan_flags) = Decimal::from_string_ctx(
    "-sNaN0001234567890123456789012345678901", ctx,
  )
  assert_true(nan.class == FpClass::NaN)
  assert_true(nan.negative)
  assert_true(nan.signaling_nan)
  assert_eq(nan.coefficient.to_string(), "1234567890123456789012345678901")
  assert_false(nan_flags.has_error())
}

///|
test "decimal parsing coefficient-native boundary paths preserve flags" {
  let ctx = DecimalContext::new(precision=7, e_min=-95, e_max=96, clamp=true)
  let (overflow, overflow_flags) = Decimal::from_string_ctx(
    "99999999E+100", ctx,
  )
  assert_true(overflow.class == FpClass::Infinity)
  assert_true(overflow_flags.overflow)
  assert_true(overflow_flags.rounded)
  assert_true(overflow_flags.inexact)

  let (tiny, tiny_flags) = Decimal::from_string_ctx("1E-1000", ctx)
  assert_true(tiny.class == FpClass::Finite)
  assert_true(tiny.coefficient.is_zero())
  assert_true(tiny_flags.rounded)
  assert_true(tiny_flags.inexact)
  assert_true(tiny_flags.subnormal)
  assert_true(tiny_flags.underflow)
}
