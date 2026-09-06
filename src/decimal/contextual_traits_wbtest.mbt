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
  let context = DecimalContext::from_arithmetic_context(arithmetic)
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
