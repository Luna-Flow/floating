///|
test "Binary contextual conversion preserves one-sided exponent bounds" {
  let lower_only = @lf_arith.ArithmeticContext::new(4, e_min=-2)
  let lower_context = BinaryContext::from_arithmetic_context(lower_only)
  assert_eq(lower_context.e_min(), Some(-2))
  assert_eq(lower_context.e_max(), None)

  let upper_only = @lf_arith.ArithmeticContext::new(4, e_max=3)
  let upper_context = BinaryContext::from_arithmetic_context(upper_only)
  assert_eq(upper_context.e_min(), None)
  assert_eq(upper_context.e_max(), Some(3))
  assert_true(BinaryContext::try_new(4, e_min=-2) is Ok(_))
  assert_true(BinaryContext::try_new(4, e_max=3) is Ok(_))
}

///|
test "BinFloat contextual arithmetic preserves range diagnostics" {
  let context = @lf_arith.ArithmeticContext::new(4, e_min=-2, e_max=3)
  let zero = BinFloat::zero(precision=8)
  let overflow_source = BinFloat::make(BinCoeff::one(), 4, 8)
  let overflow = @lf_arith.AddContextual::add_contextual(
    overflow_source, zero, context,
  ).unwrap()
  assert_true(overflow.value.classify() == FpClass::Infinity)
  assert_true(overflow.diagnostics.overflow)
  assert_true(overflow.diagnostics.inexact)
  assert_true(overflow.diagnostics.rounded)

  let underflow_source = BinFloat::make(BinCoeff::one(), -7, 8)
  let underflow = @lf_arith.AddContextual::add_contextual(
    underflow_source, zero, context,
  ).unwrap()
  assert_true(underflow.value.is_zero())
  assert_true(underflow.diagnostics.underflow)
  assert_true(underflow.diagnostics.inexact)
  assert_true(underflow.diagnostics.rounded)
  assert_false(underflow.diagnostics.subnormal)
  assert_false(underflow.diagnostics.clamped)
}
