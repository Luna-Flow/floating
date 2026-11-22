///|
/// IEEE 754-2019 §3.5.2 and §6.2.3: a propagated NaN payload is one the
/// destination format can hold, and an interchange-shaped (clamped) context has
/// p - 1 payload digits; `from_string_ctx` enforces the same limit.
// oracle: A
// source: IEEE 754-2019 payload digits p-1 for a clamped context; the 7 payload cases re-run with CPython 3.13
//   decimal (clamp 1 and 0, NaN and sNaN, 10^15 payload becomes 0), all agree
// shares: Decimal::from_string (reading the inputs)
test "NaN propagation keeps a payload the clamped format can hold (#152)" {
  let one = Decimal::from_string("1").unwrap()
  let d64 = DecimalContext::decimal64()
  let long = Decimal::quiet_nan(payload=1234567890123456N)
  let (v, _) = long.add_ctx(one, d64)
  assert_eq(v.nan_payload().to_string(), "234567890123456")
  let (w, _) = one.add_ctx(long, d64)
  assert_eq(w.nan_payload().to_string(), "234567890123456")
  let (s, flags) = Decimal::signaling_nan(payload=1234567890123456N).add_ctx(
    one, d64,
  )
  assert_eq(s.nan_payload().to_string(), "234567890123456")
  assert_true(s.is_nan() && !s.is_snan())
  assert_true(flags.invalid_operation)
  // A payload that fits is kept; a power-of-ten payload loses its top digit.
  let (fit, _) = Decimal::quiet_nan(payload=999999999999999N).add_ctx(one, d64)
  assert_eq(fit.nan_payload().to_string(), "999999999999999")
  let (pow10, _) = Decimal::quiet_nan(payload=1000000000000000N).add_ctx(
    one, d64,
  )
  assert_eq(pow10.nan_payload().to_string(), "0")
  // Without clamp the format keeps p digits.
  let loose = DecimalContext::new(precision=16, e_min=-383, e_max=384)
  let (kept, _) = long.add_ctx(one, loose)
  assert_eq(kept.nan_payload().to_string(), "1234567890123456")
  let (cut, _) = Decimal::quiet_nan(payload=12345678901234567N).add_ctx(
    one, loose,
  )
  assert_eq(cut.nan_payload().to_string(), "2345678901234567")
}
