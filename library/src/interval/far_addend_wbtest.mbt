///|
fn far_addend_power(exponent : Int32) -> Interval {
  Interval::exact(@binary.Binary::make(@binary.BinCoeff::one(), exponent, 53))
}

///|
// oracle: A
// source: worked out by hand from the outward rounding of IEEE 1788-2015 10.2: the ulp of 2^1e9 at 53 bits is 2^(1e9 - 52), so 2^1e9 + 2^-1e9 lies in (2^1e9, (2^52 + 1) * 2^(1e9 - 52)) and 2^1e9 - 2^-1e9 in ((2^53 - 1) * 2^(1e9 - 53), 2^1e9); the ends are written out as coefficients and exponents
// shares: far_addend_power (Binary::make and Interval::exact) builds the operands; Binary::make builds the expected ends; Binary::identical and compare compare them
test "far addends do not materialize the exponent gap" {
  let big = far_addend_power(1000000000)
  let tiny = far_addend_power(-1000000000)
  let sum = big.add(tiny)
  // The exact sum lies strictly inside (2^1e9, 2^1e9 + ulp), the ulp of 2^1e9 at 53 bits being
  // 2^(1e9 - 52): the tightest interval is [2^1e9, (2^52 + 1) * 2^(1e9 - 52)].
  assert_identical(sum.lower_bound(), big.lower_bound())
  assert_identical(
    sum.upper_bound(),
    @binary.Binary::make(
      @binary.BinCoeff::from_uint64((1UL << 52) + 1UL),
      1000000000 - 52,
      53,
    ),
  )
  assert_true(sum.is_member(big.lower_bound()) == true)
  // 2^1e9 - 2^-1e9 lies strictly between the number below 2^1e9, (2^53 - 1) * 2^(1e9 - 53),
  // and 2^1e9: the tightest interval is [(2^53 - 1) * 2^(1e9 - 53), 2^1e9]
  let difference = big.sub(tiny)
  assert_identical(
    difference.lower_bound(),
    @binary.Binary::make(
      @binary.BinCoeff::from_uint64((1UL << 53) - 1UL),
      1000000000 - 53,
      53,
    ),
  )
  assert_identical(difference.upper_bound(), big.upper_bound())
  let reversed = tiny.add(big)
  assert_true(reversed.equal(sum))
}

///|
// oracle: A
// source: worked out by hand: 1 + 2^-60 needs 61 bits, so at 53 bits it is enclosed by [1, 1 + 2^-52] = [1, (2^52 + 1) * 2^-52]; written out as a coefficient and an exponent
// shares: far_addend_power (Binary::make and Interval::exact) builds the operands; Binary::make builds the expected end; Binary::identical compares
test "near addends stay exact" {
  let one = far_addend_power(0)
  let small = far_addend_power(-60)
  let sum = one.add(small)
  // 1 + 2^-60 needs 61 bits; at 53 bits it is enclosed by [1, 1 + 2^-52].
  assert_identical(sum.lower_bound(), one.lower_bound())
  assert_identical(
    sum.upper_bound(),
    @binary.Binary::make(
      @binary.BinCoeff::from_uint64((1UL << 52) + 1UL),
      -52,
      53,
    ),
  )
}
