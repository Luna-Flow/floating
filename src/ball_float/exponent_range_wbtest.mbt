///|
test "interval exponentials enclose results beyond the binary exponent range" {
  let huge = BallFloat::from_int(1000000000, precision=53).exp_interval()
  assert_eq(
    huge.lower_bound().exponent2(),
    @bin_float.binary_implementation_e_max - 52,
  )
  assert_eq(huge.upper_bound().classify(), FpClass::Infinity)
  let tiny = BallFloat::from_int(-1000000000, precision=53).exp_interval()
  assert_true(tiny.lower_bound().is_zero())
  assert_false(tiny.upper_bound().is_zero())
  assert_eq(
    tiny.upper_bound().exponent2(),
    @bin_float.binary_implementation_e_min - 52,
  )
  assert_false(tiny.radius().is_zero())
}

///|
test "interval products clamp outward at the binary exponent range" {
  let big = BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 600000000, 53),
  )
  let product = big.mul(big)
  assert_false(product.lower_bound().classify() == FpClass::Infinity)
  assert_eq(product.upper_bound().classify(), FpClass::Infinity)
  let small = BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -600000000, 53),
  )
  let tiny = small.mul(small)
  assert_true(tiny.lower_bound().is_zero())
  assert_false(tiny.upper_bound().is_zero())
  let negative_tiny = small.neg().mul(small)
  assert_false(negative_tiny.lower_bound().is_zero())
  assert_true(negative_tiny.upper_bound().is_zero())
}
