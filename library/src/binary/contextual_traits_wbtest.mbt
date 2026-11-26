///|
// oracle: A, S
// source: A: IEEE Std 754-2019 3.3 (e_min = 1 - e_max): a context with only e_min = -2 has e_max = 3 and the converse, a range not of that shape (e_min = -3, e_max = 3) is refused, and round away from zero is not an attribute of 4.3; S: the precision limits (precision 0 and an e_max of 0 refused) and the conversion rules from the arithmetic package are the library's own API contract
// shares: @lf_arith.ArithmeticContext::new builds the source contexts; BinaryContext::from_arithmetic_context and try_new are the code under test; e_min and e_max read the result
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
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 7.4 and 7.5 for a context of precision 4 with e_min = -2 and e_max = 3: 2^4 + 0 overflows (the largest finite value is 15, so the result is inf, overflow and inexact) and 2^-7 + 0 is below half of the smallest subnormal 2^-5 and rounds to 0 with underflow and inexact; S: the fields rounded, subnormal and clamped of the diagnostics are the conventions of the arithmetic package
// shares: Binary::make and zero build the operands; @lf_arith.AddContextual::add_contextual is the code under test; the diagnostics fields and classify read the result
test "Binary contextual arithmetic preserves range diagnostics" {
  let context = @lf_arith.ArithmeticContext::new(4, e_min=-2, e_max=3)
  let zero = Binary::zero(precision=8)
  let overflow_source = Binary::make(BinCoeff::one(), 4, 8)
  let overflow = @lf_arith.AddContextual::add_contextual(
    overflow_source, zero, context,
  ).unwrap()
  assert_true(overflow.value.classify() == FpClass::Infinity)
  assert_true(overflow.diagnostics.overflow)
  assert_true(overflow.diagnostics.inexact)
  assert_true(overflow.diagnostics.rounded)

  let underflow_source = Binary::make(BinCoeff::one(), -7, 8)
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
