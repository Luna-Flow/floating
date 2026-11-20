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
fn bz_test_check(
  random : WordsTestRandom,
  divisor_len : Int32,
  numerator_len : Int32,
  pattern : Int32,
) -> Unit raise {
  let denominator = dispatch_test_value(random, divisor_len, pattern)
  let numerator = dispatch_test_value(random, numerator_len, (pattern + 2) % 5)
  if numerator.compare(denominator) < 0 {
    return
  }
  let (knuth_quotient, knuth_remainder) = bin_coeff_div_rem_knuth_words(
    numerator, denominator,
  )
  let (bz_quotient, bz_remainder) = bin_coeff_div_rem_burnikel_ziegler(
    numerator, denominator,
  )
  assert_eq(bz_quotient, knuth_quotient)
  assert_eq(bz_remainder, knuth_remainder)
  let (quotient, remainder) = numerator.div_rem_checked(denominator).unwrap()
  assert_eq(quotient, knuth_quotient)
  assert_eq(remainder, knuth_remainder)
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

///|
test "Burnikel-Ziegler equals Knuth around every padding boundary j * 2^k" {
  let random = { words_state: 0x7A7A_1B1B_E3E3_5C5CUL, }
  let leaf = bin_coeff_bz_leaf_words
  for k in 1..<5 {
    for j in [leaf / 2 + 1, leaf / 2 + 2, 47, 48, 49, leaf - 1, leaf] {
      for offset in [-1, 0, 1] {
        let divisor_len = j * (1 << k) + offset
        for numerator_len in [divisor_len + 1, 2 * divisor_len] {
          for pattern in [0, 1, 2] {
            bz_test_check(random, divisor_len, numerator_len, pattern)
          }
        }
      }
    }
  }
}

///|
test "Burnikel-Ziegler on unbalanced shapes equals Knuth: quotient of 1 limb, 8 and 64 times the divisor" {
  let random = { words_state: 0x1F1F_8E8E_4A4A_D7D7UL, }
  for divisor_len in [65, 97, 130, 193, 257] {
    for
      numerator_len in [divisor_len + 1, divisor_len * 8, divisor_len * 64 + 3] {
      for pattern in [0, 1, 2] {
        bz_test_check(random, divisor_len, numerator_len, pattern)
      }
    }
  }
}
