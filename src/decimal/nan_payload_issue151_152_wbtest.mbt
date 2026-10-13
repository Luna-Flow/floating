///|
/// IEEE 754-2019 §9.7: getPayload is -1 for a non-NaN; setPayload and
/// setPayloadSignaling give a NaN with the payload when it is a non-negative
/// integer the format can hold (at most p - 1 digits) and +0 otherwise,
/// whatever the receiver is.
test "payload operations follow IEEE 754 9.7 (#151)" {
  let one = Decimal::from_string("1").unwrap()
  assert_eq(one.get_payload().to_string(), "-1")
  assert_eq(Decimal::inf(Sign::Positive).get_payload().to_string(), "-1")
  assert_eq(Decimal::zero().get_payload().to_string(), "-1")
  assert_eq(Decimal::quiet_nan(payload=7N).get_payload().to_string(), "7")
  assert_eq(Decimal::signaling_nan(payload=9N).get_payload().to_string(), "9")
  assert_eq(Decimal::quiet_nan().get_payload().to_string(), "0")
  // A NaN receiver and a negative payload: +0, not NaN with |payload|.
  let negative = Decimal::quiet_nan().set_payload(-5N)
  assert_true(!negative.is_nan())
  assert_true(negative.is_zero())
  assert_true(!negative.is_negative_zero())
  assert_eq(negative.to_string(), "0")
  assert_eq(Decimal::quiet_nan().set_payload_signaling(-1N).to_string(), "0")
  // A finite receiver still yields a NaN with the payload.
  let quiet = one.set_payload(5N)
  assert_true(quiet.is_nan() && !quiet.is_signaling_nan())
  assert_eq(quiet.get_payload().to_string(), "5")
  let signaling = one.set_payload_signaling(5N)
  assert_true(signaling.is_signaling_nan())
  assert_eq(signaling.get_payload().to_string(), "5")
  assert_eq(Decimal::inf(Sign::Positive).set_payload(0N).to_string(), "nan")
  // The payload must fit p - 1 digits: 15 for decimal64, 33 for the default.
  let d64 = Decimal::from_string("1", precision=16).unwrap()
  assert_eq(
    d64.set_payload(999999999999999N).get_payload().to_string(),
    "999999999999999",
  )
  assert_eq(d64.set_payload(1000000000000000N).to_string(), "0")
  assert_eq(d64.set_payload_signaling(1000000000000000N).to_string(), "0")
  assert_true(d64.set_payload(1000000000000000N).is_zero())
  let tiny = Decimal::from_string("1", precision=1).unwrap()
  assert_true(tiny.set_payload(0N).is_nan())
  assert_true(tiny.set_payload(1N).is_zero())
}

///|
/// IEEE 754-2019 §3.5.2 and §6.2.3: a propagated NaN payload is one the
/// destination format can hold, and an interchange-shaped (clamped) context has
/// p - 1 payload digits; `from_string_ctx` enforces the same limit.
test "NaN propagation keeps a payload the clamped format can hold (#152)" {
  let one = Decimal::from_string("1").unwrap()
  let d64 = DecimalContext::decimal64()
  let long = Decimal::quiet_nan(payload=1234567890123456N)
  let (v, _) = long.add_ctx(one, d64)
  assert_eq(v.get_payload().to_string(), "234567890123456")
  let (w, _) = one.add_ctx(long, d64)
  assert_eq(w.get_payload().to_string(), "234567890123456")
  let (s, flags) = Decimal::signaling_nan(payload=1234567890123456N).add_ctx(
    one, d64,
  )
  assert_eq(s.get_payload().to_string(), "234567890123456")
  assert_true(s.is_nan() && !s.is_signaling_nan())
  assert_true(flags.invalid_operation)
  // A payload that fits is kept; a power-of-ten payload loses its top digit.
  let (fit, _) = Decimal::quiet_nan(payload=999999999999999N).add_ctx(one, d64)
  assert_eq(fit.get_payload().to_string(), "999999999999999")
  let (pow10, _) = Decimal::quiet_nan(payload=1000000000000000N).add_ctx(
    one, d64,
  )
  assert_eq(pow10.get_payload().to_string(), "0")
  // Without clamp the format keeps p digits.
  let loose = DecimalContext::new(precision=16, e_min=-383, e_max=384).unwrap()
  let (kept, _) = long.add_ctx(one, loose)
  assert_eq(kept.get_payload().to_string(), "1234567890123456")
  let (cut, _) = Decimal::quiet_nan(payload=12345678901234567N).add_ctx(
    one, loose,
  )
  assert_eq(cut.get_payload().to_string(), "2345678901234567")
}
