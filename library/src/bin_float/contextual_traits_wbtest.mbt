///|
test "Binary contextual conversion derives one bound from the other" {
  // IEEE 754-2019 3.3: e_min = 1 - e_max
  let lower_only = @lf_arith.ArithmeticContext::new(4, e_min=-2)
  let lower_context = BinaryContext::from_arithmetic_context(lower_only).unwrap()
  assert_eq(lower_context.e_min(), -2)
  assert_eq(lower_context.e_max(), 3)
  let upper_only = @lf_arith.ArithmeticContext::new(4, e_max=3)
  let upper_context = BinaryContext::from_arithmetic_context(upper_only).unwrap()
  assert_eq(upper_context.e_min(), -2)
  assert_eq(upper_context.e_max(), 3)
  let both = @lf_arith.ArithmeticContext::new(4, e_min=-2, e_max=3)
  assert_true(BinaryContext::from_arithmetic_context(both) is Ok(_))
  // a range that is not of the 3.3 shape is refused
  let skewed = @lf_arith.ArithmeticContext::new(4, e_min=-3, e_max=3)
  assert_true(BinaryContext::from_arithmetic_context(skewed) is Err(_))
  // AwayFromZero is not an IEEE 754-2019 4.3 attribute
  let away = @lf_arith.ArithmeticContext::new(
    4,
    rounding=@lf_arith.RoundingMode::AwayFromZero,
  )
  assert_true(BinaryContext::from_arithmetic_context(away) is Err(_))
  assert_true(BinaryContext::try_new(precision=4, e_max=3) is Ok(_))
  assert_true(BinaryContext::try_new(precision=4, e_max=0) is Err(_))
  assert_true(BinaryContext::try_new(precision=0) is Err(_))
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
