///|
/// The square root recursion as it was before the in-place rewrite (issue 438
/// section 8, P-A6): `Coeff` wrappers per level, the general `div_rem_checked`
/// and a second normalising shift. Kept here only as the reference that the
/// production recursion must match limb for limb.

///|
/// Root (`n / 2` limbs) and remainder (`n / 2 + 1` limbs) of the normalised
/// `n` limbs `source[start ..< start + n]`, `n` even.
fn bin_coeff_sqrt_words_recursive_reference(
  source : FixedArray[UInt64],
  start : Int32,
  n : Int32,
) -> (FixedArray[UInt64], FixedArray[UInt64]) {
  let half = n / 2
  if n <= 4 {
    let words = FixedArray::make(n, 0UL)
    for index in 0..<n {
      words.unsafe_set(index, source.unsafe_get(start + index))
    }
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(
      bin_coeff_from_words(words, n),
    )
    let root_words = FixedArray::make(half, 0UL)
    let remainder_words = FixedArray::make(half + 1, 0UL)
    bin_coeff_sqrt_store_words(root_words, 0, half, root)
    bin_coeff_sqrt_store_words(remainder_words, 0, half + 1, remainder)
    return (root_words, remainder_words)
  }
  let block = n / 4
  let high_len = n - 2 * block
  let high_half = high_len / 2
  let (high_root, high_remainder) = bin_coeff_sqrt_words_recursive_reference(
    source,
    start + 2 * block,
    high_len,
  )
  // dividend = high_remainder * X + a1, divisor = 2 * high_root
  let dividend_len = high_half + 1 + block
  let dividend = FixedArray::make(dividend_len, 0UL)
  for index in 0..<block {
    dividend.unsafe_set(index, source.unsafe_get(start + block + index))
  }
  for index in 0..<(high_half + 1) {
    dividend.unsafe_set(block + index, high_remainder.unsafe_get(index))
  }
  let divisor = FixedArray::make(high_half + 1, 0UL)
  let mut carry = 0UL
  for index in 0..<high_half {
    let word = high_root.unsafe_get(index)
    divisor.unsafe_set(index, (word << 1) | carry)
    carry = word >> 63
  }
  divisor.unsafe_set(high_half, carry)
  let dividend_value = bin_coeff_from_words(dividend, dividend_len)
  let divisor_value = bin_coeff_from_words(divisor, high_half + 1)
  let (raw_quotient, raw_remainder) = dividend_value
    .div_rem_checked(divisor_value)
    .unwrap()
  let mut quotient = raw_quotient
  let mut quotient_remainder = raw_remainder
  if bin_coeff_word_len(quotient) > block {
    // the estimate is X: use X - 1, which is then the root (see the header)
    let ones = FixedArray::make(block, 0xFFFF_FFFF_FFFF_FFFFUL)
    quotient = bin_coeff_from_words(ones, block)
    quotient_remainder = dividend_value
      .sub_checked(quotient.mul(divisor_value))
      .unwrap()
  }
  let root = FixedArray::make(half, 0UL)
  bin_coeff_sqrt_store_words(root, 0, block, quotient)
  for index in 0..<high_half {
    root.unsafe_set(block + index, high_root.unsafe_get(index))
  }
  // partial = quotient_remainder * X + a0
  let remainder_len = bin_coeff_word_len(quotient_remainder)
  let partial_words = FixedArray::make(remainder_len + block, 0UL)
  for index in 0..<block {
    partial_words.unsafe_set(index, source.unsafe_get(start + index))
  }
  bin_coeff_sqrt_store_words(
    partial_words, block, remainder_len, quotient_remainder,
  )
  let partial = bin_coeff_from_words(partial_words, remainder_len + block)
  let square = quotient.square()
  let remainder = match partial.sub_checked(square) {
    Ok(value) => value
    Err(_) => {
      // one too large: root - 1, remainder + 2 (root - 1) + 1
      let mut index = 0
      while root.unsafe_get(index) == 0UL {
        root.unsafe_set(index, 0xFFFF_FFFF_FFFF_FFFFUL)
        index += 1
      }
      root.unsafe_set(index, root.unsafe_get(index) - 1UL)
      let decremented = bin_coeff_from_words(root.copy(), half)
      partial
      .add(decremented.shift_left(1))
      .add(Coeff::one())
      .sub_checked(square)
      .unwrap()
    }
  }
  let remainder_words = FixedArray::make(half + 1, 0UL)
  bin_coeff_sqrt_store_words(remainder_words, 0, half + 1, remainder)
  (root, remainder_words)
}

///|
/// Square root with remainder of a value of more than 256 bits.
fn bin_coeff_sqrt_rem_words_reference(value : Coeff) -> (Coeff, Coeff) {
  let bits = value.bit_length()
  let mut limbs = (bits + 63) / 64
  if limbs % 2 == 1 {
    limbs += 1
  }
  let shift = (limbs * 64 - bits) & -2
  let normalized = value.shift_left(shift)
  let source = match normalized.0 {
    Heap(words, len) if len == limbs => words
    _ => abort("Coeff square root normalisation lost its width")
  }
  let (root_words, remainder_words) = bin_coeff_sqrt_words_recursive_reference(
    source, 0, limbs,
  )
  let root = bin_coeff_from_words(root_words, limbs / 2)
  let remainder = bin_coeff_from_words(remainder_words, limbs / 2 + 1)
  if shift == 0 {
    return (root, remainder)
  }
  let half_shift = shift / 2
  let error = root_words.unsafe_get(0) & ((1UL << half_shift) - 1UL)
  let error_value = Coeff::from_uint64(error)
  let original_remainder = remainder
    .add(error_value.mul(root.shift_left(1).sub_checked(error_value).unwrap()))
    .shift_right(shift)
  (root.shift_right(half_shift), original_remainder)
}

///|
fn bin_coeff_sqrt_reference_check(value : Coeff) -> Unit raise {
  let expected = bin_coeff_sqrt_rem_words_reference(value)
  let actual = bin_coeff_sqrt_rem_words_recursive(value)
  assert_true(expected.0 == actual.0)
  assert_true(expected.1 == actual.1)
  // and the scaled entry: root and remainder of `value << scale`
  for scale in [0, 1, 2, 3, 63, 64, 65, 130] {
    let shifted = value.shift_left(scale)
    let direct = bin_coeff_sqrt_rem_words_reference(shifted)
    let folded = bin_coeff_sqrt_rem_scaled(value, scale)
    if shifted.bit_length() > 256 {
      assert_true(direct.0 == folded.0)
      assert_true(direct.1 == folded.1)
    } else {
      let kernel = bin_coeff_sqrt_rem_kernel(shifted)
      assert_true(kernel.0 == folded.0)
      assert_true(kernel.1 == folded.1)
    }
  }
}

///|
test "in-place square root recursion equals the Coeff recursion" {
  let sizes = [
    257, 258, 319, 320, 321, 383, 384, 385, 447, 448, 449, 511, 512, 513, 575, 576,
    577, 639, 640, 641, 767, 768, 769, 1023, 1024, 1025, 1500, 2047, 2048, 2049,
    2300, 4095, 4096, 4097, 8191, 8192, 8193,
  ]
  for bits in sizes {
    for seed in 1..<6 {
      bin_coeff_sqrt_reference_check(
        bin_coeff_test_from_bigint(
          bin_coeff_sqrt_test_value(bits, seed.to_uint64()),
        ),
      )
    }
    // all ones, a single bit and the neighbours of exact squares force the
    // capped quotient and the negative-remainder branches
    let ones = (1N << bits) - 1N
    bin_coeff_sqrt_reference_check(bin_coeff_test_from_bigint(ones))
    bin_coeff_sqrt_reference_check(bin_coeff_test_from_bigint(1N << (bits - 1)))
    let root = bin_coeff_test_integer_sqrt_floor(ones)
    for delta in [-2N, -1N, 0N, 1N, 2N] {
      let square = (root + delta) * (root + delta)
      for adjust in [-1N, 0N, 1N] {
        let value = square + adjust
        if value > 0N && value.bit_length() > 256 {
          bin_coeff_sqrt_reference_check(bin_coeff_test_from_bigint(value))
        }
      }
    }
  }
}
