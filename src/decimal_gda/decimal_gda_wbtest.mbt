///|
test "GDA facade selects signaling NaN precedence" {
  let lhs = Decimal::signaling_nan(
    payload=@bigint.BigInt::from_int(7),
    precision=7,
  )
  let rhs = Decimal::quiet_nan(payload=@bigint.BigInt::from_int(9), precision=7)
  let outcome = add(lhs, rhs, decimal32_context())
  let result = outcome.value()
  assert_true(outcome.raised().contains(GdaSignal::InvalidOperation))
  assert_eq(result.nan_payload().to_string(), "7")
}
