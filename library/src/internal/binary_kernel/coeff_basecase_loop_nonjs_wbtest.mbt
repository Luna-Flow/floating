///|
/// The high word of a 64 by 64 bit product by the form that `bin_coeff_mul_high`
/// had before issue 438 (P-A7), kept as the reference.
fn bin_coeff_mul_high_reference(left : UInt64, right : UInt64) -> UInt64 {
  let left_low = left & bin_coeff_limb_mask
  let left_high = left >> 32
  let right_low = right & bin_coeff_limb_mask
  let right_high = right >> 32
  let low_low = left_low * right_low
  let high_low = left_high * right_low
  let low_high = left_low * right_high
  let high_high = left_high * right_high
  let middle = (low_low >> 32) +
    (high_low & bin_coeff_limb_mask) +
    (low_high & bin_coeff_limb_mask)
  high_high + (high_low >> 32) + (low_high >> 32) + (middle >> 32)
}

///|
fn bin_coeff_basecase_words(count : Int32) -> Array[UInt64] {
  let edge = [
    0UL, 1UL, 2UL, 0xffff_ffffUL, 0x1_0000_0000UL, 0x1_0000_0001UL, 0x7fff_ffff_ffff_ffffUL,
    0x8000_0000_0000_0000UL, 0xffff_ffff_0000_0000UL, 0xffff_ffff_ffff_fffeUL, 0xffff_ffff_ffff_ffffUL,
  ]
  let words = Array::makei(count, index => edge[index % edge.length()])
  let mut state = 88172645463325252UL
  for index in edge.length()..<count {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    words[index] = state ^ (state >> 29)
  }
  words
}

///|
// oracle: B, E
// source: B: core BigInt product of the two words shifted right by 64, for every pair of 400 words (edge words and a fixed-seed generator); E: the previous 32-bit form bin_coeff_mul_high_reference
// shares: nothing
// primitives: core BigInt multiplication and shift, independent of the kernel
// underneath: the high word is level B against core BigInt for every pair, so the E reference adds nothing the BigInt does not
test "high word of a word product equals the previous form and the exact product" {
  let words = bin_coeff_basecase_words(400)
  for left in words {
    for right in words {
      let expected = bin_coeff_mul_high_reference(left, right)
      assert_eq(bin_coeff_mul_high(left, right), expected)
      assert_eq(binary_fast_mul_high(left, right), expected)
      // the exact product of two words, from core BigInt, for every pair
      let exact = (BigInt::from_uint64(left) * BigInt::from_uint64(right)) >> 64
      assert_eq(BigInt::from_uint64(bin_coeff_mul_high(left, right)), exact)
    }
  }
}

///|
fn bin_coeff_basecase_value(limbs : Int32, pattern : Int32) -> BigInt {
  let words = bin_coeff_basecase_words(limbs + 11)
  let mut value = 0N
  for index in 0..<limbs {
    let word = match pattern {
      0 => words[index + (pattern + 3) % 11]
      1 => 0xffff_ffff_ffff_ffffUL
      2 =>
        if index % 2 == 0 {
          0xffff_ffff_0000_0000UL
        } else {
          0x0000_0000_ffff_ffffUL
        }
      _ => words[(index * 7 + pattern) % words.length()]
    }
    value = (value << 64) + BigInt::from_uint64(word)
  }
  value + 1N
}

///|
// oracle: B
// source: core BigInt product and square of limb patterns built from edge words (zero, one, 2^32 and its neighbours, 2^63, all ones, a fixed-seed generator) for 14 by 11 lengths from 1 to 70 limbs in five patterns: Coeff::mul, Coeff::square, bin_coeff_mul_schoolbook, bin_coeff_square_schoolbook and bin_coeff_square_words, compared through the decimal text
// shares: bin_coeff_basecase_value builds the operands (the expected value is the BigInt product of the same integer); bin_coeff_test_from_bigint and bin_coeff_test_assert_matches (Coeff::parse and Coeff::to_string in radix 10)
// primitives: core BigInt (moonbitlang/core) multiplication and shifts are an implementation independent of the kernel; Coeff::parse and Coeff::to_string: level A in the radix table (coeff_radix_oracle_wbtest.mbt, CPython int and divmod)
test "schoolbook and word products and squares of edge limbs match BigInt" {
  for left_limbs in [1, 2, 3, 4, 5, 8, 9, 16, 17, 31, 32, 33, 40, 70] {
    for right_limbs in [1, 2, 3, 4, 7, 8, 16, 31, 32, 34, 41] {
      for pattern in 0..<5 {
        let left_big = bin_coeff_basecase_value(left_limbs, pattern)
        let right_big = bin_coeff_basecase_value(right_limbs, (pattern + 2) % 5)
        let left = bin_coeff_test_from_bigint(left_big)
        let right = bin_coeff_test_from_bigint(right_big)
        bin_coeff_test_assert_matches(left.mul(right), left_big * right_big)
        bin_coeff_test_assert_matches(
          bin_coeff_mul_schoolbook(left, right),
          left_big * right_big,
        )
      }
    }
    for pattern in 0..<5 {
      let big = bin_coeff_basecase_value(left_limbs, pattern)
      let value = bin_coeff_test_from_bigint(big)
      bin_coeff_test_assert_matches(value.square(), big * big)
      bin_coeff_test_assert_matches(
        bin_coeff_square_schoolbook(value),
        big * big,
      )
      if left_limbs >= 3 {
        bin_coeff_test_assert_matches(bin_coeff_square_words(value), big * big)
        bin_coeff_test_assert_matches(
          bin_coeff_mul_words(value, value),
          big * big,
        )
      }
    }
  }
}
