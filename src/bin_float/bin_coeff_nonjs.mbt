///|
priv enum BinCoeffRepr {
  Inline64(UInt64)
  Inline128(UInt64, UInt64)
  Heap(FixedArray[UInt], Int)
} derive(Debug)

///|
pub struct BinCoeff {
  priv repr : BinCoeffRepr
} derive(Debug)

///|
let bin_coeff_limb_bits = 32

///|
let bin_coeff_limb_mask = 0xffff_ffffUL

///|
let bin_coeff_limb_base = 0x1_0000_0000UL

///|
fn bin_coeff_u64_bits(value : UInt64) -> Int {
  if value == 0UL {
    0
  } else {
    64 - value.reinterpret_as_int64().clz()
  }
}

///|
fn bin_coeff_inline(high : UInt64, low : UInt64) -> BinCoeff {
  if high == 0UL {
    { repr: Inline64(low) }
  } else {
    { repr: Inline128(high, low) }
  }
}

///|
fn bin_coeff_limb_len(value : BinCoeff) -> Int {
  match value.repr {
    Inline64(value) => if value >> 32 == 0UL { 1 } else { 2 }
    Inline128(high, _) => if high >> 32 == 0UL { 3 } else { 4 }
    Heap(_, len) => len
  }
}

///|
fn bin_coeff_limb(value : BinCoeff, index : Int) -> UInt {
  match value.repr {
    Inline64(low) =>
      match index {
        0 => (low & bin_coeff_limb_mask).to_uint()
        1 => (low >> 32).to_uint()
        _ => 0U
      }
    Inline128(high, low) =>
      match index {
        0 => (low & bin_coeff_limb_mask).to_uint()
        1 => (low >> 32).to_uint()
        2 => (high & bin_coeff_limb_mask).to_uint()
        3 => (high >> 32).to_uint()
        _ => 0U
      }
    Heap(limbs, len) =>
      if index >= 0 && index < len {
        limbs.unsafe_get(index)
      } else {
        0U
      }
  }
}

///|
fn bin_coeff_from_limbs(
  limbs : FixedArray[UInt],
  maximum_len : Int,
) -> BinCoeff {
  let mut len = maximum_len
  while len > 1 && limbs.unsafe_get(len - 1) == 0U {
    len -= 1
  }
  if len <= 0 || (len == 1 && limbs.unsafe_get(0) == 0U) {
    return BinCoeff::zero()
  }
  if len <= 2 {
    let low = limbs.unsafe_get(0).to_uint64()
    let high = if len == 2 {
      limbs.unsafe_get(1).to_uint64() << 32
    } else {
      0UL
    }
    return { repr: Inline64(high | low) }
  }
  if len <= 4 {
    let low = limbs.unsafe_get(0).to_uint64() |
      (limbs.unsafe_get(1).to_uint64() << 32)
    let high = limbs.unsafe_get(2).to_uint64() |
      (if len == 4 { limbs.unsafe_get(3).to_uint64() << 32 } else { 0UL })
    return bin_coeff_inline(high, low)
  }
  { repr: Heap(limbs, len) }
}

///|
pub fn BinCoeff::zero() -> BinCoeff {
  { repr: Inline64(0UL) }
}

///|
pub fn BinCoeff::one() -> BinCoeff {
  { repr: Inline64(1UL) }
}

///|
pub fn BinCoeff::from_uint64(value : UInt64) -> BinCoeff {
  { repr: Inline64(value) }
}

///|
pub fn BinCoeff::is_zero(self : BinCoeff) -> Bool {
  match self.repr {
    Inline64(value) => value == 0UL
    Inline128(_, _) | Heap(_, _) => false
  }
}

///|
fn BinCoeff::is_odd(self : BinCoeff) -> Bool {
  (bin_coeff_limb(self, 0) & 1U) != 0U
}

///|
pub fn BinCoeff::bit_length(self : BinCoeff) -> Int {
  match self.repr {
    Inline64(value) => bin_coeff_u64_bits(value)
    Inline128(high, _) => 64 + bin_coeff_u64_bits(high)
    Heap(limbs, len) =>
      (len - 1) * bin_coeff_limb_bits +
      (bin_coeff_limb_bits - limbs.unsafe_get(len - 1).clz())
  }
}

///|
pub fn BinCoeff::ctz(self : BinCoeff) -> Int {
  match self.repr {
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
    Heap(limbs, len) => {
      let mut index = 0
      while index < len && limbs.unsafe_get(index) == 0U {
        index += 1
      }
      if index == len {
        0
      } else {
        index * bin_coeff_limb_bits + limbs.unsafe_get(index).ctz()
      }
    }
  }
}

///|
pub fn BinCoeff::to_uint64(self : BinCoeff) -> UInt64? {
  match self.repr {
    Inline64(value) => Some(value)
    Inline128(_, _) | Heap(_, _) => None
  }
}

///|
pub fn BinCoeff::test_bit(self : BinCoeff, index : Int) -> Bool {
  if index < 0 || index >= self.bit_length() {
    return false
  }
  let limb = bin_coeff_limb(self, index / bin_coeff_limb_bits)
  (limb & (1U << (index % bin_coeff_limb_bits))) != 0U
}

///|
pub fn BinCoeff::compare(self : BinCoeff, other : BinCoeff) -> Int {
  let self_len = bin_coeff_limb_len(self)
  let other_len = bin_coeff_limb_len(other)
  if self_len != other_len {
    return if self_len < other_len { -1 } else { 1 }
  }
  let mut index = self_len - 1
  while true {
    let left = bin_coeff_limb(self, index)
    let right = bin_coeff_limb(other, index)
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

///|
fn bin_coeff_add_heap(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  match (left.repr, right.repr) {
    (Heap(left_limbs, left_len), Heap(right_limbs, right_len)) => {
      let len = Int::max(left_len, right_len)
      let limbs = FixedArray::make(len + 1, 0U)
      let mut carry = 0UL
      for index in 0..<len {
        let left_value = if index < left_len {
          left_limbs.unsafe_get(index).to_uint64()
        } else {
          0UL
        }
        let right_value = if index < right_len {
          right_limbs.unsafe_get(index).to_uint64()
        } else {
          0UL
        }
        let sum = left_value + right_value + carry
        limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
        carry = sum >> bin_coeff_limb_bits
      }
      limbs.unsafe_set(len, carry.to_uint())
      return bin_coeff_from_limbs(limbs, len + 1)
    }
    _ => ()
  }
  let left_len = bin_coeff_limb_len(left)
  let right_len = bin_coeff_limb_len(right)
  let len = Int::max(left_len, right_len)
  let limbs = FixedArray::make(len + 1, 0U)
  let mut carry = 0UL
  for index in 0..<len {
    let sum = bin_coeff_limb(left, index).to_uint64() +
      bin_coeff_limb(right, index).to_uint64() +
      carry
    limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> bin_coeff_limb_bits
  }
  limbs.unsafe_set(len, carry.to_uint())
  bin_coeff_from_limbs(limbs, len + 1)
}

///|
pub fn BinCoeff::add(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  match (self.repr, other.repr) {
    (Inline64(left), Inline64(right)) => {
      let low = left + right
      if low >= left {
        { repr: Inline64(low) }
      } else {
        { repr: Inline128(1UL, low) }
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
fn bin_coeff_add_normalized_odd(
  left : BinCoeff,
  right : BinCoeff,
) -> (BinCoeff, Int) {
  match (left.repr, right.repr) {
    (Heap(left_limbs, left_len), Heap(right_limbs, right_len)) => {
      let len = Int::max(left_len, right_len)
      let limbs = FixedArray::make(len + 1, 0U)
      let mut carry = 0UL
      for index in 0..<len {
        let left_value = if index < left_len {
          left_limbs.unsafe_get(index).to_uint64()
        } else {
          0UL
        }
        let right_value = if index < right_len {
          right_limbs.unsafe_get(index).to_uint64()
        } else {
          0UL
        }
        let sum = left_value + right_value + carry
        limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
        carry = sum >> bin_coeff_limb_bits
      }
      limbs.unsafe_set(len, carry.to_uint())
      let mut first_nonzero = 0
      while limbs.unsafe_get(first_nonzero) == 0U {
        first_nonzero += 1
      }
      let bit_shift = limbs.unsafe_get(first_nonzero).ctz()
      let normalization_shift = first_nonzero * bin_coeff_limb_bits + bit_shift
      if normalization_shift == 0 {
        return (bin_coeff_from_limbs(limbs, len + 1), 0)
      }
      let output_len = len + 1 - first_nonzero
      for output_index in 0..<output_len {
        let source_index = output_index + first_nonzero
        let mut limb = limbs.unsafe_get(source_index).to_uint64() >> bit_shift
        if bit_shift != 0 && source_index + 1 <= len {
          limb = limb |
            (
              limbs.unsafe_get(source_index + 1).to_uint64() <<
              (bin_coeff_limb_bits - bit_shift)
            )
        }
        limbs.unsafe_set(output_index, (limb & bin_coeff_limb_mask).to_uint())
      }
      return (bin_coeff_from_limbs(limbs, output_len), normalization_shift)
    }
    _ => ()
  }
  let sum = left.add(right)
  let normalization_shift = sum.ctz()
  (sum.shift_right(normalization_shift), normalization_shift)
}

///|
fn bin_coeff_sub_unchecked(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  match (left.repr, right.repr) {
    (Inline64(left), Inline64(right)) => return { repr: Inline64(left - right) }
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
  match (left.repr, right.repr) {
    (Heap(left_limbs, left_len), Heap(right_limbs, right_len)) => {
      let limbs = FixedArray::make(left_len, 0U)
      let mut borrow = 0UL
      for index in 0..<left_len {
        let minuend = left_limbs.unsafe_get(index).to_uint64()
        let subtrahend = if index < right_len {
          right_limbs.unsafe_get(index).to_uint64() + borrow
        } else {
          borrow
        }
        if minuend < subtrahend {
          limbs.unsafe_set(
            index,
            (minuend + bin_coeff_limb_base - subtrahend).to_uint(),
          )
          borrow = 1UL
        } else {
          limbs.unsafe_set(index, (minuend - subtrahend).to_uint())
          borrow = 0UL
        }
      }
      return bin_coeff_from_limbs(limbs, left_len)
    }
    _ => ()
  }
  let left_len = bin_coeff_limb_len(left)
  let right_len = bin_coeff_limb_len(right)
  let limbs = FixedArray::make(left_len, 0U)
  let mut borrow = 0UL
  for index in 0..<left_len {
    let minuend = bin_coeff_limb(left, index).to_uint64()
    let subtrahend = if index < right_len {
      bin_coeff_limb(right, index).to_uint64() + borrow
    } else {
      borrow
    }
    if minuend < subtrahend {
      limbs.unsafe_set(
        index,
        (minuend + bin_coeff_limb_base - subtrahend).to_uint(),
      )
      borrow = 1UL
    } else {
      limbs.unsafe_set(index, (minuend - subtrahend).to_uint())
      borrow = 0UL
    }
  }
  bin_coeff_from_limbs(limbs, left_len)
}

///|
fn bin_coeff_sub_normalized_odd(
  left : BinCoeff,
  right : BinCoeff,
) -> (BinCoeff, Int) {
  match (left.repr, right.repr) {
    (Heap(left_limbs, left_len), Heap(right_limbs, right_len)) => {
      let limbs = FixedArray::make(left_len, 0U)
      let mut borrow = 0UL
      for index in 0..<left_len {
        let minuend = left_limbs.unsafe_get(index).to_uint64()
        let subtrahend = if index < right_len {
          right_limbs.unsafe_get(index).to_uint64() + borrow
        } else {
          borrow
        }
        if minuend < subtrahend {
          limbs.unsafe_set(
            index,
            (minuend + bin_coeff_limb_base - subtrahend).to_uint(),
          )
          borrow = 1UL
        } else {
          limbs.unsafe_set(index, (minuend - subtrahend).to_uint())
          borrow = 0UL
        }
      }
      let mut first_nonzero = 0
      while limbs.unsafe_get(first_nonzero) == 0U {
        first_nonzero += 1
      }
      let bit_shift = limbs.unsafe_get(first_nonzero).ctz()
      let normalization_shift = first_nonzero * bin_coeff_limb_bits + bit_shift
      if normalization_shift == 0 {
        return (bin_coeff_from_limbs(limbs, left_len), 0)
      }
      let output_len = left_len - first_nonzero
      for output_index in 0..<output_len {
        let source_index = output_index + first_nonzero
        let mut limb = limbs.unsafe_get(source_index).to_uint64() >> bit_shift
        if bit_shift != 0 && source_index + 1 < left_len {
          limb = limb |
            (
              limbs.unsafe_get(source_index + 1).to_uint64() <<
              (bin_coeff_limb_bits - bit_shift)
            )
        }
        limbs.unsafe_set(output_index, (limb & bin_coeff_limb_mask).to_uint())
      }
      return (bin_coeff_from_limbs(limbs, output_len), normalization_shift)
    }
    _ => ()
  }
  let difference = bin_coeff_sub_unchecked(left, right)
  let normalization_shift = difference.ctz()
  (difference.shift_right(normalization_shift), normalization_shift)
}

///|
pub fn BinCoeff::sub_checked(
  self : BinCoeff,
  other : BinCoeff,
) -> Result[BinCoeff, String] {
  if self.compare(other) < 0 {
    Err("BinCoeff subtraction would be negative")
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
fn bin_coeff_mul_u64(left : UInt64, right : UInt64) -> BinCoeff {
  if left == 0UL || right == 0UL {
    return BinCoeff::zero()
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
) -> BinCoeff {
  if word3 == 0UL && word2 == 0UL {
    return bin_coeff_inline(word1, word0)
  }
  let limbs = FixedArray::make(8, 0U)
  limbs.unsafe_set(0, (word0 & bin_coeff_limb_mask).to_uint())
  limbs.unsafe_set(1, (word0 >> 32).to_uint())
  limbs.unsafe_set(2, (word1 & bin_coeff_limb_mask).to_uint())
  limbs.unsafe_set(3, (word1 >> 32).to_uint())
  limbs.unsafe_set(4, (word2 & bin_coeff_limb_mask).to_uint())
  limbs.unsafe_set(5, (word2 >> 32).to_uint())
  limbs.unsafe_set(6, (word3 & bin_coeff_limb_mask).to_uint())
  limbs.unsafe_set(7, (word3 >> 32).to_uint())
  bin_coeff_from_limbs(limbs, 8)
}

///|
fn bin_coeff_mul_inline_128(
  left_high : UInt64,
  left_low : UInt64,
  right_high : UInt64,
  right_low : UInt64,
) -> BinCoeff {
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
fn bin_coeff_mul_schoolbook(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  match (left.repr, right.repr) {
    (Heap(left_limbs, left_len), Heap(right_limbs, right_len)) => {
      let limbs = FixedArray::make(left_len + right_len, 0U)
      for left_index in 0..<left_len {
        let left_limb = left_limbs.unsafe_get(left_index).to_uint64()
        let mut carry = 0UL
        for right_index in 0..<right_len {
          let index = left_index + right_index
          let product = limbs.unsafe_get(index).to_uint64() +
            left_limb * right_limbs.unsafe_get(right_index).to_uint64() +
            carry
          limbs.unsafe_set(index, (product & bin_coeff_limb_mask).to_uint())
          carry = product >> bin_coeff_limb_bits
        }
        limbs.unsafe_set(left_index + right_len, carry.to_uint())
      }
      return bin_coeff_from_limbs(limbs, left_len + right_len)
    }
    _ => ()
  }
  let left_len = bin_coeff_limb_len(left)
  let right_len = bin_coeff_limb_len(right)
  let limbs = FixedArray::make(left_len + right_len, 0U)
  for left_index in 0..<left_len {
    let left_limb = bin_coeff_limb(left, left_index).to_uint64()
    let mut carry = 0UL
    for right_index in 0..<right_len {
      let index = left_index + right_index
      let product = limbs.unsafe_get(index).to_uint64() +
        left_limb * bin_coeff_limb(right, right_index).to_uint64() +
        carry
      limbs.unsafe_set(index, (product & bin_coeff_limb_mask).to_uint())
      carry = product >> bin_coeff_limb_bits
    }
    limbs.unsafe_set(left_index + right_len, carry.to_uint())
  }
  bin_coeff_from_limbs(limbs, left_len + right_len)
}

///|
fn bin_coeff_nonzero_limb_count_limited(value : BinCoeff, limit : Int) -> Int? {
  match value.repr {
    Heap(limbs, len) => {
      let mut count = 0
      for index in 0..<len {
        if limbs.unsafe_get(index) != 0U {
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
fn bin_coeff_sparse_positions(value : BinCoeff, count : Int) -> FixedArray[Int] {
  let positions = FixedArray::make(count, 0)
  match value.repr {
    Heap(limbs, len) => {
      let mut position_index = 0
      for index in 0..<len {
        if limbs.unsafe_get(index) != 0U {
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
  left : BinCoeff,
  right : BinCoeff,
  left_count : Int,
  right_count : Int,
) -> BinCoeff {
  let left_len = bin_coeff_limb_len(left)
  let right_len = bin_coeff_limb_len(right)
  let left_positions = bin_coeff_sparse_positions(left, left_count)
  let right_positions = bin_coeff_sparse_positions(right, right_count)
  let limbs = FixedArray::make(left_len + right_len, 0U)
  for left_position_index in 0..<left_count {
    let left_index = left_positions.unsafe_get(left_position_index)
    let left_limb = bin_coeff_limb(left, left_index).to_uint64()
    for right_position_index in 0..<right_count {
      let right_index = right_positions.unsafe_get(right_position_index)
      bin_coeff_add_product_at(
        limbs,
        left_len + right_len,
        left_index + right_index,
        left_limb * bin_coeff_limb(right, right_index).to_uint64(),
      )
    }
  }
  bin_coeff_from_limbs(limbs, left_len + right_len)
}

///|
fn bin_coeff_add_product_at(
  limbs : FixedArray[UInt],
  len : Int,
  offset : Int,
  product : UInt64,
) -> Unit {
  let low_sum = limbs.unsafe_get(offset).to_uint64() +
    (product & bin_coeff_limb_mask)
  limbs.unsafe_set(offset, (low_sum & bin_coeff_limb_mask).to_uint())
  let high_sum = limbs.unsafe_get(offset + 1).to_uint64() +
    (product >> bin_coeff_limb_bits) +
    (low_sum >> bin_coeff_limb_bits)
  limbs.unsafe_set(offset + 1, (high_sum & bin_coeff_limb_mask).to_uint())
  let mut carry = high_sum >> bin_coeff_limb_bits
  let mut index = offset + 2
  while carry != 0UL && index < len {
    let sum = limbs.unsafe_get(index).to_uint64() + carry
    limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> bin_coeff_limb_bits
    index += 1
  }
  guard carry == 0UL else { abort("BinCoeff square carry exceeded its output") }
}

///|
fn bin_coeff_add_limb_at(
  limbs : FixedArray[UInt],
  len : Int,
  offset : Int,
  value : UInt64,
) -> Unit {
  let mut carry = value
  let mut index = offset
  while carry != 0UL && index < len {
    let sum = limbs.unsafe_get(index).to_uint64() + carry
    limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> bin_coeff_limb_bits
    index += 1
  }
  guard carry == 0UL else { abort("BinCoeff square carry exceeded its output") }
}

///|
fn bin_coeff_square_schoolbook(value : BinCoeff) -> BinCoeff {
  let (source, source_len) = match value.repr {
    Heap(source, source_len) => (source, source_len)
    Inline64(_) | Inline128(_, _) => return value.mul(value)
  }
  let output_len = source_len * 2
  let limbs = FixedArray::make(output_len, 0U)
  for left_index in 0..<source_len {
    let left_limb = source.unsafe_get(left_index).to_uint64()
    let mut carry = 0UL
    for right_index in (left_index + 1)..<source_len {
      let offset = left_index + right_index
      let product = limbs.unsafe_get(offset).to_uint64() +
        left_limb * source.unsafe_get(right_index).to_uint64() +
        carry
      limbs.unsafe_set(offset, (product & bin_coeff_limb_mask).to_uint())
      carry = product >> bin_coeff_limb_bits
    }
    if carry != 0UL {
      bin_coeff_add_limb_at(limbs, output_len, left_index + source_len, carry)
    }
  }
  let mut double_carry = 0UL
  for index in 0..<output_len {
    let doubled = limbs.unsafe_get(index).to_uint64() * 2UL + double_carry
    limbs.unsafe_set(index, (doubled & bin_coeff_limb_mask).to_uint())
    double_carry = doubled >> bin_coeff_limb_bits
  }
  guard double_carry == 0UL else {
    abort("BinCoeff square doubling exceeded its output")
  }
  for index in 0..<source_len {
    let limb = source.unsafe_get(index).to_uint64()
    bin_coeff_add_product_at(limbs, output_len, index * 2, limb * limb)
  }
  bin_coeff_from_limbs(limbs, output_len)
}

///|
pub fn BinCoeff::mul(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  if self.is_zero() || other.is_zero() {
    return BinCoeff::zero()
  }
  match (self.repr, other.repr) {
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
  let self_len = bin_coeff_limb_len(self)
  let other_len = bin_coeff_limb_len(other)
  if self_len >= 8 && other_len >= 8 {
    let self_limit = Int::max(4, self_len / 8)
    match bin_coeff_nonzero_limb_count_limited(self, self_limit) {
      Some(self_count) => {
        let other_limit = Int::max(4, other_len / 8)
        match bin_coeff_nonzero_limb_count_limited(other, other_limit) {
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
  if Int::min(self_len, other_len) >= bin_coeff_karatsuba_threshold {
    bin_coeff_mul_large_dispatch(self, other)
  } else {
    bin_coeff_mul_schoolbook(self, other)
  }
}

///|
pub fn BinCoeff::square(self : BinCoeff) -> BinCoeff {
  let len = bin_coeff_limb_len(self)
  if len >= 32 {
    bin_coeff_square_large_dispatch(self)
  } else if len >= 8 {
    bin_coeff_square_schoolbook(self)
  } else {
    self.mul(self)
  }
}

///|
pub fn BinCoeff::shift_left(self : BinCoeff, shift : Int) -> BinCoeff {
  if shift < 0 {
    abort("BinCoeff shift count must be non-negative")
  }
  if shift == 0 || self.is_zero() {
    return self
  }
  if self.bit_length() + shift <= 128 {
    match self.repr {
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
  let source_len = bin_coeff_limb_len(self)
  let limb_shift = shift / bin_coeff_limb_bits
  let bit_shift = shift % bin_coeff_limb_bits
  let limbs = FixedArray::make(source_len + limb_shift + 1, 0U)
  let mut carry = 0UL
  for index in 0..<source_len {
    let shifted = (bin_coeff_limb(self, index).to_uint64() << bit_shift) | carry
    limbs.unsafe_set(
      index + limb_shift,
      (shifted & bin_coeff_limb_mask).to_uint(),
    )
    carry = shifted >> bin_coeff_limb_bits
  }
  limbs.unsafe_set(source_len + limb_shift, carry.to_uint())
  bin_coeff_from_limbs(limbs, source_len + limb_shift + 1)
}

///|
pub fn BinCoeff::shift_right(self : BinCoeff, shift : Int) -> BinCoeff {
  if shift < 0 {
    abort("BinCoeff shift count must be non-negative")
  }
  if shift == 0 || self.is_zero() {
    return self
  }
  match self.repr {
    Inline64(value) =>
      return { repr: Inline64(if shift >= 64 { 0UL } else { value >> shift }) }
    Inline128(high, low) => {
      if shift >= 128 {
        return BinCoeff::zero()
      }
      if shift >= 64 {
        return { repr: Inline64(high >> (shift - 64)) }
      }
      return bin_coeff_inline(
        high >> shift,
        (low >> shift) | (high << (64 - shift)),
      )
    }
    Heap(_, _) => ()
  }
  if shift >= self.bit_length() {
    return BinCoeff::zero()
  }
  let source_len = bin_coeff_limb_len(self)
  let limb_shift = shift / bin_coeff_limb_bits
  let bit_shift = shift % bin_coeff_limb_bits
  let output_len = source_len - limb_shift
  let limbs = FixedArray::make(output_len, 0U)
  for output_index in 0..<output_len {
    let source_index = output_index + limb_shift
    let mut limb = bin_coeff_limb(self, source_index).to_uint64() >> bit_shift
    if bit_shift > 0 && source_index + 1 < source_len {
      limb = limb |
        (
          bin_coeff_limb(self, source_index + 1).to_uint64() <<
          (bin_coeff_limb_bits - bit_shift)
        )
    }
    limbs.unsafe_set(output_index, (limb & bin_coeff_limb_mask).to_uint())
  }
  bin_coeff_from_limbs(limbs, output_len)
}

///|
fn bin_coeff_inline_words(value : BinCoeff) -> (UInt64, UInt64)? {
  match value.repr {
    Inline64(low) => Some((0UL, low))
    Inline128(high, low) => Some((high, low))
    Heap(_, _) => None
  }
}

///|
pub fn BinCoeff::bit_and(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high & right_high, left_low & right_low)
    _ => ()
  }
  let len = Int::min(bin_coeff_limb_len(self), bin_coeff_limb_len(other))
  let limbs = FixedArray::make(len, 0U)
  for index in 0..<len {
    limbs.unsafe_set(
      index,
      bin_coeff_limb(self, index) & bin_coeff_limb(other, index),
    )
  }
  bin_coeff_from_limbs(limbs, len)
}

///|
pub fn BinCoeff::bit_or(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high | right_high, left_low | right_low)
    _ => ()
  }
  let len = Int::max(bin_coeff_limb_len(self), bin_coeff_limb_len(other))
  let limbs = FixedArray::make(len, 0U)
  for index in 0..<len {
    limbs.unsafe_set(
      index,
      bin_coeff_limb(self, index) | bin_coeff_limb(other, index),
    )
  }
  bin_coeff_from_limbs(limbs, len)
}

///|
pub fn BinCoeff::bit_xor(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  match (bin_coeff_inline_words(self), bin_coeff_inline_words(other)) {
    (Some((left_high, left_low)), Some((right_high, right_low))) =>
      return bin_coeff_inline(left_high ^ right_high, left_low ^ right_low)
    _ => ()
  }
  let len = Int::max(bin_coeff_limb_len(self), bin_coeff_limb_len(other))
  let limbs = FixedArray::make(len, 0U)
  for index in 0..<len {
    limbs.unsafe_set(
      index,
      bin_coeff_limb(self, index) ^ bin_coeff_limb(other, index),
    )
  }
  bin_coeff_from_limbs(limbs, len)
}

///|
fn bin_coeff_div_rem_word(
  numerator : BinCoeff,
  denominator : UInt,
) -> (BinCoeff, BinCoeff) {
  let source_len = bin_coeff_limb_len(numerator)
  let quotient = FixedArray::make(source_len, 0U)
  let denominator64 = denominator.to_uint64()
  let mut remainder = 0UL
  let mut index = source_len - 1
  while true {
    let accumulated = (remainder << bin_coeff_limb_bits) |
      bin_coeff_limb(numerator, index).to_uint64()
    quotient.unsafe_set(index, (accumulated / denominator64).to_uint())
    remainder = accumulated % denominator64
    if index == 0 {
      break
    }
    index -= 1
  }
  (bin_coeff_from_limbs(quotient, source_len), BinCoeff::from_uint64(remainder))
}

///|
fn bin_coeff_div_rem_knuth(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff) {
  let numerator_len = bin_coeff_limb_len(numerator)
  let denominator_len = bin_coeff_limb_len(denominator)
  let top = bin_coeff_limb(denominator, denominator_len - 1)
  let normalization_shift = top.clz()
  let divisor = FixedArray::make(denominator_len, 0UL)
  let mut divisor_carry = 0UL
  for index in 0..<denominator_len {
    let shifted = (
        bin_coeff_limb(denominator, index).to_uint64() << normalization_shift
      ) |
      divisor_carry
    divisor.unsafe_set(index, shifted & bin_coeff_limb_mask)
    divisor_carry = shifted >> bin_coeff_limb_bits
  }
  let dividend = FixedArray::make(numerator_len + 1, 0UL)
  let mut dividend_carry = 0UL
  for index in 0..<numerator_len {
    let shifted = (
        bin_coeff_limb(numerator, index).to_uint64() << normalization_shift
      ) |
      dividend_carry
    dividend.unsafe_set(index, shifted & bin_coeff_limb_mask)
    dividend_carry = shifted >> bin_coeff_limb_bits
  }
  dividend.unsafe_set(numerator_len, dividend_carry)
  let quotient_len = numerator_len - denominator_len + 1
  let quotient = FixedArray::make(quotient_len, 0U)
  let divisor_top = divisor.unsafe_get(denominator_len - 1)
  let divisor_next = divisor.unsafe_get(denominator_len - 2)
  let mut offset = quotient_len - 1
  while true {
    let high = dividend.unsafe_get(offset + denominator_len)
    let next = dividend.unsafe_get(offset + denominator_len - 1)
    let mut trial = 0UL
    let mut trial_remainder = 0UL
    if high >= divisor_top {
      trial = bin_coeff_limb_mask
      trial_remainder = next + divisor_top
    } else {
      let trial_dividend = (high << bin_coeff_limb_bits) | next
      trial = trial_dividend / divisor_top
      trial_remainder = trial_dividend % divisor_top
    }
    let next_dividend = dividend.unsafe_get(offset + denominator_len - 2)
    while trial_remainder < bin_coeff_limb_base &&
          trial * divisor_next >
          (trial_remainder << bin_coeff_limb_bits) + next_dividend {
      trial -= 1UL
      trial_remainder += divisor_top
    }
    let mut carry = 0UL
    let mut borrow = 0UL
    for index in 0..<denominator_len {
      let product = trial * divisor.unsafe_get(index) + carry
      carry = product >> bin_coeff_limb_bits
      let low = product & bin_coeff_limb_mask
      let current = dividend.unsafe_get(offset + index)
      let subtrahend = low + borrow
      if current < subtrahend {
        dividend.unsafe_set(
          offset + index,
          current + bin_coeff_limb_base - subtrahend,
        )
        borrow = 1UL
      } else {
        dividend.unsafe_set(offset + index, current - subtrahend)
        borrow = 0UL
      }
    }
    let high_index = offset + denominator_len
    let high_subtrahend = carry + borrow
    let current_high = dividend.unsafe_get(high_index)
    let underflow = current_high < high_subtrahend
    dividend.unsafe_set(
      high_index,
      if underflow {
        current_high + bin_coeff_limb_base - high_subtrahend
      } else {
        current_high - high_subtrahend
      },
    )
    if underflow {
      trial -= 1UL
      let mut add_carry = 0UL
      for index in 0..<denominator_len {
        let sum = dividend.unsafe_get(offset + index) +
          divisor.unsafe_get(index) +
          add_carry
        dividend.unsafe_set(offset + index, sum & bin_coeff_limb_mask)
        add_carry = sum >> bin_coeff_limb_bits
      }
      dividend.unsafe_set(
        high_index,
        (dividend.unsafe_get(high_index) + add_carry) & bin_coeff_limb_mask,
      )
    }
    quotient.unsafe_set(offset, trial.to_uint())
    if offset == 0 {
      break
    }
    offset -= 1
  }
  let remainder_limbs = FixedArray::make(denominator_len, 0U)
  if normalization_shift == 0 {
    for index in 0..<denominator_len {
      remainder_limbs.unsafe_set(index, dividend.unsafe_get(index).to_uint())
    }
  } else {
    for index in 0..<denominator_len {
      let mut limb = dividend.unsafe_get(index) >> normalization_shift
      if index + 1 < denominator_len {
        limb = limb |
          (
            dividend.unsafe_get(index + 1) <<
            (bin_coeff_limb_bits - normalization_shift)
          )
      }
      remainder_limbs.unsafe_set(index, (limb & bin_coeff_limb_mask).to_uint())
    }
  }
  (
    bin_coeff_from_limbs(quotient, quotient_len),
    bin_coeff_from_limbs(remainder_limbs, denominator_len),
  )
}

///|
pub fn BinCoeff::div_rem_checked(
  self : BinCoeff,
  denominator : BinCoeff,
) -> Result[(BinCoeff, BinCoeff), String] {
  if denominator.is_zero() {
    return Err("BinCoeff division by zero")
  }
  if self.compare(denominator) < 0 {
    return Ok((BinCoeff::zero(), self))
  }
  match (self.repr, denominator.repr) {
    (Inline64(numerator), Inline64(denominator)) =>
      return Ok(
        (
          BinCoeff::from_uint64(numerator / denominator),
          BinCoeff::from_uint64(numerator % denominator),
        ),
      )
    _ => ()
  }
  if bin_coeff_limb_len(denominator) == 1 {
    Ok(bin_coeff_div_rem_word(self, bin_coeff_limb(denominator, 0)))
  } else if bin_coeff_limb_len(denominator) >= 1024 {
    Ok(bin_coeff_div_rem_newton(self, denominator))
  } else if bin_coeff_limb_len(denominator) >= 48 {
    Ok(bin_coeff_div_rem_burnikel_ziegler(self, denominator))
  } else {
    Ok(bin_coeff_div_rem_knuth(self, denominator))
  }
}

///|
fn bin_coeff_short_div_rem(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff) {
  if numerator.compare(denominator) < 0 {
    return (BinCoeff::zero(), numerator)
  }
  match (numerator.repr, denominator.repr) {
    (Inline64(numerator), Inline64(denominator)) =>
      return (
        BinCoeff::from_uint64(numerator / denominator),
        BinCoeff::from_uint64(numerator % denominator),
      )
    _ => ()
  }
  if bin_coeff_limb_len(denominator) == 1 {
    bin_coeff_div_rem_word(numerator, bin_coeff_limb(denominator, 0))
  } else if bin_coeff_limb_len(denominator) >= 4 {
    match bin_coeff_short_div_high_product(numerator, denominator) {
      Some(result) => result
      None => bin_coeff_div_rem_knuth(numerator, denominator)
    }
  } else {
    bin_coeff_div_rem_knuth(numerator, denominator)
  }
}

///|
pub fn BinCoeff::gcd(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  if bin_coeff_limb_len(self) <= 4 && bin_coeff_limb_len(other) <= 4 {
    if self.is_zero() {
      return other
    }
    if other.is_zero() {
      return self
    }
    let common_shift = Int::min(self.ctz(), other.ctz())
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
pub fn BinCoeff::pow_nat(self : BinCoeff, exponent : UInt) -> BinCoeff {
  if exponent == 0U {
    return BinCoeff::one()
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
fn bin_coeff_digit(character : Int) -> Int {
  match character {
    '0'..='9' => character - '0'
    'A'..='Z' => character + (10 - 'A')
    'a'..='z' => character + (10 - 'a')
    _ => -1
  }
}

///|
fn bin_coeff_digit_char(digit : Int) -> Char {
  if digit < 10 {
    Int::unsafe_to_char('0'.to_int() + digit)
  } else {
    Int::unsafe_to_char('a'.to_int() + digit - 10)
  }
}

///|
fn bin_coeff_mul_small(value : BinCoeff, multiplier : UInt) -> BinCoeff {
  if multiplier == 0U || value.is_zero() {
    return BinCoeff::zero()
  }
  if multiplier == 1U {
    return value
  }
  match value.repr {
    Inline64(value) => return bin_coeff_mul_u64(value, multiplier.to_uint64())
    _ => ()
  }
  let len = bin_coeff_limb_len(value)
  let limbs = FixedArray::make(len + 1, 0U)
  let mut carry = 0UL
  for index in 0..<len {
    let product = bin_coeff_limb(value, index).to_uint64() *
      multiplier.to_uint64() +
      carry
    limbs.unsafe_set(index, (product & bin_coeff_limb_mask).to_uint())
    carry = product >> bin_coeff_limb_bits
  }
  limbs.unsafe_set(len, carry.to_uint())
  bin_coeff_from_limbs(limbs, len + 1)
}

///|
fn bin_coeff_radix_shift(radix : Int) -> Int? {
  if radix >= 2 && (radix & (radix - 1)) == 0 {
    Some(radix.ctz())
  } else {
    None
  }
}

///|
fn bin_coeff_radix_chunk(radix : Int) -> (Int, UInt) {
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
  start : Int,
  radix : Int,
  digit_bits : Int,
) -> Result[BinCoeff, String] {
  let digit_count = source.length() - start
  let limbs = FixedArray::make((digit_count * digit_bits + 31) / 32, 0U)
  for source_index in start..<source.length() {
    let digit = bin_coeff_digit(source.unsafe_get(source_index).to_int())
    if digit < 0 || digit >= radix {
      return Err("BinCoeff contains a digit outside the selected radix")
    }
    let reverse_index = source.length() - 1 - source_index
    let bit_offset = reverse_index * digit_bits
    let limb_index = bit_offset / 32
    let shift = bit_offset % 32
    let digit64 = digit.to_uint64()
    limbs.unsafe_set(
      limb_index,
      limbs.unsafe_get(limb_index) |
      ((digit64 << shift) & bin_coeff_limb_mask).to_uint(),
    )
    if shift + digit_bits > 32 {
      limbs.unsafe_set(
        limb_index + 1,
        limbs.unsafe_get(limb_index + 1) | (digit64 >> (32 - shift)).to_uint(),
      )
    }
  }
  Ok(bin_coeff_from_limbs(limbs, limbs.length()))
}

///|
priv struct BinCoeffRadixSegment {
  value : BinCoeff
  power : BinCoeff
}

///|
fn bin_coeff_parse_chunks_divide_and_conquer(
  chunks : FixedArray[UInt],
  start : Int,
  len : Int,
  chunk_power : UInt,
) -> BinCoeffRadixSegment {
  if len <= 32 {
    let mut value = BinCoeff::zero()
    let mut power = BinCoeff::one()
    for index in start..<(start + len) {
      value = bin_coeff_mul_small(value, chunk_power).add(
        BinCoeff::from_uint64(chunks.unsafe_get(index).to_uint64()),
      )
      power = bin_coeff_mul_small(power, chunk_power)
    }
    return { value, power }
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
pub fn BinCoeff::parse(
  source : String,
  radix? : Int = 10,
) -> Result[BinCoeff, String] {
  if radix < 2 || radix > 36 {
    return Err("BinCoeff radix must be between 2 and 36")
  }
  if source.length() == 0 {
    return Err("BinCoeff cannot parse an empty string")
  }
  let start = if source.unsafe_get(0) == '+' { 1 } else { 0 }
  if start == source.length() {
    return Err("BinCoeff requires at least one digit")
  }
  if source.unsafe_get(0) == '-' {
    return Err("BinCoeff cannot be negative")
  }
  match bin_coeff_radix_shift(radix) {
    Some(digit_bits) =>
      return bin_coeff_parse_power_of_two(source, start, radix, digit_bits)
    None => ()
  }
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  let digit_count = source.length() - start
  let chunk_count = (digit_count + chunk_width - 1) / chunk_width
  let mut width = digit_count % chunk_width
  if width == 0 {
    width = chunk_width
  }
  let mut index = start
  if chunk_count >= 64 {
    let chunks = FixedArray::make(chunk_count, 0U)
    let mut chunk_index = 0
    while index < source.length() {
      let end = index + width
      let mut chunk = 0UL
      while index < end {
        let digit = bin_coeff_digit(source.unsafe_get(index).to_int())
        if digit < 0 || digit >= radix {
          return Err("BinCoeff contains a digit outside the selected radix")
        }
        chunk = chunk * radix.to_uint64() + digit.to_uint64()
        index += 1
      }
      chunks.unsafe_set(chunk_index, chunk.to_uint())
      chunk_index += 1
      width = chunk_width
    }
    return Ok(
      bin_coeff_parse_chunks_divide_and_conquer(
        chunks, 0, chunk_count, chunk_power,
      ).value,
    )
  }
  let mut value = BinCoeff::zero()
  while index < source.length() {
    let end = index + width
    let mut chunk = 0UL
    while index < end {
      let digit = bin_coeff_digit(source.unsafe_get(index).to_int())
      if digit < 0 || digit >= radix {
        return Err("BinCoeff contains a digit outside the selected radix")
      }
      chunk = chunk * radix.to_uint64() + digit.to_uint64()
      index += 1
    }
    value = bin_coeff_mul_small(value, chunk_power).add(
      BinCoeff::from_uint64(chunk),
    )
    width = chunk_width
  }
  Ok(value)
}

///|
pub fn BinCoeff::from_bytes_be(source : BytesView) -> BinCoeff {
  if source.length() == 0 {
    return BinCoeff::zero()
  }
  let len = (source.length() + 3) / 4
  let limbs = FixedArray::make(len, 0U)
  for offset in 0..<source.length() {
    let source_index = source.length() - 1 - offset
    let limb_index = offset / 4
    let shift = offset % 4 * 8
    limbs.unsafe_set(
      limb_index,
      limbs.unsafe_get(limb_index) |
      (source.unsafe_get(source_index).to_uint() << shift),
    )
  }
  bin_coeff_from_limbs(limbs, len)
}

///|
pub fn BinCoeff::to_bytes_be(self : BinCoeff) -> Bytes {
  if self.is_zero() {
    return Bytes::make(1, 0)
  }
  let byte_len = (self.bit_length() + 7) / 8
  Bytes::makei(byte_len, index => {
    let offset = byte_len - 1 - index
    let limb = bin_coeff_limb(self, offset / 4)
    ((limb >> (offset % 4 * 8)) & 0xffU).reinterpret_as_int().to_byte()
  })
}

///|
fn bin_coeff_to_string_power_of_two(
  value : BinCoeff,
  digit_bits : Int,
) -> String {
  let digit_count = (value.bit_length() + digit_bits - 1) / digit_bits
  let mask = (1U << digit_bits) - 1U
  let builder = StringBuilder::new()
  let mut digit_index = digit_count - 1
  while true {
    let bit_offset = digit_index * digit_bits
    let limb_index = bit_offset / 32
    let shift = bit_offset % 32
    let mut digit = bin_coeff_limb(value, limb_index).to_uint64() >> shift
    if shift + digit_bits > 32 {
      digit = digit |
        (bin_coeff_limb(value, limb_index + 1).to_uint64() << (32 - shift))
    }
    builder.write_char(
      bin_coeff_digit_char((digit.to_uint() & mask).reinterpret_as_int()),
    )
    if digit_index == 0 {
      break
    }
    digit_index -= 1
  }
  builder.to_string()
}

///|
fn bin_coeff_format_chunks_divide_and_conquer(
  value : BinCoeff,
  powers : Array[BinCoeff],
  level : Int,
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
fn bin_coeff_small_chunk_string(
  value : UInt64,
  radix : Int,
  minimum_width : Int,
) -> String {
  let digits : Array[Char] = []
  let mut value = value
  if value == 0UL {
    digits.push('0')
  } else {
    while value != 0UL {
      digits.push(bin_coeff_digit_char((value % radix.to_uint64()).to_int()))
      value /= radix.to_uint64()
    }
  }
  let builder = StringBuilder::new()
  for _ in digits.length()..<minimum_width {
    builder.write_char('0')
  }
  let mut index = digits.length() - 1
  while true {
    builder.write_char(digits[index])
    if index == 0 {
      break
    }
    index -= 1
  }
  builder.to_string()
}

///|
pub fn BinCoeff::to_string(self : BinCoeff, radix? : Int = 10) -> String {
  if radix < 2 || radix > 36 {
    abort("BinCoeff radix must be between 2 and 36")
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
  if bin_coeff_limb_len(self) >= 128 {
    let powers : Array[BinCoeff] = [
      BinCoeff::from_uint64(chunk_power.to_uint64()),
    ]
    while self.compare(powers[powers.length() - 1]) >= 0 {
      powers.push(powers[powers.length() - 1].square())
    }
    let chunks : Array[UInt64] = []
    bin_coeff_format_chunks_divide_and_conquer(
      self,
      powers,
      powers.length() - 1,
      false,
      chunks,
    )
    let builder = StringBuilder::new()
    for index in 0..<chunks.length() {
      builder.write_string(
        bin_coeff_small_chunk_string(
          chunks[index],
          radix,
          if index == 0 {
            1
          } else {
            chunk_width
          },
        ),
      )
    }
    return builder.to_string()
  }
  let chunks : Array[UInt64] = []
  let mut remaining = self
  while !remaining.is_zero() {
    let (quotient, remainder) = bin_coeff_div_rem_word(remaining, chunk_power)
    chunks.push(remainder.to_uint64().unwrap())
    remaining = quotient
  }
  let builder = StringBuilder::new()
  let mut index = chunks.length() - 1
  while true {
    builder.write_string(
      bin_coeff_small_chunk_string(
        chunks[index],
        radix,
        if index == chunks.length() - 1 {
          1
        } else {
          chunk_width
        },
      ),
    )
    if index == 0 {
      break
    }
    index -= 1
  }
  builder.to_string()
}

///|
pub impl Eq for BinCoeff with fn equal(self, other) {
  self.compare(other) == 0
}

///|
pub impl Compare for BinCoeff with fn compare(self, other) {
  BinCoeff::compare(self, other)
}

///|
pub impl Show for BinCoeff with fn to_string(self) {
  self.to_string()
}

///|
pub impl Add for BinCoeff with fn add(self, other) {
  BinCoeff::add(self, other)
}

///|
pub impl Mul for BinCoeff with fn mul(self, other) {
  BinCoeff::mul(self, other)
}

///|
pub impl Shl for BinCoeff with fn shl(self, shift) {
  self.shift_left(shift)
}

///|
pub impl Shr for BinCoeff with fn shr(self, shift) {
  self.shift_right(shift)
}
