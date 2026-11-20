///|
/// Integer square root with remainder on word arrays (issue #19, stage 4):
/// Zimmermann's Karatsuba square root, `SqrtRem`, with every block a whole
/// number of 64-bit limbs, so that a level costs one division, one square and
/// a few array copies instead of about twenty-five `Coeff` temporaries.
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
  value : Coeff,
) -> Unit {
  guard bin_coeff_word_len(value) <= count else {
    abort("Coeff square root block exceeded its width")
  }
  match value.0 {
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
  // `D = high_remainder * X + a1` has `high_half + 1 + block` limbs. Dividing
  // by `2 s'` is dividing `floor(D / 2)` by `s'` (`floor(D / (2 s')) =
  // floor(floor(D / 2) / s')`), and `s'` already has its top bit set (the
  // radicand is normalised), so Knuth's divisor needs no shift and no copy.
  // The remainder of `D` by `2 s'` is `2 r + (D mod 2)` for the remainder `r`
  // of `floor(D / 2)` by `s'`.
  let dividend_len = high_half + block
  let dividend = FixedArray::make(dividend_len + 1, 0UL)
  for index in 0..<block {
    dividend.unsafe_set(index, source.unsafe_get(start + block + index))
  }
  for index in 0..<(high_half + 1) {
    dividend.unsafe_set(block + index, high_remainder.unsafe_get(index))
  }
  let low_bit = dividend.unsafe_get(0) & 1UL
  for index in 0..<dividend_len {
    dividend.unsafe_set(
      index,
      (dividend.unsafe_get(index) >> 1) | (dividend.unsafe_get(index + 1) << 63),
    )
  }
  dividend.unsafe_set(dividend_len, dividend.unsafe_get(dividend_len) >> 1)
  let quotient = FixedArray::make(block + 1, 0UL)
  bin_coeff_knuth_words_core(
    dividend,
    high_root,
    high_half,
    quotient,
    block + 1,
  )
  // the estimate is at most X; a quotient of exactly X is capped at X - 1
  let capped = quotient.unsafe_get(block) != 0UL
  guard !capped || quotient.unsafe_get(block) == 1UL else {
    abort("Coeff square root quotient estimate exceeded X")
  }
  let root = FixedArray::make(half, 0UL)
  for index in 0..<block {
    root.unsafe_set(
      index,
      if capped {
        0xFFFF_FFFF_FFFF_FFFFUL
      } else {
        quotient.unsafe_get(index)
      },
    )
  }
  for index in 0..<high_half {
    root.unsafe_set(block + index, high_root.unsafe_get(index))
  }
  // partial = u * X + a0 with u = 2 r + low_bit (plus 2 s' when capped)
  let partial_len = half + 1
  let partial = FixedArray::make(partial_len, 0UL)
  for index in 0..<block {
    partial.unsafe_set(index, source.unsafe_get(start + index))
  }
  let mut carry = low_bit
  for index in 0..<high_half {
    let word = dividend.unsafe_get(index)
    partial.unsafe_set(block + index, (word << 1) | carry)
    carry = word >> 63
  }
  partial.unsafe_set(half, carry)
  if capped {
    for _ in 0..<2 {
      bin_coeff_words_add_into(
        partial, block, partial_len, high_root, 0, high_half,
      )
    }
  }
  let square = FixedArray::make(2 * block, 0UL)
  let scratch = if bin_coeff_words_scratch_len(block) > 0 {
    FixedArray::make(bin_coeff_words_scratch_len(block), 0UL)
  } else {
    bin_coeff_sqrt_empty_scratch
  }
  bin_coeff_words_sqr_scratch(square, 0, root, 0, block, scratch, 0)
  if bin_coeff_words_compare_padded(
      partial,
      0,
      partial_len,
      square,
      0,
      2 * block,
      partial_len,
    ) <
    0 {
    // one too large: root - 1, remainder + 2 (root - 1) + 1
    let mut index = 0
    while root.unsafe_get(index) == 0UL {
      root.unsafe_set(index, 0xFFFF_FFFF_FFFF_FFFFUL)
      index += 1
    }
    root.unsafe_set(index, root.unsafe_get(index) - 1UL)
    for _ in 0..<2 {
      bin_coeff_words_add_into(partial, 0, partial_len, root, 0, half)
    }
    let mut position = 0
    let mut increment = 1UL
    while increment != 0UL && position < partial_len {
      let total = partial.unsafe_get(position) + increment
      partial.unsafe_set(position, total)
      increment = if total == 0UL { 1UL } else { 0UL }
      position += 1
    }
  }
  bin_coeff_words_sub_in_place(partial, 0, partial_len, square, 0, 2 * block)
  (root, partial)
}

///|
let bin_coeff_sqrt_empty_scratch : FixedArray[UInt64] = FixedArray::make(0, 0UL)

///|
/// The root and remainder of the original radicand from those of the
/// normalised one (`radicand * 2^shift`, `shift` even, `limbs` limbs).
fn bin_coeff_sqrt_rem_normalized(
  source : FixedArray[UInt64],
  limbs : Int32,
  shift : Int32,
) -> (Coeff, Coeff) {
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
  let error_value = Coeff::from_uint64(error)
  let original_remainder = remainder
    .add(error_value.mul(root.shift_left(1).sub_checked(error_value).unwrap()))
    .shift_right(shift)
  (root.shift_right(half_shift), original_remainder)
}

///|
/// Square root with remainder of a value of more than 256 bits.
fn bin_coeff_sqrt_rem_words_recursive(value : Coeff) -> (Coeff, Coeff) {
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
  bin_coeff_sqrt_rem_normalized(source, limbs, shift)
}

///|
/// `value << shift` as exactly `limbs` little-endian limbs (the shifted value
/// must fit).
fn bin_coeff_words_shifted(
  value : Coeff,
  shift : Int32,
  limbs : Int32,
) -> FixedArray[UInt64] {
  let words = FixedArray::make(limbs, 0UL)
  let word_shift = shift / 64
  let bit_shift = shift % 64
  let len = bin_coeff_word_len(value)
  if bit_shift == 0 {
    for index in 0..<len {
      words.unsafe_set(index + word_shift, bin_coeff_word(value, index))
    }
  } else {
    let back = 64 - bit_shift
    let mut carry = 0UL
    for index in 0..<len {
      let word = bin_coeff_word(value, index)
      words.unsafe_set(index + word_shift, (word << bit_shift) | carry)
      carry = word >> back
    }
    if len + word_shift < limbs {
      words.unsafe_set(len + word_shift, carry)
    }
  }
  words
}

///|
/// `bin_coeff_sqrt_rem_kernel(value << scale)` without forming the shifted
/// value twice: for a radicand of more than 256 bits the recursion needs an
/// even number of limbs with a set bit in the top two, and that normalising
/// shift is folded into the shift by `scale`.
pub fn bin_coeff_sqrt_rem_scaled(
  value : Coeff,
  scale : Int32,
) -> (Coeff, Coeff) {
  let bits = value.bit_length() + scale
  if bits <= 256 || value.is_zero() {
    return bin_coeff_sqrt_rem_kernel(value.shift_left(scale))
  }
  let mut limbs = (bits + 63) / 64
  if limbs % 2 == 1 {
    limbs += 1
  }
  let shift = (limbs * 64 - bits) & -2
  let source = bin_coeff_words_shifted(value, scale + shift, limbs)
  bin_coeff_sqrt_rem_normalized(source, limbs, shift)
}

///|
/// The root and remainder of `value << scale`, packed into one value so that no
/// tuple is returned (it would be a heap object), for a radicand whose root has
/// at least `precision` bits:
///
/// - if the root has exactly `precision` bits, the root rounded to nearest
///   (`root + 1` when the remainder exceeds the root, the square root then lies
///   above `root + 1/2`; it never equals it), at the exponent of the root. This
///   value has `precision` bits, or `precision + 1` when the increment carries;
/// - otherwise `4 * root + 2 * b + s` with `b = 1` when the remainder exceeds
///   the root and `s = 1` when it is not zero: the two low bits are the round
///   and sticky bits under the root, the value has `precision + 3` bits or more
///   and its exponent is two below that of the root.
///
/// The caller tells the cases apart by the bit length (`<= precision + 1`).
pub fn bin_coeff_sqrt_scaled_rounded(
  value : Coeff,
  scale : Int32,
  precision : Int32,
) -> Coeff {
  let (root, remainder) = bin_coeff_sqrt_rem_scaled(value, scale)
  let above_half = remainder.compare(root) > 0
  if root.bit_length() == precision {
    return if above_half { root.add(Coeff::one()) } else { root }
  }
  let low = if above_half {
    3UL
  } else if remainder.is_zero() {
    0UL
  } else {
    1UL
  }
  bin_coeff_shift2_or(root, low)
}

///|
/// `value * 4 + low` for `low < 4`, built from the limbs without general `Coeff`
/// arithmetic (a shift and an addition of a general `Coeff` allocate several
/// temporaries, which costs more than the square root of a 128-bit radicand).
fn bin_coeff_shift2_or(value : Coeff, low : UInt64) -> Coeff {
  match value.0 {
    Inline64(word) =>
      if word >> 62 == 0UL {
        Coeff::from_uint64((word << 2) | low)
      } else {
        bin_coeff_inline(word >> 62, (word << 2) | low)
      }
    Inline128(high, word) => {
      let top = high >> 62
      let new_high = (high << 2) | (word >> 62)
      let new_low = (word << 2) | low
      if top == 0UL {
        bin_coeff_inline(new_high, new_low)
      } else {
        bin_coeff_from_words([new_low, new_high, top], 3)
      }
    }
    Heap(words, len) => {
      let result = FixedArray::make(len + 1, 0UL)
      let mut carry = low
      for index in 0..<len {
        let word = words.unsafe_get(index)
        result.unsafe_set(index, (word << 2) | carry)
        carry = word >> 62
      }
      result.unsafe_set(len, carry)
      bin_coeff_from_words(result, len + 1)
    }
  }
}
