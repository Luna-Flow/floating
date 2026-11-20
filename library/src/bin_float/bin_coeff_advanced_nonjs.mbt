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
  { negative: negative && !magnitude.is_zero(), magnitude, }
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
  shift : Int32,
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
/// `length` 64-bit limbs of `value` starting at limb `start`.
fn bin_coeff_word_slice(
  value : BinCoeff,
  start : Int32,
  length : Int32,
) -> BinCoeff {
  let source_len = bin_coeff_word_len(value)
  if length <= 0 || start >= source_len {
    return BinCoeff::zero()
  }
  let len = Int32::min(length, source_len - start)
  let words = FixedArray::make(len, 0UL)
  match value.repr {
    Heap(source, _) =>
      for index in 0..<len {
        words.unsafe_set(index, source.unsafe_get(start + index))
      }
    _ =>
      for index in 0..<len {
        words.unsafe_set(index, bin_coeff_word(value, start + index))
      }
  }
  bin_coeff_from_words(words, len)
}

///|
/// `destination += value * 2^(64 * offset)` on 64-bit limbs.
fn bin_coeff_add_word_shifted_into(
  destination : FixedArray[UInt64],
  destination_len : Int32,
  value : BinCoeff,
  offset : Int32,
) -> Unit {
  let value_len = bin_coeff_word_len(value)
  let mut carry = 0UL
  for value_index in 0..<value_len {
    let destination_index = offset + value_index
    guard destination_index < destination_len else {
      abort("BinCoeff shifted accumulation exceeded its output")
    }
    let current = destination.unsafe_get(destination_index)
    let addend = bin_coeff_word(value, value_index)
    let sum = current + addend
    let carry_one = if sum < current { 1UL } else { 0UL }
    let total = sum + carry
    let carry_two = if total < sum { 1UL } else { 0UL }
    destination.unsafe_set(destination_index, total)
    carry = carry_one + carry_two
  }
  let mut destination_index = offset + value_len
  while carry != 0UL && destination_index < destination_len {
    let current = destination.unsafe_get(destination_index)
    let total = current + carry
    destination.unsafe_set(destination_index, total)
    carry = if total < current { 1UL } else { 0UL }
    destination_index += 1
  }
  guard carry == 0UL else {
    abort("BinCoeff shifted accumulation exceeded its output")
  }
}

///|
fn bin_coeff_mul_toom3(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let maximum_len = Int32::max(
    bin_coeff_word_len(left),
    bin_coeff_word_len(right),
  )
  let split = (maximum_len + 2) / 3
  let left0 = bin_coeff_word_slice(left, 0, split)
  let left1 = bin_coeff_word_slice(left, split, split)
  let left2 = bin_coeff_word_slice(left, 2 * split, split)
  let right0 = bin_coeff_word_slice(right, 0, split)
  let right1 = bin_coeff_word_slice(right, split, split)
  let right2 = bin_coeff_word_slice(right, 2 * split, split)
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
  let shift = split * 64
  coefficient0
  .add(coefficient1.nonnegative().shift_left(shift))
  .add(coefficient2.nonnegative().shift_left(2 * shift))
  .add(coefficient3.nonnegative().shift_left(3 * shift))
  .add(coefficient4.shift_left(4 * shift))
}

///|
/// Product of two heap values of at least `bin_coeff_words_karatsuba_cutoff`
/// limbs: the two-prime NTT (or its overlap-add for a short operand against a
/// long one) from `bin_coeff_ntt_mul_min_words`, Toom-3 where the transform
/// does not fit, otherwise the word Karatsuba, which cuts an unbalanced
/// product into blocks of the shorter operand itself.
fn bin_coeff_mul_large_dispatch(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let left_len = bin_coeff_word_len(left)
  let right_len = bin_coeff_word_len(right)
  let shorter_len = Int32::min(left_len, right_len)
  let longer_len = Int32::max(left_len, right_len)
  if shorter_len >= bin_coeff_ntt_mul_min_words &&
    bin_coeff_ntt_fits(left, right) {
    bin_coeff_mul_ntt(left, right)
  } else if shorter_len >= bin_coeff_ntt_mul_min_words &&
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
  } else if shorter_len >= bin_coeff_toom3_min_words &&
    longer_len <= 2 * shorter_len {
    bin_coeff_mul_toom3(left, right)
  } else {
    bin_coeff_mul_words(left, right)
  }
}

///|
/// Square of a heap value of at least 16 limbs: the two-prime NTT from
/// `bin_coeff_ntt_square_min_words`, the word Karatsuba square where it is
/// enabled, otherwise (Wasm) the schoolbook or 32-bit-limb square below
/// `bin_coeff_square_recursive_min_words`, the general product below
/// `bin_coeff_square_toom3_min_words` and Toom-3 above it.
fn bin_coeff_square_large_dispatch(value : BinCoeff) -> BinCoeff {
  let len = bin_coeff_word_len(value)
  if len >= bin_coeff_ntt_square_min_words && bin_coeff_ntt_fits(value, value) {
    bin_coeff_square_ntt(value)
  } else if bin_coeff_square_words_enabled &&
    len >= bin_coeff_words_square_cutoff &&
    len < bin_coeff_limb32_min_words / 2 &&
    len < bin_coeff_toom3_min_words {
    bin_coeff_square_words(value)
  } else if len < bin_coeff_square_recursive_min_words {
    if len >= bin_coeff_limb32_min_words / 2 {
      bin_coeff_square_limb32(value)
    } else {
      bin_coeff_square_schoolbook(value)
    }
  } else if len < bin_coeff_square_toom3_min_words {
    bin_coeff_mul_large_dispatch(value, value)
  } else {
    bin_coeff_mul_toom3(value, value)
  }
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
/// Lehmer's gcd. Each round runs Euclid on the leading 63 bits of `a` and the
/// bits of `b` at the same positions, then applies the accumulated cofactors
/// to the full operands. Both leading digits must be taken from the same bit
/// window: digits taken from each operand's own top limb have unrelated
/// scales, and the cofactors they produce subtract only a small multiple of
/// `b` per round, so an operand pair like a 301-bit odd number and `2^543`
/// needed about `2^220` rounds.
fn bin_coeff_gcd_lehmer(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  let mut a = left
  let mut b = right
  while !b.is_zero() {
    if a.compare(b) < 0 {
      let smaller = a
      a = b
      b = smaller
    }
    if bin_coeff_word_len(b) < 4 {
      return bin_coeff_gcd_euclid(a, b)
    }
    let shift = a.bit_length() - 63
    if b.bit_length() <= shift {
      // `b` has no bits in the leading window, so `a / b >= 2^62`: one
      // division step makes all the progress a Lehmer round could.
      let remainder = a.div_rem_checked(b).unwrap().1
      a = b
      b = remainder
      continue
    }
    let mut x = a.shift_right(shift).to_uint64().unwrap().reinterpret_as_int64()
    let mut y = b.shift_right(shift).to_uint64().unwrap().reinterpret_as_int64()
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
