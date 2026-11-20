///|
#derive(Eq)
#warnings("-unused_value")
priv enum DecCoeffMulAlgorithm {
  Inline
  Schoolbook
  Sparse
  Unbalanced
  Karatsuba
  Toom3
  Ntt
}

///|
priv struct DecCoeffSignedScratch {
  negative : Bool
  magnitude : DecCoeff
}

///|
fn dec_coeff_signed_scratch(
  negative : Bool,
  magnitude : DecCoeff,
) -> DecCoeffSignedScratch {
  { negative: negative && !magnitude.is_zero(), magnitude, }
}

///|
fn DecCoeffSignedScratch::neg(
  self : DecCoeffSignedScratch,
) -> DecCoeffSignedScratch {
  dec_coeff_signed_scratch(!self.negative, self.magnitude)
}

///|
fn DecCoeffSignedScratch::add(
  self : DecCoeffSignedScratch,
  other : DecCoeffSignedScratch,
) -> DecCoeffSignedScratch {
  let (negative, magnitude) = dec_coeff_signed_add_repr(
    self.negative,
    self.magnitude,
    other.negative,
    other.magnitude,
  )
  dec_coeff_signed_scratch(negative, magnitude)
}

///|
fn DecCoeffSignedScratch::sub(
  self : DecCoeffSignedScratch,
  other : DecCoeffSignedScratch,
) -> DecCoeffSignedScratch {
  self.add(other.neg())
}

///|
fn DecCoeffSignedScratch::mul(
  self : DecCoeffSignedScratch,
  other : DecCoeffSignedScratch,
) -> DecCoeffSignedScratch {
  dec_coeff_signed_scratch(
    self.negative != other.negative,
    dec_coeff_multiply_repr(self.magnitude, other.magnitude),
  )
}

///|
fn DecCoeffSignedScratch::div_exact_small(
  self : DecCoeffSignedScratch,
  divisor : Int32,
) -> DecCoeffSignedScratch {
  let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(
    self.magnitude,
    divisor,
  )
  guard remainder == 0 else {
    abort("Toom-3 interpolation division was not exact")
  }
  dec_coeff_signed_scratch(self.negative, quotient)
}

///|
fn DecCoeffSignedScratch::nonnegative(self : DecCoeffSignedScratch) -> DecCoeff {
  guard !self.negative else {
    abort("Toom-3 produced a negative output coefficient")
  }
  self.magnitude
}

///|
priv struct DecCoeffScratchArena {
  slots : Array[DecCoeff]
  mut used : Int32
  limb_buffers : Array[Array[UInt32]]
  mut limb_used : Int32
}

///|
fn dec_coeff_scratch_arena_new() -> DecCoeffScratchArena {
  { slots: [], used: 0, limb_buffers: [], limb_used: 0, }
}

///|
fn DecCoeffScratchArena::mark(self : DecCoeffScratchArena) -> (Int32, Int32) {
  (self.used, self.limb_used)
}

///|
fn DecCoeffScratchArena::alloc_limbs(
  self : DecCoeffScratchArena,
  length : Int32,
) -> Array[UInt32] {
  guard length > 0 else { return [0U] }
  let slot = self.limb_used
  self.limb_used += 1
  if slot >= self.limb_buffers.length() {
    self.limb_buffers.push([])
  }
  let buffer = self.limb_buffers[slot]
  dec_coeff_ensure_length(buffer, length)
  buffer
}

///|
fn DecCoeffScratchArena::save(
  self : DecCoeffScratchArena,
  value : DecCoeff,
) -> DecCoeff {
  if self.used < self.slots.length() {
    self.slots[self.used] = value
  } else {
    self.slots.push(value)
  }
  self.used += 1
  value
}

///|
fn DecCoeffScratchArena::rewind(
  self : DecCoeffScratchArena,
  mark : (Int32, Int32),
) -> Unit {
  self.used = Int32::max(0, mark.0)
  self.limb_used = Int32::max(0, mark.1)
}

///|
pub fn dec_coeff_slice(
  value : DecCoeff,
  start : Int32,
  length : Int32,
) -> DecCoeff {
  let source_len = dec_coeff_unit_len(value)
  if length <= 0 || start >= source_len {
    return dec_coeff_zero()
  }
  let len = Int32::min(length, source_len - start)
  let units = Array::make(len, 0U)
  for index in 0..<len {
    units[index] = dec_coeff_limb_at(value, start + index)
  }
  dec_coeff_from_unit_accumulator(units, len)
}

///|
fn dec_coeff_slice_arena(
  value : DecCoeff,
  start : Int32,
  length : Int32,
  arena : DecCoeffScratchArena,
) -> DecCoeff {
  let source_len = dec_coeff_unit_len(value)
  if length <= 0 || start >= source_len {
    return dec_coeff_zero()
  }
  let len = Int32::min(length, source_len - start)
  let units = arena.alloc_limbs(len)
  for index in 0..<len {
    units[index] = dec_coeff_limb_at(value, start + index)
  }
  dec_coeff_from_unit_accumulator(units, len)
}

///|
fn dec_coeff_shift_limbs(value : DecCoeff, shift : Int32) -> DecCoeff {
  guard shift >= 0 else { abort("decimal coefficient limb shift is negative") }
  if shift == 0 || value.is_zero() {
    return value
  }
  let source_len = dec_coeff_unit_len(value)
  let units = Array::make(source_len + shift, 0U)
  for index in 0..<source_len {
    units[index + shift] = dec_coeff_limb_at(value, index)
  }
  dec_coeff_from_unit_accumulator(units, units.length())
}

///|
fn dec_coeff_add_product_at(
  result : Array[UInt64],
  index : Int32,
  product : UInt64,
) -> Unit {
  let mut target = index
  let mut carry = product
  while carry != 0UL {
    let current = result[target] + carry
    result[target] = current % dec_coeff_wide_base
    carry = current / dec_coeff_wide_base
    target += 1
  }
}

///|
fn dec_coeff_accumulate_at(
  accumulator : Array[UInt64],
  value : DecCoeff,
  offset : Int32,
) -> Unit {
  let value_len = dec_coeff_unit_len(value)
  let mut carry = 0UL
  for index in 0..<value_len {
    let target = offset + index
    let sum = accumulator[target] +
      dec_coeff_limb_at(value, index).to_uint64() +
      carry
    accumulator[target] = sum % dec_coeff_wide_base
    carry = sum / dec_coeff_wide_base
  }
  let mut target = offset + value_len
  while carry != 0UL {
    let sum = accumulator[target] + carry
    accumulator[target] = sum % dec_coeff_wide_base
    carry = sum / dec_coeff_wide_base
    target += 1
  }
}

///|
fn dec_coeff_mul_inline(left : DecCoeff, right : DecCoeff) -> DecCoeff {
  let product = dec_coeff_limb_at(left, 0).to_uint64() *
    dec_coeff_limb_at(right, 0).to_uint64()
  if product < dec_coeff_wide_base {
    dec_coeff_from_int(product.to_int())
  } else {
    dec_coeff_from_unit_accumulator(
      [
        (product % dec_coeff_wide_base).to_uint(),
        (product / dec_coeff_wide_base).to_uint(),
      ],
      2,
    )
  }
}

///|
/// The square of a limb array in column order, into `result` (zeroed, at least
/// `2 * len` long). Column `c` is `2 * sum(v[i] * v[c - i], i < c - i)` plus
/// `v[c / 2]^2` when `c` is even.
///
/// The cross products are accumulated without the factor 2, in groups of
/// `dec_coeff_column_fold` = 16 as in `dec_coeff_mul_columns`: the accumulator
/// `acc` starts at 0 (no carry in it), sixteen products add less than
/// `16 * (10^9 - 1)^2 < 1.6 * 10^19 < 2^64 = 1.8446... * 10^19`, then it is
/// folded (`q = acc / 10^9`, `acc` below `10^9`, `q` added to `folded`), and at
/// the end of the column one more fold leaves `acc < 10^9`. A doubled product
/// would be below `2 * 10^18` and only 9 of them would fit in 64 bits; doubling
/// after the sum keeps 16 per fold. The doubling is applied once to the two
/// results: the column value is `carry + v[c / 2]^2 + 2 * acc`, below
/// `carry + 10^18 + 2 * 10^9`, and the carry out is `value / 10^9 + 2 * folded`.
///
/// Bound on the carry: a column has `n <= len / 2` cross products, each below
/// `10^18`, so `folded < n * 10^9` and `2 * folded < len * 10^9`. The result
/// array has `2 * len + 1 < 2^31` elements, so `len < 2^30` and `2 * folded <
/// 1.08 * 10^18`; with `value / 10^9 < carry / 10^9 + 10^9 + 3` the induction on
/// the columns gives `carry < 1.08 * 10^18 + 10^9 + 3 + carry / 10^9`, i.e.
/// `carry < 1.0800001 * 10^18`, and `value < 2.1 * 10^18 < 2^64`: the sums
/// cannot overflow for any operand the function can receive.
///
/// No short-operand case is needed here: the square is faster than the former
/// loop at every length measured (5 to 112 limbs) and its groups hold 16
/// cross products at all sizes.
fn dec_coeff_square_columns(
  value : Array[UInt32],
  len : Int32,
  result : Array[UInt32],
) -> Unit {
  let base = dec_coeff_wide_base
  let columns = 2 * len - 1
  let mut carry = 0UL
  for column in 0..<columns {
    let start = Int32::max(0, column - (len - 1))
    // cross products: index < column - index
    let stop = (column - 1) / 2
    let mut acc = 0UL
    let mut folded = 0UL
    let mut index = start
    while index <= stop && column > 0 {
      let group_end = if stop - index >= dec_coeff_column_fold {
        index + dec_coeff_column_fold - 1
      } else {
        stop
      }
      while index <= group_end {
        acc += value.unsafe_get(index).to_uint64() *
          value.unsafe_get(column - index).to_uint64()
        index += 1
      }
      if index <= stop {
        let quotient = acc / base
        acc = acc - quotient * base
        folded += quotient
      }
    }
    let quotient = acc / base
    acc = acc - quotient * base
    folded += quotient
    let mut total = carry + 2UL * acc
    if column % 2 == 0 {
      let middle = value.unsafe_get(column / 2).to_uint64()
      total += middle * middle
    }
    let next = total / base
    result.unsafe_set(column, (total - next * base).to_uint())
    carry = next + 2UL * folded
  }
  let mut column = columns
  while carry != 0UL {
    let quotient = carry / base
    result.unsafe_set(column, (carry - quotient * base).to_uint())
    carry = quotient
    column += 1
  }
}

///|
fn dec_coeff_square_schoolbook(value : DecCoeff) -> DecCoeff {
  if value.is_zero() {
    return dec_coeff_zero()
  }
  let len = dec_coeff_unit_len(value)
  let result = Array::make(len * 2 + 1, 0U)
  dec_coeff_square_columns(dec_coeff_limb_view(value), len, result)
  dec_coeff_from_unit_accumulator(result, result.length())
}

///|
fn dec_coeff_nonzero_count_limited(value : DecCoeff, limit : Int32) -> Int32? {
  let len = dec_coeff_unit_len(value)
  let mut count = 0
  for index in 0..<len {
    if dec_coeff_limb_at(value, index) != 0U {
      count += 1
      if count > limit {
        return None
      }
    }
  }
  Some(count)
}

///|
fn dec_coeff_maybe_sparse(value : DecCoeff) -> Bool {
  let len = dec_coeff_unit_len(value)
  let probes = Int32::min(8, len)
  for probe in 0..<probes {
    let index = probe * len / probes
    if dec_coeff_limb_at(value, index) == 0U {
      return true
    }
  }
  false
}

///|
fn dec_coeff_mul_sparse(left : DecCoeff, right : DecCoeff) -> DecCoeff {
  let left_len = dec_coeff_unit_len(left)
  let right_len = dec_coeff_unit_len(right)
  let result = Array::make(left_len + right_len + 1, 0UL)
  let left_indices : Array[Int32] = []
  let left_values : Array[UInt64] = []
  let right_indices : Array[Int32] = []
  let right_values : Array[UInt64] = []
  for index in 0..<left_len {
    let value = dec_coeff_limb_at(left, index)
    if value != 0U {
      left_indices.push(index)
      left_values.push(value.to_uint64())
    }
  }
  for index in 0..<right_len {
    let value = dec_coeff_limb_at(right, index)
    if value != 0U {
      right_indices.push(index)
      right_values.push(value.to_uint64())
    }
  }
  for left_index in 0..<left_indices.length() {
    for right_index in 0..<right_indices.length() {
      dec_coeff_add_product_at(
        result,
        left_indices[left_index] + right_indices[right_index],
        left_values[left_index] * right_values[right_index],
      )
    }
  }
  dec_coeff_from_wide_accumulator(result, result.length())
}

///|
fn dec_coeff_mul_karatsuba_inner(
  left : DecCoeff,
  right : DecCoeff,
  arena : DecCoeffScratchArena,
  base_threshold : Int32,
  square : Bool,
  depth : Int32,
) -> DecCoeff {
  let left_len = dec_coeff_unit_len(left)
  let right_len = dec_coeff_unit_len(right)
  let shorter = Int32::min(left_len, right_len)
  let longer = Int32::max(left_len, right_len)
  if shorter < base_threshold || longer > 2 * shorter || depth >= 64 {
    return if square {
      dec_coeff_square_schoolbook(left)
    } else {
      dec_coeff_mul_schoolbook(left, right)
    }
  }
  let mark = arena.mark()
  let split = (longer + 1) / 2
  let left0 = arena.save(dec_coeff_slice_arena(left, 0, split, arena))
  let left1 = arena.save(
    dec_coeff_slice_arena(left, split, longer - split, arena),
  )
  let right0 = arena.save(dec_coeff_slice_arena(right, 0, split, arena))
  let right1 = arena.save(
    dec_coeff_slice_arena(right, split, longer - split, arena),
  )
  let z0 = arena.save(
    dec_coeff_mul_karatsuba_inner(
      left0,
      right0,
      arena,
      base_threshold,
      square,
      depth + 1,
    ),
  )
  let z2 = arena.save(
    dec_coeff_mul_karatsuba_inner(
      left1,
      right1,
      arena,
      base_threshold,
      square,
      depth + 1,
    ),
  )
  let sums = dec_coeff_mul_karatsuba_inner(
    dec_coeff_magnitude_add_repr(left0, left1),
    dec_coeff_magnitude_add_repr(right0, right1),
    arena,
    base_threshold,
    square,
    depth + 1,
  )
  let z1 = dec_coeff_magnitude_sub_repr(
    dec_coeff_magnitude_sub_repr(sums, z0),
    z2,
  )
  let result = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(z0, dec_coeff_shift_limbs(z1, split)),
    dec_coeff_shift_limbs(z2, split * 2),
  )
  arena.rewind(mark)
  result
}

///|
fn dec_coeff_mul_karatsuba(left : DecCoeff, right : DecCoeff) -> DecCoeff {
  let arena = dec_coeff_scratch_arena_new()
  dec_coeff_mul_karatsuba_inner(
    left, right, arena, dec_coeff_karatsuba_threshold, false, 0,
  )
}

///|
fn dec_coeff_square_karatsuba(value : DecCoeff) -> DecCoeff {
  let arena = dec_coeff_scratch_arena_new()
  dec_coeff_mul_karatsuba_inner(
    value, value, arena, dec_coeff_karatsuba_square_threshold, true, 0,
  )
}

///|
fn dec_coeff_mul_toom3(left : DecCoeff, right : DecCoeff) -> DecCoeff {
  let arena = dec_coeff_scratch_arena_new()
  let mark = arena.mark()
  let maximum_len = Int32::max(
    dec_coeff_unit_len(left),
    dec_coeff_unit_len(right),
  )
  let split = (maximum_len + 2) / 3
  let left0 = arena.save(dec_coeff_slice_arena(left, 0, split, arena))
  let left1 = arena.save(dec_coeff_slice_arena(left, split, split, arena))
  let left2 = arena.save(dec_coeff_slice_arena(left, split * 2, split, arena))
  let right0 = arena.save(dec_coeff_slice_arena(right, 0, split, arena))
  let right1 = arena.save(dec_coeff_slice_arena(right, split, split, arena))
  let right2 = arena.save(dec_coeff_slice_arena(right, split * 2, split, arena))
  let left_at_one = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(left0, left1),
    left2,
  )
  let right_at_one = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(right0, right1),
    right2,
  )
  let left_at_minus_one = dec_coeff_signed_scratch(false, left0)
    .sub(dec_coeff_signed_scratch(false, left1))
    .add(dec_coeff_signed_scratch(false, left2))
  let right_at_minus_one = dec_coeff_signed_scratch(false, right0)
    .sub(dec_coeff_signed_scratch(false, right1))
    .add(dec_coeff_signed_scratch(false, right2))
  let left_at_two = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(
      left0,
      dec_coeff_multiply_by_unit_repr(left1, 2),
    ),
    dec_coeff_multiply_by_unit_repr(left2, 4),
  )
  let right_at_two = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(
      right0,
      dec_coeff_multiply_by_unit_repr(right1, 2),
    ),
    dec_coeff_multiply_by_unit_repr(right2, 4),
  )
  let coefficient0 = dec_coeff_multiply_repr(left0, right0)
  let coefficient4 = dec_coeff_multiply_repr(left2, right2)
  let product1 = dec_coeff_signed_scratch(
    false,
    dec_coeff_multiply_repr(left_at_one, right_at_one),
  )
  let product_minus_one = left_at_minus_one.mul(right_at_minus_one)
  let product2 = dec_coeff_signed_scratch(
    false,
    dec_coeff_multiply_repr(left_at_two, right_at_two),
  )
  let coefficient0_signed = dec_coeff_signed_scratch(false, coefficient0)
  let coefficient4_signed = dec_coeff_signed_scratch(false, coefficient4)
  let odd_sum = product1.sub(product_minus_one).div_exact_small(2)
  let coefficient2 = product1
    .add(product_minus_one)
    .div_exact_small(2)
    .sub(coefficient0_signed)
    .sub(coefficient4_signed)
  let odd_weighted = product2
    .sub(coefficient0_signed)
    .sub(
      dec_coeff_signed_scratch(
        coefficient2.negative,
        dec_coeff_multiply_by_unit_repr(coefficient2.magnitude, 4),
      ),
    )
    .sub(
      dec_coeff_signed_scratch(
        false,
        dec_coeff_multiply_by_unit_repr(coefficient4, 16),
      ),
    )
    .div_exact_small(2)
  let coefficient3 = odd_weighted.sub(odd_sum).div_exact_small(3)
  let coefficient1 = odd_sum.sub(coefficient3)
  let result = dec_coeff_magnitude_add_repr(
    dec_coeff_magnitude_add_repr(
      dec_coeff_magnitude_add_repr(
        dec_coeff_magnitude_add_repr(
          coefficient0,
          dec_coeff_shift_limbs(coefficient1.nonnegative(), split),
        ),
        dec_coeff_shift_limbs(coefficient2.nonnegative(), split * 2),
      ),
      dec_coeff_shift_limbs(coefficient3.nonnegative(), split * 3),
    ),
    dec_coeff_shift_limbs(coefficient4, split * 4),
  )
  arena.rewind(mark)
  result
}

///|
fn dec_coeff_mul_unbalanced(shorter : DecCoeff, longer : DecCoeff) -> DecCoeff {
  let shorter_len = dec_coeff_unit_len(shorter)
  let longer_len = dec_coeff_unit_len(longer)
  if shorter_len >= dec_coeff_karatsuba_threshold {
    let arena = dec_coeff_scratch_arena_new()
    let accumulator = Array::make(shorter_len + longer_len + 1, 0UL)
    let mut start = 0
    while start < longer_len {
      let mark = arena.mark()
      let block = arena.save(
        dec_coeff_slice_arena(
          longer,
          start,
          Int32::min(shorter_len, longer_len - start),
          arena,
        ),
      )
      let product = dec_coeff_multiply_repr(shorter, block)
      dec_coeff_accumulate_at(accumulator, product, start)
      arena.rewind(mark)
      start += shorter_len
    }
    return dec_coeff_from_wide_accumulator(accumulator, accumulator.length())
  }
  let accumulator = Array::make(shorter_len + longer_len + 1, 0UL)
  for right_index in 0..<longer_len {
    let multiplier = dec_coeff_limb_at(longer, right_index).to_uint64()
    if multiplier == 0UL {
      continue
    }
    for left_index in 0..<shorter_len {
      let limb = dec_coeff_limb_at(shorter, left_index).to_uint64()
      if limb != 0UL {
        dec_coeff_add_product_at(
          accumulator,
          left_index + right_index,
          limb * multiplier,
        )
      }
    }
  }
  dec_coeff_from_wide_accumulator(accumulator, accumulator.length())
}

///|
fn dec_coeff_mul_algorithm(
  left : DecCoeff,
  right : DecCoeff,
) -> DecCoeffMulAlgorithm {
  let left_len = dec_coeff_unit_len(left)
  let right_len = dec_coeff_unit_len(right)
  if left_len == 1 && right_len == 1 {
    return Inline
  }
  if left_len >= 8 &&
    right_len >= 8 &&
    (dec_coeff_maybe_sparse(left) || dec_coeff_maybe_sparse(right)) {
    match dec_coeff_nonzero_count_limited(left, left_len) {
      Some(left_count) =>
        match dec_coeff_nonzero_count_limited(right, right_len) {
          Some(right_count) if left_count.to_int64() *
            right_count.to_int64() *
            4L <
            left_len.to_int64() * right_len.to_int64() => return Sparse
          _ => ()
        }
      None => ()
    }
  }
  let shorter = Int32::min(left_len, right_len)
  let longer = Int32::max(left_len, right_len)
  if longer > 2 * shorter {
    return Unbalanced
  }
  if dec_coeff_ntt_mul_profitable(left, right) &&
    dec_coeff_ntt_fits(left, right) {
    Ntt
  } else if shorter >= dec_coeff_toom3_threshold {
    Toom3
  } else if shorter >= dec_coeff_karatsuba_threshold {
    Karatsuba
  } else {
    Schoolbook
  }
}

///|
fn dec_coeff_ntt_mul_profitable(left : DecCoeff, right : DecCoeff) -> Bool {
  let transform_length = dec_coeff_ntt_transform_length(left, right)
  let threshold = if transform_length <= 8192 {
    dec_coeff_ntt_mul_threshold
  } else if transform_length <= 16384 {
    dec_coeff_ntt_mul_threshold_16k
  } else if transform_length <= 32768 {
    dec_coeff_ntt_mul_threshold_32k
  } else if transform_length <= 65536 {
    dec_coeff_ntt_mul_threshold_64k
  } else {
    dec_coeff_ntt_mul_threshold_large
  }
  Int32::min(dec_coeff_unit_len(left), dec_coeff_unit_len(right)) >= threshold
}

///|
fn dec_coeff_multiply_forced(
  algorithm : DecCoeffMulAlgorithm,
  left : DecCoeff,
  right : DecCoeff,
) -> DecCoeff {
  match algorithm {
    Inline => dec_coeff_mul_inline(left, right)
    Schoolbook => dec_coeff_mul_schoolbook(left, right)
    Sparse => dec_coeff_mul_sparse(left, right)
    Unbalanced =>
      if dec_coeff_unit_len(left) <= dec_coeff_unit_len(right) {
        dec_coeff_mul_unbalanced(left, right)
      } else {
        dec_coeff_mul_unbalanced(right, left)
      }
    Karatsuba => dec_coeff_mul_karatsuba(left, right)
    Toom3 => dec_coeff_mul_toom3(left, right)
    Ntt => dec_coeff_mul_ntt(left, right)
  }
}

///|
pub fn dec_coeff_multiply_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return dec_coeff_zero()
  }
  if dec_coeff_unit_len(lhs) == 1 {
    let unit = dec_coeff_limb_at(lhs, 0).reinterpret_as_int()
    if unit == 1 {
      return rhs
    }
    return dec_coeff_multiply_by_unit_repr(rhs, unit)
  }
  if dec_coeff_unit_len(rhs) == 1 {
    let unit = dec_coeff_limb_at(rhs, 0).reinterpret_as_int()
    if unit == 1 {
      return lhs
    }
    return dec_coeff_multiply_by_unit_repr(lhs, unit)
  }
  if dec_coeff_small_value(lhs) is Some(left) &&
    dec_coeff_small_value(rhs) is Some(right) &&
    right <= (dec_coeff_small_limit - 1UL) / left {
    return DecCoeff::Small(left * right)
  }
  if dec_coeff_compare_repr(lhs, rhs) == 0 {
    return dec_coeff_square_repr(lhs)
  }
  dec_coeff_multiply_forced(dec_coeff_mul_algorithm(lhs, rhs), lhs, rhs)
}

///|
fn dec_coeff_square_algorithm(value : DecCoeff) -> DecCoeffMulAlgorithm {
  let len = dec_coeff_unit_len(value)
  if len == 1 {
    Inline
  } else if len >= dec_coeff_toom3_threshold {
    if dec_coeff_ntt_square_toom3_profitable(value) &&
      dec_coeff_ntt_fits(value, value) {
      Ntt
    } else {
      Toom3
    }
  } else if dec_coeff_ntt_square_profitable(value) &&
    dec_coeff_ntt_fits(value, value) {
    Ntt
  } else if len >= dec_coeff_karatsuba_square_threshold {
    Karatsuba
  } else {
    Schoolbook
  }
}

///|
fn dec_coeff_ntt_square_profitable(value : DecCoeff) -> Bool {
  let transform_length = dec_coeff_ntt_transform_length(value, value)
  let threshold = if transform_length <= 4096 {
    dec_coeff_ntt_square_threshold
  } else if transform_length <= 8192 {
    dec_coeff_ntt_square_threshold_8k
  } else if transform_length <= 16384 {
    dec_coeff_ntt_square_threshold_16k
  } else if transform_length <= 32768 {
    dec_coeff_ntt_square_threshold_32k
  } else if transform_length <= 65536 {
    dec_coeff_ntt_square_threshold_64k
  } else {
    dec_coeff_ntt_square_threshold_large
  }
  dec_coeff_unit_len(value) >= threshold
}

///|
fn dec_coeff_ntt_square_toom3_profitable(value : DecCoeff) -> Bool {
  let transform_length = dec_coeff_ntt_transform_length(value, value)
  let threshold = if transform_length <= 4096 {
    dec_coeff_ntt_square_toom3_threshold
  } else if transform_length <= 8192 {
    dec_coeff_ntt_square_toom3_threshold_8k
  } else if transform_length <= 16384 {
    dec_coeff_ntt_square_toom3_threshold_16k
  } else if transform_length <= 32768 {
    dec_coeff_ntt_square_toom3_threshold_32k
  } else if transform_length <= 65536 {
    dec_coeff_ntt_square_toom3_threshold_64k
  } else {
    dec_coeff_ntt_square_toom3_threshold_large
  }
  dec_coeff_unit_len(value) >= threshold
}

///|
pub fn dec_coeff_square_repr(value : DecCoeff) -> DecCoeff {
  if value.is_zero() {
    return dec_coeff_zero()
  }
  if dec_coeff_small_value(value) is Some(small) &&
    small <= (dec_coeff_small_limit - 1UL) / small {
    return DecCoeff::Small(small * small)
  }
  match dec_coeff_square_algorithm(value) {
    Inline => dec_coeff_mul_inline(value, value)
    Schoolbook => dec_coeff_square_schoolbook(value)
    Karatsuba => dec_coeff_square_karatsuba(value)
    Toom3 => dec_coeff_mul_toom3(value, value)
    Ntt => dec_coeff_square_ntt(value)
    Sparse | Unbalanced => abort("invalid decimal coefficient square dispatch")
  }
}
