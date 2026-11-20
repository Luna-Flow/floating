///|
/// Integer square roots of one, two and four words without a bit-by-bit loop:
/// a double-precision estimate refined by one Newton step on 128-bit
/// arithmetic and settled by exact comparisons for up to 128 bits, and a
/// word-level Karatsuba square root (Zimmermann's SqrtRem: the root of the
/// upper half, one 128 by 64 bit division for the low half of the root) for up
/// to 256 bits. The restoring loops they replace remain as the references of
/// the tests (`bin_coeff_sqrt_rem_u128`, `bin_coeff_sqrt_rem_u256`).

///|
/// `floor(sqrt(value))`.
fn bin_coeff_isqrt64(value : UInt64) -> UInt64 {
  if value < 2UL {
    return value
  }
  let mut root = value.to_double().sqrt().to_uint64()
  if root > 0xffff_ffffUL {
    root = 0xffff_ffffUL
  }
  while root * root > value {
    root -= 1UL
  }
  while root < 0xffff_ffffUL && (root + 1UL) * (root + 1UL) <= value {
    root += 1UL
  }
  root
}

///|
/// `floor(sqrt(high * 2^64 + low))`.
fn bin_coeff_isqrt128(high : UInt64, low : UInt64) -> UInt64 {
  if high == 0UL {
    return bin_coeff_isqrt64(low)
  }
  let estimate = (high.to_double() * 18446744073709551616.0 + low.to_double()).sqrt()
  let mut root = if estimate >= 18446744073709551615.0 {
    0xffff_ffff_ffff_ffffUL
  } else {
    estimate.to_uint64()
  }
  if root > high {
    // one Newton step, `(root + value / root) / 2` without overflow
    let quotient = binary_fast_div_wide(high, low, root)
    root = (root >> 1) + (quotient >> 1) + (root & quotient & 1UL)
  }
  // settle: root^2 <= value < (root + 1)^2
  while true {
    let square_high = bin_coeff_mul_high(root, root)
    let square_low = root * root
    if square_high > high || (square_high == high && square_low > low) {
      root -= 1UL
      continue
    }
    if root != 0xffff_ffff_ffff_ffffUL {
      let next = root + 1UL
      let next_high = bin_coeff_mul_high(next, next)
      let next_low = next * next
      if next_high < high || (next_high == high && next_low <= low) {
        root = next
        continue
      }
    }
    break
  }
  root
}

///|
fn bin_coeff_sqrt_rem_u128_words(
  value_high : UInt64,
  value_low : UInt64,
) -> (Coeff, Coeff) {
  let root = bin_coeff_isqrt128(value_high, value_low)
  let square_low = root * root
  let borrow = if value_low < square_low { 1UL } else { 0UL }
  (
    Coeff::from_uint64(root),
    bin_coeff_inline(
      value_high - bin_coeff_mul_high(root, root) - borrow,
      value_low - square_low,
    ),
  )
}

///|
/// The square `words` (four little-endian words) of the 128-bit `high:low`.
fn bin_coeff_square128_into(
  high : UInt64,
  low : UInt64,
  words : FixedArray[UInt64],
) -> Unit {
  let low_low_high = bin_coeff_mul_high(low, low)
  let cross_low = high * low
  let cross_high = bin_coeff_mul_high(high, low)
  let top_low = high * high
  let top_high = bin_coeff_mul_high(high, high)
  words.unsafe_set(0, low * low)
  // word 1: the high half of low^2 plus the low half of 2 * high * low
  let mut word1 = low_low_high
  let mut carry1 = 0UL
  word1 += cross_low
  if word1 < cross_low {
    carry1 += 1UL
  }
  word1 += cross_low
  if word1 < cross_low {
    carry1 += 1UL
  }
  words.unsafe_set(1, word1)
  // word 2: the high half of 2 * high * low, the low half of high^2, carries
  let mut word2 = top_low
  let mut carry2 = 0UL
  word2 += carry1
  if word2 < carry1 {
    carry2 += 1UL
  }
  word2 += cross_high
  if word2 < cross_high {
    carry2 += 1UL
  }
  word2 += cross_high
  if word2 < cross_high {
    carry2 += 1UL
  }
  words.unsafe_set(2, word2)
  words.unsafe_set(3, top_high + carry2)
}

///|
/// Compares four little-endian words with four others.
fn bin_coeff_compare4(
  left : FixedArray[UInt64],
  right3 : UInt64,
  right2 : UInt64,
  right1 : UInt64,
  right0 : UInt64,
) -> Int32 {
  let word3 = left.unsafe_get(3)
  if word3 != right3 {
    return if word3 > right3 { 1 } else { -1 }
  }
  let word2 = left.unsafe_get(2)
  if word2 != right2 {
    return if word2 > right2 { 1 } else { -1 }
  }
  let word1 = left.unsafe_get(1)
  if word1 != right1 {
    return if word1 > right1 { 1 } else { -1 }
  }
  let word0 = left.unsafe_get(0)
  if word0 != right0 {
    return if word0 > right0 { 1 } else { -1 }
  }
  0
}

///|
/// Word `index` of the 256-bit `word3:word2:word1:word0 << shift`,
/// `0 <= shift < 256`.
fn bin_coeff_shl256_word(
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - shift / 64
  let bit_shift = shift % 64
  let part = match source {
    0 => word0
    1 => word1
    2 => word2
    3 => word3
    _ => 0UL
  }
  if bit_shift == 0 {
    return part
  }
  let lower = match source - 1 {
    0 => word0
    1 => word1
    2 => word2
    _ => 0UL
  }
  (part << bit_shift) | (lower >> (64 - bit_shift))
}

///|
/// Square root with remainder of a value of 129 to 256 bits.
fn bin_coeff_sqrt_rem_u256_words(value : Coeff) -> (Coeff, Coeff) {
  let word0 = bin_coeff_word(value, 0)
  let word1 = bin_coeff_word(value, 1)
  let word2 = bin_coeff_word(value, 2)
  let word3 = bin_coeff_word(value, 3)
  // normalize: an even left shift that puts a set bit in the top two bits
  let shift = (256 - value.bit_length()) & -2
  let normal0 = bin_coeff_shl256_word(word3, word2, word1, word0, shift, 0)
  let normal1 = bin_coeff_shl256_word(word3, word2, word1, word0, shift, 1)
  let normal2 = bin_coeff_shl256_word(word3, word2, word1, word0, shift, 2)
  let normal3 = bin_coeff_shl256_word(word3, word2, word1, word0, shift, 3)
  // root of the upper half and its remainder (at most 2 * root, 65 bits)
  let upper_root = bin_coeff_isqrt128(normal3, normal2)
  let upper_square_low = upper_root * upper_root
  let upper_borrow = if normal2 < upper_square_low { 1UL } else { 0UL }
  let remainder_high = normal3 -
    bin_coeff_mul_high(upper_root, upper_root) -
    upper_borrow
  let remainder_low = normal2 - upper_square_low
  // q = floor((remainder * 2^64 + normal1) / (2 * upper_root)), at most 2^64
  let half_high = (remainder_high << 63) | (remainder_low >> 1)
  let half_low = (remainder_low << 63) | (normal1 >> 1)
  let quotient = if half_high < upper_root {
    binary_fast_div_wide(half_high, half_low, upper_root)
  } else {
    0xffff_ffff_ffff_ffffUL
  }
  let mut root_high = upper_root
  let mut root_low = quotient
  // settle on the exact square: at most a unit or two off
  let square = FixedArray::make(4, 0UL)
  while true {
    bin_coeff_square128_into(root_high, root_low, square)
    if bin_coeff_compare4(square, normal3, normal2, normal1, normal0) > 0 {
      if root_low == 0UL {
        root_high -= 1UL
      }
      root_low -= 1UL
      continue
    }
    let next_low = root_low + 1UL
    let next_high = if next_low == 0UL { root_high + 1UL } else { root_high }
    if next_high != 0UL || next_low != 0UL {
      bin_coeff_square128_into(next_high, next_low, square)
      if bin_coeff_compare4(square, normal3, normal2, normal1, normal0) <= 0 {
        root_high = next_high
        root_low = next_low
        continue
      }
    }
    break
  }
  // undo the normalization: the root of value is the root >> (shift / 2)
  let root_shift = shift / 2
  if root_shift > 0 {
    root_low = (root_low >> root_shift) | (root_high << (64 - root_shift))
    root_high = root_high >> root_shift
  }
  // remainder = value - root^2
  bin_coeff_square128_into(root_high, root_low, square)
  let remainder = FixedArray::make(4, 0UL)
  let difference0 = word0 - square.unsafe_get(0)
  let borrow0 = if word0 < square.unsafe_get(0) { 1UL } else { 0UL }
  let partial1 = word1 - square.unsafe_get(1)
  let difference1 = partial1 - borrow0
  let borrow1 = if word1 < square.unsafe_get(1) || partial1 < borrow0 {
    1UL
  } else {
    0UL
  }
  let partial2 = word2 - square.unsafe_get(2)
  let difference2 = partial2 - borrow1
  let borrow2 = if word2 < square.unsafe_get(2) || partial2 < borrow1 {
    1UL
  } else {
    0UL
  }
  remainder.unsafe_set(0, difference0)
  remainder.unsafe_set(1, difference1)
  remainder.unsafe_set(2, difference2)
  remainder.unsafe_set(3, word3 - square.unsafe_get(3) - borrow2)
  (bin_coeff_inline(root_high, root_low), bin_coeff_from_words(remainder, 4))
}
