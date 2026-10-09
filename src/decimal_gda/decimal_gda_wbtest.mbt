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

///|
test "Decimal GDA checked parsing uses the arithmetic context" {
  let context = @lf_arith.ArithmeticContext::new(
    3,
    rounding=@lf_arith.RoundingMode::TowardZero,
  )
  let rounded : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1.239", context,
  )
  let rounded = rounded.unwrap()
  inspect(rounded.to_string(), content="1.23")
  let toward_positive = @lf_arith.ArithmeticContext::new(
    3,
    rounding=@lf_arith.RoundingMode::TowardPositive,
  )
  let positive_result : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1.231", toward_positive,
  )
  inspect(positive_result.unwrap().to_string(), content="1.24")

  let negative_result : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "-1.231", toward_positive,
  )
  inspect(negative_result.unwrap().to_string(), content="-1.23")

  let decimal32 = @lf_arith.ArithmeticContext::new(
    7,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
  let overflow : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1E+200", decimal32,
  )
  let overflow = overflow.unwrap()
  assert_true(overflow.class == FpClass::Infinity)
  let (overflow_value, overflow_flags) = Decimal::from_string_ctx(
    "1E+200",
    DecimalContext::from_arithmetic_context(decimal32),
  )
  assert_true(overflow_flags.overflow)
  assert_true(overflow_value.class == FpClass::Infinity)

  let invalid : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "not-a-decimal", context,
  )
  assert_true(invalid is Err(_))
}
