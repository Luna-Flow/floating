///|
#derive(Debug)
pub enum CoeffRepr {
  Inline64(UInt64)
  Inline128(UInt64, UInt64)
  // little-endian 64-bit limbs, `len` of them used (len >= 3, top limb nonzero)
  Heap(FixedArray[UInt64], Int32)
}

///|
#derive(Debug)
pub struct Coeff(CoeffRepr)

///|
let bin_coeff_limb_bits = 32

///|
let bin_coeff_limb_mask = 0xffff_ffffUL

///|
let bin_coeff_limb_base = 0x1_0000_0000UL

///|
/// Smallest length, in 64-bit limbs, of both operands of a product that is
/// tested for the sparse (few nonzero limbs) policy.
let bin_coeff_sparse_min_words = 4

///|
fn bin_coeff_u64_bits(value : UInt64) -> Int32 {
  if value == 0UL {
    0
  } else {
    64 - value.reinterpret_as_int64().clz()
  }
}

///|
pub fn bin_coeff_inline(high : UInt64, low : UInt64) -> Coeff {
  if high == 0UL {
    Coeff(Inline64(low))
  } else {
    Coeff(Inline128(high, low))
  }
}

///|
/// Number of 64-bit limbs (1 for zero).
fn bin_coeff_word_len(value : Coeff) -> Int32 {
  match value.0 {
    Inline64(_) => 1
    Inline128(_, _) => 2
    Heap(_, len) => len
  }
}

///|
/// The `index`-th 64-bit limb, zero beyond the top.
pub fn bin_coeff_word(value : Coeff, index : Int32) -> UInt64 {
  match value.0 {
    Inline64(low) => if index == 0 { low } else { 0UL }
    Inline128(high, low) =>
      match index {
        0 => low
        1 => high
        _ => 0UL
      }
    Heap(words, len) =>
      if index >= 0 && index < len {
        words.unsafe_get(index)
      } else {
        0UL
      }
  }
}

///|
/// Builds a value from little-endian 64-bit limbs; the array is kept by a
/// heap value, so the caller must not modify it afterwards.
pub fn bin_coeff_from_words(
  words : FixedArray[UInt64],
  maximum_len : Int32,
) -> Coeff {
  let mut len = maximum_len
  while len > 1 && words.unsafe_get(len - 1) == 0UL {
    len -= 1
  }
  if len <= 0 {
    return Coeff::zero()
  }
  if len == 1 {
    return Coeff(Inline64(words.unsafe_get(0)))
  }
  if len == 2 {
    return bin_coeff_inline(words.unsafe_get(1), words.unsafe_get(0))
  }
  Coeff(Heap(words, len))
}

///|
/// High 64 bits of the 128-bit product of two words.
fn bin_coeff_mul_high(left : UInt64, right : UInt64) -> UInt64 {
  let left_low = left & bin_coeff_limb_mask
  let left_high = left >> 32
  let right_low = right & bin_coeff_limb_mask
  let right_high = right >> 32
  let cross = left_high * right_low + ((left_low * right_low) >> 32)
  left_high * right_high +
  (cross >> 32) +
  ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
}

///|
pub fn Coeff::zero() -> Coeff {
  Coeff(Inline64(0UL))
}

///|
pub fn Coeff::one() -> Coeff {
  Coeff(Inline64(1UL))
}

///|
pub fn Coeff::from_uint64(value : UInt64) -> Coeff {
  Coeff(Inline64(value))
}

///|
pub fn Coeff::is_zero(self : Coeff) -> Bool {
  match self.0 {
    Inline64(value) => value == 0UL
    Inline128(_, _) | Heap(_, _) => false
  }
}

///|
pub fn Coeff::is_odd(self : Coeff) -> Bool {
  (bin_coeff_word(self, 0) & 1UL) != 0UL
}

///|
pub fn Coeff::bit_length(self : Coeff) -> Int32 {
  match self.0 {
    Inline64(value) => bin_coeff_u64_bits(value)
    Inline128(high, _) => 64 + bin_coeff_u64_bits(high)
    Heap(words, len) =>
      (len - 1) * 64 + bin_coeff_u64_bits(words.unsafe_get(len - 1))
  }
}

///|
pub fn Coeff::ctz(self : Coeff) -> Int32 {
  match self.0 {
    Inline64(value) =>
      if value == 0UL {
        0
      } else {
        value.reinterpret_as_int64().ctz()
      }
    Inline128(high, low) =>
      if low != 0UL {
        low.reinterpret_as_int64().ctz()
      } else {
        64 + high.reinterpret_as_int64().ctz()
      }
    Heap(words, len) => {
      let mut index = 0
      while index < len && words.unsafe_get(index) == 0UL {
        index += 1
      }
      if index == len {
        0
      } else {
        index * 64 + words.unsafe_get(index).reinterpret_as_int64().ctz()
      }
    }
  }
}

///|
pub fn Coeff::to_uint64(self : Coeff) -> UInt64? {
  match self.0 {
    Inline64(value) => Some(value)
    Inline128(_, _) | Heap(_, _) => None
  }
}

///|
pub fn Coeff::test_bit(self : Coeff, index : Int32) -> Bool {
  if index < 0 || index >= self.bit_length() {
    return false
  }
  (bin_coeff_word(self, index / 64) & (1UL << (index % 64))) != 0UL
}

///|
pub fn Coeff::compare(self : Coeff, other : Coeff) -> Int32 {
  let self_len = bin_coeff_word_len(self)
  let other_len = bin_coeff_word_len(other)
  if self_len != other_len {
    return if self_len < other_len { -1 } else { 1 }
  }
  match (self.0, other.0) {
    (Heap(left_words, _), Heap(right_words, _)) => {
      let mut index = self_len - 1
      while true {
        let left = left_words.unsafe_get(index)
        let right = right_words.unsafe_get(index)
        if left != right {
          return if left < right { -1 } else { 1 }
        }
        if index == 0 {
          break
        }
        index -= 1
      }
      0
    }
    _ => {
      let mut index = self_len - 1
      while true {
        let left = bin_coeff_word(self, index)
        let right = bin_coeff_word(other, index)
        if left != right {
          return if left < right { -1 } else { 1 }
        }
        if index == 0 {
          break
        }
        index -= 1
      }
      0
    }
  }
}

///|
fn bin_coeff_add_heap(left : Coeff, right : Coeff) -> Coeff {
  let left_len = bin_coeff_word_len(left)
  let right_len = bin_coeff_word_len(right)
  let len = Int32::max(left_len, right_len)
  let words = FixedArray::make(len + 1, 0UL)
  let mut carry = 0UL
  match (left.0, right.0) {
    (Heap(left_words, _), Heap(right_words, _)) =>
      for index in 0..<len {
        let left_value = if index < left_len {
          left_words.unsafe_get(index)
        } else {
          0UL
        }
        let right_value = if index < right_len {
          right_words.unsafe_get(index)
        } else {
          0UL
        }
        let sum = left_value + right_value
        let carry_one = if sum < left_value { 1UL } else { 0UL }
        let total = sum + carry
        let carry_two = if total < sum { 1UL } else { 0UL }
        words.unsafe_set(index, total)
        carry = carry_one + carry_two
      }
    _ =>
      for index in 0..<len {
        let left_value = bin_coeff_word(left, index)
        let sum = left_value + bin_coeff_word(right, index)
        let carry_one = if sum < left_value { 1UL } else { 0UL }
        let total = sum + carry
        let carry_two = if total < sum { 1UL } else { 0UL }
        words.unsafe_set(index, total)
        carry = carry_one + carry_two
      }
  }
  words.unsafe_set(len, carry)
  bin_coeff_from_words(words, len + 1)
}

///|
pub fn Coeff::add(self : Coeff, other : Coeff) -> Coeff {
  match (self.0, other.0) {
    (Inline64(left), Inline64(right)) => {
      let low = left + right
      if low >= left {
        Coeff(Inline64(low))
      } else {
        Coeff(Inline128(1UL, low))
      }
    }
    (Inline128(high, low), Inline64(value))
    | (Inline64(value), Inline128(high, low)) => {
      let result_low = low + value
      let carry = if result_low < low { 1UL } else { 0UL }
      let result_high = high + carry
      if result_high >= high {
        bin_coeff_inline(result_high, result_low)
      } else {
        bin_coeff_add_heap(self, other)
      }
    }
    (Inline128(left_high, left_low), Inline128(right_high, right_low)) => {
      let low = left_low + right_low
      let carry = if low < left_low { 1UL } else { 0UL }
      let partial_high = left_high + right_high
      let high = partial_high + carry
      if partial_high >= left_high && high >= partial_high {
        bin_coeff_inline(high, low)
      } else {
        bin_coeff_add_heap(self, other)
      }
    }
    _ => bin_coeff_add_heap(self, other)
  }
}

///|
pub fn bin_coeff_add_normalized_odd(
  left : Coeff,
  right : Coeff,
) -> (Coeff, Int32) {
  match (left.0, right.0) {
    (Heap(left_words, left_len), Heap(right_words, right_len)) => {
      let len = Int32::max(left_len, right_len)
      let words = FixedArray::make(len + 1, 0UL)
      let mut carry = 0UL
      for index in 0..<len {
        let left_value = if index < left_len {
          left_words.unsafe_get(index)
        } else {
          0UL
        }
        let right_value = if index < right_len {
          right_words.unsafe_get(index)
        } else {
          0UL
        }
        let sum = left_value + right_value
        let carry_one = if sum < left_value { 1UL } else { 0UL }
        let total = sum + carry
        let carry_two = if total < sum { 1UL } else { 0UL }
        words.unsafe_set(index, total)
        carry = carry_one + carry_two
      }
      words.unsafe_set(len, carry)
      return bin_coeff_normalize_odd_words(words, len + 1)
    }
    _ => ()
  }
  let sum = left.add(right)
  let normalization_shift = sum.ctz()
  (sum.shift_right(normalization_shift), normalization_shift)
}

///|
/// Strips the trailing zero bits of the nonzero words `words[0..len)` in
/// place and returns the value with the number of bits removed.
fn bin_coeff_normalize_odd_words(
  words : FixedArray[UInt64],
  len : Int32,
) -> (Coeff, Int32) {
  let mut first_nonzero = 0
  while words.unsafe_get(first_nonzero) == 0UL {
    first_nonzero += 1
  }
  let bit_shift = words.unsafe_get(first_nonzero).reinterpret_as_int64().ctz()
  let normalization_shift = first_nonzero * 64 + bit_shift
  if normalization_shift == 0 {
    return (bin_coeff_from_words(words, len), 0)
  }
  let output_len = len - first_nonzero
  for output_index in 0..<output_len {
    let source_index = output_index + first_nonzero
    let mut word = words.unsafe_get(source_index) >> bit_shift
    if bit_shift != 0 && source_index + 1 < len {
      word = word | (words.unsafe_get(source_index + 1) << (64 - bit_shift))
    }
    words.unsafe_set(output_index, word)
  }
  (bin_coeff_from_words(words, output_len), normalization_shift)
}

///|
fn bin_coeff_sub_unchecked(left : Coeff, right : Coeff) -> Coeff {
  match (left.0, right.0) {
    (Inline64(left), Inline64(right)) => return Coeff(Inline64(left - right))
    (Inline128(high, low), Inline64(value)) => {
      let borrow = if low < value { 1UL } else { 0UL }
      return bin_coeff_inline(high - borrow, low - value)
    }
    (Inline128(left_high, left_low), Inline128(right_high, right_low)) => {
      let borrow = if left_low < right_low { 1UL } else { 0UL }
      return bin_coeff_inline(
        left_high - right_high - borrow,
        left_low - right_low,
      )
    }
    _ => ()
  }
  let left_len = bin_coeff_word_len(left)
  let right_len = bin_coeff_word_len(right)
  let words = FixedArray::make(left_len, 0UL)
  bin_coeff_sub_words(left, right, words, left_len, right_len)
  bin_coeff_from_words(words, left_len)
}

///|
/// `words[0..left_len) = left - right` for `left >= right`.
fn bin_coeff_sub_words(
  left : Coeff,
  right : Coeff,
  words : FixedArray[UInt64],
  left_len : Int32,
  right_len : Int32,
) -> Unit {
  let mut borrow = 0UL
  match (left.0, right.0) {
    (Heap(left_words, _), Heap(right_words, _)) =>
      for index in 0..<left_len {
        let minuend = left_words.unsafe_get(index)
        let subtrahend = if index < right_len {
          right_words.unsafe_get(index)
        } else {
          0UL
        }
        let difference = minuend - subtrahend
        let borrow_one = if minuend < subtrahend { 1UL } else { 0UL }
        let result = difference - borrow
        let borrow_two = if difference < borrow { 1UL } else { 0UL }
        words.unsafe_set(index, result)
        borrow = borrow_one + borrow_two
      }
    _ =>
      for index in 0..<left_len {
        let minuend = bin_coeff_word(left, index)
        let subtrahend = bin_coeff_word(right, index)
        let difference = minuend - subtrahend
        let borrow_one = if minuend < subtrahend { 1UL } else { 0UL }
        let result = difference - borrow
        let borrow_two = if difference < borrow { 1UL } else { 0UL }
        words.unsafe_set(index, result)
        borrow = borrow_one + borrow_two
      }
  }
}

///|
pub fn bin_coeff_sub_normalized_odd(
  left : Coeff,
  right : Coeff,
) -> (Coeff, Int32) {
  match (left.0, right.0) {
    (Heap(_, left_len), Heap(_, right_len)) => {
      let words = FixedArray::make(left_len, 0UL)
      bin_coeff_sub_words(left, right, words, left_len, right_len)
      return bin_coeff_normalize_odd_words(words, left_len)
    }
    _ => ()
  }
  let difference = bin_coeff_sub_unchecked(left, right)
  let normalization_shift = difference.ctz()
  (difference.shift_right(normalization_shift), normalization_shift)
}

///|
pub fn Coeff::sub_checked(self : Coeff, other : Coeff) -> Result[Coeff, String] {
  if self.compare(other) < 0 {
    Err("Coeff subtraction would be negative")
  } else {
    Ok(bin_coeff_sub_unchecked(self, other))
  }
}

///|
fn bin_coeff_mul_u64_words(left : UInt64, right : UInt64) -> (UInt64, UInt64) {
  let left_low = left & bin_coeff_limb_mask
  let left_high = left >> 32
  let right_low = right & bin_coeff_limb_mask
  let right_high = right >> 32
  let first = left_low * right_low
  let low_word = first & bin_coeff_limb_mask
  let mut middle = left_high * right_low + (first >> 32)
  let high_carry = middle >> 32
  middle = left_low * right_high + (middle & bin_coeff_limb_mask)
  let high = left_high * right_high + high_carry + (middle >> 32)
  let low = (middle << 32) | low_word
  (high, low)
}

///|
fn bin_coeff_mul_u64(left : UInt64, right : UInt64) -> Coeff {
  if left == 0UL || right == 0UL {
    return Coeff::zero()
  }
  let (high, low) = bin_coeff_mul_u64_words(left, right)
  bin_coeff_inline(high, low)
}

///|
fn bin_coeff_from_words_256(
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
) -> Coeff {
  if word3 == 0UL && word2 == 0UL {
    return bin_coeff_inline(word1, word0)
  }
  let words = FixedArray::make(4, 0UL)
  words.unsafe_set(0, word0)
  words.unsafe_set(1, word1)
  words.unsafe_set(2, word2)
  words.unsafe_set(3, word3)
  bin_coeff_from_words(words, 4)
}

///|
fn bin_coeff_mul_inline_128(
  left_high : UInt64,
  left_low : UInt64,
  right_high : UInt64,
  right_low : UInt64,
) -> Coeff {
  let (product00_high, product00_low) = bin_coeff_mul_u64_words(
    left_low, right_low,
  )
  let (product01_high, product01_low) = bin_coeff_mul_u64_words(
    left_low, right_high,
  )
  let (product10_high, product10_low) = bin_coeff_mul_u64_words(
    left_high, right_low,
  )
  let (product11_high, product11_low) = bin_coeff_mul_u64_words(
    left_high, right_high,
  )
  let partial_word1 = product00_high + product01_low
  let mut carry1 = if partial_word1 < product00_high { 1UL } else { 0UL }
  let word1 = partial_word1 + product10_low
  if word1 < partial_word1 {
    carry1 += 1UL
  }
  let partial_word2 = product01_high + product10_high
  let mut carry2 = if partial_word2 < product01_high { 1UL } else { 0UL }
  let next_word2 = partial_word2 + product11_low
  if next_word2 < partial_word2 {
    carry2 += 1UL
  }
  let word2 = next_word2 + carry1
  if word2 < next_word2 {
    carry2 += 1UL
  }
  bin_coeff_from_words_256(product11_high + carry2, word2, word1, product00_low)
}

///|
fn bin_coeff_mul_schoolbook(left : Coeff, right : Coeff) -> Coeff {
  let left_len = bin_coeff_word_len(left)
  let right_len = bin_coeff_word_len(right)
  let words = FixedArray::make(left_len + right_len, 0UL)
  match (left.0, right.0) {
    (Heap(left_words, _), Heap(right_words, _)) =>
      for left_index in 0..<left_len {
        let left_word = left_words.unsafe_get(left_index)
        let left_low = left_word & bin_coeff_limb_mask
        let left_high = left_word >> 32
        let mut carry = 0UL
        for right_index in 0..<right_len {
          let index = left_index + right_index
          let right_word = right_words.unsafe_get(right_index)
          let low = left_word * right_word
          let right_low = right_word & bin_coeff_limb_mask
          let right_high = right_word >> 32
          let cross = left_high * right_low + ((left_low * right_low) >> 32)
          let product_high = left_high * right_high +
            (cross >> 32) +
            ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
          let partial = low + carry
          let carry_one = if partial < low { 1UL } else { 0UL }
          let total = partial + words.unsafe_get(index)
          let carry_two = if total < partial { 1UL } else { 0UL }
          words.unsafe_set(index, total)
          carry = product_high + carry_one + carry_two
        }
        words.unsafe_set(left_index + right_len, carry)
      }
    _ =>
      for left_index in 0..<left_len {
        let left_word = bin_coeff_word(left, left_index)
        let left_low = left_word & bin_coeff_limb_mask
        let left_high = left_word >> 32
        let mut carry = 0UL
        for right_index in 0..<right_len {
          let index = left_index + right_index
          let right_word = bin_coeff_word(right, right_index)
          let low = left_word * right_word
          let right_low = right_word & bin_coeff_limb_mask
          let right_high = right_word >> 32
          let cross = left_high * right_low + ((left_low * right_low) >> 32)
          let product_high = left_high * right_high +
            (cross >> 32) +
            ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
          let partial = low + carry
          let carry_one = if partial < low { 1UL } else { 0UL }
          let total = partial + words.unsafe_get(index)
          let carry_two = if total < partial { 1UL } else { 0UL }
          words.unsafe_set(index, total)
          carry = product_high + carry_one + carry_two
        }
        words.unsafe_set(left_index + right_len, carry)
      }
  }
  bin_coeff_from_words(words, left_len + right_len)
}

///|
/// The number of nonzero limbs of a heap value, or `None` when there are more
/// than `limit` (the sparse-multiplication policy counts 64-bit limbs).
fn bin_coeff_nonzero_word_count_limited(value : Coeff, limit : Int32) -> Int32? {
  match value.0 {
    Heap(words, len) => {
      let mut count = 0
      for index in 0..<len {
        if words.unsafe_get(index) != 0UL {
          count += 1
          if count > limit {
            return None
          }
        }
      }
      Some(count)
    }
    Inline64(_) | Inline128(_, _) => None
  }
}

///|
/// The indices of the `count` nonzero limbs of a heap value.
fn bin_coeff_sparse_positions(
  value : Coeff,
  count : Int32,
) -> FixedArray[Int32] {
  let positions = FixedArray::make(count, 0)
  match value.0 {
    Heap(words, len) => {
      let mut position_index = 0
      for index in 0..<len {
        if words.unsafe_get(index) != 0UL {
          positions.unsafe_set(position_index, index)
          position_index += 1
        }
      }
    }
    Inline64(_) | Inline128(_, _) => ()
  }
  positions
}

///|
fn bin_coeff_mul_sparse(
  left : Coeff,
  right : Coeff,
  left_count : Int32,
  right_count : Int32,
) -> Coeff {
  let left_len = bin_coeff_word_len(left)
  let right_len = bin_coeff_word_len(right)
  let left_positions = bin_coeff_sparse_positions(left, left_count)
  let right_positions = bin_coeff_sparse_positions(right, right_count)
  let words = FixedArray::make(left_len + right_len, 0UL)
  for left_position_index in 0..<left_count {
    let left_index = left_positions.unsafe_get(left_position_index)
    let left_word = bin_coeff_word(left, left_index)
    for right_position_index in 0..<right_count {
      let right_index = right_positions.unsafe_get(right_position_index)
      let right_word = bin_coeff_word(right, right_index)
      bin_coeff_add_product_at(
        words,
        left_len + right_len,
        left_index + right_index,
        left_word * right_word,
        bin_coeff_mul_high(left_word, right_word),
      )
    }
  }
  bin_coeff_from_words(words, left_len + right_len)
}

///|
/// `words[offset ..] += high * 2^64 + low`, the carry running up to `len`.
fn bin_coeff_add_product_at(
  words : FixedArray[UInt64],
  len : Int32,
  offset : Int32,
  low : UInt64,
  high : UInt64,
) -> Unit {
  let low_sum = words.unsafe_get(offset) + low
  let low_carry = if low_sum < low { 1UL } else { 0UL }
  words.unsafe_set(offset, low_sum)
  let high_sum = words.unsafe_get(offset + 1) + high
  let high_carry_one = if high_sum < high { 1UL } else { 0UL }
  let high_total = high_sum + low_carry
  let high_carry_two = if high_total < high_sum { 1UL } else { 0UL }
  words.unsafe_set(offset + 1, high_total)
  let mut carry = high_carry_one + high_carry_two
  let mut index = offset + 2
  while carry != 0UL && index < len {
    let sum = words.unsafe_get(index) + carry
    words.unsafe_set(index, sum)
    carry = if sum < carry { 1UL } else { 0UL }
    index += 1
  }
  guard carry == 0UL else { abort("Coeff sparse carry exceeded its output") }
}

///|
fn bin_coeff_square_schoolbook(value : Coeff) -> Coeff {
  let (source, source_len) = match value.0 {
    Heap(source, source_len) => (source, source_len)
    Inline64(_) | Inline128(_, _) => return value.mul(value)
  }
  let output_len = source_len * 2
  let words = FixedArray::make(output_len, 0UL)
  // the cross products a_i * a_j, i < j, once
  for left_index in 0..<source_len {
    let left_word = source.unsafe_get(left_index)
    let left_low = left_word & bin_coeff_limb_mask
    let left_high = left_word >> 32
    let mut carry = 0UL
    for right_index in (left_index + 1)..<source_len {
      let offset = left_index + right_index
      let right_word = source.unsafe_get(right_index)
      let low = left_word * right_word
      let right_low = right_word & bin_coeff_limb_mask
      let right_high = right_word >> 32
      let cross = left_high * right_low + ((left_low * right_low) >> 32)
      let product_high = left_high * right_high +
        (cross >> 32) +
        ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
      let partial = low + carry
      let carry_one = if partial < low { 1UL } else { 0UL }
      let total = partial + words.unsafe_get(offset)
      let carry_two = if total < partial { 1UL } else { 0UL }
      words.unsafe_set(offset, total)
      carry = product_high + carry_one + carry_two
    }
    words.unsafe_set(left_index + source_len, carry)
  }
  // double them
  let mut shifted_out = 0UL
  for index in 0..<output_len {
    let word = words.unsafe_get(index)
    words.unsafe_set(index, (word << 1) | shifted_out)
    shifted_out = word >> 63
  }
  guard shifted_out == 0UL else {
    abort("Coeff square doubling exceeded its output")
  }
  // add the squares a_i * a_i at 2 i
  let mut carry = 0UL
  for index in 0..<source_len {
    let word = source.unsafe_get(index)
    let low = word * word
    let high = bin_coeff_mul_high(word, word)
    let low_sum = words.unsafe_get(2 * index) + low
    let low_carry = if low_sum < low { 1UL } else { 0UL }
    let low_total = low_sum + carry
    let low_carry_two = if low_total < low_sum { 1UL } else { 0UL }
    words.unsafe_set(2 * index, low_total)
    let high_sum = words.unsafe_get(2 * index + 1) + high
    let high_carry = if high_sum < high { 1UL } else { 0UL }
    let high_total = high_sum + low_carry + low_carry_two
    let high_carry_two = if high_total < high_sum { 1UL } else { 0UL }
    words.unsafe_set(2 * index + 1, high_total)
    carry = high_carry + high_carry_two
  }
  guard carry == 0UL else { abort("Coeff square carry exceeded its output") }
  bin_coeff_from_words(words, output_len)
}

///|
pub fn Coeff::mul(self : Coeff, other : Coeff) -> Coeff {
  if self.is_zero() || other.is_zero() {
    return Coeff::zero()
  }
  match (self.0, other.0) {
    (Inline64(left), Inline64(right)) => return bin_coeff_mul_u64(left, right)
    (Inline128(left_high, left_low), Inline64(right)) =>
      return bin_coeff_mul_inline_128(left_high, left_low, 0UL, right)
    (Inline64(left), Inline128(right_high, right_low)) =>
      return bin_coeff_mul_inline_128(0UL, left, right_high, right_low)
    (Inline128(left_high, left_low), Inline128(right_high, right_low)) =>
      return bin_coeff_mul_inline_128(
        left_high, left_low, right_high, right_low,
      )
    _ => ()
  }
  let self_len = bin_coeff_word_len(self)
  let other_len = bin_coeff_word_len(other)
  if self_len >= bin_coeff_sparse_min_words &&
    other_len >= bin_coeff_sparse_min_words {
    let self_limit = Int32::max(2, self_len / 8)
    match bin_coeff_nonzero_word_count_limited(self, self_limit) {
      Some(self_count) => {
        let other_limit = Int32::max(2, other_len / 8)
        match bin_coeff_nonzero_word_count_limited(other, other_limit) {
          Some(other_count) if self_count.to_int64() *
            other_count.to_int64() *
            4L <
            self_len.to_int64() * other_len.to_int64() =>
            return bin_coeff_mul_sparse(self, other, self_count, other_count)
          _ => ()
        }
      }
      None => ()
    }
  }
  if Int32::min(bin_coeff_word_len(self), bin_coeff_word_len(other)) >=
    bin_coeff_words_karatsuba_cutoff {
    bin_coeff_mul_large_dispatch(self, other)
  } else {
    bin_coeff_mul_schoolbook(self, other)
  }
}

///|
pub fn Coeff::square(self : Coeff) -> Coeff {
  let len = bin_coeff_word_len(self)
  if len >= 16 {
    bin_coeff_square_large_dispatch(self)
  } else if len >= 4 {
    bin_coeff_square_schoolbook(self)
  } else {
    self.mul(self)
  }
}

///|
pub fn Coeff::shift_left(self : Coeff, shift : Int32) -> Coeff {
  if shift < 0 {
    abort("Coeff shift count must be non-negative")
  }
  if shift == 0 || self.is_zero() {
    return self
  }
  if self.bit_length() + shift <= 128 {
    match self.0 {
      Inline64(value) =>
        if shift < 64 {
          return bin_coeff_inline(value >> (64 - shift), value << shift)
        } else {
          return bin_coeff_inline(value << (shift - 64), 0UL)
        }
      Inline128(high, low) =>
        return bin_coeff_inline(
          (high << shift) | (low >> (64 - shift)),
          low << shift,
        )
      Heap(_, _) => ()
    }
  }
  let source_len = bin_coeff_word_len(self)
  let word_shift = shift / 64
  let bit_shift = shift % 64
  let words = FixedArray::make(source_len + word_shift + 1, 0UL)
  match self.0 {
    Heap(source, _) =>
      if bit_shift == 0 {
        for index in 0..<source_len {
          words.unsafe_set(index + word_shift, source.unsafe_get(index))
        }
      } else {
        let mut carry = 0UL
        for index in 0..<source_len {
          let word = source.unsafe_get(index)
          words.unsafe_set(index + word_shift, (word << bit_shift) | carry)
          carry = word >> (64 - bit_shift)
        }
        words.unsafe_set(source_len + word_shift, carry)
      }
    _ =>
      if bit_shift == 0 {
        for index in 0..<source_len {
          words.unsafe_set(index + word_shift, bin_coeff_word(self, index))
        }
      } else {
        let mut carry = 0UL
        for index in 0..<source_len {
          let word = bin_coeff_word(self, index)
          words.unsafe_set(index + word_shift, (word << bit_shift) | carry)
          carry = word >> (64 - bit_shift)
        }
        words.unsafe_set(source_len + word_shift, carry)
      }
  }
  bin_coeff_from_words(words, source_len + word_shift + 1)
}

///|
pub fn Coeff::shift_right(self : Coeff, shift : Int32) -> Coeff {
  if shift < 0 {
    abort("Coeff shift count must be non-negative")
  }
  if shift == 0 || self.is_zero() {
    return self
  }
  match self.0 {
    Inline64(value) =>
      return Coeff(Inline64(if shift >= 64 { 0UL } else { value >> shift }))
    Inline128(high, low) => {
      if shift >= 128 {
        return Coeff::zero()
      }
      if shift >= 64 {
        return Coeff(Inline64(high >> (shift - 64)))
      }
      return bin_coeff_inline(
        high >> shift,
        (low >> shift) | (high << (64 - shift)),
      )
    }
    Heap(_, _) => ()
  }
  if shift >= self.bit_length() {
    return Coeff::zero()
  }
  let source_len = bin_coeff_word_len(self)
  let word_shift = shift / 64
  let bit_shift = shift % 64
  let output_len = source_len - word_shift
  let words = FixedArray::make(output_len, 0UL)
  match self.0 {
    Heap(source, _) =>
      for output_index in 0..<output_len {
        let source_index = output_index + word_shift
        let mut word = source.unsafe_get(source_index) >> bit_shift
        if bit_shift > 0 && source_index + 1 < source_len {
          word = word |
            (source.unsafe_get(source_index + 1) << (64 - bit_shift))
        }
        words.unsafe_set(output_index, word)
      }
    _ => ()
  }
  bin_coeff_from_words(words, output_len)
}

///|
fn bin_coeff_inline_words(value : Coeff) -> (UInt64, UInt64)? {
  match value.0 {
    Inline64(low) => Some((0UL, low))
    Inline128(high, low) => Some((high, low))
    Heap(_, _) => None
  }
}

///|
pub fn Coeff::bit_and(self : Coeff, other : Coeff) -> Coeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high & right_high, left_low & right_low)
    _ => ()
  }
  let len = Int32::min(bin_coeff_word_len(self), bin_coeff_word_len(other))
  let words = FixedArray::make(len, 0UL)
  for index in 0..<len {
    words.unsafe_set(
      index,
      bin_coeff_word(self, index) & bin_coeff_word(other, index),
    )
  }
  bin_coeff_from_words(words, len)
}

///|
pub fn Coeff::bit_or(self : Coeff, other : Coeff) -> Coeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high | right_high, left_low | right_low)
    _ => ()
  }
  let len = Int32::max(bin_coeff_word_len(self), bin_coeff_word_len(other))
  let words = FixedArray::make(len, 0UL)
  for index in 0..<len {
    words.unsafe_set(
      index,
      bin_coeff_word(self, index) | bin_coeff_word(other, index),
    )
  }
  bin_coeff_from_words(words, len)
}

///|
pub fn Coeff::bit_xor(self : Coeff, other : Coeff) -> Coeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high ^ right_high, left_low ^ right_low)
    _ => ()
  }
  let len = Int32::max(bin_coeff_word_len(self), bin_coeff_word_len(other))
  let words = FixedArray::make(len, 0UL)
  for index in 0..<len {
    words.unsafe_set(
      index,
      bin_coeff_word(self, index) ^ bin_coeff_word(other, index),
    )
  }
  bin_coeff_from_words(words, len)
}

///|
/// Quotient and remainder by a divisor below 2^32: one pass over a copy of the
/// limbs, a 64 by 32 bit division per half-limb.
fn bin_coeff_div_rem_word(
  numerator : Coeff,
  denominator : UInt32,
) -> (Coeff, Coeff) {
  let source_len = bin_coeff_word_len(numerator)
  let quotient = FixedArray::make(source_len, 0UL)
  for index in 0..<source_len {
    quotient.unsafe_set(index, bin_coeff_word(numerator, index))
  }
  let remainder = bin_coeff_words_div_small_in_place(
    quotient,
    source_len,
    denominator.to_uint64(),
  )
  (bin_coeff_from_words(quotient, source_len), Coeff::from_uint64(remainder))
}

///|
fn bin_coeff_div_rem_knuth(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  if bin_coeff_knuth_words_enabled {
    bin_coeff_div_rem_knuth_words(numerator, denominator)
  } else {
    bin_coeff_div_rem_knuth_limb32(numerator, denominator)
  }
}

///|
pub fn Coeff::div_rem_checked(
  self : Coeff,
  denominator : Coeff,
) -> Result[(Coeff, Coeff), String] {
  if denominator.is_zero() {
    return Err("Coeff division by zero")
  }
  if self.compare(denominator) < 0 {
    return Ok((Coeff::zero(), self))
  }
  match (self.0, denominator.0) {
    (Inline64(numerator), Inline64(denominator)) =>
      return Ok(
        (
          Coeff::from_uint64(numerator / denominator),
          Coeff::from_uint64(numerator % denominator),
        ),
      )
    _ => ()
  }
  if bin_coeff_word_len(denominator) == 1 &&
    denominator.0 is Inline64(divisor) &&
    divisor <= 0xffff_ffffUL {
    Ok(bin_coeff_div_rem_word(self, divisor.to_uint()))
  } else if bin_coeff_word_len(denominator) >=
    bin_coeff_newton_division_min_words {
    Ok(bin_coeff_div_rem_newton(self, denominator))
  } else if bin_coeff_word_len(denominator) >= bin_coeff_bz_division_min_words {
    Ok(bin_coeff_div_rem_burnikel_ziegler(self, denominator))
  } else {
    Ok(bin_coeff_div_rem_knuth(self, denominator))
  }
}

///|
pub fn bin_coeff_short_div_rem(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  if numerator.compare(denominator) < 0 {
    return (Coeff::zero(), numerator)
  }
  match (numerator.0, denominator.0) {
    (Inline64(numerator), Inline64(denominator)) =>
      return (
        Coeff::from_uint64(numerator / denominator),
        Coeff::from_uint64(numerator % denominator),
      )
    _ => ()
  }
  if bin_coeff_word_len(denominator) == 1 &&
    denominator.0 is Inline64(divisor) &&
    divisor <= 0xffff_ffffUL {
    bin_coeff_div_rem_word(numerator, divisor.to_uint())
  } else if denominator.bit_length() > 96 {
    match bin_coeff_short_div_high_product(numerator, denominator) {
      Some(result) => result
      None => bin_coeff_div_rem_knuth(numerator, denominator)
    }
  } else {
    bin_coeff_div_rem_knuth(numerator, denominator)
  }
}

///|
pub fn Coeff::gcd(self : Coeff, other : Coeff) -> Coeff {
  if bin_coeff_word_len(self) <= 2 && bin_coeff_word_len(other) <= 2 {
    if self.is_zero() {
      return other
    }
    if other.is_zero() {
      return self
    }
    let common_shift = Int32::min(self.ctz(), other.ctz())
    let mut left = self.shift_right(self.ctz())
    let mut right = other.shift_right(other.ctz())
    while left != right {
      if left.compare(right) > 0 {
        left = left.sub_checked(right).unwrap()
        left = left.shift_right(left.ctz())
      } else {
        right = right.sub_checked(left).unwrap()
        right = right.shift_right(right.ctz())
      }
    }
    return left.shift_left(common_shift)
  }
  bin_coeff_gcd_lehmer(self, other)
}

///|
pub fn Coeff::pow_nat(self : Coeff, exponent : UInt32) -> Coeff {
  if exponent == 0U {
    return Coeff::one()
  }
  let mut result = self
  let mut bit_index = 30 - exponent.clz()
  while bit_index >= 0 {
    result = result.square()
    if (exponent & (1U << bit_index)) != 0U {
      result = result.mul(self)
    }
    bit_index -= 1
  }
  result
}

///|
fn bin_coeff_digit(character : Int32) -> Int32 {
  match character {
    '0'..<='9' => character - '0'
    'A'..<='Z' => character + (10 - 'A')
    'a'..<='z' => character + (10 - 'a')
    _ => -1
  }
}

///|
fn bin_coeff_digit_char(digit : Int32) -> Char {
  if digit < 10 {
    Int32::unsafe_to_char('0'.to_int() + digit)
  } else {
    Int32::unsafe_to_char('a'.to_int() + digit - 10)
  }
}

///|
fn bin_coeff_mul_small(value : Coeff, multiplier : UInt32) -> Coeff {
  if multiplier == 0U || value.is_zero() {
    return Coeff::zero()
  }
  if multiplier == 1U {
    return value
  }
  match value.0 {
    Inline64(value) => return bin_coeff_mul_u64(value, multiplier.to_uint64())
    _ => ()
  }
  let len = bin_coeff_word_len(value)
  let words = FixedArray::make(len + 1, 0UL)
  for index in 0..<len {
    words.unsafe_set(index, bin_coeff_word(value, index))
  }
  let new_len = bin_coeff_words_mul_add_small_in_place(
    words,
    len,
    multiplier.to_uint64(),
    0UL,
  )
  bin_coeff_from_words(words, new_len)
}

///|
fn bin_coeff_radix_shift(radix : Int32) -> Int32? {
  if radix >= 2 && (radix & (radix - 1)) == 0 {
    Some(radix.ctz())
  } else {
    None
  }
}

///|
fn bin_coeff_radix_chunk(radix : Int32) -> (Int32, UInt32) {
  let radix64 = radix.to_uint64()
  let mut width = 1
  let mut power = radix64
  while power <= 0xffff_ffffUL / radix64 {
    power *= radix64
    width += 1
  }
  (width, power.to_uint())
}

///|
fn bin_coeff_parse_power_of_two(
  source : String,
  start : Int32,
  radix : Int32,
  digit_bits : Int32,
) -> Result[Coeff, String] {
  let digit_count = source.length() - start
  let words = FixedArray::make(
    Int32::max((digit_count * digit_bits + 63) / 64, 1),
    0UL,
  )
  for source_index in start..<source.length() {
    let digit = bin_coeff_digit(source.unsafe_get(source_index).to_int())
    if digit < 0 || digit >= radix {
      return Err("Coeff contains a digit outside the selected radix")
    }
    let reverse_index = source.length() - 1 - source_index
    let bit_offset = reverse_index * digit_bits
    let word_index = bit_offset / 64
    let shift = bit_offset % 64
    let digit64 = digit.to_uint64()
    words.unsafe_set(
      word_index,
      words.unsafe_get(word_index) | (digit64 << shift),
    )
    if shift + digit_bits > 64 {
      words.unsafe_set(
        word_index + 1,
        words.unsafe_get(word_index + 1) | (digit64 >> (64 - shift)),
      )
    }
  }
  Ok(bin_coeff_from_words(words, words.length()))
}

///|
priv struct CoeffRadixSegment {
  value : Coeff
  power : Coeff
}

///|
fn bin_coeff_parse_chunks_divide_and_conquer(
  chunks : FixedArray[UInt32],
  start : Int32,
  len : Int32,
  chunk_power : UInt32,
) -> CoeffRadixSegment {
  if len <= 32 {
    let mut value = Coeff::zero()
    let mut power = Coeff::one()
    for index in start..<(start + len) {
      value = bin_coeff_mul_small(value, chunk_power).add(
        Coeff::from_uint64(chunks.unsafe_get(index).to_uint64()),
      )
      power = bin_coeff_mul_small(power, chunk_power)
    }
    return { value, power, }
  }
  let left_len = len / 2
  let right_len = len - left_len
  let left = bin_coeff_parse_chunks_divide_and_conquer(
    chunks, start, left_len, chunk_power,
  )
  let right = bin_coeff_parse_chunks_divide_and_conquer(
    chunks,
    start + left_len,
    right_len,
    chunk_power,
  )
  {
    value: left.value.mul(right.power).add(right.value),
    power: left.power.mul(right.power),
  }
}

///|
pub fn Coeff::parse(
  source : String,
  radix~ : Int32 = 10,
) -> Result[Coeff, String] {
  if radix < 2 || radix > 36 {
    return Err("Coeff radix must be between 2 and 36")
  }
  if source.length() == 0 {
    return Err("Coeff cannot parse an empty string")
  }
  let start = if source.unsafe_get(0) == '+' { 1 } else { 0 }
  if start == source.length() {
    return Err("Coeff requires at least one digit")
  }
  if source.unsafe_get(0) == '-' {
    return Err("Coeff cannot be negative")
  }
  match bin_coeff_radix_shift(radix) {
    Some(digit_bits) =>
      return bin_coeff_parse_power_of_two(source, start, radix, digit_bits)
    None => ()
  }
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  let chunks = match
    bin_coeff_parse_radix_chunks(source, start, radix, chunk_width) {
    Ok(chunks) => chunks
    Err(message) => return Err(message)
  }
  if chunks.length() >= bin_coeff_radix_parse_dc_chunks {
    Ok(
      bin_coeff_parse_chunks_divide_and_conquer(
        chunks,
        0,
        chunks.length(),
        chunk_power,
      ).value,
    )
  } else {
    Ok(bin_coeff_parse_chunks_in_place(chunks, chunk_power))
  }
}

///|
pub fn Coeff::from_bytes_be(source : BytesView) -> Coeff {
  if source.length() == 0 {
    return Coeff::zero()
  }
  let len = (source.length() + 7) / 8
  let words = FixedArray::make(len, 0UL)
  for offset in 0..<source.length() {
    let source_index = source.length() - 1 - offset
    let word_index = offset / 8
    let shift = offset % 8 * 8
    words.unsafe_set(
      word_index,
      words.unsafe_get(word_index) |
      (source.unsafe_get(source_index).to_uint64() << shift),
    )
  }
  bin_coeff_from_words(words, len)
}

///|
pub fn Coeff::to_bytes_be(self : Coeff) -> Bytes {
  if self.is_zero() {
    return Bytes::make(1, 0)
  }
  let byte_len = (self.bit_length() + 7) / 8
  Bytes::makei(byte_len, index => {
    let offset = byte_len - 1 - index
    let word = bin_coeff_word(self, offset / 8)
    ((word >> (offset % 8 * 8)) & 0xffUL).to_int().to_byte()
  })
}

///|
fn bin_coeff_to_string_power_of_two(
  value : Coeff,
  digit_bits : Int32,
) -> String {
  let digit_count = (value.bit_length() + digit_bits - 1) / digit_bits
  let mask = (1UL << digit_bits) - 1UL
  let builder = StringBuilder()
  let mut digit_index = digit_count - 1
  while true {
    let bit_offset = digit_index * digit_bits
    let word_index = bit_offset / 64
    let shift = bit_offset % 64
    let mut digit = bin_coeff_word(value, word_index) >> shift
    if shift + digit_bits > 64 {
      digit = digit | (bin_coeff_word(value, word_index + 1) << (64 - shift))
    }
    builder.write_char(bin_coeff_digit_char((digit & mask).to_int()))
    if digit_index == 0 {
      break
    }
    digit_index -= 1
  }
  builder.to_string()
}

///|
fn bin_coeff_format_chunks_divide_and_conquer(
  value : Coeff,
  powers : Array[Coeff],
  level : Int32,
  padded : Bool,
  chunks : Array[UInt64],
) -> Unit {
  if level == 0 {
    chunks.push(value.to_uint64().unwrap())
    return
  }
  let divisor = powers[level - 1]
  if !padded && value.compare(divisor) < 0 {
    bin_coeff_format_chunks_divide_and_conquer(
      value,
      powers,
      level - 1,
      false,
      chunks,
    )
    return
  }
  let (quotient, remainder) = value.div_rem_checked(divisor).unwrap()
  bin_coeff_format_chunks_divide_and_conquer(
    quotient,
    powers,
    level - 1,
    padded,
    chunks,
  )
  bin_coeff_format_chunks_divide_and_conquer(
    remainder,
    powers,
    level - 1,
    true,
    chunks,
  )
}

///|
pub fn Coeff::to_radix_string(self : Coeff, radix : Int32) -> String {
  if radix < 2 || radix > 36 {
    abort("Coeff radix must be between 2 and 36")
  }
  if self.is_zero() {
    return "0"
  }
  match bin_coeff_radix_shift(radix) {
    Some(digit_bits) =>
      return bin_coeff_to_string_power_of_two(self, digit_bits)
    None => ()
  }
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  if bin_coeff_word_len(self) >= bin_coeff_radix_format_dc_words {
    bin_coeff_to_radix_divide_and_conquer(self, radix, chunk_width, chunk_power)
  } else {
    bin_coeff_to_radix_in_place(self, radix, chunk_width, chunk_power)
  }
}

///|
pub impl Eq for Coeff with fn equal(self, other) {
  self.compare(other) == 0
}

///|
pub impl Compare for Coeff with fn compare(self, other) {
  Coeff::compare(self, other)
}

///|
pub impl Show for Coeff with fn to_string(self) {
  self.to_radix_string(10)
}

///|
pub extend Coeff with Show::{to_string}

///|
pub impl Add for Coeff with fn add(self, other) {
  Coeff::add(self, other)
}

///|
pub impl Mul for Coeff with fn mul(self, other) {
  Coeff::mul(self, other)
}

///|
pub impl Shl for Coeff with fn shl(self, shift) {
  self.shift_left(shift)
}

///|
pub impl Shr for Coeff with fn shr(self, shift) {
  self.shift_right(shift)
}

///|
pub extend Coeff with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Coeff with Eq::{not_equal, equal}

///|
pub extend Coeff with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend Coeff with Show::{output}

///|
pub extend Coeff with Shl::{shl}

///|
pub extend Coeff with Shr::{shr}
