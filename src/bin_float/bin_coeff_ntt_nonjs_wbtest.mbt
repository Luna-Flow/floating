///|
test "BinCoeff NTT constants and exact reconstruction" {
  let modulus_product = bin_coeff_ntt_prime1 * bin_coeff_ntt_prime2
  assert_eq(modulus_product, 753649251896000513UL)
  assert_eq(
    bin_coeff_ntt_prime1 * bin_coeff_ntt_crt_inverse % bin_coeff_ntt_prime2,
    1UL,
  )
  assert_eq(
    (bin_coeff_ntt_prime1 * bin_coeff_ntt_nprime1) & 0xffff_ffffUL,
    0xffff_ffffUL,
  )
  assert_eq(
    (bin_coeff_ntt_prime2 * bin_coeff_ntt_nprime2) & 0xffff_ffffUL,
    0xffff_ffffUL,
  )
  assert_eq((1UL << 32) % bin_coeff_ntt_prime1, bin_coeff_ntt_r_prime1)
  assert_eq((1UL << 32) % bin_coeff_ntt_prime2, bin_coeff_ntt_r_prime2)
  assert_eq(
    bin_coeff_ntt_r_prime1 * bin_coeff_ntt_r_prime1 % bin_coeff_ntt_prime1,
    bin_coeff_ntt_r2_prime1,
  )
  assert_eq(
    bin_coeff_ntt_r_prime2 * bin_coeff_ntt_r_prime2 % bin_coeff_ntt_prime2,
    bin_coeff_ntt_r2_prime2,
  )
  assert_eq(
    bin_coeff_ntt_pow_normal(
      bin_coeff_ntt_root1,
      bin_coeff_ntt_prime1 - 1UL,
      bin_coeff_ntt_prime1,
      bin_coeff_ntt_nprime1,
      bin_coeff_ntt_r2_prime1,
      bin_coeff_ntt_r_prime1,
    ),
    1UL,
  )
  assert_true(
    bin_coeff_ntt_pow_normal(
      bin_coeff_ntt_root1,
      (bin_coeff_ntt_prime1 - 1UL) / 2UL,
      bin_coeff_ntt_prime1,
      bin_coeff_ntt_nprime1,
      bin_coeff_ntt_r2_prime1,
      bin_coeff_ntt_r_prime1,
    ) !=
    1UL,
  )
  for
    constants in [
      (
        bin_coeff_ntt_prime1, bin_coeff_ntt_root1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1,
        bin_coeff_ntt_r_prime1,
      ),
      (
        bin_coeff_ntt_prime2, bin_coeff_ntt_root2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2,
        bin_coeff_ntt_r_prime2,
      ),
    ] {
    let (prime, primitive_root, nprime, r2, montgomery_one) = constants
    assert_eq((prime - 1UL) % bin_coeff_ntt_max_length.to_uint64(), 0UL)
    let maximum_root = bin_coeff_ntt_pow_normal(
      primitive_root,
      (prime - 1UL) / bin_coeff_ntt_max_length.to_uint64(),
      prime,
      nprime,
      r2,
      montgomery_one,
    )
    assert_eq(
      bin_coeff_ntt_pow_normal(
        maximum_root,
        bin_coeff_ntt_max_length.to_uint64(),
        prime,
        nprime,
        r2,
        montgomery_one,
      ),
      1UL,
    )
    assert_true(
      bin_coeff_ntt_pow_normal(
        maximum_root,
        (bin_coeff_ntt_max_length / 2).to_uint64(),
        prime,
        nprime,
        r2,
        montgomery_one,
      ) !=
      1UL,
    )
  }
  let maximum_digit = 0xffffUL
  let maximum_terms = (bin_coeff_ntt_max_length / 2).to_uint64()
  let maximum_coefficient = maximum_terms * maximum_digit * maximum_digit
  let maximum_carry = maximum_coefficient / maximum_digit + 1UL
  assert_true(modulus_product > maximum_coefficient)
  assert_true(maximum_coefficient + maximum_carry >= maximum_coefficient)
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
test "BinCoeff NTT production crossover is exact" {
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
