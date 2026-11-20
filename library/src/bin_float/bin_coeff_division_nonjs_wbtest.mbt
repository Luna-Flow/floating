///|
test "BinCoeff reciprocal Newton division is exact" {
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
test "BinCoeff reciprocal Newton production threshold" {
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
