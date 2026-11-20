///|
/// The 64-bit-limb storage and its 32-bit compatibility view agree with the
/// bits of the value, at every boundary between the inline and heap
/// representations and with a top limb whose upper half is zero.
fn bin_coeff_words_test_value(bits : Int32, fill : Int32) -> Coeff {
  // `bits` bits: the top bit set, the rest from a pattern
  let words = FixedArray::make((bits + 63) / 64, 0UL)
  for index in 0..<words.length() {
    words[index] = match fill {
      0 => 0xA5A5_A5A5_5A5A_5A5AUL + index.to_uint64() * 0x0123_4567_89AB_CDEFUL
      1 => 0xFFFF_FFFF_FFFF_FFFFUL
      2 => 0UL
      _ => 1UL
    }
  }
  let top = words.length() - 1
  let used = bits - 64 * top
  if used < 64 {
    words[top] = words[top] & ((1UL << used) - 1UL)
  }
  words[top] = words[top] | (1UL << (used - 1))
  bin_coeff_from_words(words, words.length())
}

///|
test "Coeff 64-bit limbs: sizes, words and the 32-bit view agree" {
  for
    bits in [
      1, 2, 31, 32, 33, 63, 64, 65, 96, 127, 128, 129, 159, 160, 161, 191, 192, 193,
      224, 225, 255, 256, 257, 300, 512, 513,
    ] {
    for fill in 0..<4 {
      let value = bin_coeff_words_test_value(bits, fill)
      assert_eq(value.bit_length(), bits)
      let word_len = (bits + 63) / 64
      assert_eq(bin_coeff_word_len(value), word_len)
      let limb_len = (bits + 31) / 32
      assert_eq(bin_coeff_limb_len(value), limb_len)
      // the 32-bit limbs are the two halves of the 64-bit ones
      for index in 0..<limb_len {
        let word = bin_coeff_word(value, index / 2)
        let expected = if index % 2 == 0 {
          (word & bin_coeff_limb_mask).to_uint()
        } else {
          (word >> 32).to_uint()
        }
        assert_eq(bin_coeff_limb(value, index), expected)
      }
      assert_eq(bin_coeff_limb(value, limb_len), 0U)
      assert_eq(bin_coeff_word(value, word_len), 0UL)
      // packing the limbs back gives the same value
      let limbs = FixedArray::make(limb_len + 1, 0U)
      for index in 0..<limb_len {
        limbs[index] = bin_coeff_limb(value, index)
      }
      assert_eq(bin_coeff_from_limbs(limbs, limb_len + 1), value)
      // representation invariants: inline up to 128 bits, heap above
      match value.0 {
        Inline64(_) => assert_true(bits <= 64)
        Inline128(high, _) => {
          assert_true(bits > 64 && bits <= 128)
          assert_true(high != 0UL)
        }
        Heap(words, len) => {
          assert_true(bits > 128)
          assert_true(len >= 3 && words[len - 1] != 0UL)
        }
      }
      // shifts round trip through the word paths
      for amount in [1, 5, 31, 32, 63, 64, 65, 127, 128, 129, 200] {
        assert_eq(value.shift_left(amount).shift_right(amount), value)
        assert_eq(value.shift_left(amount).bit_length(), bits + amount)
      }
      // addition and subtraction against the shifted value
      let doubled = value.add(value)
      assert_eq(doubled, value.shift_left(1))
      assert_eq(doubled.sub_checked(value).unwrap(), value)
      assert_eq(value.compare(doubled), -1)
      assert_eq(doubled.compare(value), 1)
      assert_eq(value.compare(value), 0)
    }
  }
}

///|
test "Coeff 64-bit limbs: carries across word boundaries" {
  for words in [2, 3, 4, 7, 8, 17] {
    // 2^(64 * words) - 1 plus one carries through every word
    let ones = FixedArray::make(words, 0xFFFF_FFFF_FFFF_FFFFUL)
    let all_ones = bin_coeff_from_words(ones, words)
    let power = all_ones.add(Coeff::one())
    assert_eq(power, Coeff::one().shift_left(64 * words))
    assert_eq(power.sub_checked(Coeff::one()).unwrap(), all_ones)
    assert_eq(power.bit_length(), 64 * words + 1)
    assert_eq(power.ctz(), 64 * words)
    // and the products of such values
    let square = all_ones.mul(all_ones)
    assert_eq(square, all_ones.square())
    assert_eq(
      square,
      power
      .shift_left(64 * words)
      .sub_checked(power.shift_left(1))
      .unwrap()
      .add(Coeff::one()),
    )
  }
}
