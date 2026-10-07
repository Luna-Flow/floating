///|
fn far_addend_power(exponent : Int) -> BallFloat {
  BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, 53),
  )
}

///|
test "far addends do not materialize the exponent gap" {
  let big = far_addend_power(1000000000)
  let tiny = far_addend_power(-1000000000)
  let sum = big.add(tiny)
  // The exact sum lies strictly inside (2^1e9, 2^1e9 + ulp).
  assert_eq(sum.lower_bound(), big.lower_bound())
  assert_true(sum.upper_bound().compare(big.upper_bound()) > 0)
  assert_true(sum.contains(big.lower_bound()) == true)
  let difference = big.sub(tiny)
  assert_true(difference.lower_bound().compare(big.lower_bound()) < 0)
  assert_eq(difference.upper_bound(), big.upper_bound())
  let reversed = tiny.add(big)
  assert_true(reversed.set_equal(sum))
}

///|
test "near addends stay exact" {
  let one = far_addend_power(0)
  let small = far_addend_power(-60)
  let sum = one.add(small)
  // 1 + 2^-60 needs 61 bits; at 53 bits it is enclosed by [1, 1 + 2^-52].
  assert_eq(sum.lower_bound(), one.lower_bound())
  assert_eq(
    sum.upper_bound(),
    @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_uint64((1UL << 52) + 1UL),
      -52,
      53,
    ),
  )
}
