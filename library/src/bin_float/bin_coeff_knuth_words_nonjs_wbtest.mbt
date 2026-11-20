///|
fn knuth_test_check(numerator : BinCoeff, denominator : BinCoeff) -> Unit raise {
  if denominator.is_zero() || numerator.compare(denominator) < 0 {
    return
  }
  let (quotient, remainder) = bin_coeff_div_rem_knuth_words(
    numerator, denominator,
  )
  // the defining identity ...
  assert_true(remainder.compare(denominator) < 0)
  assert_eq(quotient.mul(denominator).add(remainder), numerator)
  // ... and the 32-bit-limb implementation
  let (old_quotient, old_remainder) = bin_coeff_div_rem_knuth_limb32(
    numerator, denominator,
  )
  assert_eq(quotient, old_quotient)
  assert_eq(remainder, old_remainder)
}

///|
test "64-bit-digit Knuth division equals the 32-bit one on random and adversarial operands" {
  let random = { words_state: 0xD1B5_4A32_D192_ED03UL, }
  for denominator_len in [1, 2, 3, 4, 5, 8, 16, 17, 33] {
    for extra in [0, 1, 2, 3, 7, 20] {
      for pattern in 0..<5 {
        let numerator_len = denominator_len + extra
        let denominator = bin_coeff_from_words(
          words_test_array(random, denominator_len, pattern),
          denominator_len,
        )
        let numerator = bin_coeff_from_words(
          words_test_array(random, numerator_len, (pattern + 1) % 5),
          numerator_len,
        )
        knuth_test_check(numerator, denominator)
        // numerator just below and at a multiple of the denominator
        let multiple = denominator.mul(
          bin_coeff_from_words(
            words_test_array(random, extra + 1, (pattern + 2) % 5),
            extra + 1,
          ),
        )
        knuth_test_check(multiple, denominator)
        if !multiple.is_zero() {
          knuth_test_check(
            multiple.sub_checked(BinCoeff::one()).unwrap(),
            denominator,
          )
        }
        knuth_test_check(
          multiple.add(denominator.sub_checked(BinCoeff::one()).unwrap()),
          denominator,
        )
        // a divisor with a small top word (large normalization shift) and
        // one whose top words are all ones (maximal digit estimates)
        let small_top = denominator.shift_right(denominator.bit_length() - 3)
        knuth_test_check(
          numerator,
          small_top
          .shift_left(Int32::max(0, 64 * denominator_len - 3))
          .add(BinCoeff::one()),
        )
        let ones = bin_coeff_from_words(
          FixedArray::make(denominator_len, 0xFFFF_FFFF_FFFF_FFFFUL),
          denominator_len,
        )
        knuth_test_check(numerator, ones)
        knuth_test_check(ones.mul(ones), ones)
        knuth_test_check(
          ones.mul(ones).sub_checked(BinCoeff::one()).unwrap(),
          ones.sub_checked(BinCoeff::one()).unwrap(),
        )
      }
    }
  }
}

///|
test "division of large operands inverts multiplication (Burnikel-Ziegler range)" {
  let random = { words_state: 0x600D_F00D_1234_5678UL, }
  for denominator_len in [95, 96, 97, 191, 192, 193, 400, 1100, 2100] {
    for quotient_len in [1, 7, denominator_len, 2 * denominator_len + 3] {
      for pattern in [0, 1, 2, 4] {
        let denominator = bin_coeff_from_words(
          words_test_array(random, denominator_len, pattern),
          denominator_len,
        )
        let quotient = bin_coeff_from_words(
          words_test_array(random, quotient_len, (pattern + 1) % 5),
          quotient_len,
        )
        let remainder = denominator.sub_checked(BinCoeff::one()).unwrap()
        let numerator = denominator.mul(quotient).add(remainder)
        let (found_quotient, found_remainder) = numerator
          .div_rem_checked(denominator)
          .unwrap()
        assert_eq(found_quotient, quotient)
        assert_eq(found_remainder, remainder)
        // Newton reciprocal division (now outside the dispatch) agrees too
        if denominator_len <= 400 {
          let (newton_quotient, newton_remainder) = bin_coeff_div_rem_newton(
            numerator, denominator,
          )
          assert_eq(newton_quotient, quotient)
          assert_eq(newton_remainder, remainder)
        }
      }
    }
  }
}
