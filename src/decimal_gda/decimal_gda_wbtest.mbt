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

///|
test "decimal direct constructors preserve public representations" {
  let zero = Decimal::zero(precision=0)
  assert_true(zero.is_zero())
  assert_false(zero.is_negative_zero())
  assert_eq(zero.precision(), 1)

  let negative_zero = Decimal::negative_zero(precision=0)
  assert_true(negative_zero.is_negative_zero())
  assert_eq(negative_zero.precision(), 1)

  let one = Decimal::one(precision=0)
  assert_eq(one.to_string(), "1")
  assert_eq(one.precision(), 1)

  let min_int = -2147483647 - 1
  assert_eq(Decimal::from_int(min_int).to_string(), "-2147483648")
  assert_true(Decimal::inf(Sign::Positive).is_infinite())
  assert_true(Decimal::nan().is_qnan())
}
