///|
priv struct BinCoeffSignedScratch {
  negative : Bool
  magnitude : BinCoeff
}

///|
fn bin_coeff_signed_scratch(
  negative : Bool,
  magnitude : BinCoeff,
) -> BinCoeffSignedScratch {
  { negative: negative && !magnitude.is_zero(), magnitude }
}

///|
fn BinCoeffSignedScratch::neg(
  self : BinCoeffSignedScratch,
) -> BinCoeffSignedScratch {
  bin_coeff_signed_scratch(!self.negative, self.magnitude)
}

///|
fn BinCoeffSignedScratch::add(
  self : BinCoeffSignedScratch,
  other : BinCoeffSignedScratch,
) -> BinCoeffSignedScratch {
  if self.negative == other.negative {
    return bin_coeff_signed_scratch(
      self.negative,
      self.magnitude.add(other.magnitude),
    )
  }
  let comparison = self.magnitude.compare(other.magnitude)
  if comparison == 0 {
    bin_coeff_signed_scratch(false, BinCoeff::zero())
  } else if comparison > 0 {
    bin_coeff_signed_scratch(
      self.negative,
      self.magnitude.sub_checked(other.magnitude).unwrap(),
    )
  } else {
    bin_coeff_signed_scratch(
      other.negative,
      other.magnitude.sub_checked(self.magnitude).unwrap(),
    )
  }
}

///|
fn BinCoeffSignedScratch::sub(
  self : BinCoeffSignedScratch,
  other : BinCoeffSignedScratch,
) -> BinCoeffSignedScratch {
  self.add(other.neg())
}

///|
fn BinCoeffSignedScratch::mul(
  self : BinCoeffSignedScratch,
  other : BinCoeffSignedScratch,
) -> BinCoeffSignedScratch {
  bin_coeff_signed_scratch(
    self.negative != other.negative,
    self.magnitude.mul(other.magnitude),
  )
}

///|
fn BinCoeffSignedScratch::shift_left(
  self : BinCoeffSignedScratch,
  shift : Int,
) -> BinCoeffSignedScratch {
  bin_coeff_signed_scratch(self.negative, self.magnitude.shift_left(shift))
}

///|
fn BinCoeffSignedScratch::div_exact_small(
  self : BinCoeffSignedScratch,
  divisor : UInt64,
) -> BinCoeffSignedScratch {
  let (quotient, remainder) = self.magnitude
    .div_rem_checked(BinCoeff::from_uint64(divisor))
    .unwrap()
  guard remainder.is_zero() else {
    abort("Toom-3 interpolation division was not exact")
  }
  bin_coeff_signed_scratch(self.negative, quotient)
}

///|
fn BinCoeffSignedScratch::nonnegative(self : BinCoeffSignedScratch) -> BinCoeff {
  guard !self.negative else {
    abort("Toom-3 produced a negative output coefficient")
  }
  self.magnitude
}

///|
fn bin_coeff_slice(value : BinCoeff, start : Int, length : Int) -> BinCoeff {
  let source_len = bin_coeff_limb_len(value)
  if length <= 0 || start >= source_len {
    return BinCoeff::zero()
  }
  let len = Int::min(length, source_len - start)
  let limbs = FixedArray::make(len, 0U)
  for index in 0..<len {
    limbs.unsafe_set(index, bin_coeff_limb(value, start + index))
  }
  bin_coeff_from_limbs(limbs, len)
}

///|
priv struct BinCoeffScratchArena {
  slots : FixedArray[BinCoeff]
  mut used : Int
}

///|
fn bin_coeff_scratch_arena_new(capacity : Int) -> BinCoeffScratchArena {
  { slots: FixedArray::make(Int::max(1, capacity), BinCoeff::zero()), used: 0 }
}

///|
fn BinCoeffScratchArena::mark(self : BinCoeffScratchArena) -> Int {
  self.used
}

///|
fn BinCoeffScratchArena::save(
  self : BinCoeffScratchArena,
  value : BinCoeff,
) -> BinCoeff {
  if self.used < self.slots.length() {
    self.slots.unsafe_set(self.used, value)
    self.used += 1
  }
  value
}

///|
fn BinCoeffScratchArena::rewind(
  self : BinCoeffScratchArena,
  mark : Int,
) -> Unit {
  self.used = Int::max(0, mark)
}

///|
fn bin_coeff_mul_karatsuba_scratch(
  left : BinCoeff,
  right : BinCoeff,
  arena : BinCoeffScratchArena,
) -> BinCoeff {
  let mark = arena.mark()
  let result = arena.save(bin_coeff_mul_karatsuba(left, right))
  arena.rewind(mark)
  result
}

///|
fn bin_coeff_mul_karatsuba(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let maximum_len = Int::max(
    bin_coeff_limb_len(left),
    bin_coeff_limb_len(right),
  )
  let split = (maximum_len + 1) / 2
  let left_low = bin_coeff_slice(left, 0, split)
  let left_high = bin_coeff_slice(left, split, maximum_len - split)
  let right_low = bin_coeff_slice(right, 0, split)
  let right_high = bin_coeff_slice(right, split, maximum_len - split)
  let low_product = left_low.mul(right_low)
  let high_product = left_high.mul(right_high)
  let middle = left_low
    .add(left_high)
    .mul(right_low.add(right_high))
    .sub_checked(low_product)
    .unwrap()
    .sub_checked(high_product)
    .unwrap()
  low_product
  .add(middle.shift_left(split * bin_coeff_limb_bits))
  .add(high_product.shift_left(2 * split * bin_coeff_limb_bits))
}

///|
fn bin_coeff_mul_toom3(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let maximum_len = Int::max(
    bin_coeff_limb_len(left),
    bin_coeff_limb_len(right),
  )
  let split = (maximum_len + 2) / 3
  let left0 = bin_coeff_slice(left, 0, split)
  let left1 = bin_coeff_slice(left, split, split)
  let left2 = bin_coeff_slice(left, 2 * split, split)
  let right0 = bin_coeff_slice(right, 0, split)
  let right1 = bin_coeff_slice(right, split, split)
  let right2 = bin_coeff_slice(right, 2 * split, split)
  let left_at_one = left0.add(left1).add(left2)
  let right_at_one = right0.add(right1).add(right2)
  let left_at_minus_one = bin_coeff_signed_scratch(false, left0)
    .sub(bin_coeff_signed_scratch(false, left1))
    .add(bin_coeff_signed_scratch(false, left2))
  let right_at_minus_one = bin_coeff_signed_scratch(false, right0)
    .sub(bin_coeff_signed_scratch(false, right1))
    .add(bin_coeff_signed_scratch(false, right2))
  let left_at_two = left0.add(left1.shift_left(1)).add(left2.shift_left(2))
  let right_at_two = right0.add(right1.shift_left(1)).add(right2.shift_left(2))
  let coefficient0 = left0.mul(right0)
  let coefficient4 = left2.mul(right2)
  let product1 = bin_coeff_signed_scratch(false, left_at_one.mul(right_at_one))
  let product_minus_one = left_at_minus_one.mul(right_at_minus_one)
  let product2 = bin_coeff_signed_scratch(false, left_at_two.mul(right_at_two))
  let coefficient0_signed = bin_coeff_signed_scratch(false, coefficient0)
  let coefficient4_signed = bin_coeff_signed_scratch(false, coefficient4)
  let odd_sum = product1.sub(product_minus_one).div_exact_small(2UL)
  let coefficient2 = product1
    .add(product_minus_one)
    .div_exact_small(2UL)
    .sub(coefficient0_signed)
    .sub(coefficient4_signed)
  let odd_weighted = product2
    .sub(coefficient0_signed)
    .sub(coefficient2.shift_left(2))
    .sub(coefficient4_signed.shift_left(4))
    .div_exact_small(2UL)
  let coefficient3 = odd_weighted.sub(odd_sum).div_exact_small(3UL)
  let coefficient1 = odd_sum.sub(coefficient3)
  let shift = split * bin_coeff_limb_bits
  coefficient0
  .add(coefficient1.nonnegative().shift_left(shift))
  .add(coefficient2.nonnegative().shift_left(2 * shift))
  .add(coefficient3.nonnegative().shift_left(3 * shift))
  .add(coefficient4.shift_left(4 * shift))
}

///|
fn bin_coeff_mul_unbalanced(shorter : BinCoeff, longer : BinCoeff) -> BinCoeff {
  let block_len = bin_coeff_limb_len(shorter)
  let longer_len = bin_coeff_limb_len(longer)
  let mut result = BinCoeff::zero()
  let mut start = 0
  while start < longer_len {
    let block = bin_coeff_slice(longer, start, block_len)
    let product = shorter.mul(block)
    result = result.add(product.shift_left(start * bin_coeff_limb_bits))
    start += block_len
  }
  result
}

///|
fn bin_coeff_mul_large_dispatch(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let left_len = bin_coeff_limb_len(left)
  let right_len = bin_coeff_limb_len(right)
  let shorter_len = Int::min(left_len, right_len)
  let longer_len = Int::max(left_len, right_len)
  if shorter_len >= bin_coeff_ntt_mul_threshold &&
    bin_coeff_ntt_fits(left, right) {
    bin_coeff_mul_ntt(left, right)
  } else if shorter_len >= bin_coeff_ntt_mul_threshold &&
    bin_coeff_ntt_overlap_possible(
      if left_len <= right_len {
        left
      } else {
        right
      },
    ) {
    if left_len <= right_len {
      bin_coeff_mul_ntt_overlap(left, right)
    } else {
      bin_coeff_mul_ntt_overlap(right, left)
    }
  } else if longer_len > 2 * shorter_len {
    if left_len <= right_len {
      bin_coeff_mul_unbalanced(left, right)
    } else {
      bin_coeff_mul_unbalanced(right, left)
    }
  } else if shorter_len >= bin_coeff_toom3_threshold {
    bin_coeff_mul_toom3(left, right)
  } else {
    let arena = bin_coeff_scratch_arena_new(16)
    bin_coeff_mul_karatsuba_scratch(left, right, arena)
  }
}

///|
fn bin_coeff_square_large_dispatch(value : BinCoeff) -> BinCoeff {
  let len = bin_coeff_limb_len(value)
  if len >= bin_coeff_ntt_square_threshold && bin_coeff_ntt_fits(value, value) {
    bin_coeff_square_ntt(value)
  } else if len < 768 {
    bin_coeff_square_schoolbook(value)
  } else if len >= 96 {
    bin_coeff_mul_toom3(value, value)
  } else {
    bin_coeff_mul_karatsuba(value, value)
  }
}

///|
fn bin_coeff_top_u64(value : BinCoeff) -> UInt64 {
  let len = bin_coeff_limb_len(value)
  if len == 0 {
    return 0UL
  }
  bin_coeff_limb(value, len - 1).to_uint64()
}

///|
fn bin_coeff_mul_signed_small(
  value : BinCoeff,
  factor : Int64,
) -> BinCoeffSignedScratch {
  if factor == 0L {
    return bin_coeff_signed_scratch(false, BinCoeff::zero())
  }
  let negative = factor < 0L
  let magnitude = if negative {
    (-factor).reinterpret_as_uint64()
  } else {
    factor.reinterpret_as_uint64()
  }
  bin_coeff_signed_scratch(
    negative,
    value.mul(BinCoeff::from_uint64(magnitude)),
  )
}

///|
fn bin_coeff_gcd_lehmer(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let mut a = left
  let mut b = right
  while !b.is_zero() {
    if bin_coeff_limb_len(a) < 8 || bin_coeff_limb_len(b) < 8 {
      return bin_coeff_gcd_euclid(a, b)
    }
    let mut x = bin_coeff_top_u64(a).reinterpret_as_int64()
    let mut y = bin_coeff_top_u64(b).reinterpret_as_int64()
    let mut aa : Int64 = 1L
    let mut ab : Int64 = 0L
    let mut ba : Int64 = 0L
    let mut bb : Int64 = 1L
    let mut steps = 0
    while y != 0L && steps < 32 {
      let q = x / y
      if q <= 0L {
        break
      }
      let next_x = x - q * y
      let next_aa = aa - q * ba
      let next_ab = ab - q * bb
      if next_aa.abs() > 1_000_000L || next_ab.abs() > 1_000_000L {
        break
      }
      x = y
      y = next_x
      aa = ba
      ab = bb
      ba = next_aa
      bb = next_ab
      steps += 1
    }
    if steps == 0 {
      let remainder = a.div_rem_checked(b).unwrap().1
      a = b
      b = remainder
    } else {
      let next_a = bin_coeff_mul_signed_small(a, aa).add(
        bin_coeff_mul_signed_small(b, ab),
      )
      let next_b = bin_coeff_mul_signed_small(a, ba).add(
        bin_coeff_mul_signed_small(b, bb),
      )
      guard !next_a.negative && !next_b.negative else {
        let remainder = a.div_rem_checked(b).unwrap().1
        a = b
        b = remainder
        continue
      }
      if next_a.magnitude.compare(a) >= 0 && next_b.magnitude.compare(b) >= 0 {
        let remainder = a.div_rem_checked(b).unwrap().1
        a = b
        b = remainder
        continue
      }
      a = next_a.magnitude
      b = next_b.magnitude
    }
  }
  a
}

///|
fn bin_coeff_gcd_euclid(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let mut a = left
  let mut b = right
  while !b.is_zero() {
    let remainder = a.div_rem_checked(b).unwrap().1
    a = b
    b = remainder
  }
  a
}
