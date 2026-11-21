///|
test "Coeff reciprocal Newton division is exact" {
  for divisor_limbs in [5, 33, 129] {
    let denominator_big = bin_coeff_test_limb_pattern(divisor_limbs, 8)
    let numerator_big = bin_coeff_test_limb_pattern(divisor_limbs * 2 + 7, 12)
    let denominator = bin_coeff_test_from_bigint(denominator_big)
    let numerator = bin_coeff_test_from_bigint(numerator_big)
    let (quotient, remainder) = bin_coeff_div_rem_newton(numerator, denominator)
    bin_coeff_test_assert_matches(quotient, numerator_big / denominator_big)
    bin_coeff_test_assert_matches(remainder, numerator_big % denominator_big)
    assert_eq(quotient.mul(denominator).add(remainder), numerator)
  }
}

///|
test "Coeff reciprocal Newton production threshold" {
  for divisor_limbs in [1022, 1023, 1024, 1025, 1026] {
    let denominator_big = bin_coeff_test_limb_pattern(divisor_limbs, 6)
    let numerator_big = bin_coeff_test_limb_pattern(divisor_limbs + 73, 10)
    let denominator = bin_coeff_test_from_bigint(denominator_big)
    let numerator = bin_coeff_test_from_bigint(numerator_big)
    let (quotient, remainder) = numerator.div_rem_checked(denominator).unwrap()
    bin_coeff_test_assert_matches(quotient, numerator_big / denominator_big)
    bin_coeff_test_assert_matches(remainder, numerator_big % denominator_big)
    assert_eq(quotient.mul(denominator).add(remainder), numerator)
  }
}

///|
test "the padded length of Burnikel-Ziegler is j * 2^k with j <= leaf, never more than 2^k - 1 above the divisor" {
  let leaf = bin_coeff_bz_leaf_words
  for divisor_len in 1..<3000 {
    let n = bin_coeff_bz_padded_words(divisor_len)
    assert_true(n >= divisor_len)
    if divisor_len <= leaf {
      assert_eq(n, divisor_len)
    } else {
      // n = j * 2^k with the block length j at most the leaf, and k minimal
      let mut blocks = 1
      while n / blocks > leaf || n % blocks != 0 {
        blocks *= 2
      }
      assert_true(n / blocks <= leaf)
      assert_true(n - divisor_len < blocks)
      assert_true(
        blocks == 1 || n / (blocks / 2) > leaf || n % (blocks / 2) != 0,
      )
    }
  }
}
