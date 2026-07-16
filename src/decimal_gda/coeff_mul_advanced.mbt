///|
#warnings("-unused_value")
priv enum GdaCoeffMulAlgorithm {
  Inline
  Schoolbook
  Sparse
  Unbalanced
  Karatsuba
  Toom3
  Ntt
} derive(Eq)

///|
priv struct GdaCoeffSignedScratch {
  negative : Bool
  magnitude : GdaCoeff
}

///|
fn gda_coeff_signed_scratch(
  negative : Bool,
  magnitude : GdaCoeff,
) -> GdaCoeffSignedScratch {
  { negative: negative && !magnitude.is_zero(), magnitude }
}

///|
fn GdaCoeffSignedScratch::neg(
  self : GdaCoeffSignedScratch,
) -> GdaCoeffSignedScratch {
  gda_coeff_signed_scratch(!self.negative, self.magnitude)
}

///|
fn GdaCoeffSignedScratch::add(
  self : GdaCoeffSignedScratch,
  other : GdaCoeffSignedScratch,
) -> GdaCoeffSignedScratch {
  let (negative, magnitude) = gda_coeff_signed_add_repr(
    self.negative,
    self.magnitude,
    other.negative,
    other.magnitude,
  )
  gda_coeff_signed_scratch(negative, magnitude)
}

///|
fn GdaCoeffSignedScratch::sub(
  self : GdaCoeffSignedScratch,
  other : GdaCoeffSignedScratch,
) -> GdaCoeffSignedScratch {
  self.add(other.neg())
}

///|
fn GdaCoeffSignedScratch::mul(
  self : GdaCoeffSignedScratch,
  other : GdaCoeffSignedScratch,
) -> GdaCoeffSignedScratch {
  gda_coeff_signed_scratch(
    self.negative != other.negative,
    gda_coeff_multiply_repr(self.magnitude, other.magnitude),
  )
}

///|
fn GdaCoeffSignedScratch::div_exact_small(
  self : GdaCoeffSignedScratch,
  divisor : Int,
) -> GdaCoeffSignedScratch {
  let (quotient, remainder) = gda_coeff_div_rem_by_unit_repr(
    self.magnitude,
    divisor,
  )
  guard remainder == 0 else {
    abort("Toom-3 interpolation division was not exact")
  }
  gda_coeff_signed_scratch(self.negative, quotient)
}

///|
fn GdaCoeffSignedScratch::nonnegative(self : GdaCoeffSignedScratch) -> GdaCoeff {
  guard !self.negative else {
    abort("Toom-3 produced a negative output coefficient")
  }
  self.magnitude
}

///|
priv struct GdaCoeffScratchArena {
  slots : Array[GdaCoeff]
  mut used : Int
  limb_buffers : Array[Array[UInt]]
  mut limb_used : Int
}

///|
fn gda_coeff_scratch_arena_new() -> GdaCoeffScratchArena {
  { slots: [], used: 0, limb_buffers: [], limb_used: 0 }
}

///|
fn GdaCoeffScratchArena::mark(self : GdaCoeffScratchArena) -> (Int, Int) {
  (self.used, self.limb_used)
}

///|
fn GdaCoeffScratchArena::alloc_limbs(
  self : GdaCoeffScratchArena,
  length : Int,
) -> Array[UInt] {
  guard length > 0 else { return [0U] }
  let slot = self.limb_used
  self.limb_used += 1
  if slot >= self.limb_buffers.length() {
    self.limb_buffers.push([])
  }
  let buffer = self.limb_buffers[slot]
  gda_coeff_ensure_length(buffer, length)
  buffer
}

///|
fn GdaCoeffScratchArena::save(
  self : GdaCoeffScratchArena,
  value : GdaCoeff,
) -> GdaCoeff {
  if self.used < self.slots.length() {
    self.slots[self.used] = value
  } else {
    self.slots.push(value)
  }
  self.used += 1
  value
}

///|
fn GdaCoeffScratchArena::rewind(
  self : GdaCoeffScratchArena,
  mark : (Int, Int),
) -> Unit {
  self.used = Int::max(0, mark.0)
  self.limb_used = Int::max(0, mark.1)
}

///|
fn gda_coeff_slice(value : GdaCoeff, start : Int, length : Int) -> GdaCoeff {
  let source_len = gda_coeff_unit_len(value)
  if length <= 0 || start >= source_len {
    return gda_coeff_zero()
  }
  let len = Int::min(length, source_len - start)
  let units = Array::make(len, 0U)
  for index in 0..<len {
    units[index] = gda_coeff_limb_at(value, start + index)
  }
  gda_coeff_from_unit_accumulator(units, len)
}

///|
fn gda_coeff_slice_arena(
  value : GdaCoeff,
  start : Int,
  length : Int,
  arena : GdaCoeffScratchArena,
) -> GdaCoeff {
  let source_len = gda_coeff_unit_len(value)
  if length <= 0 || start >= source_len {
    return gda_coeff_zero()
  }
  let len = Int::min(length, source_len - start)
  let units = arena.alloc_limbs(len)
  for index in 0..<len {
    units[index] = gda_coeff_limb_at(value, start + index)
  }
  gda_coeff_from_unit_accumulator(units, len)
}

///|
fn gda_coeff_shift_limbs(value : GdaCoeff, shift : Int) -> GdaCoeff {
  guard shift >= 0 else { abort("decimal coefficient limb shift is negative") }
  if shift == 0 || value.is_zero() {
    return value
  }
  let source_len = gda_coeff_unit_len(value)
  let units = Array::make(source_len + shift, 0U)
  for index in 0..<source_len {
    units[index + shift] = gda_coeff_limb_at(value, index)
  }
  gda_coeff_from_unit_accumulator(units, units.length())
}

///|
fn gda_coeff_add_product_at(
  result : Array[UInt64],
  index : Int,
  product : UInt64,
) -> Unit {
  let mut target = index
  let mut carry = product
  while carry != 0UL {
    let current = result[target] + carry
    result[target] = current % gda_coeff_wide_base
    carry = current / gda_coeff_wide_base
    target += 1
  }
}

///|
fn gda_coeff_accumulate_at(
  accumulator : Array[UInt64],
  value : GdaCoeff,
  offset : Int,
) -> Unit {
  let value_len = gda_coeff_unit_len(value)
  let mut carry = 0UL
  for index in 0..<value_len {
    let target = offset + index
    let sum = accumulator[target] +
      gda_coeff_limb_at(value, index).to_uint64() +
      carry
    accumulator[target] = sum % gda_coeff_wide_base
    carry = sum / gda_coeff_wide_base
  }
  let mut target = offset + value_len
  while carry != 0UL {
    let sum = accumulator[target] + carry
    accumulator[target] = sum % gda_coeff_wide_base
    carry = sum / gda_coeff_wide_base
    target += 1
  }
}

///|
fn gda_coeff_mul_inline(left : GdaCoeff, right : GdaCoeff) -> GdaCoeff {
  let product = gda_coeff_limb_at(left, 0).to_uint64() *
    gda_coeff_limb_at(right, 0).to_uint64()
  if product < gda_coeff_wide_base {
    gda_coeff_from_int(product.to_int())
  } else {
    gda_coeff_from_unit_accumulator(
      [
        (product % gda_coeff_wide_base).to_uint(),
        (product / gda_coeff_wide_base).to_uint(),
      ],
      2,
    )
  }
}

///|
fn gda_coeff_square_schoolbook(value : GdaCoeff) -> GdaCoeff {
  if value.is_zero() {
    return gda_coeff_zero()
  }
  let len = gda_coeff_unit_len(value)
  let result = Array::make(len * 2 + 1, 0UL)
  for left in 0..<len {
    let left_limb = gda_coeff_limb_at(value, left).to_uint64()
    gda_coeff_add_product_at(result, left * 2, left_limb * left_limb)
    for right in (left + 1)..<len {
      let product = left_limb * gda_coeff_limb_at(value, right).to_uint64()
      gda_coeff_add_product_at(result, left + right, product * 2UL)
    }
  }
  gda_coeff_from_wide_accumulator(result, result.length())
}

///|
fn gda_coeff_nonzero_count_limited(value : GdaCoeff, limit : Int) -> Int? {
  let len = gda_coeff_unit_len(value)
  let mut count = 0
  for index in 0..<len {
    if gda_coeff_limb_at(value, index) != 0U {
      count += 1
      if count > limit {
        return None
      }
    }
  }
  Some(count)
}

///|
fn gda_coeff_maybe_sparse(value : GdaCoeff) -> Bool {
  let len = gda_coeff_unit_len(value)
  let probes = Int::min(8, len)
  for probe in 0..<probes {
    let index = probe * len / probes
    if gda_coeff_limb_at(value, index) == 0U {
      return true
    }
  }
  false
}

///|
fn gda_coeff_mul_sparse(left : GdaCoeff, right : GdaCoeff) -> GdaCoeff {
  let left_len = gda_coeff_unit_len(left)
  let right_len = gda_coeff_unit_len(right)
  let result = Array::make(left_len + right_len + 1, 0UL)
  let left_indices : Array[Int] = []
  let left_values : Array[UInt64] = []
  let right_indices : Array[Int] = []
  let right_values : Array[UInt64] = []
  for index in 0..<left_len {
    let value = gda_coeff_limb_at(left, index)
    if value != 0U {
      left_indices.push(index)
      left_values.push(value.to_uint64())
    }
  }
  for index in 0..<right_len {
    let value = gda_coeff_limb_at(right, index)
    if value != 0U {
      right_indices.push(index)
      right_values.push(value.to_uint64())
    }
  }
  for left_index in 0..<left_indices.length() {
    for right_index in 0..<right_indices.length() {
      gda_coeff_add_product_at(
        result,
        left_indices[left_index] + right_indices[right_index],
        left_values[left_index] * right_values[right_index],
      )
    }
  }
  gda_coeff_from_wide_accumulator(result, result.length())
}

///|
fn gda_coeff_mul_karatsuba_inner(
  left : GdaCoeff,
  right : GdaCoeff,
  arena : GdaCoeffScratchArena,
  base_threshold : Int,
  square : Bool,
  depth : Int,
) -> GdaCoeff {
  let left_len = gda_coeff_unit_len(left)
  let right_len = gda_coeff_unit_len(right)
  let shorter = Int::min(left_len, right_len)
  let longer = Int::max(left_len, right_len)
  if shorter < base_threshold || longer > 2 * shorter || depth >= 64 {
    return if square {
      gda_coeff_square_schoolbook(left)
    } else {
      gda_coeff_mul_schoolbook(left, right)
    }
  }
  let mark = arena.mark()
  let split = (longer + 1) / 2
  let left0 = arena.save(gda_coeff_slice_arena(left, 0, split, arena))
  let left1 = arena.save(
    gda_coeff_slice_arena(left, split, longer - split, arena),
  )
  let right0 = arena.save(gda_coeff_slice_arena(right, 0, split, arena))
  let right1 = arena.save(
    gda_coeff_slice_arena(right, split, longer - split, arena),
  )
  let z0 = arena.save(
    gda_coeff_mul_karatsuba_inner(
      left0,
      right0,
      arena,
      base_threshold,
      square,
      depth + 1,
    ),
  )
  let z2 = arena.save(
    gda_coeff_mul_karatsuba_inner(
      left1,
      right1,
      arena,
      base_threshold,
      square,
      depth + 1,
    ),
  )
  let sums = gda_coeff_mul_karatsuba_inner(
    gda_coeff_magnitude_add_repr(left0, left1),
    gda_coeff_magnitude_add_repr(right0, right1),
    arena,
    base_threshold,
    square,
    depth + 1,
  )
  let z1 = gda_coeff_magnitude_sub_repr(
    gda_coeff_magnitude_sub_repr(sums, z0),
    z2,
  )
  let result = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(z0, gda_coeff_shift_limbs(z1, split)),
    gda_coeff_shift_limbs(z2, split * 2),
  )
  arena.rewind(mark)
  result
}

///|
fn gda_coeff_mul_karatsuba(left : GdaCoeff, right : GdaCoeff) -> GdaCoeff {
  let arena = gda_coeff_scratch_arena_new()
  gda_coeff_mul_karatsuba_inner(
    left, right, arena, gda_coeff_karatsuba_threshold, false, 0,
  )
}

///|
fn gda_coeff_square_karatsuba(value : GdaCoeff) -> GdaCoeff {
  let arena = gda_coeff_scratch_arena_new()
  gda_coeff_mul_karatsuba_inner(
    value, value, arena, gda_coeff_karatsuba_square_threshold, true, 0,
  )
}

///|
fn gda_coeff_mul_toom3(left : GdaCoeff, right : GdaCoeff) -> GdaCoeff {
  let arena = gda_coeff_scratch_arena_new()
  let mark = arena.mark()
  let maximum_len = Int::max(
    gda_coeff_unit_len(left),
    gda_coeff_unit_len(right),
  )
  let split = (maximum_len + 2) / 3
  let left0 = arena.save(gda_coeff_slice_arena(left, 0, split, arena))
  let left1 = arena.save(gda_coeff_slice_arena(left, split, split, arena))
  let left2 = arena.save(gda_coeff_slice_arena(left, split * 2, split, arena))
  let right0 = arena.save(gda_coeff_slice_arena(right, 0, split, arena))
  let right1 = arena.save(gda_coeff_slice_arena(right, split, split, arena))
  let right2 = arena.save(gda_coeff_slice_arena(right, split * 2, split, arena))
  let left_at_one = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(left0, left1),
    left2,
  )
  let right_at_one = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(right0, right1),
    right2,
  )
  let left_at_minus_one = gda_coeff_signed_scratch(false, left0)
    .sub(gda_coeff_signed_scratch(false, left1))
    .add(gda_coeff_signed_scratch(false, left2))
  let right_at_minus_one = gda_coeff_signed_scratch(false, right0)
    .sub(gda_coeff_signed_scratch(false, right1))
    .add(gda_coeff_signed_scratch(false, right2))
  let left_at_two = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(
      left0,
      gda_coeff_multiply_by_unit_repr(left1, 2),
    ),
    gda_coeff_multiply_by_unit_repr(left2, 4),
  )
  let right_at_two = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(
      right0,
      gda_coeff_multiply_by_unit_repr(right1, 2),
    ),
    gda_coeff_multiply_by_unit_repr(right2, 4),
  )
  let coefficient0 = gda_coeff_multiply_repr(left0, right0)
  let coefficient4 = gda_coeff_multiply_repr(left2, right2)
  let product1 = gda_coeff_signed_scratch(
    false,
    gda_coeff_multiply_repr(left_at_one, right_at_one),
  )
  let product_minus_one = left_at_minus_one.mul(right_at_minus_one)
  let product2 = gda_coeff_signed_scratch(
    false,
    gda_coeff_multiply_repr(left_at_two, right_at_two),
  )
  let coefficient0_signed = gda_coeff_signed_scratch(false, coefficient0)
  let coefficient4_signed = gda_coeff_signed_scratch(false, coefficient4)
  let odd_sum = product1.sub(product_minus_one).div_exact_small(2)
  let coefficient2 = product1
    .add(product_minus_one)
    .div_exact_small(2)
    .sub(coefficient0_signed)
    .sub(coefficient4_signed)
  let odd_weighted = product2
    .sub(coefficient0_signed)
    .sub(
      gda_coeff_signed_scratch(
        coefficient2.negative,
        gda_coeff_multiply_by_unit_repr(coefficient2.magnitude, 4),
      ),
    )
    .sub(
      gda_coeff_signed_scratch(
        false,
        gda_coeff_multiply_by_unit_repr(coefficient4, 16),
      ),
    )
    .div_exact_small(2)
  let coefficient3 = odd_weighted.sub(odd_sum).div_exact_small(3)
  let coefficient1 = odd_sum.sub(coefficient3)
  let result = gda_coeff_magnitude_add_repr(
    gda_coeff_magnitude_add_repr(
      gda_coeff_magnitude_add_repr(
        gda_coeff_magnitude_add_repr(
          coefficient0,
          gda_coeff_shift_limbs(coefficient1.nonnegative(), split),
        ),
        gda_coeff_shift_limbs(coefficient2.nonnegative(), split * 2),
      ),
      gda_coeff_shift_limbs(coefficient3.nonnegative(), split * 3),
    ),
    gda_coeff_shift_limbs(coefficient4, split * 4),
  )
  arena.rewind(mark)
  result
}

///|
fn gda_coeff_mul_unbalanced(shorter : GdaCoeff, longer : GdaCoeff) -> GdaCoeff {
  let shorter_len = gda_coeff_unit_len(shorter)
  let longer_len = gda_coeff_unit_len(longer)
  if shorter_len >= gda_coeff_karatsuba_threshold {
    let arena = gda_coeff_scratch_arena_new()
    let accumulator = Array::make(shorter_len + longer_len + 1, 0UL)
    let mut start = 0
    while start < longer_len {
      let mark = arena.mark()
      let block = arena.save(
        gda_coeff_slice_arena(
          longer,
          start,
          Int::min(shorter_len, longer_len - start),
          arena,
        ),
      )
      let product = gda_coeff_multiply_repr(shorter, block)
      gda_coeff_accumulate_at(accumulator, product, start)
      arena.rewind(mark)
      start += shorter_len
    }
    return gda_coeff_from_wide_accumulator(accumulator, accumulator.length())
  }
  let accumulator = Array::make(shorter_len + longer_len + 1, 0UL)
  for right_index in 0..<longer_len {
    let multiplier = gda_coeff_limb_at(longer, right_index).to_uint64()
    if multiplier == 0UL {
      continue
    }
    for left_index in 0..<shorter_len {
      let limb = gda_coeff_limb_at(shorter, left_index).to_uint64()
      if limb != 0UL {
        gda_coeff_add_product_at(
          accumulator,
          left_index + right_index,
          limb * multiplier,
        )
      }
    }
  }
  gda_coeff_from_wide_accumulator(accumulator, accumulator.length())
}

///|
fn gda_coeff_mul_algorithm(
  left : GdaCoeff,
  right : GdaCoeff,
) -> GdaCoeffMulAlgorithm {
  let left_len = gda_coeff_unit_len(left)
  let right_len = gda_coeff_unit_len(right)
  if left_len == 1 && right_len == 1 {
    return Inline
  }
  if left_len >= 8 &&
    right_len >= 8 &&
    (gda_coeff_maybe_sparse(left) || gda_coeff_maybe_sparse(right)) {
    match gda_coeff_nonzero_count_limited(left, left_len) {
      Some(left_count) =>
        match gda_coeff_nonzero_count_limited(right, right_len) {
          Some(right_count) if left_count.to_int64() *
            right_count.to_int64() *
            4L <
            left_len.to_int64() * right_len.to_int64() => return Sparse
          _ => ()
        }
      None => ()
    }
  }
  let shorter = Int::min(left_len, right_len)
  let longer = Int::max(left_len, right_len)
  if longer > 2 * shorter {
    return Unbalanced
  }
  if gda_coeff_ntt_mul_profitable(left, right) &&
    gda_coeff_ntt_fits(left, right) {
    Ntt
  } else if shorter >= gda_coeff_toom3_threshold {
    Toom3
  } else if shorter >= gda_coeff_karatsuba_threshold {
    Karatsuba
  } else {
    Schoolbook
  }
}

///|
fn gda_coeff_ntt_mul_profitable(left : GdaCoeff, right : GdaCoeff) -> Bool {
  let transform_length = gda_coeff_ntt_transform_length(left, right)
  let threshold = if transform_length <= 8192 {
    gda_coeff_ntt_mul_threshold
  } else if transform_length <= 16384 {
    gda_coeff_ntt_mul_threshold_16k
  } else if transform_length <= 32768 {
    gda_coeff_ntt_mul_threshold_32k
  } else if transform_length <= 65536 {
    gda_coeff_ntt_mul_threshold_64k
  } else {
    gda_coeff_ntt_mul_threshold_large
  }
  Int::min(gda_coeff_unit_len(left), gda_coeff_unit_len(right)) >= threshold
}

///|
fn gda_coeff_multiply_forced(
  algorithm : GdaCoeffMulAlgorithm,
  left : GdaCoeff,
  right : GdaCoeff,
) -> GdaCoeff {
  match algorithm {
    Inline => gda_coeff_mul_inline(left, right)
    Schoolbook => gda_coeff_mul_schoolbook(left, right)
    Sparse => gda_coeff_mul_sparse(left, right)
    Unbalanced =>
      if gda_coeff_unit_len(left) <= gda_coeff_unit_len(right) {
        gda_coeff_mul_unbalanced(left, right)
      } else {
        gda_coeff_mul_unbalanced(right, left)
      }
    Karatsuba => gda_coeff_mul_karatsuba(left, right)
    Toom3 => gda_coeff_mul_toom3(left, right)
    Ntt => gda_coeff_mul_ntt(left, right)
  }
}

///|
fn gda_coeff_multiply_repr(lhs : GdaCoeff, rhs : GdaCoeff) -> GdaCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return gda_coeff_zero()
  }
  if gda_coeff_unit_len(lhs) == 1 {
    let unit = gda_coeff_limb_at(lhs, 0).reinterpret_as_int()
    if unit == 1 {
      return rhs
    }
    return gda_coeff_multiply_by_unit_repr(rhs, unit)
  }
  if gda_coeff_unit_len(rhs) == 1 {
    let unit = gda_coeff_limb_at(rhs, 0).reinterpret_as_int()
    if unit == 1 {
      return lhs
    }
    return gda_coeff_multiply_by_unit_repr(lhs, unit)
  }
  if gda_coeff_small_value(lhs) is Some(left) &&
    gda_coeff_small_value(rhs) is Some(right) &&
    right <= (gda_coeff_small_limit - 1UL) / left {
    return GdaCoeff::Small(left * right)
  }
  if gda_coeff_compare_repr(lhs, rhs) == 0 {
    return gda_coeff_square_repr(lhs)
  }
  gda_coeff_multiply_forced(gda_coeff_mul_algorithm(lhs, rhs), lhs, rhs)
}

///|
fn gda_coeff_square_algorithm(value : GdaCoeff) -> GdaCoeffMulAlgorithm {
  let len = gda_coeff_unit_len(value)
  if len == 1 {
    Inline
  } else if len >= gda_coeff_toom3_threshold {
    if gda_coeff_ntt_square_toom3_profitable(value) &&
      gda_coeff_ntt_fits(value, value) {
      Ntt
    } else {
      Toom3
    }
  } else if gda_coeff_ntt_square_profitable(value) &&
    gda_coeff_ntt_fits(value, value) {
    Ntt
  } else if len >= gda_coeff_karatsuba_square_threshold {
    Karatsuba
  } else {
    Schoolbook
  }
}

///|
fn gda_coeff_ntt_square_profitable(value : GdaCoeff) -> Bool {
  let transform_length = gda_coeff_ntt_transform_length(value, value)
  let threshold = if transform_length <= 4096 {
    gda_coeff_ntt_square_threshold
  } else if transform_length <= 8192 {
    gda_coeff_ntt_square_threshold_8k
  } else if transform_length <= 16384 {
    gda_coeff_ntt_square_threshold_16k
  } else if transform_length <= 32768 {
    gda_coeff_ntt_square_threshold_32k
  } else if transform_length <= 65536 {
    gda_coeff_ntt_square_threshold_64k
  } else {
    gda_coeff_ntt_square_threshold_large
  }
  gda_coeff_unit_len(value) >= threshold
}

///|
fn gda_coeff_ntt_square_toom3_profitable(value : GdaCoeff) -> Bool {
  let transform_length = gda_coeff_ntt_transform_length(value, value)
  let threshold = if transform_length <= 4096 {
    gda_coeff_ntt_square_toom3_threshold
  } else if transform_length <= 8192 {
    gda_coeff_ntt_square_toom3_threshold_8k
  } else if transform_length <= 16384 {
    gda_coeff_ntt_square_toom3_threshold_16k
  } else if transform_length <= 32768 {
    gda_coeff_ntt_square_toom3_threshold_32k
  } else if transform_length <= 65536 {
    gda_coeff_ntt_square_toom3_threshold_64k
  } else {
    gda_coeff_ntt_square_toom3_threshold_large
  }
  gda_coeff_unit_len(value) >= threshold
}

///|
fn gda_coeff_square_repr(value : GdaCoeff) -> GdaCoeff {
  if value.is_zero() {
    return gda_coeff_zero()
  }
  if gda_coeff_small_value(value) is Some(small) &&
    small <= (gda_coeff_small_limit - 1UL) / small {
    return GdaCoeff::Small(small * small)
  }
  match gda_coeff_square_algorithm(value) {
    Inline => gda_coeff_mul_inline(value, value)
    Schoolbook => gda_coeff_square_schoolbook(value)
    Karatsuba => gda_coeff_square_karatsuba(value)
    Toom3 => gda_coeff_mul_toom3(value, value)
    Ntt => gda_coeff_square_ntt(value)
    Sparse | Unbalanced => abort("invalid decimal coefficient square dispatch")
  }
}
