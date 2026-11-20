///|
struct WordsTestRandom {
  mut words_state : UInt64
}

///|
fn WordsTestRandom::next(self : WordsTestRandom) -> UInt64 {
  self.words_state = self.words_state * 6364136223846793005UL +
    1442695040888963407UL
  (self.words_state >> 17) | (self.words_state << 47)
}

///|
/// `len` limbs of a pattern: 0 random, 1 all ones, 2 zero limbs inside,
/// 3 a single set bit at the top, 4 alternating all ones and zero limbs.
fn words_test_array(
  random : WordsTestRandom,
  len : Int32,
  pattern : Int32,
) -> FixedArray[UInt64] {
  let words = FixedArray::make(len, 0UL)
  for index in 0..<len {
    words[index] = match pattern {
      0 => random.next()
      1 => 0xFFFF_FFFF_FFFF_FFFFUL
      2 => if index < 3 || index >= len - 3 { random.next() } else { 0UL }
      3 => 0UL
      _ => if index % 2 == 0 { 0xFFFF_FFFF_FFFF_FFFFUL } else { 0UL }
    }
  }
  // a nonzero top limb
  words[len - 1] = words[len - 1] | (1UL << 63)
  words
}

///|
test "word-range Karatsuba equals the schoolbook product around and above the cutoff" {
  let random = { words_state: 0xFEED_FACE_CAFE_BEEFUL, }
  let cutoff = bin_coeff_words_karatsuba_cutoff
  let sizes = [
    cutoff - 1,
    cutoff,
    cutoff + 1,
    cutoff + 2,
    2 * cutoff - 1,
    2 * cutoff,
    2 * cutoff + 1,
    3 * cutoff + 5,
    4 * cutoff,
    7 * cutoff + 3,
  ]
  for left_len in sizes {
    for right_len in sizes {
      for pattern in 0..<5 {
        let left = words_test_array(random, left_len, pattern)
        let right = words_test_array(random, right_len, (pattern + 1) % 5)
        let expected = FixedArray::make(left_len + right_len, 0UL)
        bin_coeff_words_school(
          expected, 0, left, 0, left_len, right, 0, right_len,
        )
        // an offset result inside a larger array, with garbage around it
        let actual = FixedArray::make(left_len + right_len + 6, 0x5555UL)
        bin_coeff_words_mul(actual, 3, left, 0, left_len, right, 0, right_len)
        for index in 0..<(left_len + right_len) {
          assert_eq(actual[3 + index], expected[index])
        }
        assert_eq(actual[0], 0x5555UL)
        assert_eq(actual[left_len + right_len + 5], 0x5555UL)
      }
    }
  }
}

///|
test "BinCoeff product through the word-range Karatsuba equals BigInt" {
  let random = { words_state: 0x1357_9BDF_2468_ACE0UL, }
  let cutoff = bin_coeff_words_karatsuba_cutoff
  for words in [cutoff, cutoff + 1, 2 * cutoff + 1, 5 * cutoff] {
    for pattern in [0, 1, 2, 4] {
      let left_words = words_test_array(random, words, pattern)
      let right_words = words_test_array(random, words - 1, (pattern + 3) % 5)
      let left = bin_coeff_from_words(left_words.copy(), words)
      let right = bin_coeff_from_words(right_words.copy(), words - 1)
      let product = left.mul(right)
      assert_eq(product, bin_coeff_mul_schoolbook(left, right))
      assert_eq(left.mul(left), left.square())
      assert_eq(
        left.mul(right).to_radix_string(16),
        bin_coeff_mul_words(left, right).to_radix_string(16),
      )
    }
  }
}

///|
test "32-bit-limb Karatsuba (the Wasm route) equals the schoolbook product" {
  let random = { words_state: 0x0BAD_C0DE_1234_5678UL, }
  let cutoff = bin_coeff_limb32_karatsuba_cutoff / 2
  let sizes = [
    3,
    5,
    cutoff - 1,
    cutoff,
    cutoff + 1,
    2 * cutoff,
    2 * cutoff + 1,
    3 * cutoff + 5,
    5 * cutoff,
    9 * cutoff + 2,
  ]
  for left_len in sizes {
    for right_len in sizes {
      for pattern in 0..<5 {
        let left = bin_coeff_from_words(
          words_test_array(random, left_len, pattern),
          left_len,
        )
        let right = bin_coeff_from_words(
          words_test_array(random, right_len, (pattern + 2) % 5),
          right_len,
        )
        assert_eq(
          bin_coeff_mul_limb32(left, right),
          bin_coeff_mul_schoolbook(left, right),
        )
      }
    }
  }
}

///|
test "32-bit-limb squaring (the Wasm route) equals the schoolbook square" {
  let random = { words_state: 0x5151_5151_ABAB_ABABUL, }
  for len in [3, 4, 5, 8, 17, 31, 32, 33, 64, 100, 161, 257] {
    for pattern in 0..<5 {
      let value = bin_coeff_from_words(
        words_test_array(random, len, pattern),
        len,
      )
      assert_eq(
        bin_coeff_square_limb32(value),
        bin_coeff_square_schoolbook(value),
      )
      assert_eq(
        bin_coeff_square_limb32(value),
        bin_coeff_mul_schoolbook(value, value),
      )
    }
  }
}

///|
test "32-bit limb slices of 64-bit storage equal the limb-by-limb view" {
  let random = { words_state: 0x7777_1111_3333_9999UL, }
  for len in [3, 4, 5, 9, 16, 33] {
    for pattern in 0..<5 {
      let value = bin_coeff_from_words(
        words_test_array(random, len, pattern),
        len,
      )
      let limb_len = bin_coeff_limb_len(value)
      for
        start in [
          0,
          1,
          2,
          3,
          limb_len / 2,
          limb_len - 1,
          limb_len,
          limb_len + 2,
        ] {
        for length in [0, 1, 2, 3, 6, limb_len / 2, limb_len, limb_len + 5] {
          let limbs = FixedArray::make(Int32::max(length, 1), 0U)
          for index in 0..<length {
            limbs[index] = bin_coeff_limb(value, start + index)
          }
          let expected = if length <= 0 || start >= limb_len {
            BinCoeff::zero()
          } else {
            bin_coeff_from_limbs(limbs, Int32::min(length, limb_len - start))
          }
          assert_eq(bin_coeff_slice(value, start, length), expected)
        }
      }
    }
  }
}

///|
test "scratch-buffer Karatsuba equals the allocating Karatsuba of #326 and the schoolbook" {
  let random = { words_state: 0x2468_ACE0_1357_9BDFUL, }
  let cutoff = bin_coeff_words_karatsuba_cutoff
  let sizes = [
    cutoff,
    cutoff + 1,
    2 * cutoff - 1,
    2 * cutoff,
    2 * cutoff + 1,
    3 * cutoff + 5,
    4 * cutoff,
    4 * cutoff + 1,
    5 * cutoff - 3,
    9 * cutoff + 7,
    16 * cutoff,
  ]
  for left_len in sizes {
    for right_len in sizes {
      // one pattern per pair keeps the test cheap; the pattern rotates
      let pattern = (left_len + right_len) % 5
      let left = words_test_array(random, left_len, pattern)
      let right = words_test_array(random, right_len, (pattern + 2) % 5)
      let total = left_len + right_len
      let expected = FixedArray::make(total, 0UL)
      bin_coeff_words_school(
        expected, 0, left, 0, left_len, right, 0, right_len,
      )
      let reference = FixedArray::make(total, 0UL)
      ref_words_mul(reference, 0, left, 0, left_len, right, 0, right_len)
      let actual = FixedArray::make(total + 4, 0x5555UL)
      bin_coeff_words_mul(actual, 2, left, 0, left_len, right, 0, right_len)
      for index in 0..<total {
        assert_eq(reference[index], expected[index])
        assert_eq(actual[2 + index], expected[index])
      }
      assert_eq(actual[1], 0x5555UL)
      assert_eq(actual[total + 2], 0x5555UL)
    }
  }
}

///|
test "word-range Karatsuba square equals the schoolbook square and product" {
  let random = { words_state: 0x7A7A_3C3C_9E9E_1B1BUL, }
  let cutoff = bin_coeff_words_square_cutoff
  let sizes = [
    1,
    2,
    cutoff - 1,
    cutoff,
    cutoff + 1,
    cutoff + 2,
    2 * cutoff - 1,
    2 * cutoff,
    2 * cutoff + 1,
    3 * cutoff + 5,
    4 * cutoff,
    4 * cutoff + 1,
    7 * cutoff + 3,
    16 * cutoff,
  ]
  for len in sizes {
    for pattern in 0..<5 {
      let value = words_test_array(random, len, pattern)
      let expected = FixedArray::make(2 * len, 0UL)
      bin_coeff_words_school(expected, 0, value, 0, len, value, 0, len)
      let school = FixedArray::make(2 * len, 0UL)
      bin_coeff_words_sqr_school(school, 0, value, 0, len)
      // an offset result and source inside larger arrays, with garbage around
      let source = FixedArray::make(len + 5, 0x7777UL)
      for index in 0..<len {
        source[3 + index] = value[index]
      }
      let actual = FixedArray::make(2 * len + 6, 0x5555UL)
      let scratch = FixedArray::make(bin_coeff_words_scratch_len(len) + 3, 0UL)
      bin_coeff_words_sqr_scratch(actual, 3, source, 3, len, scratch, 2)
      for index in 0..<(2 * len) {
        assert_eq(school[index], expected[index])
        assert_eq(actual[3 + index], expected[index])
      }
      assert_eq(actual[2], 0x5555UL)
      assert_eq(actual[2 * len + 3], 0x5555UL)
    }
  }
}

///|
test "BinCoeff square around the schoolbook, Karatsuba and NTT square cutoffs" {
  let random = { words_state: 0x0F0F_A5A5_3C3C_9696UL, }
  let sizes = [
    16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 383, 384, 385,
    511, 512, 520,
  ]
  for len in sizes {
    for pattern in [0, 1, 2, 4] {
      let value = bin_coeff_from_words(
        words_test_array(random, len, pattern),
        len,
      )
      let expected = bin_coeff_mul_schoolbook(value, value)
      assert_eq(value.square(), expected)
      assert_eq(bin_coeff_square_words(value), expected)
      assert_eq(value.mul(value), expected)
    }
  }
}

///|
test "BinCoeff square at the NTT square cutoff equals the Karatsuba square and product" {
  let random = { words_state: 0x1D1D_E2E2_4B4B_8F8FUL, }
  // the NTT square starts at `bin_coeff_ntt_square_threshold` 32-bit limbs
  let boundary = bin_coeff_ntt_square_threshold / 2
  for len in [boundary - 1, boundary, boundary + 1] {
    for pattern in [0, 1] {
      let value = bin_coeff_from_words(
        words_test_array(random, len, pattern),
        len,
      )
      let karatsuba = bin_coeff_square_words(value)
      assert_eq(value.square(), karatsuba)
      assert_eq(bin_coeff_square_ntt(value), karatsuba)
      assert_eq(value.mul(value), karatsuba)
    }
  }
}
