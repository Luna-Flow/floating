///|
/// Multiplication on raw 64-bit limb ranges (issue #19, stage 2): schoolbook
/// below a cutoff, Karatsuba above it, and block multiplication for unbalanced
/// operands. The recursion works on array ranges and allocates only a few
/// small temporaries per node, instead of wrapping every intermediate value in
/// a `BinCoeff`.

///|
/// `result[result_offset ..< result_offset + left_len + right_len] =
/// left * right` by the schoolbook method.
fn bin_coeff_words_school(
  result : FixedArray[UInt64],
  result_offset : Int32,
  left : FixedArray[UInt64],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt64],
  right_offset : Int32,
  right_len : Int32,
) -> Unit {
  for index in 0..<(left_len + right_len) {
    result.unsafe_set(result_offset + index, 0UL)
  }
  for left_index in 0..<left_len {
    let left_word = left.unsafe_get(left_offset + left_index)
    let mut carry = 0UL
    for right_index in 0..<right_len {
      let index = result_offset + left_index + right_index
      let right_word = right.unsafe_get(right_offset + right_index)
      let low = left_word * right_word
      let mut high = bin_coeff_mul_high(left_word, right_word)
      let sum = low + result.unsafe_get(index)
      if sum < low {
        high += 1UL
      }
      let total = sum + carry
      if total < sum {
        high += 1UL
      }
      result.unsafe_set(index, total)
      carry = high
    }
    result.unsafe_set(result_offset + left_index + right_len, carry)
  }
}

///|
/// `target[target_offset ..] += source[0 ..< source_len]`, the carry running
/// up through `target[.. < target_end]`.
fn bin_coeff_words_add_into(
  target : FixedArray[UInt64],
  target_offset : Int32,
  target_end : Int32,
  source : FixedArray[UInt64],
  source_len : Int32,
) -> Unit {
  let mut carry = 0UL
  for index in 0..<source_len {
    let position = target_offset + index
    let current = target.unsafe_get(position)
    let addend = source.unsafe_get(index)
    let sum = current + addend
    let carry_one = if sum < current { 1UL } else { 0UL }
    let total = sum + carry
    let carry_two = if total < sum { 1UL } else { 0UL }
    target.unsafe_set(position, total)
    carry = carry_one + carry_two
  }
  let mut position = target_offset + source_len
  while carry != 0UL && position < target_end {
    let current = target.unsafe_get(position)
    let total = current + carry
    target.unsafe_set(position, total)
    carry = if total < current { 1UL } else { 0UL }
    position += 1
  }
  guard carry == 0UL else { abort("BinCoeff word accumulation overflowed") }
}

///|
/// Compares `high[high_offset ..< high_offset + high_len]` (zero above) with
/// `low` of length `len`, where `high_len <= len`.
fn bin_coeff_words_compare_padded(
  first : FixedArray[UInt64],
  first_offset : Int32,
  first_len : Int32,
  second : FixedArray[UInt64],
  second_offset : Int32,
  second_len : Int32,
  len : Int32,
) -> Int32 {
  let mut index = len - 1
  while index >= 0 {
    let left = if index < first_len {
      first.unsafe_get(first_offset + index)
    } else {
      0UL
    }
    let right = if index < second_len {
      second.unsafe_get(second_offset + index)
    } else {
      0UL
    }
    if left != right {
      return if left < right { -1 } else { 1 }
    }
    index -= 1
  }
  0
}

///|
/// `result[0 ..< len] = larger - smaller` for `larger >= smaller` as padded
/// ranges of length `len`.
fn bin_coeff_words_sub_padded(
  result : FixedArray[UInt64],
  larger : FixedArray[UInt64],
  larger_offset : Int32,
  larger_len : Int32,
  smaller : FixedArray[UInt64],
  smaller_offset : Int32,
  smaller_len : Int32,
  len : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<len {
    let minuend = if index < larger_len {
      larger.unsafe_get(larger_offset + index)
    } else {
      0UL
    }
    let subtrahend = if index < smaller_len {
      smaller.unsafe_get(smaller_offset + index)
    } else {
      0UL
    }
    let difference = minuend - subtrahend
    let borrow_one = if minuend < subtrahend { 1UL } else { 0UL }
    let value = difference - borrow
    let borrow_two = if difference < borrow { 1UL } else { 0UL }
    result.unsafe_set(index, value)
    borrow = borrow_one + borrow_two
  }
}

///|
/// `result[result_offset ..< result_offset + left_len + right_len] =
/// left * right`.
fn bin_coeff_words_mul(
  result : FixedArray[UInt64],
  result_offset : Int32,
  left : FixedArray[UInt64],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt64],
  right_offset : Int32,
  right_len : Int32,
) -> Unit {
  let shorter = Int32::min(left_len, right_len)
  if shorter < bin_coeff_words_karatsuba_cutoff {
    bin_coeff_words_school(
      result, result_offset, left, left_offset, left_len, right, right_offset, right_len,
    )
    return
  }
  let longer = Int32::max(left_len, right_len)
  let half = (longer + 1) / 2
  if shorter <= half {
    // unbalanced: the longer operand in blocks of the shorter one
    bin_coeff_words_mul_blocks(
      result, result_offset, left, left_offset, left_len, right, right_offset, right_len,
    )
    return
  }
  let left_high_len = left_len - half
  let right_high_len = right_len - half
  // z0 = low * low and z2 = high * high fill the result without overlap
  bin_coeff_words_mul(
    result, result_offset, left, left_offset, half, right, right_offset, half,
  )
  bin_coeff_words_mul(
    result,
    result_offset + 2 * half,
    left,
    left_offset + half,
    left_high_len,
    right,
    right_offset + half,
    right_high_len,
  )
  // |a0 - a1| and |b0 - b1| with their signs
  let left_difference = FixedArray::make(half, 0UL)
  let right_difference = FixedArray::make(half, 0UL)
  let left_negative = bin_coeff_words_compare_padded(
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
    bin_coeff_words_sub_padded(
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
    bin_coeff_words_sub_padded(
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
  let right_negative = bin_coeff_words_compare_padded(
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
    bin_coeff_words_sub_padded(
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
    bin_coeff_words_sub_padded(
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
  let difference_product = FixedArray::make(2 * half, 0UL)
  bin_coeff_words_mul(
    difference_product, 0, left_difference, 0, half, right_difference, 0, half,
  )
  // middle = z0 + z2 -+ |a0 - a1| * |b0 - b1| (minus when the signs agree)
  let middle_len = 2 * half + 1
  let middle = FixedArray::make(middle_len, 0UL)
  for index in 0..<(2 * half) {
    middle.unsafe_set(index, result.unsafe_get(result_offset + index))
  }
  let high_product_len = left_high_len + right_high_len
  let high_product = FixedArray::make(high_product_len, 0UL)
  for index in 0..<high_product_len {
    high_product.unsafe_set(
      index,
      result.unsafe_get(result_offset + 2 * half + index),
    )
  }
  bin_coeff_words_add_into(
    middle, 0, middle_len, high_product, high_product_len,
  )
  if left_negative == right_negative {
    bin_coeff_words_sub_in_place(
      middle,
      middle_len,
      difference_product,
      2 * half,
    )
  } else {
    bin_coeff_words_add_into(
      middle,
      0,
      middle_len,
      difference_product,
      2 * half,
    )
  }
  bin_coeff_words_add_into(
    result,
    result_offset + half,
    result_offset + left_len + right_len,
    middle,
    {
      let mut length = middle_len
      while length > 0 && middle.unsafe_get(length - 1) == 0UL {
        length -= 1
      }
      length
    },
  )
}

///|
/// `target[0 ..< target_len] -= source[0 ..< source_len]` (the result is not
/// negative).
fn bin_coeff_words_sub_in_place(
  target : FixedArray[UInt64],
  target_len : Int32,
  source : FixedArray[UInt64],
  source_len : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<target_len {
    let minuend = target.unsafe_get(index)
    let subtrahend = if index < source_len {
      source.unsafe_get(index)
    } else {
      0UL
    }
    let difference = minuend - subtrahend
    let borrow_one = if minuend < subtrahend { 1UL } else { 0UL }
    let value = difference - borrow
    let borrow_two = if difference < borrow { 1UL } else { 0UL }
    target.unsafe_set(index, value)
    borrow = borrow_one + borrow_two
  }
  guard borrow == 0UL else { abort("BinCoeff word subtraction went negative") }
}

///|
/// Unbalanced product: the longer operand is cut into blocks of the shorter
/// one's length and the block products are accumulated.
fn bin_coeff_words_mul_blocks(
  result : FixedArray[UInt64],
  result_offset : Int32,
  left : FixedArray[UInt64],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt64],
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
    result.unsafe_set(result_offset + index, 0UL)
  }
  let product = FixedArray::make(2 * short_len, 0UL)
  let mut start = 0
  while start < long_len {
    let block_len = Int32::min(short_len, long_len - start)
    bin_coeff_words_mul(
      product,
      0,
      long_array,
      long_offset + start,
      block_len,
      short_array,
      short_offset,
      short_len,
    )
    let used = block_len + short_len
    let mut length = used
    while length > 0 && product.unsafe_get(length - 1) == 0UL {
      length -= 1
    }
    bin_coeff_words_add_into(
      result,
      result_offset + start,
      result_offset + total,
      product,
      length,
    )
    start += short_len
  }
}

///|
/// Product of two heap values by the word-range Karatsuba method.
fn bin_coeff_mul_words(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  match (left.repr, right.repr) {
    (Heap(_, left_len), Heap(_, right_len)) if Int32::min(left_len, right_len) >=
      bin_coeff_limb32_min_words => bin_coeff_mul_limb32(left, right)
    (Heap(left_words, left_len), Heap(right_words, right_len)) => {
      let result = FixedArray::make(left_len + right_len, 0UL)
      bin_coeff_words_mul(
        result, 0, left_words, 0, left_len, right_words, 0, right_len,
      )
      bin_coeff_from_words(result, left_len + right_len)
    }
    _ => bin_coeff_mul_schoolbook(left, right)
  }
}
