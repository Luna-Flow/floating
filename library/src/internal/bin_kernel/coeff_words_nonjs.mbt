///|
/// Multiplication on raw 64-bit limb ranges (issue #19, stage 2): schoolbook
/// below a cutoff, Karatsuba above it, and block multiplication for unbalanced
/// operands. The recursion works on array ranges and allocates only a few
/// small temporaries per node, instead of wrapping every intermediate value in
/// a `Coeff`.

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
    let left_low = left_word & bin_coeff_limb_mask
    let left_high = left_word >> 32
    let mut carry = 0UL
    for right_index in 0..<right_len {
      let index = result_offset + left_index + right_index
      let right_word = right.unsafe_get(right_offset + right_index)
      let low = left_word * right_word
      let right_low = right_word & bin_coeff_limb_mask
      let right_high = right_word >> 32
      let cross = left_high * right_low + ((left_low * right_low) >> 32)
      let product_high = left_high * right_high +
        (cross >> 32) +
        ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
      let partial = low + carry
      let carry_one = if partial < low { 1UL } else { 0UL }
      let total = partial + result.unsafe_get(index)
      let carry_two = if total < partial { 1UL } else { 0UL }
      result.unsafe_set(index, total)
      carry = product_high + carry_one + carry_two
    }
    result.unsafe_set(result_offset + left_index + right_len, carry)
  }
}

///|
/// `target[target_offset ..] += source[source_offset ..< source_offset +
/// source_len]`, the carry running up through `target[.. < target_end]`.
fn bin_coeff_words_add_into(
  target : FixedArray[UInt64],
  target_offset : Int32,
  target_end : Int32,
  source : FixedArray[UInt64],
  source_offset : Int32,
  source_len : Int32,
) -> Unit {
  let mut carry = 0UL
  for index in 0..<source_len {
    let position = target_offset + index
    let current = target.unsafe_get(position)
    let addend = source.unsafe_get(source_offset + index)
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
  guard carry == 0UL else { abort("Coeff word accumulation overflowed") }
}

///|
/// `target[target_offset ..< target_offset + target_len] -=
/// source[source_offset ..< source_offset + source_len]` (the result is not
/// negative).
fn bin_coeff_words_sub_in_place(
  target : FixedArray[UInt64],
  target_offset : Int32,
  target_len : Int32,
  source : FixedArray[UInt64],
  source_offset : Int32,
  source_len : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<target_len {
    let minuend = target.unsafe_get(target_offset + index)
    let subtrahend = if index < source_len {
      source.unsafe_get(source_offset + index)
    } else {
      0UL
    }
    let difference = minuend - subtrahend
    let borrow_one = if minuend < subtrahend { 1UL } else { 0UL }
    let value = difference - borrow
    let borrow_two = if difference < borrow { 1UL } else { 0UL }
    target.unsafe_set(target_offset + index, value)
    borrow = borrow_one + borrow_two
  }
  guard borrow == 0UL else { abort("Coeff word subtraction went negative") }
}

///|
/// Compares `first[first_offset ..< first_offset + first_len]` with
/// `second[second_offset ..< second_offset + second_len]` as numbers of `len`
/// limbs (zero above the given lengths, which are at most `len`).
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
/// `result[result_offset ..< result_offset + len] = larger - smaller` for
/// `larger >= smaller` as padded ranges of length `len`.
fn bin_coeff_words_sub_padded(
  result : FixedArray[UInt64],
  result_offset : Int32,
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
    result.unsafe_set(result_offset + index, value)
    borrow = borrow_one + borrow_two
  }
}

///|
/// `|first - second|` of two ranges of `len` limbs (the shorter one zero
/// padded) into `result[result_offset ..< result_offset + len]`; true when
/// `first < second`.
fn bin_coeff_words_abs_difference(
  result : FixedArray[UInt64],
  result_offset : Int32,
  first : FixedArray[UInt64],
  first_offset : Int32,
  first_len : Int32,
  second : FixedArray[UInt64],
  second_offset : Int32,
  second_len : Int32,
  len : Int32,
) -> Bool {
  let negative = bin_coeff_words_compare_padded(
      first, first_offset, first_len, second, second_offset, second_len, len,
    ) <
    0
  if negative {
    bin_coeff_words_sub_padded(
      result, result_offset, second, second_offset, second_len, first, first_offset,
      first_len, len,
    )
  } else {
    bin_coeff_words_sub_padded(
      result, result_offset, first, first_offset, first_len, second, second_offset,
      second_len, len,
    )
  }
  negative
}

///|
/// Limbs of scratch space that `bin_coeff_words_mul_scratch` and
/// `bin_coeff_words_sqr_scratch` need for operands of at most `longest` limbs:
/// the temporaries of one node (at most `6 * half + 2` limbs) plus those of
/// the largest node below it, since the children run one after another.
fn bin_coeff_words_scratch_len(longest : Int32) -> Int32 {
  let mut total = 0
  let mut size = longest
  while size >=
        Int32::min(
          bin_coeff_words_karatsuba_cutoff, bin_coeff_words_square_cutoff,
        ) {
    let half = (size + 1) / 2
    total += 6 * half + 2
    size = half
  }
  total
}

///|
/// `result[result_offset ..< result_offset + left_len + right_len] =
/// left * right`, Karatsuba on a shared scratch array: `scratch[scratch_offset
/// ..]` holds the two absolute differences, their product and the middle term
/// of a node, so a call allocates nothing.
fn bin_coeff_words_mul_scratch(
  result : FixedArray[UInt64],
  result_offset : Int32,
  left : FixedArray[UInt64],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt64],
  right_offset : Int32,
  right_len : Int32,
  scratch : FixedArray[UInt64],
  scratch_offset : Int32,
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
      scratch, scratch_offset,
    )
    return
  }
  let left_high_len = left_len - half
  let right_high_len = right_len - half
  // z0 = low * low and z2 = high * high fill the result without overlap
  bin_coeff_words_mul_scratch(
    result, result_offset, left, left_offset, half, right, right_offset, half, scratch,
    scratch_offset,
  )
  bin_coeff_words_mul_scratch(
    result,
    result_offset + 2 * half,
    left,
    left_offset + half,
    left_high_len,
    right,
    right_offset + half,
    right_high_len,
    scratch,
    scratch_offset,
  )
  // node temporaries: |a0 - a1|, |b0 - b1|, their product, the middle term
  let left_difference = scratch_offset
  let right_difference = scratch_offset + half
  let product = scratch_offset + 2 * half
  let middle = scratch_offset + 4 * half
  let middle_len = 2 * half + 1
  let left_negative = bin_coeff_words_abs_difference(
    scratch,
    left_difference,
    left,
    left_offset,
    half,
    left,
    left_offset + half,
    left_high_len,
    half,
  )
  let right_negative = bin_coeff_words_abs_difference(
    scratch,
    right_difference,
    right,
    right_offset,
    half,
    right,
    right_offset + half,
    right_high_len,
    half,
  )
  bin_coeff_words_mul_scratch(
    scratch,
    product,
    scratch,
    left_difference,
    half,
    scratch,
    right_difference,
    half,
    scratch,
    scratch_offset + 6 * half + 2,
  )
  // middle = z0 + z2 -+ |a0 - a1| * |b0 - b1| (minus when the signs agree)
  for index in 0..<middle_len {
    scratch.unsafe_set(middle + index, 0UL)
  }
  for index in 0..<(2 * half) {
    scratch.unsafe_set(middle + index, result.unsafe_get(result_offset + index))
  }
  bin_coeff_words_add_into(
    scratch,
    middle,
    middle + middle_len,
    result,
    result_offset + 2 * half,
    left_high_len + right_high_len,
  )
  if left_negative == right_negative {
    bin_coeff_words_sub_in_place(
      scratch,
      middle,
      middle_len,
      scratch,
      product,
      2 * half,
    )
  } else {
    bin_coeff_words_add_into(
      scratch,
      middle,
      middle + middle_len,
      scratch,
      product,
      2 * half,
    )
  }
  let mut used = middle_len
  while used > 0 && scratch.unsafe_get(middle + used - 1) == 0UL {
    used -= 1
  }
  bin_coeff_words_add_into(
    result,
    result_offset + half,
    result_offset + left_len + right_len,
    scratch,
    middle,
    used,
  )
}

///|
/// Unbalanced product: the longer operand is cut into blocks of the shorter
/// one's length and the block products are accumulated. `scratch` holds the
/// block product (`2 * shorter` limbs) and, above it, the Karatsuba scratch of
/// the block products.
fn bin_coeff_words_mul_blocks(
  result : FixedArray[UInt64],
  result_offset : Int32,
  left : FixedArray[UInt64],
  left_offset : Int32,
  left_len : Int32,
  right : FixedArray[UInt64],
  right_offset : Int32,
  right_len : Int32,
  scratch : FixedArray[UInt64],
  scratch_offset : Int32,
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
  let mut start = 0
  while start < long_len {
    let block_len = Int32::min(short_len, long_len - start)
    bin_coeff_words_mul_scratch(
      scratch,
      scratch_offset,
      long_array,
      long_offset + start,
      block_len,
      short_array,
      short_offset,
      short_len,
      scratch,
      scratch_offset + 2 * short_len,
    )
    let used = block_len + short_len
    let mut length = used
    while length > 0 && scratch.unsafe_get(scratch_offset + length - 1) == 0UL {
      length -= 1
    }
    bin_coeff_words_add_into(
      result,
      result_offset + start,
      result_offset + total,
      scratch,
      scratch_offset,
      length,
    )
    start += short_len
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
  let scratch = FixedArray::make(
    bin_coeff_words_scratch_len(Int32::max(left_len, right_len)) +
    2 * Int32::min(left_len, right_len),
    0UL,
  )
  bin_coeff_words_mul_scratch(
    result, result_offset, left, left_offset, left_len, right, right_offset, right_len,
    scratch, 0,
  )
}

///|
/// `result[result_offset ..< result_offset + 2 * len] = value^2` by the
/// half-product schoolbook method (the cross products once, doubled, plus the
/// squares of the limbs).
fn bin_coeff_words_sqr_school(
  result : FixedArray[UInt64],
  result_offset : Int32,
  source : FixedArray[UInt64],
  source_offset : Int32,
  len : Int32,
) -> Unit {
  let output_len = 2 * len
  for index in 0..<output_len {
    result.unsafe_set(result_offset + index, 0UL)
  }
  for left_index in 0..<len {
    let left_word = source.unsafe_get(source_offset + left_index)
    let left_low = left_word & bin_coeff_limb_mask
    let left_high = left_word >> 32
    let mut carry = 0UL
    for right_index in (left_index + 1)..<len {
      let position = result_offset + left_index + right_index
      let right_word = source.unsafe_get(source_offset + right_index)
      let low = left_word * right_word
      let right_low = right_word & bin_coeff_limb_mask
      let right_high = right_word >> 32
      let cross = left_high * right_low + ((left_low * right_low) >> 32)
      let product_high = left_high * right_high +
        (cross >> 32) +
        ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
      let partial = low + carry
      let carry_one = if partial < low { 1UL } else { 0UL }
      let total = partial + result.unsafe_get(position)
      let carry_two = if total < partial { 1UL } else { 0UL }
      result.unsafe_set(position, total)
      carry = product_high + carry_one + carry_two
    }
    result.unsafe_set(result_offset + left_index + len, carry)
  }
  let mut shifted_out = 0UL
  for index in 0..<output_len {
    let word = result.unsafe_get(result_offset + index)
    result.unsafe_set(result_offset + index, (word << 1) | shifted_out)
    shifted_out = word >> 63
  }
  let mut carry = 0UL
  for index in 0..<len {
    let word = source.unsafe_get(source_offset + index)
    let low = word * word
    let high = bin_coeff_mul_high(word, word)
    let low_position = result_offset + 2 * index
    let low_sum = result.unsafe_get(low_position) + low
    let low_carry = if low_sum < low { 1UL } else { 0UL }
    let low_total = low_sum + carry
    let low_carry_two = if low_total < low_sum { 1UL } else { 0UL }
    result.unsafe_set(low_position, low_total)
    let high_sum = result.unsafe_get(low_position + 1) + high
    let high_carry = if high_sum < high { 1UL } else { 0UL }
    let high_total = high_sum + low_carry + low_carry_two
    let high_carry_two = if high_total < high_sum { 1UL } else { 0UL }
    result.unsafe_set(low_position + 1, high_total)
    carry = high_carry + high_carry_two
  }
}

///|
/// `result[result_offset ..< result_offset + 2 * len] = value^2`, Karatsuba on
/// a shared scratch array: three half-size squares (`lo^2`, `hi^2` and
/// `(lo - hi)^2`) instead of three products.
fn bin_coeff_words_sqr_scratch(
  result : FixedArray[UInt64],
  result_offset : Int32,
  source : FixedArray[UInt64],
  source_offset : Int32,
  len : Int32,
  scratch : FixedArray[UInt64],
  scratch_offset : Int32,
) -> Unit {
  if len < bin_coeff_words_square_cutoff {
    bin_coeff_words_sqr_school(
      result, result_offset, source, source_offset, len,
    )
    return
  }
  let half = (len + 1) / 2
  let high_len = len - half
  bin_coeff_words_sqr_scratch(
    result, result_offset, source, source_offset, half, scratch, scratch_offset,
  )
  bin_coeff_words_sqr_scratch(
    result,
    result_offset + 2 * half,
    source,
    source_offset + half,
    high_len,
    scratch,
    scratch_offset,
  )
  let difference = scratch_offset
  let product = scratch_offset + half
  let middle = scratch_offset + 3 * half
  let middle_len = 2 * half + 1
  ignore(
    bin_coeff_words_abs_difference(
      scratch,
      difference,
      source,
      source_offset,
      half,
      source,
      source_offset + half,
      high_len,
      half,
    ),
  )
  bin_coeff_words_sqr_scratch(
    scratch,
    product,
    scratch,
    difference,
    half,
    scratch,
    scratch_offset + 6 * half + 2,
  )
  for index in 0..<middle_len {
    scratch.unsafe_set(middle + index, 0UL)
  }
  for index in 0..<(2 * half) {
    scratch.unsafe_set(middle + index, result.unsafe_get(result_offset + index))
  }
  bin_coeff_words_add_into(
    scratch,
    middle,
    middle + middle_len,
    result,
    result_offset + 2 * half,
    2 * high_len,
  )
  bin_coeff_words_sub_in_place(
    scratch,
    middle,
    middle_len,
    scratch,
    product,
    2 * half,
  )
  let mut used = middle_len
  while used > 0 && scratch.unsafe_get(middle + used - 1) == 0UL {
    used -= 1
  }
  bin_coeff_words_add_into(
    result,
    result_offset + half,
    result_offset + 2 * len,
    scratch,
    middle,
    used,
  )
}

///|
/// The square of a heap value by the word-range Karatsuba square.
fn bin_coeff_square_words(value : Coeff) -> Coeff {
  match value.0 {
    Heap(words, len) => {
      let result = FixedArray::make(2 * len, 0UL)
      let scratch = FixedArray::make(bin_coeff_words_scratch_len(len), 0UL)
      bin_coeff_words_sqr_scratch(result, 0, words, 0, len, scratch, 0)
      bin_coeff_from_words(result, 2 * len)
    }
    _ => value.mul(value)
  }
}

///|
/// Product of two heap values by the word-range Karatsuba method.
fn bin_coeff_mul_words(left : Coeff, right : Coeff) -> Coeff {
  match (left.0, right.0) {
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
