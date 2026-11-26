///|
/// IEEE 754-2019 §9.7: getPayload is -1 for a non-NaN; setPayload and
/// setPayloadSignaling give a NaN with the payload when it is a non-negative
/// integer the format can hold (at most p - 1 digits) and +0 otherwise,
/// whatever the receiver is.
// oracle: A, S
// source: IEEE 754-2019 9.7 (read from the PDF text): getPayload of a NaN is its payload as a non-negative integer and -1 for a non-NaN; setPayload and setPayloadSignaling give a quiet or signaling NaN with the payload when it is an admissible non-negative integer and +0 otherwise; which payloads are admissible (at most p - 1 digits: 15 for decimal64, none beyond for precision 1) is implementation-defined and here the library's choice (level S); written out
// shares: Decimal::from_string, quiet_nan, signaling_nan, zero, inf, set_payload, set_payload_signaling, get_payload, nan_payload, is_nan, is_signaling_nan, is_zero, is_negative_zero and to_string (build the operands and read the results), add_ctx (the code under test where it propagates)
test "payload operations follow IEEE 754 9.7 (#151)" {
  let one = Decimal::from_string("1").unwrap()
  assert_eq(one.get_payload().to_string(), "-1")
  assert_eq(Decimal::inf().get_payload().to_string(), "-1")
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
  assert_eq(Decimal::inf().set_payload(0N).to_string(), "nan")
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
// oracle: A, S
// source: IEEE 754-2019 3.5.2 and 6.2.3: a propagated NaN carries the payload of an input NaN when the destination can hold it (p - 1 = 15 digits for decimal64) and a signaling NaN gives a quiet NaN with invalid operation; keeping the low 15 digits of a 16-digit payload (234567890123456) and zero for 10^15 is the library's convention for a payload that does not fit (level S)
// shares: Decimal::from_string, quiet_nan, signaling_nan, zero, inf, set_payload, set_payload_signaling, get_payload, nan_payload, is_nan, is_signaling_nan, is_zero, is_negative_zero and to_string (build the operands and read the results), add_ctx (the code under test where it propagates)
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
}
