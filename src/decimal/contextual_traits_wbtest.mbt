///|
test "Decimal contextual format follows decimal64" {
  let context = @lf_arith.ArithmeticContext::decimal64()
  let epsilon : Decimal = @lf_arith.NumericFormatContextual::epsilon_contextual(
    context,
  )
  inspect(epsilon.to_string(), content="1E-15")
}

///|
test "Decimal contextual division preserves rounding diagnostics" {
  let context = @lf_arith.ArithmeticContext::decimal64()
  let numerator = Decimal::from_int(1, precision=16)
  let denominator = Decimal::from_int(3, precision=16)
  let outcome = @lf_arith.DivContextual::div_contextual(
    numerator, denominator, context,
  ).unwrap()
  inspect(outcome.value.to_string(), content="0.3333333333333333")
  inspect(outcome.diagnostics.inexact, content="true")
  inspect(outcome.diagnostics.rounded, content="true")
}

///|
test "Decimal checked parsing uses the arithmetic context" {
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
    DecimalContext::from_arithmetic_context(decimal32).unwrap(),
  )
  assert_true(overflow_flags.overflow)
  assert_true(overflow_value.class == FpClass::Infinity)

  let invalid : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "not-a-decimal", context,
  )
  assert_true(invalid is Err(_))
}

///|
test "IEEE context exposes 2019 semantics and explicit rounding updates" {
  let ctx = DecimalContext::decimal64()
  assert_true(ctx.is754version2019())
  let directed = ctx.with_rounding(@lf_arith.RoundingMode::TowardPositive)
  assert_true(directed.rounding() == @lf_arith.RoundingMode::TowardPositive)
  assert_true(directed.is754version2019())
}

///|
test "Decimal contextual conversion preserves exponent bounds and clamp" {
  let arithmetic = @lf_arith.ArithmeticContext::new(
    7,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
  let context = DecimalContext::from_arithmetic_context(arithmetic).unwrap()
  assert_eq(context.precision(), 7)
  assert_eq(context.e_min(), -95)
  assert_eq(context.e_max(), 96)
  assert_true(context.clamp())
}

///|
test "Decimal checked powers preserve arithmetic exponent bounds" {
  let context = @lf_arith.ArithmeticContext::new(7, e_min=-95, e_max=2)
  let result = @lf_arith.PowNatChecked::pow_nat_checked(
    Decimal::from_int(2, precision=7),
    10U,
    context,
  ).unwrap()
  assert_true(result.classify() == @lf_arith.FpClass::Infinity)
}

///|
test "Decimal checked integer powers use the exact exponent" {
  // An exponent longer than the context precision must not be rounded
  // before use: rounding 12345679 to seven digits makes it even (#51).
  let context = @lf_arith.ArithmeticContext::new(7)
  let minus_one = Decimal::from_int(-1, precision=7)
  let int_power = fn(exponent : Int) {
    @lf_arith.PowIntChecked::pow_int_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  let nat_power = fn(exponent : UInt) {
    @lf_arith.PowNatChecked::pow_nat_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  assert_eq(int_power(12345679), "-1")
  assert_eq(int_power(-12345679), "-1")
  assert_eq(int_power(12345678), "1")
  assert_eq(int_power(2147483647), "-1")
  assert_eq(int_power(-2147483648), "1")
  assert_eq(nat_power(12345679U), "-1")
  assert_eq(nat_power(999999999U), "-1")
  assert_eq(nat_power(999999998U), "1")
}

///|
test "Decimal context translation rejects out of range bounds" {
  let invalid = @lf_arith.ArithmeticContext::new(7, e_min=-1_000_000_000)
  assert_true(DecimalContext::from_arithmetic_context(invalid) is Err(_))
  let outcome = @lf_arith.AddContextual::add_contextual(
    Decimal::one(),
    Decimal::one(),
    invalid,
  )
  assert_true(outcome is Err(_))
}
