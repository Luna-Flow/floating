///|
/// Row primitives on 64-bit limbs, portable form (issue 438, section 8).
///
/// These are the reference of `luna_limbs.c`: on native the wrappers of
/// `coeff_limbs_native.mbt` call the C functions of the same name, on every
/// other target the wrappers of `coeff_limbs_other_nonjs.mbt` call these. All
/// rows take arrays and offsets in limbs and return a carry limb; none checks
/// lengths. The schoolbook product and square are `bin_coeff_words_school` and
/// `bin_coeff_words_sqr_school` (`coeff_words_nonjs.mbt`), the same contract.

///|
/// `r[ro ..< ro + n] = a[ao ..< ao + n] * b`; returns the carry limb (the limb
/// that belongs at `r[ro + n]`, which is not written).
fn bin_limbs_mul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let total = low + carry
    r.unsafe_set(ro + index, total)
    carry = high + (if total < low { 1UL } else { 0UL })
  }
  carry
}

///|
/// `r[ro ..< ro + n] += a[ao ..< ao + n] * b`; returns the carry limb. The
/// ranges may be the same range of one array (`r` and `a` equal): each limb of
/// both is read before the limb of `r` is written.
fn bin_limbs_addmul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let partial = low + carry
    let carry_one = if partial < low { 1UL } else { 0UL }
    let total = partial + r.unsafe_get(ro + index)
    let carry_two = if total < partial { 1UL } else { 0UL }
    r.unsafe_set(ro + index, total)
    carry = high + carry_one + carry_two
  }
  carry
}

///|
/// `r[ro ..< ro + n] -= a[ao ..< ao + n] * b`; returns the carry limb plus the
/// borrow out of the row, folded into one limb (it never exceeds 2^64 - 1): the
/// caller subtracts it from the limb above the row, and the row has borrowed
/// out exactly when that subtraction does. Same aliasing as
/// `bin_limbs_addmul_1_portable`.
fn bin_limbs_submul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let low_total = low + carry
    let carry_one = if low_total < low { 1UL } else { 0UL }
    let current = r.unsafe_get(ro + index)
    let borrow = if current < low_total { 1UL } else { 0UL }
    r.unsafe_set(ro + index, current - low_total)
    carry = high + carry_one + borrow
  }
  carry
}
