///|
/// The `count` limbs of `words` from `offset` are the integer `expected`.
fn bin_limbs_assert_row(
  words : FixedArray[UInt64],
  offset : Int32,
  count : Int32,
  expected : BigInt,
) -> Unit raise {
  assert_eq(bin_limbs_big(words, offset, count), expected)
}

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
// oracle: B
// source: core BigInt multiplication of the integers of the operand limbs (sizes around the Karatsuba cutoff, up to 7 cutoffs, five limb patterns); replaces the comparison with bin_coeff_words_school, whose own level A is the limb row table up to 100 limbs
// shares: words_test_array (the operands only) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (limbs to BigInt by shift and addition of core; level A in "bin_limbs_big reads the limbs least significant first")
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
        let expected = bin_limbs_big(left, 0, left_len) *
          bin_limbs_big(right, 0, right_len)
        // an offset result inside a larger array, with garbage around it
        let actual = FixedArray::make(left_len + right_len + 6, 0x5555UL)
        bin_coeff_words_mul(actual, 3, left, 0, left_len, right, 0, right_len)
        bin_limbs_assert_row(actual, 3, left_len + right_len, expected)
        assert_eq(actual[0], 0x5555UL)
        assert_eq(actual[1], 0x5555UL)
        assert_eq(actual[2], 0x5555UL)
        assert_eq(actual[left_len + right_len + 3], 0x5555UL)
        assert_eq(actual[left_len + right_len + 5], 0x5555UL)
      }
    }
  }
}

///|
/// The integer of a coefficient, read limb by limb with `bin_coeff_word`.
fn bin_coeff_test_big(value : Coeff) -> BigInt {
  bin_limbs_big(
    FixedArray::makei(bin_coeff_word_len(value), index => {
      bin_coeff_word(value, index)
    }),
    0,
    bin_coeff_word_len(value),
  )
}

///|
// oracle: B
// source: core BigInt multiplication of the integers of the operand limbs: Coeff::mul, Coeff::square and bin_coeff_mul_words all equal it (replaces the comparison with bin_coeff_mul_schoolbook and the hexadecimal text of the two routes)
// shares: bin_coeff_from_words and bin_coeff_word_len and bin_coeff_word (the product is read limb by limb through bin_coeff_test_big), words_test_array
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first"); bin_coeff_word and bin_coeff_word_len, accessors of the stored limbs
test "Coeff product through the word-range Karatsuba equals BigInt" {
  let random = { words_state: 0x1357_9BDF_2468_ACE0UL, }
  let cutoff = bin_coeff_words_karatsuba_cutoff
  for words in [cutoff, cutoff + 1, 2 * cutoff + 1, 5 * cutoff] {
    for pattern in [0, 1, 2, 4] {
      let left_words = words_test_array(random, words, pattern)
      let right_words = words_test_array(random, words - 1, (pattern + 3) % 5)
      let left_big = bin_limbs_big(left_words, 0, words)
      let right_big = bin_limbs_big(right_words, 0, words - 1)
      let left = bin_coeff_from_words(left_words.copy(), words)
      let right = bin_coeff_from_words(right_words.copy(), words - 1)
      assert_eq(bin_coeff_test_big(left.mul(right)), left_big * right_big)
      assert_eq(bin_coeff_test_big(left.mul(left)), left_big * left_big)
      assert_eq(bin_coeff_test_big(left.square()), left_big * left_big)
      assert_eq(
        bin_coeff_test_big(bin_coeff_mul_words(left, right)),
        left_big * right_big,
      )
    }
  }
}

///|
// oracle: B
// source: bin_coeff_mul_schoolbook, a different algorithm from the 32-bit-limb Karatsuba, on every pair of ten sizes around the cutoff (3 to 9 cutoffs plus 2 words) in five operand patterns
// shares: bin_coeff_from_words and words_test_array build the operands; Coeff equality compares; bin_coeff_mul_limb32 is the code under test
// primitives: bin_coeff_mul_schoolbook: level B against core BigInt in `schoolbook and word products and squares of edge limbs match BigInt` (coeff_basecase_loop_nonjs_wbtest.mbt)
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
// oracle: B
// source: bin_coeff_square_schoolbook and bin_coeff_mul_schoolbook(value, value), different algorithms from the 32-bit-limb square, for 12 lengths from 3 to 257 words in five patterns
// shares: bin_coeff_from_words and words_test_array build the operands; Coeff equality compares; bin_coeff_square_limb32 is the code under test
// primitives: bin_coeff_square_schoolbook and bin_coeff_mul_schoolbook: level B against core BigInt in `schoolbook and word products and squares of edge limbs match BigInt` (coeff_basecase_loop_nonjs_wbtest.mbt)
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
// oracle: B
// source: the slice rebuilt word by word with bin_coeff_word and bin_coeff_from_words (another route to the same words), for starts and lengths around the word length (empty, one word, past the end), six lengths in five patterns
// shares: bin_coeff_word, bin_coeff_word_len, bin_coeff_from_words, words_test_array and FixedArray::make build the expected slice and the operands; bin_coeff_word_slice is the code under test
// primitives: bin_coeff_word and bin_coeff_word_len: level A in `Coeff 64-bit limbs: sizes, words and the 32-bit view agree` (coeff_words_nonjs_wbtest.mbt, the words as the halves written out)
test "word slices of 64-bit storage equal the limb-by-limb view" {
  let random = { words_state: 0x7777_1111_3333_9999UL, }
  for len in [3, 4, 5, 9, 16, 33] {
    for pattern in 0..<5 {
      let value = bin_coeff_from_words(
        words_test_array(random, len, pattern),
        len,
      )
      let word_len = bin_coeff_word_len(value)
      for start in [0, 1, 2, word_len / 2, word_len - 1, word_len, word_len + 2] {
        for length in [0, 1, 2, 3, word_len / 2, word_len, word_len + 5] {
          let words = FixedArray::make(Int32::max(length, 1), 0UL)
          for index in 0..<length {
            words[index] = bin_coeff_word(value, start + index)
          }
          let expected = if length <= 0 || start >= word_len {
            Coeff::zero()
          } else {
            bin_coeff_from_words(words, Int32::min(length, word_len - start))
          }
          assert_eq(bin_coeff_word_slice(value, start, length), expected)
        }
      }
    }
  }
}

///|
// oracle: B, E
// source: B: the exact product from core BigInt on the integers of the limbs (bin_limbs_big, shifts and sums of core BigInt), and the schoolbook product bin_coeff_words_school, a different algorithm from the Karatsuba under test; the guard limbs around the result stay unchanged; E: the allocating Karatsuba reference ref_words_mul
// shares: nothing between the Karatsuba and core BigInt; the limb operands are read through bin_limbs_big
// primitives: bin_limbs_big, a pure core BigInt loop, with its own level A block in coeff_test_support_wbtest.mbt
// underneath: the product oracle table coeff_product_oracle_wbtest.mbt, route words (level A, CPython products)
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
      // the exact product of the operands from core BigInt
      let product = bin_limbs_big(left, 0, left_len) *
        bin_limbs_big(right, 0, right_len)
      assert_eq(bin_limbs_big(actual, 2, total), product)
    }
  }
}

///|
// oracle: B
// source: bin_coeff_words_school (the product of the value by itself) and bin_coeff_words_sqr_school, different algorithms from the scratch-buffer Karatsuba square, on 14 sizes from 1 to 16 cutoffs in five patterns, with an offset result and source inside larger arrays and garbage limbs around that must stay unchanged
// shares: words_test_array and FixedArray::make build the operands and the guard limbs; bin_coeff_words_scratch_len sizes the scratch; bin_coeff_words_sqr_scratch is the code under test
// primitives: bin_coeff_words_school: level B against core BigInt and the allocating Karatsuba in `word-range Karatsuba equals the schoolbook product around and above the cutoff` (this file)
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
// oracle: B
// source: bin_coeff_mul_schoolbook(value, value), a different algorithm from the square routes, for 20 lengths from 16 to 520 words around the schoolbook, Karatsuba and NTT square cutoffs in four patterns; the square, bin_coeff_square_words and the product of the value by itself must all equal it
// shares: bin_coeff_from_words and words_test_array build the operands; Coeff equality compares; Coeff::square, bin_coeff_square_words and Coeff::mul are the code under test
// primitives: bin_coeff_mul_schoolbook: level B against core BigInt in `schoolbook and word products and squares of edge limbs match BigInt` (coeff_basecase_loop_nonjs_wbtest.mbt)
test "Coeff square around the schoolbook, Karatsuba and NTT square cutoffs" {
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
// oracle: B
// source: core BigInt squaring of the integer of the operand limbs: Coeff::square, the Karatsuba square, the NTT square and the product of the value by itself all equal it (replaces the comparison between the routes)
// shares: bin_coeff_from_words and the limb accessors (bin_coeff_test_big), words_test_array
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first"); bin_coeff_word and bin_coeff_word_len, accessors of the stored limbs
test "Coeff square at the NTT square cutoff equals the Karatsuba square and product" {
  let random = { words_state: 0x1D1D_E2E2_4B4B_8F8FUL, }
  // the NTT square starts at `bin_coeff_ntt_square_min_words` limbs
  let boundary = bin_coeff_ntt_square_min_words
  for len in [boundary - 1, boundary, boundary + 1] {
    for pattern in [0, 1] {
      let words = words_test_array(random, len, pattern)
      let expected = bin_limbs_big(words, 0, len) * bin_limbs_big(words, 0, len)
      let value = bin_coeff_from_words(words.copy(), len)
      assert_eq(bin_coeff_test_big(value.square()), expected)
      assert_eq(bin_coeff_test_big(bin_coeff_square_words(value)), expected)
      assert_eq(bin_coeff_test_big(bin_coeff_square_ntt(value)), expected)
      assert_eq(bin_coeff_test_big(value.mul(value)), expected)
    }
  }
}
