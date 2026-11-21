///|
/// Test-only reference implementations of the integer square root kept from
/// before the word-array recursion (#398): the `Coeff` divide-and-conquer
/// root, its fixed-width base case and the 512-bit kernel on 32-bit limbs.

///|
/// Base case width, in bits, of the reference divide-and-conquer root.
let bin_coeff_sqrt_dc_base_bits = 256

///|
fn bin_coeff_sqrt_rem_u512(value : Coeff) -> (Coeff, Coeff) {
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
/// Square root with remainder through the allocation-free fixed-width kernels,
/// for values of at most 512 bits (the base case of the divide-and-conquer
/// recursion); wider values use the restoring reference.
fn bin_coeff_sqrt_rem_fixed_width(value : Coeff) -> (Coeff, Coeff) {
  match value.0 {
    Inline64(word) => {
      let (root, remainder) = bin_coeff_sqrt_rem_u64(word)
      (Coeff::from_uint64(root), Coeff::from_uint64(remainder))
    }
    Inline128(high, low) =>
      if bin_coeff_sqrt_words_enabled {
        bin_coeff_sqrt_rem_u128_words(high, low)
      } else {
        bin_coeff_sqrt_rem_u128(high, low)
      }
    Heap(_, _) if value.bit_length() <= 256 =>
      if bin_coeff_sqrt_words_enabled {
        bin_coeff_sqrt_rem_u256_words(value)
      } else {
        bin_coeff_sqrt_rem_u256(value)
      }
    Heap(_, _) if value.bit_length() <= 512 => bin_coeff_sqrt_rem_u512(value)
    Heap(_, _) => bin_coeff_sqrt_rem_restoring(value)
  }
}

///|
fn bin_coeff_sqrt_rem_divide_conquer(value : Coeff) -> (Coeff, Coeff) {
  let value_bits = value.bit_length()
  if value_bits <= bin_coeff_sqrt_dc_base_bits {
    return bin_coeff_sqrt_rem_fixed_width(value)
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
  let maximum_quotient = Coeff::one()
    .shift_left(block_bits)
    .sub_checked(Coeff::one())
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
    root = root.sub_checked(Coeff::one()).unwrap()
    remainder = remainder.add(
      bin_coeff_signed_scratch(false, root.shift_left(1).add(Coeff::one())),
    )
    corrections += 1
    guard corrections <= 1 else {
      abort("divide-and-conquer sqrt exceeded correction bound")
    }
  }
  let mut remainder_magnitude = remainder.magnitude
  while remainder_magnitude.compare(root.shift_left(1)) > 0 {
    let delta = root.shift_left(1).add(Coeff::one())
    guard remainder_magnitude.compare(delta) >= 0 else { break }
    remainder_magnitude = remainder_magnitude.sub_checked(delta).unwrap()
    root = root.add(Coeff::one())
  }
  (root, remainder_magnitude)
}

///|
fn bin_coeff_sqrt_rem_restoring(value : Coeff) -> (Coeff, Coeff) {
  if value.is_zero() {
    return (Coeff::zero(), Coeff::zero())
  }
  let pair_count = (value.bit_length() + 1) / 2
  let mut root = Coeff::zero()
  let mut remainder = Coeff::zero()
  let mut pair_index = pair_count - 1
  while true {
    let low_bit = pair_index * 2
    let pair = (if value.test_bit(low_bit + 1) { 2UL } else { 0UL }) +
      (if value.test_bit(low_bit) { 1UL } else { 0UL })
    remainder = remainder.shift_left(2).add(Coeff::from_uint64(pair))
    root = root.shift_left(1)
    let candidate = root.shift_left(1).add(Coeff::one())
    if remainder.compare(candidate) >= 0 {
      remainder = remainder.sub_checked(candidate).unwrap()
      root = root.add(Coeff::one())
    }
    if pair_index == 0 {
      break
    }
    pair_index -= 1
  }
  (root, remainder)
}
