///|
/// Karatsuba multiplication on 32-bit limb ranges, the counterpart of the
/// 64-bit-limb code in `bin_coeff_words_nonjs.mbt`. On Wasm and Wasm-GC a
/// 64-bit limb product costs four `i64.mul` and the saving of the wider limb
/// shrinks to the loop overhead, so above `bin_coeff_limb32_min_words` the
/// operands are split into 32-bit limbs, multiplied here and packed back:
/// the conversions are linear, the product quadratic to subquadratic.

///|
/// `result[offset ..< offset + left_len + right_len] = left * right`
/// by the schoolbook method on 32-bit limbs.
fn bin_coeff_limb32_school(
  result : FixedArray[UInt32],
  result_offset : Int32,
  left : FixedArray[UInt32],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt32],
  right_offset : Int32,
  right_len : Int32,
) -> Unit {
  for index in 0..<(left_len + right_len) {
    result.unsafe_set(result_offset + index, 0U)
  }
  for left_index in 0..<left_len {
    let left_limb = left.unsafe_get(left_offset + left_index).to_uint64()
    let mut carry = 0UL
    for right_index in 0..<right_len {
      let index = result_offset + left_index + right_index
      let product = result.unsafe_get(index).to_uint64() +
        left_limb * right.unsafe_get(right_offset + right_index).to_uint64() +
        carry
      result.unsafe_set(index, (product & bin_coeff_limb_mask).to_uint())
      carry = product >> 32
    }
    result.unsafe_set(result_offset + left_index + right_len, carry.to_uint())
  }
}

///|
fn bin_coeff_limb32_add_into(
  target : FixedArray[UInt32],
  target_offset : Int32,
  target_end : Int32,
  source : FixedArray[UInt32],
  source_len : Int32,
) -> Unit {
  let mut carry = 0UL
  for index in 0..<source_len {
    let position = target_offset + index
    let sum = target.unsafe_get(position).to_uint64() +
      source.unsafe_get(index).to_uint64() +
      carry
    target.unsafe_set(position, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> 32
  }
  let mut position = target_offset + source_len
  while carry != 0UL && position < target_end {
    let sum = target.unsafe_get(position).to_uint64() + carry
    target.unsafe_set(position, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> 32
    position += 1
  }
  guard carry == 0UL else { abort("BinCoeff limb accumulation overflowed") }
}

///|
fn bin_coeff_limb32_sub_in_place(
  target : FixedArray[UInt32],
  target_len : Int32,
  source : FixedArray[UInt32],
  source_len : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<target_len {
    let minuend = target.unsafe_get(index).to_uint64()
    let subtrahend = (if index < source_len {
        source.unsafe_get(index).to_uint64()
      } else {
        0UL
      }) +
      borrow
    if minuend < subtrahend {
      target.unsafe_set(
        index,
        (minuend + bin_coeff_limb_base - subtrahend).to_uint(),
      )
      borrow = 1UL
    } else {
      target.unsafe_set(index, (minuend - subtrahend).to_uint())
      borrow = 0UL
    }
  }
  guard borrow == 0UL else { abort("BinCoeff limb subtraction went negative") }
}

///|
/// Compares two ranges padded with zeros to `len` limbs.
fn bin_coeff_limb32_compare_padded(
  first : FixedArray[UInt32],
  first_offset : Int32,
  first_len : Int32,
  second : FixedArray[UInt32],
  second_offset : Int32,
  second_len : Int32,
  len : Int32,
) -> Int32 {
  let mut index = len - 1
  while index >= 0 {
    let left = if index < first_len {
      first.unsafe_get(first_offset + index)
    } else {
      0U
    }
    let right = if index < second_len {
      second.unsafe_get(second_offset + index)
    } else {
      0U
    }
    if left != right {
      return if left < right { -1 } else { 1 }
    }
    index -= 1
  }
  0
}

///|
/// `result[0 ..< len] = larger - smaller` as padded ranges (`larger >= smaller`).
fn bin_coeff_limb32_sub_padded(
  result : FixedArray[UInt32],
  larger : FixedArray[UInt32],
  larger_offset : Int32,
  larger_len : Int32,
  smaller : FixedArray[UInt32],
  smaller_offset : Int32,
  smaller_len : Int32,
  len : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<len {
    let minuend = if index < larger_len {
      larger.unsafe_get(larger_offset + index).to_uint64()
    } else {
      0UL
    }
    let subtrahend = (if index < smaller_len {
        smaller.unsafe_get(smaller_offset + index).to_uint64()
      } else {
        0UL
      }) +
      borrow
    if minuend < subtrahend {
      result.unsafe_set(
        index,
        (minuend + bin_coeff_limb_base - subtrahend).to_uint(),
      )
      borrow = 1UL
    } else {
      result.unsafe_set(index, (minuend - subtrahend).to_uint())
      borrow = 0UL
    }
  }
}

///|
fn bin_coeff_limb32_trim(values : FixedArray[UInt32], len : Int32) -> Int32 {
  let mut length = len
  while length > 0 && values.unsafe_get(length - 1) == 0U {
    length -= 1
  }
  length
}

///|
/// `result[offset ..< offset + left_len + right_len] = left * right`.
fn bin_coeff_limb32_mul(
  result : FixedArray[UInt32],
  result_offset : Int32,
  left : FixedArray[UInt32],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt32],
  right_offset : Int32,
  right_len : Int32,
) -> Unit {
  let shorter = Int32::min(left_len, right_len)
  if shorter < bin_coeff_limb32_karatsuba_cutoff {
    bin_coeff_limb32_school(
      result, result_offset, left, left_offset, left_len, right, right_offset, right_len,
    )
    return
  }
  let longer = Int32::max(left_len, right_len)
  let half = (longer + 1) / 2
  if shorter <= half {
    bin_coeff_limb32_mul_blocks(
      result, result_offset, left, left_offset, left_len, right, right_offset, right_len,
    )
    return
  }
  let left_high_len = left_len - half
  let right_high_len = right_len - half
  bin_coeff_limb32_mul(
    result, result_offset, left, left_offset, half, right, right_offset, half,
  )
  bin_coeff_limb32_mul(
    result,
    result_offset + 2 * half,
    left,
    left_offset + half,
    left_high_len,
    right,
    right_offset + half,
    right_high_len,
  )
  let left_difference = FixedArray::make(half, 0U)
  let right_difference = FixedArray::make(half, 0U)
  let left_negative = bin_coeff_limb32_compare_padded(
      left,
      left_offset,
      half,
      left,
      left_offset + half,
      left_high_len,
      half,
    ) <
    0
  if left_negative {
    bin_coeff_limb32_sub_padded(
      left_difference,
      left,
      left_offset + half,
      left_high_len,
      left,
      left_offset,
      half,
      half,
    )
  } else {
    bin_coeff_limb32_sub_padded(
      left_difference,
      left,
      left_offset,
      half,
      left,
      left_offset + half,
      left_high_len,
      half,
    )
  }
  let right_negative = bin_coeff_limb32_compare_padded(
      right,
      right_offset,
      half,
      right,
      right_offset + half,
      right_high_len,
      half,
    ) <
    0
  if right_negative {
    bin_coeff_limb32_sub_padded(
      right_difference,
      right,
      right_offset + half,
      right_high_len,
      right,
      right_offset,
      half,
      half,
    )
  } else {
    bin_coeff_limb32_sub_padded(
      right_difference,
      right,
      right_offset,
      half,
      right,
      right_offset + half,
      right_high_len,
      half,
    )
  }
  let difference_product = FixedArray::make(2 * half, 0U)
  bin_coeff_limb32_mul(
    difference_product, 0, left_difference, 0, half, right_difference, 0, half,
  )
  let middle_len = 2 * half + 1
  let middle = FixedArray::make(middle_len, 0U)
  for index in 0..<(2 * half) {
    middle.unsafe_set(index, result.unsafe_get(result_offset + index))
  }
  let high_product_len = left_high_len + right_high_len
  let high_product = FixedArray::make(high_product_len, 0U)
  for index in 0..<high_product_len {
    high_product.unsafe_set(
      index,
      result.unsafe_get(result_offset + 2 * half + index),
    )
  }
  bin_coeff_limb32_add_into(
    middle, 0, middle_len, high_product, high_product_len,
  )
  if left_negative == right_negative {
    bin_coeff_limb32_sub_in_place(
      middle,
      middle_len,
      difference_product,
      2 * half,
    )
  } else {
    bin_coeff_limb32_add_into(
      middle,
      0,
      middle_len,
      difference_product,
      2 * half,
    )
  }
  bin_coeff_limb32_add_into(
    result,
    result_offset + half,
    result_offset + left_len + right_len,
    middle,
    bin_coeff_limb32_trim(middle, middle_len),
  )
}

///|
fn bin_coeff_limb32_mul_blocks(
  result : FixedArray[UInt32],
  result_offset : Int32,
  left : FixedArray[UInt32],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt32],
  right_offset : Int32,
  right_len : Int32,
) -> Unit {
  let left_is_longer = left_len >= right_len
  let long_array = if left_is_longer { left } else { right }
  let long_offset = if left_is_longer { left_offset } else { right_offset }
  let long_len = if left_is_longer { left_len } else { right_len }
  let short_array = if left_is_longer { right } else { left }
  let short_offset = if left_is_longer { right_offset } else { left_offset }
  let short_len = if left_is_longer { right_len } else { left_len }
  let total = left_len + right_len
  for index in 0..<total {
    result.unsafe_set(result_offset + index, 0U)
  }
  let product = FixedArray::make(2 * short_len, 0U)
  let mut start = 0
  while start < long_len {
    let block_len = Int32::min(short_len, long_len - start)
    bin_coeff_limb32_mul(
      product,
      0,
      long_array,
      long_offset + start,
      block_len,
      short_array,
      short_offset,
      short_len,
    )
    bin_coeff_limb32_add_into(
      result,
      result_offset + start,
      result_offset + total,
      product,
      bin_coeff_limb32_trim(product, block_len + short_len),
    )
    start += short_len
  }
}

///|
/// The 32-bit limbs of a heap value's 64-bit words.
fn bin_coeff_limb32_unpack(
  words : FixedArray[UInt64],
  word_len : Int32,
) -> FixedArray[UInt32] {
  let limbs = FixedArray::make(2 * word_len, 0U)
  for index in 0..<word_len {
    let word = words.unsafe_get(index)
    limbs.unsafe_set(2 * index, (word & bin_coeff_limb_mask).to_uint())
    limbs.unsafe_set(2 * index + 1, (word >> 32).to_uint())
  }
  limbs
}

///|
/// Product of two heap values through 32-bit limb ranges.
fn bin_coeff_mul_limb32(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  match (left.repr, right.repr) {
    (Heap(left_words, left_len), Heap(right_words, right_len)) => {
      let left_limbs = bin_coeff_limb32_unpack(left_words, left_len)
      let right_limbs = bin_coeff_limb32_unpack(right_words, right_len)
      let limb_len = 2 * (left_len + right_len)
      let product = FixedArray::make(limb_len, 0U)
      bin_coeff_limb32_mul(
        product,
        0,
        left_limbs,
        0,
        2 * left_len,
        right_limbs,
        0,
        2 * right_len,
      )
      bin_coeff_from_limbs(product, limb_len)
    }
    _ => bin_coeff_mul_schoolbook(left, right)
  }
}
