///|
fn bin_coeff_sqrt_rem_u64(value : UInt64) -> (UInt64, UInt64) {
  if value < 2UL {
    return (value, 0UL)
  }
  let mut remainder = value
  let mut root = 0UL
  let mut bit = 1UL << 62
  while bit > remainder {
    bit = bit >> 2
  }
  while bit != 0UL {
    let candidate = root + bit
    if remainder >= candidate {
      remainder -= candidate
      root = (root >> 1) + bit
    } else {
      root = root >> 1
    }
    bit = bit >> 2
  }
  (root, remainder)
}

///|
fn bin_coeff_sqrt_rem_u128(
  value_high : UInt64,
  value_low : UInt64,
) -> (BinCoeff, BinCoeff) {
  let value = bin_coeff_inline(value_high, value_low)
  let pair_count = (value.bit_length() + 1) / 2
  let mut root = 0UL
  let mut remainder_high = 0UL
  let mut remainder_low = 0UL
  let mut pair_index = pair_count - 1
  while true {
    let bit_offset = pair_index * 2
    let pair = if bit_offset >= 64 {
      (value_high >> (bit_offset - 64)) & 3UL
    } else if bit_offset == 63 {
      ((value_high & 1UL) << 1) | (value_low >> 63)
    } else {
      (value_low >> bit_offset) & 3UL
    }
    remainder_high = (remainder_high << 2) | (remainder_low >> 62)
    remainder_low = (remainder_low << 2) | pair
    root = root << 1
    let candidate_high = root >> 63
    let candidate_low = (root << 1) | 1UL
    if remainder_high > candidate_high ||
      (remainder_high == candidate_high && remainder_low >= candidate_low) {
      let borrow = if remainder_low < candidate_low { 1UL } else { 0UL }
      remainder_low -= candidate_low
      remainder_high = remainder_high - candidate_high - borrow
      root += 1UL
    }
    if pair_index == 0 {
      break
    }
    pair_index -= 1
  }
  (BinCoeff::from_uint64(root), bin_coeff_inline(remainder_high, remainder_low))
}

///|
fn bin_coeff_sqrt_rem_u256(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  let words = FixedArray::make(4, 0UL)
  for word_index in 0..<4 {
    words.unsafe_set(
      word_index,
      bin_coeff_limb(value, word_index * 2).to_uint64() |
      (bin_coeff_limb(value, word_index * 2 + 1).to_uint64() << 32),
    )
  }
  let pair_count = (value.bit_length() + 1) / 2
  let mut root_high = 0UL
  let mut root_low = 0UL
  let mut remainder2 = 0UL
  let mut remainder1 = 0UL
  let mut remainder0 = 0UL
  let mut pair_index = pair_count - 1
  while true {
    let bit_offset = pair_index * 2
    let pair = (words.unsafe_get(bit_offset / 64) >> (bit_offset % 64)) & 3UL
    remainder2 = (remainder2 << 2) | (remainder1 >> 62)
    remainder1 = (remainder1 << 2) | (remainder0 >> 62)
    remainder0 = (remainder0 << 2) | pair
    root_high = (root_high << 1) | (root_low >> 63)
    root_low = root_low << 1
    let candidate0 = (root_low << 1) | 1UL
    let candidate1 = (root_high << 1) | (root_low >> 63)
    let candidate2 = root_high >> 63
    if remainder2 > candidate2 ||
      (
        remainder2 == candidate2 &&
        (
          remainder1 > candidate1 ||
          (remainder1 == candidate1 && remainder0 >= candidate0)
        )
      ) {
      let borrow0 = if remainder0 < candidate0 { 1UL } else { 0UL }
      remainder0 -= candidate0
      let partial1 = remainder1 - candidate1
      let borrow1 = if remainder1 < candidate1 || partial1 < borrow0 {
        1UL
      } else {
        0UL
      }
      remainder1 = partial1 - borrow0
      remainder2 = remainder2 - candidate2 - borrow1
      let next_low = root_low + 1UL
      if next_low == 0UL {
        root_high += 1UL
      }
      root_low = next_low
    }
    if pair_index == 0 {
      break
    }
    pair_index -= 1
  }
  let remainder_limbs = FixedArray::make(6, 0U)
  remainder_limbs.unsafe_set(0, (remainder0 & bin_coeff_limb_mask).to_uint())
  remainder_limbs.unsafe_set(1, (remainder0 >> 32).to_uint())
  remainder_limbs.unsafe_set(2, (remainder1 & bin_coeff_limb_mask).to_uint())
  remainder_limbs.unsafe_set(3, (remainder1 >> 32).to_uint())
  remainder_limbs.unsafe_set(4, (remainder2 & bin_coeff_limb_mask).to_uint())
  remainder_limbs.unsafe_set(5, (remainder2 >> 32).to_uint())
  (
    bin_coeff_inline(root_high, root_low),
    bin_coeff_from_limbs(remainder_limbs, 6),
  )
}

///|
fn bin_coeff_sqrt_rem_u512(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  let source = FixedArray::make(8, 0UL)
  for word_index in 0..<8 {
    source.unsafe_set(
      word_index,
      bin_coeff_limb(value, word_index * 2).to_uint64() |
      (bin_coeff_limb(value, word_index * 2 + 1).to_uint64() << 32),
    )
  }
  let root = FixedArray::make(4, 0UL)
  let remainder = FixedArray::make(5, 0UL)
  let candidate = FixedArray::make(5, 0UL)
  let pair_count = (value.bit_length() + 1) / 2
  let mut pair_index = pair_count - 1
  while true {
    let bit_offset = pair_index * 2
    let pair = (source.unsafe_get(bit_offset / 64) >> (bit_offset % 64)) & 3UL
    let mut shift_carry = pair
    for index in 0..<5 {
      let word = remainder.unsafe_get(index)
      remainder.unsafe_set(index, (word << 2) | shift_carry)
      shift_carry = word >> 62
    }
    shift_carry = 0UL
    for index in 0..<4 {
      let word = root.unsafe_get(index)
      root.unsafe_set(index, (word << 1) | shift_carry)
      shift_carry = word >> 63
    }
    let mut candidate_carry = 1UL
    for index in 0..<4 {
      let word = root.unsafe_get(index)
      candidate.unsafe_set(index, (word << 1) | candidate_carry)
      candidate_carry = word >> 63
    }
    candidate.unsafe_set(4, candidate_carry)
    let mut comparison = 0
    let mut compare_index = 4
    while true {
      let remainder_word = remainder.unsafe_get(compare_index)
      let candidate_word = candidate.unsafe_get(compare_index)
      if remainder_word != candidate_word {
        comparison = if remainder_word < candidate_word { -1 } else { 1 }
        break
      }
      if compare_index == 0 {
        break
      }
      compare_index -= 1
    }
    if comparison >= 0 {
      let mut borrow = 0UL
      for index in 0..<5 {
        let current = remainder.unsafe_get(index)
        let partial = current - candidate.unsafe_get(index)
        let next_borrow = if current < candidate.unsafe_get(index) ||
          partial < borrow {
          1UL
        } else {
          0UL
        }
        remainder.unsafe_set(index, partial - borrow)
        borrow = next_borrow
      }
      let mut increment = 1UL
      let mut index = 0
      while increment != 0UL && index < 4 {
        let word = root.unsafe_get(index) + increment
        root.unsafe_set(index, word)
        increment = if word == 0UL { 1UL } else { 0UL }
        index += 1
      }
    }
    if pair_index == 0 {
      break
    }
    pair_index -= 1
  }
  let root_limbs = FixedArray::make(8, 0U)
  for word_index in 0..<4 {
    let word = root.unsafe_get(word_index)
    root_limbs.unsafe_set(
      word_index * 2,
      (word & bin_coeff_limb_mask).to_uint(),
    )
    root_limbs.unsafe_set(word_index * 2 + 1, (word >> 32).to_uint())
  }
  let remainder_limbs = FixedArray::make(10, 0U)
  for word_index in 0..<5 {
    let word = remainder.unsafe_get(word_index)
    remainder_limbs.unsafe_set(
      word_index * 2,
      (word & bin_coeff_limb_mask).to_uint(),
    )
    remainder_limbs.unsafe_set(word_index * 2 + 1, (word >> 32).to_uint())
  }
  (
    bin_coeff_from_limbs(root_limbs, 8),
    bin_coeff_from_limbs(remainder_limbs, 10),
  )
}

///|
fn bin_coeff_sqrt_rem_restoring(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  if value.is_zero() {
    return (BinCoeff::zero(), BinCoeff::zero())
  }
  let pair_count = (value.bit_length() + 1) / 2
  let mut root = BinCoeff::zero()
  let mut remainder = BinCoeff::zero()
  let mut pair_index = pair_count - 1
  while true {
    let low_bit = pair_index * 2
    let pair = (if value.test_bit(low_bit + 1) { 2UL } else { 0UL }) +
      (if value.test_bit(low_bit) { 1UL } else { 0UL })
    remainder = remainder.shift_left(2).add(BinCoeff::from_uint64(pair))
    root = root.shift_left(1)
    let candidate = root.shift_left(1).add(BinCoeff::one())
    if remainder.compare(candidate) >= 0 {
      remainder = remainder.sub_checked(candidate).unwrap()
      root = root.add(BinCoeff::one())
    }
    if pair_index == 0 {
      break
    }
    pair_index -= 1
  }
  (root, remainder)
}

///|
fn bin_coeff_sqrt_rem_divide_conquer(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  let value_bits = value.bit_length()
  if value_bits <= 128 {
    return bin_coeff_sqrt_rem_restoring(value)
  }
  let root_bits = (value_bits + 1) / 2
  let block_bits = root_bits / 2
  let upper = value.shift_right(block_bits)
  let high = upper.shift_right(block_bits)
  let low = value.sub_checked(upper.shift_left(block_bits)).unwrap()
  let middle = upper.sub_checked(high.shift_left(block_bits)).unwrap()
  let (high_root, high_remainder) = bin_coeff_sqrt_rem_divide_conquer(high)
  let dividend = high_remainder.shift_left(block_bits).add(middle)
  let divisor = high_root.shift_left(1)
  let (raw_quotient, raw_remainder) = dividend.div_rem_checked(divisor).unwrap()
  let maximum_quotient = BinCoeff::one()
    .shift_left(block_bits)
    .sub_checked(BinCoeff::one())
    .unwrap()
  let (quotient, quotient_remainder) = if raw_quotient.compare(maximum_quotient) >
    0 {
    (
      maximum_quotient,
      dividend.sub_checked(maximum_quotient.mul(divisor)).unwrap(),
    )
  } else {
    (raw_quotient, raw_remainder)
  }
  let mut root = high_root.shift_left(block_bits).add(quotient)
  let partial_remainder = quotient_remainder.shift_left(block_bits).add(low)
  let mut remainder = bin_coeff_signed_scratch(false, partial_remainder).sub(
    bin_coeff_signed_scratch(false, quotient.square()),
  )
  let mut corrections = 0
  while remainder.negative {
    root = root.sub_checked(BinCoeff::one()).unwrap()
    remainder = remainder.add(
      bin_coeff_signed_scratch(false, root.shift_left(1).add(BinCoeff::one())),
    )
    corrections += 1
    guard corrections <= 1 else {
      abort("divide-and-conquer sqrt exceeded correction bound")
    }
  }
  let mut remainder_magnitude = remainder.magnitude
  while remainder_magnitude.compare(root.shift_left(1)) > 0 {
    let delta = root.shift_left(1).add(BinCoeff::one())
    guard remainder_magnitude.compare(delta) >= 0 else { break }
    remainder_magnitude = remainder_magnitude.sub_checked(delta).unwrap()
    root = root.add(BinCoeff::one())
  }
  (root, remainder_magnitude)
}

///|
fn bin_coeff_sqrt_rem_kernel(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  match value.repr {
    Inline64(value) => {
      let (root, remainder) = bin_coeff_sqrt_rem_u64(value)
      (BinCoeff::from_uint64(root), BinCoeff::from_uint64(remainder))
    }
    Inline128(high, low) => bin_coeff_sqrt_rem_u128(high, low)
    Heap(_, _) if value.bit_length() <= 256 => bin_coeff_sqrt_rem_u256(value)
    Heap(_, _) if value.bit_length() <= 512 => bin_coeff_sqrt_rem_u512(value)
    Heap(_, _) => bin_coeff_sqrt_rem_divide_conquer(value)
  }
}
