///|
fn dispatch_test_value(
  random : WordsTestRandom,
  len : Int32,
  pattern : Int32,
) -> Coeff {
  bin_coeff_from_words(words_test_array(random, len, pattern), len)
}

///|
/// Sparse operand: `count` nonzero limbs spread over `len`, a nonzero top.
fn dispatch_test_sparse(
  random : WordsTestRandom,
  len : Int32,
  count : Int32,
) -> Coeff {
  let words = FixedArray::make(len, 0UL)
  for index in 0..<count {
    words[index * (len - 1) / Int32::max(count - 1, 1)] = random.next() | 1UL
  }
  words[len - 1] = words[len - 1] | (1UL << 63)
  bin_coeff_from_words(words, len)
}

///|
test "bit operations on limbs equal the 32-bit limb loops" {
  let random = { words_state: 0x1234_5678_9ABC_DEF1UL, }
  for left_len in [1, 2, 3, 4, 5, 8, 17, 33] {
    for right_len in [1, 2, 3, 5, 6, 16, 40] {
      for pattern in [0, 1, 2, 4] {
        let left = dispatch_test_value(random, left_len, pattern)
        let right = dispatch_test_value(random, right_len, (pattern + 1) % 5)
        let limb_len = Int32::max(
          bin_coeff_limb_len(left),
          bin_coeff_limb_len(right),
        )
        let and_limbs = FixedArray::make(limb_len, 0U)
        let or_limbs = FixedArray::make(limb_len, 0U)
        let xor_limbs = FixedArray::make(limb_len, 0U)
        for index in 0..<limb_len {
          let a = bin_coeff_limb(left, index)
          let b = bin_coeff_limb(right, index)
          and_limbs[index] = a & b
          or_limbs[index] = a | b
          xor_limbs[index] = a ^ b
        }
        assert_eq(
          left.bit_and(right),
          bin_coeff_from_limbs(and_limbs, limb_len),
        )
        assert_eq(left.bit_or(right), bin_coeff_from_limbs(or_limbs, limb_len))
        assert_eq(
          left.bit_xor(right),
          bin_coeff_from_limbs(xor_limbs, limb_len),
        )
        assert_eq(left.bit_and(right), right.bit_and(left))
      }
    }
  }
}

///|
test "sparse products equal the schoolbook product" {
  let random = { words_state: 0x0F1E_2D3C_4B5A_6978UL, }
  for len in [4, 5, 8, 9, 16, 17, 32, 40] {
    for count in [1, 2, 3, 4, len / 8, len / 4] {
      if count < 1 || count > len {
        continue
      }
      let sparse = dispatch_test_sparse(random, len, count)
      for other_len in [4, 6, 16, 33] {
        let dense = dispatch_test_value(random, other_len, 0)
        let sparse_other = dispatch_test_sparse(random, other_len, 2)
        assert_eq(sparse.mul(dense), bin_coeff_mul_schoolbook(sparse, dense))
        assert_eq(dense.mul(sparse), bin_coeff_mul_schoolbook(dense, sparse))
        assert_eq(
          sparse.mul(sparse_other),
          bin_coeff_mul_schoolbook(sparse, sparse_other),
        )
      }
      assert_eq(sparse.mul(sparse), bin_coeff_mul_schoolbook(sparse, sparse))
    }
  }
  // all-ones limbs next to zero limbs: carries run across the sparse gaps
  for len in [4, 8, 16, 33] {
    let words = FixedArray::make(len, 0UL)
    words[0] = 0xFFFF_FFFF_FFFF_FFFFUL
    words[len - 1] = 0xFFFF_FFFF_FFFF_FFFFUL
    let value = bin_coeff_from_words(words, len)
    assert_eq(value.mul(value), bin_coeff_mul_schoolbook(value, value))
  }
}

///|
test "unbalanced products through the limb array blocks equal the schoolbook product" {
  let random = { words_state: 0x5D5D_9A9A_0C0C_3B3BUL, }
  let cutoff = bin_coeff_words_karatsuba_cutoff
  for short_len in [cutoff, cutoff + 1, 2 * cutoff + 3, 40] {
    for factor in [3, 4, 7] {
      for pattern in [0, 1, 2] {
        let short = dispatch_test_value(random, short_len, pattern)
        let long = dispatch_test_value(random, short_len * factor + 1, pattern)
        let expected = bin_coeff_mul_schoolbook(short, long)
        assert_eq(short.mul(long), expected)
        assert_eq(long.mul(short), expected)
      }
    }
  }
}

///|
test "NTT overlap-add and the NTT product equal the word Karatsuba product" {
  let random = { words_state: 0x6C6C_2D2D_F1F1_A0A0UL, }
  for short_len in [40, 100] {
    for long_len in [short_len, 2 * short_len + 1, 400] {
      for pattern in [0, 1, 4] {
        let short = dispatch_test_value(random, short_len, pattern)
        let long = dispatch_test_value(random, long_len, (pattern + 2) % 5)
        let expected = bin_coeff_mul_words(short, long)
        assert_eq(bin_coeff_mul_ntt(short, long), expected)
        assert_eq(bin_coeff_mul_ntt_overlap(short, long), expected)
      }
    }
  }
}

///|
test "bits, bytes and power-of-two radixes on 64-bit limbs" {
  let random = { words_state: 0x3F3F_C2C2_5959_0E0EUL, }
  for len in [1, 2, 3, 4, 5, 9, 17] {
    for pattern in [0, 1, 2, 4] {
      let value = dispatch_test_value(random, len, pattern)
      let bits = value.bit_length()
      for
        index in [0, 1, 31, 32, 63, 64, 65, 127, 128, bits - 1, bits, bits + 7] {
        assert_eq(
          value.test_bit(index),
          index >= 0 && index < bits && value.shift_right(index).is_odd(),
        )
      }
      assert_eq(Coeff::from_bytes_be(value.to_bytes_be()[:]), value)
      assert_eq(value.to_bytes_be().length(), (bits + 7) / 8)
      for radix in [2, 4, 8, 16, 32] {
        let text = value.to_radix_string(radix)
        assert_eq(Coeff::parse(text, radix~).unwrap(), value)
      }
      assert_eq(value.to_radix_string(16).length(), (bits + 3) / 4)
    }
  }
  // bytes with leading zeros and lengths around the limb size
  for byte_count in [2, 7, 8, 9, 15, 16, 17, 23, 24, 25] {
    let bytes = Bytes::makei(byte_count, index => {
      if index == 0 {
        b'\x00'
      } else {
        b'\xA5'
      }
    })
    let value = Coeff::from_bytes_be(bytes[:])
    assert_eq(value.to_bytes_be().length(), byte_count - 1)
  }
}

///|
// oracle: B, E
// source: B: the reassembled product of both routes (the 64-bit words and the 32-bit view) equals the core BigInt product of the integers of the operand limbs (replaces the comparison with bin_coeff_mul_schoolbook). E: the digit fill of the 32-bit view equals the fill of the 64-bit words, digit by digit, on the same operands
// shares: bin_coeff_ntt_convolution_mod and the residues it gives both routes (the two reassemblies read the same residues), dispatch_test_value (the operands only), bin_coeff_test_big (the product is read limb by limb)
// primitives: bin_coeff_ntt_convolution_mod and bin_coeff_ntt_digit_length: level A in the `conv` and `fill` rows of the NTT table (coeff_ntt_oracle_wbtest.mbt, operands up to 1,000 limbs, CPython)
// underneath: bin_coeff_ntt_fill_words, the 64-bit-limb digit fill: level A, the `fill` rows of the NTT table, which run it with both primes and the shapes of regression_value; the 32-bit-view fill is Wasm only and has no oracle of its own (open point 1 of x-kern), its agreement with the 64-bit fill on lengths 1 to 40 limbs is all this block states
test "NTT conversions on 64-bit limbs and on the 32-bit view agree" {
  let random = { words_state: 0x4A4A_91B1_E7E7_0C0CUL, }
  for left_len in [1, 2, 3, 9, 40] {
    for right_len in [1, 2, 5, 40, 41] {
      for pattern in [0, 1, 2] {
        let left = dispatch_test_value(random, left_len, pattern)
        let right = dispatch_test_value(random, right_len, (pattern + 1) % 5)
        // the digits
        let digits = bin_coeff_ntt_digit_length(left)
        let by_words = FixedArray::make(digits, 0U)
        let by_limbs = FixedArray::make(digits, 0U)
        bin_coeff_ntt_fill_words(
          by_words, left, digits, bin_coeff_ntt_prime1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1,
        )
        bin_coeff_ntt_fill_limb32(
          by_limbs, left, digits, bin_coeff_ntt_prime1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1,
        )
        for index in 0..<digits {
          assert_eq(by_words[index], by_limbs[index])
        }
        // the product reassembled both ways from the same residues
        let coefficient_count = digits + bin_coeff_ntt_digit_length(right) - 1
        let transform_length = bin_coeff_ntt_transform_length(coefficient_count)
        let residues1 = bin_coeff_ntt_convolution_mod(
          left, right, false, transform_length, coefficient_count, bin_coeff_ntt_prime1,
          bin_coeff_ntt_root1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1, bin_coeff_ntt_r_prime1,
        )
        let residues2 = bin_coeff_ntt_convolution_mod(
          left, right, false, transform_length, coefficient_count, bin_coeff_ntt_prime2,
          bin_coeff_ntt_root2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2, bin_coeff_ntt_r_prime2,
        )
        let expected = bin_coeff_test_big(left) * bin_coeff_test_big(right)
        assert_eq(
          bin_coeff_test_big(
            bin_coeff_ntt_reconstruct_words(
              residues1,
              residues2,
              coefficient_count,
              bin_coeff_word_len(left) + bin_coeff_word_len(right),
            ),
          ),
          expected,
        )
        assert_eq(
          bin_coeff_test_big(
            bin_coeff_ntt_reconstruct_limb32(
              residues1,
              residues2,
              coefficient_count,
              bin_coeff_limb_len(left) + bin_coeff_limb_len(right),
            ),
          ),
          expected,
        )
      }
    }
  }
}
