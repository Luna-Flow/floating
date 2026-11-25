///|
// oracle: A
// source: worked by hand: exp(10^9) = 2^1442695040 is above 2^e_max, so the lower end is the largest finite number (exponent2 = e_max - 52 at 53 bits) and the upper end is +infinity; exp(-10^9) = 2^-1442695040 is below the smallest subnormal 2^(e_min - 52), so the interval is [0, 2^(e_min - 52)] with a positive radius (IEEE 754-2019 4.3.2 directed rounding, 1788-2015 12.12.7)
// shares: Interval::from_int, exp, exponent2, classify, is_zero and radius (the code under test); Binary::binary_value_e_max and e_min are the format limits
test "interval exponentials enclose results beyond the binary exponent range" {
  let huge = Interval::from_int(1000000000, precision=53).exp()
  assert_eq(huge.lower_bound().exponent2(), @binary.binary_value_e_max - 52)
  assert_eq(huge.upper_bound().classify(), FpClass::Infinity)
  let tiny = Interval::from_int(-1000000000, precision=53).exp()
  assert_true(tiny.lower_bound().is_zero())
  assert_false(tiny.upper_bound().is_zero())
  assert_eq(tiny.upper_bound().exponent2(), @binary.binary_value_e_min - 52)
  assert_false(tiny.radius().is_zero())
}

///|
// oracle: A
// source: worked by hand: (2^600000000)^2 = 2^1200000000 is above 2^e_max (e_max = 1073741823), so the interval product has a finite lower end (the largest finite number) and an upper end of +infinity; (2^-600000000)^2 = 2^-1200000000 is below the smallest subnormal, so the product is [0, smallest subnormal] and the product with the negative operand is [-smallest subnormal, 0] (IEEE 754-2019 4.3.2, IEEE 1788-2015 12.12.7)
// shares: Interval::exact, Binary::make, mul, neg, classify and is_zero (the code under test)
test "interval products clamp outward at the binary exponent range" {
  let big = Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 600000000, 53),
  )
  let product = big.mul(big)
  assert_false(product.lower_bound().classify() == FpClass::Infinity)
  assert_eq(product.upper_bound().classify(), FpClass::Infinity)
  let small = Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), -600000000, 53),
  )
  let tiny = small.mul(small)
  assert_true(tiny.lower_bound().is_zero())
  assert_false(tiny.upper_bound().is_zero())
  let negative_tiny = small.neg().mul(small)
  assert_false(negative_tiny.lower_bound().is_zero())
  assert_true(negative_tiny.upper_bound().is_zero())
}
