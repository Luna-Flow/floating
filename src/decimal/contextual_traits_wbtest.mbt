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
