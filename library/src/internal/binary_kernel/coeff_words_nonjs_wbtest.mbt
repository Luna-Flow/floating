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

///|
/// The previous loop of `binary_coeff_fast_add_parts` (`bin_window_combine` and
/// `bin_window_word` of `binary_fast_coeff_nonjs.mbt` before the row
/// primitive), kept verbatim as the reference of the window row.
fn window_word_reference(
  words : FixedArray[UInt64],
  len : Int32,
  word_shift : Int32,
  bit_shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - word_shift
  let low = if source >= 0 && source < len {
    words.unsafe_get(source)
  } else {
    0UL
  }
  if bit_shift == 0 {
    return low
  }
  let below = if source >= 1 && source <= len {
    words.unsafe_get(source - 1)
  } else {
    0UL
  }
  (low << bit_shift) | (below >> (64 - bit_shift))
}

///|
fn window_combine_reference(
  words : FixedArray[UInt64],
  count : Int32,
  x : FixedArray[UInt64],
  x_len : Int32,
  x_word_shift : Int32,
  x_bit_shift : Int32,
  y : FixedArray[UInt64],
  y_len : Int32,
  y_word_shift : Int32,
  y_bit_shift : Int32,
  subtract : Bool,
  carry_in : UInt64,
) -> UInt64 {
  let mask = if subtract { 0xFFFFFFFFFFFFFFFFUL } else { 0UL }
  let mut carry = if subtract { 1UL - carry_in } else { carry_in }
  let use_y = y_len > 0
  let mut low = x_word_shift + 1
  let mut high = x_word_shift + x_len
  if use_y {
    low = Int32::max(low, y_word_shift + 1)
    high = Int32::min(high, y_word_shift + y_len)
  }
  low = Int32::max(0, Int32::min(low, count))
  high = Int32::min(count, Int32::max(high, low))
  for index in 0..<low {
    let a = window_word_reference(x, x_len, x_word_shift, x_bit_shift, index)
    let b = window_word_reference(y, y_len, y_word_shift, y_bit_shift, index) ^
      mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  let x_down = 63 - x_bit_shift
  if low < high {
    let mut x_previous = x.unsafe_get(low - x_word_shift - 1)
    if use_y {
      let y_down = 63 - y_bit_shift
      let mut y_previous = y.unsafe_get(low - y_word_shift - 1)
      for index in low..<high {
        let x_current = x.unsafe_get(index - x_word_shift)
        let y_current = y.unsafe_get(index - y_word_shift)
        let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
        let b = ((y_current << y_bit_shift) | (y_previous >> 1 >> y_down)) ^
          mask
        x_previous = x_current
        y_previous = y_current
        let partial = a + b
        let sum = partial + carry
        let first = if partial < a { 1UL } else { 0UL }
        let second = if sum < partial { 1UL } else { 0UL }
        carry = first | second
        words.unsafe_set(index, sum)
      }
    } else {
      for index in low..<high {
        let x_current = x.unsafe_get(index - x_word_shift)
        let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
        x_previous = x_current
        let partial = a + mask
        let sum = partial + carry
        let first = if partial < a { 1UL } else { 0UL }
        let second = if sum < partial { 1UL } else { 0UL }
        carry = first | second
        words.unsafe_set(index, sum)
      }
    }
  }
  for index in high..<count {
    let a = window_word_reference(x, x_len, x_word_shift, x_bit_shift, index)
    let b = window_word_reference(y, y_len, y_word_shift, y_bit_shift, index) ^
      mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  if subtract {
    1UL - carry
  } else {
    carry
  }
}

///|
/// A limb array of `len` limbs of a pattern: 0 random, 1 all ones, 2 zero, 3
/// alternating all ones and zero, 4 single top bit, 5 random with zero runs.
fn window_test_array(
  random : WordsTestRandom,
  len : Int32,
  pattern : Int32,
) -> FixedArray[UInt64] {
  let words = FixedArray::make(len, 0UL)
  for index in 0..<len {
    words[index] = match pattern {
      0 => random.next()
      1 => 0xFFFF_FFFF_FFFF_FFFFUL
      2 => 0UL
      3 => if index % 2 == 0 { 0xFFFF_FFFF_FFFF_FFFFUL } else { 0UL }
      4 => 0x8000_0000_0000_0000UL
      _ => if index % 3 == 0 { 0UL } else { random.next() }
    }
  }
  words
}

///|
/// One call of the window row against the reference: the same result array
/// and the same returned carry. `run` is the body under test.
fn window_check_one(
  run : (
    FixedArray[UInt64],
    Int32,
    FixedArray[UInt64],
    Int32,
    Int32,
    Int32,
    FixedArray[UInt64],
    Int32,
    Int32,
    Int32,
    Bool,
    UInt64,
  ) -> UInt64,
  count : Int32,
  x : FixedArray[UInt64],
  x_word_shift : Int32,
  x_bit_shift : Int32,
  y : FixedArray[UInt64],
  y_len : Int32,
  y_word_shift : Int32,
  y_bit_shift : Int32,
  subtract : Bool,
  carry_in : UInt64,
) -> Unit raise {
  let expected = FixedArray::make(count, 0xABCDUL)
  let actual = FixedArray::make(count, 0xABCDUL)
  let expected_carry = window_combine_reference(
    expected,
    count,
    x,
    x.length(),
    x_word_shift,
    x_bit_shift,
    y,
    y_len,
    y_word_shift,
    y_bit_shift,
    subtract,
    carry_in,
  )
  let actual_carry = run(
    actual,
    count,
    x,
    x.length(),
    x_word_shift,
    x_bit_shift,
    y,
    y_len,
    y_word_shift,
    y_bit_shift,
    subtract,
    carry_in,
  )
  assert_eq(actual_carry, expected_carry)
  assert_eq(actual, expected)
}

///|
fn window_check_all(
  run : (
    FixedArray[UInt64],
    Int32,
    FixedArray[UInt64],
    Int32,
    Int32,
    Int32,
    FixedArray[UInt64],
    Int32,
    Int32,
    Int32,
    Bool,
    UInt64,
  ) -> UInt64,
  seed : UInt64,
) -> Unit raise {
  let random = { words_state: seed, }
  let shifts = [0, 1, 2, 31, 32, 33, 62, 63]
  for count in [1, 2, 3, 4, 5, 7, 8, 9, 12, 13, 14, 15, 16, 17, 31, 32, 33, 40] {
    for x_len in [1, 2, count - 1, count, count + 1, count + 3] {
      if x_len >= 1 {
        for y_len in [0, 1, x_len - 1, x_len, x_len + 2] {
          if y_len >= 0 {
            for pattern in 0..<6 {
              let x = window_test_array(random, x_len, pattern)
              let y = window_test_array(
                random,
                Int32::max(y_len, 1),
                (pattern + 1) % 6,
              )
              // word shifts: x at the window bottom, one limb up, near the top;
              // y cut at the bottom, aligned, above
              for x_word_shift in [0, 1, count / 2] {
                for y_word_shift in [-2, -1, 0, 1, count / 2, count + 1] {
                  for subtract in [false, true] {
                    for carry_in in [0UL, 1UL] {
                      for k in 0..<shifts.length() {
                        // every x shift with a sampled y shift and the other way round
                        let a_shift = shifts[k]
                        let b_shift = shifts[(k * 3 + pattern) % shifts.length()]
                        window_check_one(
                          run, count, x, x_word_shift, a_shift, y, y_len, y_word_shift,
                          b_shift, subtract, carry_in,
                        )
                        window_check_one(
                          run, count, x, x_word_shift, b_shift, y, y_len, y_word_shift,
                          a_shift, subtract, carry_in,
                        )
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  // every bit shift of both operands, one geometry
  let x = window_test_array(random, 12, 0)
  let y = window_test_array(random, 10, 5)
  for x_bit_shift in 0..<64 {
    for y_bit_shift in 0..<64 {
      for subtract in [false, true] {
        window_check_one(
          run, 14, x, 1, x_bit_shift, y, 10, 2, y_bit_shift, subtract, 1UL,
        )
      }
    }
  }
}

///|
test "the portable window row equals the previous loop: every bit shift, word shifts, subtraction with and without borrow, short and empty second operand, lengths 1 to 40, special limbs" {
  window_check_all(bin_limbs_window_combine_portable, 0x1B873593CC9E2D51UL)
}

///|
test "the window row of the active tier (C rows, assembly tier or portable) equals the previous loop" {
  window_check_all(bin_limbs_window_combine, 0x85EBCA6B27D4EB2FUL)
}

///|
test "the window row at the limits of its contract: word shifts of magnitude 2^28, both bodies" {
  let random = { words_state: 0x2545F4914F6CDD1DUL, }
  let limit = bin_limbs_window_max
  let shifts = [-limit, -limit + 1, -1, 0, 1, limit - 1, limit]
  for count in [1, 3, 9, 14, 20] {
    for x_len in [1, 5, 16] {
      for y_len in [0, 1, 9] {
        for x_word_shift in shifts {
          for y_word_shift in shifts {
            for subtract in [false, true] {
              for bit_shift in [0, 1, 63] {
                let x = window_test_array(random, x_len, 0)
                let y = window_test_array(random, Int32::max(y_len, 1), 5)
                let expected = FixedArray::make(count, 0x77UL)
                let reference_carry = window_combine_reference(
                  expected,
                  count,
                  x,
                  x_len,
                  x_word_shift,
                  bit_shift,
                  y,
                  y_len,
                  y_word_shift,
                  63 - bit_shift,
                  subtract,
                  1UL,
                )
                let portable = FixedArray::make(count, 0x77UL)
                let portable_carry = bin_limbs_window_combine_portable(
                  portable,
                  count,
                  x,
                  x_len,
                  x_word_shift,
                  bit_shift,
                  y,
                  y_len,
                  y_word_shift,
                  63 - bit_shift,
                  subtract,
                  1UL,
                )
                assert_eq(portable_carry, reference_carry)
                assert_eq(portable, expected)
                let tier = FixedArray::make(count, 0x77UL)
                let tier_carry = bin_limbs_window_combine(
                  tier,
                  count,
                  x,
                  x_len,
                  x_word_shift,
                  bit_shift,
                  y,
                  y_len,
                  y_word_shift,
                  63 - bit_shift,
                  subtract,
                  1UL,
                )
                assert_eq(tier_carry, reference_carry)
                assert_eq(tier, expected)
              }
            }
          }
        }
      }
    }
  }
}

///|
test "panic the window row rejects a word shift beyond its contract" {
  let words = FixedArray::make(4, 0UL)
  let x = FixedArray::make(4, 1UL)
  ignore(
    bin_limbs_window_combine(
      words,
      4,
      x,
      4,
      bin_limbs_window_max + 1,
      0,
      x,
      0,
      0,
      0,
      false,
      0UL,
    ),
  )
}

///|
/// `bin_limbs_product` against the integer product of the operands, and against
/// the loop of rows it replaces (`bin_limbs_mul_1` then `bin_limbs_addmul_1`, as
/// the series loops had it), on both operands (every pair of the sizes below),
/// six operand patterns (random, all ones, zero, alternating, a single top bit,
/// random with zero limbs), result and sources at offsets 0 and (3, 2, 1) of
/// larger arrays.
// oracle: B
// source: core BigInt multiplication of the integers of the operand limbs: the whole result array, every limb outside the row left at 0x5A5A, for the product and for the loop of rows (replaces the comparison with bin_coeff_words_school)
// shares: window_test_array (the operands only)
// primitives: bin_limbs_big (limbs to BigInt by shift and addition of core; level A in "bin_limbs_big reads the limbs least significant first")
test "the limb product equals the schoolbook product and the loop of rows it replaces" {
  let random = { words_state: 0x7F4A7C159E3779B9UL, }
  let sizes = [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 15, 16, 17, 31, 33, 40]
  let mut cases = 0
  for an in sizes {
    for bn in sizes {
      for pattern in 0..<6 {
        for offsets in [(0, 0, 0), (3, 2, 1)] {
          let (ro, ao, bo) = offsets
          let a = window_test_array(random, an + ao + 2, pattern)
          let b = window_test_array(random, bn + bo + 2, (pattern + 1) % 6)
          let product = bin_limbs_big(a, ao, an) * bin_limbs_big(b, bo, bn)
          let looped = FixedArray::make(an + bn + ro + 3, 0x5A5AUL)
          let actual = FixedArray::make(an + bn + ro + 3, 0x5A5AUL)
          // the loop of rows as the series loops had it
          looped.unsafe_set(
            ro + bn,
            bin_limbs_mul_1(looped, ro, b, bo, bn, a.unsafe_get(ao)),
          )
          for j in 1..<an {
            looped.unsafe_set(
              ro + j + bn,
              bin_limbs_addmul_1(
                looped,
                ro + j,
                b,
                bo,
                bn,
                a.unsafe_get(ao + j),
              ),
            )
          }
          bin_limbs_product(actual, ro, a, ao, an, b, bo, bn)
          for result in [actual, looped] {
            bin_limbs_assert_row(result, ro, an + bn, product)
            for index in 0..<ro {
              assert_eq(result[index], 0x5A5AUL)
            }
            for index in (ro + an + bn)..<result.length() {
              assert_eq(result[index], 0x5A5AUL)
            }
          }
          cases += 1
        }
      }
    }
  }
  assert_eq(cases, 16 * 16 * 6 * 2)
}

///|
/// The contract's edges: the carry limb is written (all `an + bn` limbs of a
/// dirty result are replaced), a single-limb operand on either side, and the
/// largest limbs everywhere (every column carries).
// oracle: B
// source: core BigInt multiplication of the all-ones operands, (2^(64 an) - 1)(2^(64 bn) - 1), built from shifts, against the whole dirty result
// shares: nothing
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "the limb product writes every result limb: dirty result, one-limb operands, all-ones" {
  for an in [1, 2, 9] {
    for bn in [1, 3, 10] {
      let a = FixedArray::make(an, 0xFFFF_FFFF_FFFF_FFFFUL)
      let b = FixedArray::make(bn, 0xFFFF_FFFF_FFFF_FFFFUL)
      let actual = FixedArray::make(an + bn, 0xBEEFUL)
      bin_limbs_product(actual, 0, a, 0, an, b, 0, bn)
      let expected = ((BigInt::from_int(1) << (64 * an)) - BigInt::from_int(1)) *
        ((BigInt::from_int(1) << (64 * bn)) - BigInt::from_int(1))
      bin_limbs_assert_row(actual, 0, an + bn, expected)
    }
  }
}

///|
/// The coefficient of an array form: the first `count` limbs.
fn array_form_coeff(words : FixedArray[UInt64], count : Int32) -> Coeff {
  bin_coeff_from_words(words, count)
}

///|
// Oracle: level E (the coefficient form this array form wraps). Underneath: the
// kernel's grade-school references (level B, they share only the limb
// primitives) and the TestFloat and MPFR corpora of `just gate binary 3` (level A).
test "bin_words_mul equals Coeff::mul: every route, sparse and dense operands, any lengths" {
  let random = { words_state: 0x71D6_7FFF_EDA6_0000UL, }
  for
    left_len in [1, 2, 3, 4, 5, 8, 9, 20, 31, 32, 33, 47, 48, 49, 64, 100, 130] {
    for right_len in [3, 4, 5, 8, 9, 31, 33, 48, 49, 64, 130, 200] {
      for pattern in [0, 1, 2, 3, 4] {
        let left = dispatch_test_value(random, left_len, pattern)
        let right = dispatch_test_value(random, right_len, (pattern + 1) % 5)
        // the contract: nonzero operands, at least one of them wider than 128 bits
        if left.bit_length() > 128 || right.bit_length() > 128 {
          let words = bin_words_mul(left, right)
          assert_eq(array_form_coeff(words, words.length()), left.mul(right))
        }
      }
    }
  }
  // sparse operands (the sparse route keeps its coefficient)
  for len in [8, 33, 100] {
    let left = dispatch_test_sparse(random, len, 2)
    let right = dispatch_test_sparse(random, len + 3, 3)
    let words = bin_words_mul(left, right)
    assert_eq(array_form_coeff(words, words.length()), left.mul(right))
  }
}

///|
// Oracle: level E (the coefficient forms the array forms wrap). Underneath: the
// kernel's grade-school references (level B) and the TestFloat and MPFR corpora
// of `just gate binary 3` (level A).
test "the array forms of the short product, the short and the exact scaled division and the root equal their coefficient forms" {
  let random = { words_state: 0x2F6A_1C9E_B3D5_8407UL, }
  // short product
  for precision in [700, 1000, 1500, 2048, 3000] {
    for trim in [0, 1, 17, 63] {
      for pattern in [0, 1, 4] {
        let left_len = (precision - trim + 63) / 64
        let left = dispatch_test_value(random, left_len, pattern)
        let right = dispatch_test_value(random, left_len, (pattern + 2) % 5)
        if bin_coeff_mul_short_ok(left, right, precision) {
          let words = bin_words_mul_short(left, right, precision)
          let coefficient = bin_coeff_mul_short(left, right, precision)
          if words.length() == 0 {
            assert_true(coefficient.is_zero())
          } else {
            let limbs = bin_coeff_short_product_limbs(precision)
            assert_eq(array_form_coeff(words, limbs), coefficient)
          }
        }
      }
    }
  }
  // short and exact division
  for divisor_len in [2, 3, 8, 20, 60, 90] {
    for extra in [0, 1, 7, 30] {
      for pattern in [0, 1, 4] {
        let divisor = dispatch_test_value(random, divisor_len, pattern)
        let dividend = dispatch_test_value(
          random,
          divisor_len + extra,
          (pattern + 1) % 5,
        )
        for scale in [0, 5, 70, 300, 1000] {
          if bin_coeff_div_short_ok(dividend, scale + 32, divisor) {
            for precision in [100, 600, 2000] {
              let words = bin_words_div_short_quotient(
                dividend,
                scale + 32,
                divisor,
                precision,
              )
              let coefficient = bin_coeff_div_short_quotient(
                dividend,
                scale + 32,
                divisor,
                precision,
              )
              if words.length() == 0 {
                assert_true(coefficient.is_zero())
              } else {
                assert_eq(array_form_coeff(words, words.length()), coefficient)
              }
            }
          }
          if bin_coeff_div_scaled_ok(dividend, scale, divisor) {
            let words = bin_words_div_scaled_quotient(dividend, scale, divisor)
            assert_eq(
              array_form_coeff(words, words.length()),
              bin_coeff_div_scaled_quotient(dividend, scale, divisor),
            )
          }
        }
      }
    }
  }
  // the root
  for len in [3, 5, 9, 17, 40, 80] {
    for scale in [0, 2, 64, 130, 400] {
      for pattern in [0, 1, 4] {
        let value = dispatch_test_value(random, len, pattern)
        let bits = value.bit_length() + scale
        for precision in [bits / 2 - 1, bits / 2 - 2, bits / 2 - 70] {
          if precision >= 129 {
            let words = bin_words_sqrt_scaled_rounded(value, scale, precision)
            assert_eq(
              array_form_coeff(words, words.length()),
              bin_coeff_sqrt_scaled_rounded(value, scale, precision),
            )
          }
        }
      }
    }
  }
}

///|
// Oracle: level A (expected values written out in the test).
test "bin_coeff_owned_words clears the limbs above a heap value: the array form never exposes scratch" {
  // a heap coefficient over a longer array with a dirty tail, as
  // `bin_coeff_mul_short` builds one (H in the first limbs, scratch above)
  let array : FixedArray[UInt64] = [
    0x1111UL, 0x2222UL, 0x3333UL, 0x4444UL, 0xDEAD_BEEFUL, 0xFFFF_FFFFUL, 0x7UL,
  ]
  let value = bin_coeff_from_words(array, 4)
  let words = bin_coeff_owned_words(value)
  assert_true(physical_equal(words, array))
  assert_eq(words.length(), 7)
  assert_eq(words[0], 0x1111UL)
  assert_eq(words[3], 0x4444UL)
  for index in 4..<7 {
    assert_eq(words[index], 0UL)
  }
  // the value is unchanged
  assert_eq(
    value,
    bin_coeff_from_words([0x1111UL, 0x2222UL, 0x3333UL, 0x4444UL], 4),
  )
  // small values give exact-size arrays
  assert_eq(bin_coeff_owned_words(Coeff::from_uint64(5UL)), [5UL])
  assert_eq(bin_coeff_owned_words(bin_coeff_inline(3UL, 9UL)), [9UL, 3UL])
}
