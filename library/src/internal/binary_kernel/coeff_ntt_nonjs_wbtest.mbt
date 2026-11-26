///|
// oracle: A, B
// source: A: the constants of the two primes, their product and the carry bound written as literals (998244353 = 119 2^23 + 1 and 754974721 = 45 2^24 + 1, their product 753649251896000513, 2^22 65535^2 = 18013848757862400, computed with CPython integers); the relations between the constants (nprime, r, r2, crt_inverse, the order of the roots) are the `const` and `mont` rows of the NTT table (coeff_ntt_oracle_wbtest.mbt), no longer recomputed here with the library's own power function. B: core BigInt products and squares of operands of 5 to 129 limbs against bin_coeff_mul_ntt and bin_coeff_square_ntt
// shares: bin_coeff_test_from_bigint and bin_coeff_test_assert_matches (Coeff::parse and Coeff::to_string in radix 10), bin_coeff_test_limb_pattern for the operands only
// primitives: Coeff::parse and Coeff::to_string: level A in the radix table (coeff_radix_oracle_wbtest.mbt, CPython int and divmod); the constants are the literals above
test "Coeff NTT constants and exact reconstruction" {
  assert_eq(bin_coeff_ntt_prime1, 998244353UL)
  assert_eq(bin_coeff_ntt_prime2, 754974721UL)
  assert_eq(bin_coeff_ntt_prime1 * bin_coeff_ntt_prime2, 753649251896000513UL)
  // the largest convolution coefficient, 2^22 terms of two 16-bit digits, and its
  // carry into the next digit, stay below the product of the primes
  let maximum_coefficient = 18013848757862400UL
  assert_eq(
    (bin_coeff_ntt_max_length / 2).to_uint64() * 65535UL * 65535UL,
    maximum_coefficient,
  )
  assert_true(maximum_coefficient < 753649251896000513UL)
  assert_true(
    maximum_coefficient + (maximum_coefficient / 65535UL + 1UL) <
    753649251896000513UL,
  )
  for limbs in [5, 17, 64, 129] {
    let left_big = bin_coeff_test_limb_pattern(limbs, 5)
    let right_big = bin_coeff_test_limb_pattern(limbs - 1, 13)
    let left = bin_coeff_test_from_bigint(left_big)
    let right = bin_coeff_test_from_bigint(right_big)
    bin_coeff_test_assert_matches(
      bin_coeff_mul_ntt(left, right),
      left_big * right_big,
    )
    bin_coeff_test_assert_matches(
      bin_coeff_square_ntt(left),
      left_big * left_big,
    )
  }
}

///|
// oracle: B
// source: core BigInt: the square of 2^(3072 * 32) - 1 and the product of 2^(4096 * 32) - 1 by 2^(4096 * 32 - 17) + 2^(4096 * 16 + 3) + 1, the two production crossovers of the NTT, compared through the decimal text
// shares: bin_coeff_test_from_bigint and bin_coeff_test_assert_matches (Coeff::parse and Coeff::to_string in radix 10)
// primitives: core BigInt (moonbitlang/core) multiplication and shifts are an implementation independent of the kernel; Coeff::parse and Coeff::to_string: level A in the radix table (coeff_radix_oracle_wbtest.mbt, CPython int and divmod)
test "Coeff NTT production crossover is exact" {
  let square_limbs = 3072
  let square_big = (1N << (square_limbs * 32)) - 1N
  let square_value = bin_coeff_test_from_bigint(square_big)
  bin_coeff_test_assert_matches(square_value.square(), square_big * square_big)
  let multiply_limbs = 4096
  let left_big = (1N << (multiply_limbs * 32)) - 1N
  let right_big = (1N << (multiply_limbs * 32 - 17)) +
    (1N << (multiply_limbs * 16 + 3)) +
    1N
  let left = bin_coeff_test_from_bigint(left_big)
  let right = bin_coeff_test_from_bigint(right_big)
  bin_coeff_test_assert_matches(left.mul(right), left_big * right_big)
}
