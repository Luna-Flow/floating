///|
/// Integer square root with remainder on word arrays (issue #19, stage 4):
/// Zimmermann's Karatsuba square root, `SqrtRem`, with every block a whole
/// number of 64-bit limbs, so that a level costs one division, one square and
/// a few array copies instead of about twenty-five `BinCoeff` temporaries.
///
/// The radicand is shifted left by an even number of bits, below 128, so that
/// it has an even number `n` of limbs with the top two bits not both zero
/// (`N >= B^n / 4`, the normalisation under which the quotient estimate is at
/// most one block). With `l = n / 4` limbs per block `X = 2^(64 l)` the value
/// is `N = H X^2 + a1 X + a0`; the root `s'` and remainder `r'` of the top
/// part `H` come from the recursion, `(q, u) = divrem(r' X + a1, 2 s')`,
/// `s = s' X + q` and `r = u X + a0 - q^2`, corrected by one if `r` is
/// negative. A quotient of exactly `X` is capped at `X - 1`: the root cannot
/// exceed `s' X + X - 1` because `H < (s' + 1)^2`, so the capped root is the
/// root and its remainder is at most `2 s`. Up to 256 bits the existing fixed-width kernels
/// are the base case. The root of the original radicand is `s' >> t` for the
/// shift `2 t`, and its remainder is `(r' + e (2 s' - e)) >> 2 t` for
/// `e = s' mod 2^t`, which needs only a one-limb product.

///|
/// Copies `value` (at most `count` limbs) into `destination[offset ..]`.
fn bin_coeff_sqrt_store_words(
  destination : FixedArray[UInt64],
  offset : Int32,
  count : Int32,
  value : BinCoeff,
) -> Unit {
  guard bin_coeff_word_len(value) <= count else {
    abort("BinCoeff square root block exceeded its width")
  }
  match value.repr {
    Heap(words, len) =>
      for index in 0..<len {
        destination.unsafe_set(offset + index, words.unsafe_get(index))
      }
    Inline64(word) => destination.unsafe_set(offset, word)
    Inline128(high, low) => {
      destination.unsafe_set(offset, low)
      destination.unsafe_set(offset + 1, high)
    }
  }
}

///|
/// Root (`n / 2` limbs) and remainder (`n / 2 + 1` limbs) of the normalised
/// `n` limbs `source[start ..< start + n]`, `n` even.
fn bin_coeff_sqrt_words_recursive(
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
  let (high_root, high_remainder) = bin_coeff_sqrt_words_recursive(
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
      .add(BinCoeff::one())
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
fn bin_coeff_sqrt_rem_words_recursive(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  let bits = value.bit_length()
  let mut limbs = (bits + 63) / 64
  if limbs % 2 == 1 {
    limbs += 1
  }
  let shift = (limbs * 64 - bits) & -2
  let normalized = value.shift_left(shift)
  let source = match normalized.repr {
    Heap(words, len) if len == limbs => words
    _ => abort("BinCoeff square root normalisation lost its width")
  }
  let (root_words, remainder_words) = bin_coeff_sqrt_words_recursive(
    source, 0, limbs,
  )
  let root = bin_coeff_from_words(root_words, limbs / 2)
  let remainder = bin_coeff_from_words(remainder_words, limbs / 2 + 1)
  if shift == 0 {
    return (root, remainder)
  }
  let half_shift = shift / 2
  let error = root_words.unsafe_get(0) & ((1UL << half_shift) - 1UL)
  let error_value = BinCoeff::from_uint64(error)
  let original_remainder = remainder
    .add(error_value.mul(root.shift_left(1).sub_checked(error_value).unwrap()))
    .shift_right(shift)
  (root.shift_right(half_shift), original_remainder)
}
