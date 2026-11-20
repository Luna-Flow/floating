///|
/// Knuth's algorithm D on 64-bit digits (issue #19, stage 3): quotient and
/// remainder of two heap values whose divisor has at least one 64-bit limb.
/// The digit estimate divides 128 by 64 bits and the correction compares
/// 128-bit products, so it needs the high half of a 64 by 64 bit product
/// (`bin_coeff_mul_high`) and `binary_fast_div_wide`.
fn bin_coeff_div_rem_knuth_words(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  let numerator_len = bin_coeff_word_len(numerator)
  let denominator_len = bin_coeff_word_len(denominator)
  let normalization_shift = 64 -
    bin_coeff_u64_bits(bin_coeff_word(denominator, denominator_len - 1))
  // a divisor of one limb: one 128 by 64 bit division per limb of the dividend
  if denominator_len == 1 {
    let divisor = bin_coeff_word(denominator, 0)
    let quotient = FixedArray::make(numerator_len, 0UL)
    let mut remainder = 0UL
    let mut index = numerator_len - 1
    while index >= 0 {
      let limb = bin_coeff_word(numerator, index)
      let digit = binary_fast_div_wide(remainder, limb, divisor)
      quotient.unsafe_set(index, digit)
      remainder = limb - digit * divisor
      index -= 1
    }
    return (
      bin_coeff_from_words(quotient, numerator_len),
      Coeff::from_uint64(remainder),
    )
  }
  let divisor = FixedArray::make(denominator_len, 0UL)
  let dividend = FixedArray::make(numerator_len + 1, 0UL)
  if normalization_shift == 0 {
    for index in 0..<denominator_len {
      divisor.unsafe_set(index, bin_coeff_word(denominator, index))
    }
    for index in 0..<numerator_len {
      dividend.unsafe_set(index, bin_coeff_word(numerator, index))
    }
  } else {
    let back = 64 - normalization_shift
    let mut carry = 0UL
    for index in 0..<denominator_len {
      let word = bin_coeff_word(denominator, index)
      divisor.unsafe_set(index, (word << normalization_shift) | carry)
      carry = word >> back
    }
    carry = 0UL
    for index in 0..<numerator_len {
      let word = bin_coeff_word(numerator, index)
      dividend.unsafe_set(index, (word << normalization_shift) | carry)
      carry = word >> back
    }
    dividend.unsafe_set(numerator_len, carry)
  }
  let quotient_len = numerator_len - denominator_len + 1
  let quotient = FixedArray::make(quotient_len, 0UL)
  bin_coeff_knuth_words_core(
    dividend, divisor, denominator_len, quotient, quotient_len,
  )
  let remainder = FixedArray::make(denominator_len, 0UL)
  if normalization_shift == 0 {
    for index in 0..<denominator_len {
      remainder.unsafe_set(index, dividend.unsafe_get(index))
    }
  } else {
    let back = 64 - normalization_shift
    for index in 0..<denominator_len {
      // the word above the divisor is zero after the division
      let word = (dividend.unsafe_get(index) >> normalization_shift) |
        (dividend.unsafe_get(index + 1) << back)
      remainder.unsafe_set(index, word)
    }
  }
  (
    bin_coeff_from_words(quotient, quotient_len),
    bin_coeff_from_words(remainder, denominator_len),
  )
}

///|
/// The quotient loop of Knuth's algorithm D on 64-bit digits. `divisor` has
/// `denominator_len >= 2` limbs with the top bit set; `dividend` has
/// `quotient_len + denominator_len` limbs (normalised by the same shift, the top
/// limb holding the bits shifted out). The quotient limbs go to `quotient`
/// (`quotient_len` limbs, zero on entry); the remainder is left in
/// `dividend[0 ..< denominator_len]`.
fn bin_coeff_knuth_words_core(
  dividend : FixedArray[UInt64],
  divisor : FixedArray[UInt64],
  denominator_len : Int32,
  quotient : FixedArray[UInt64],
  quotient_len : Int32,
) -> Unit {
  let divisor_top = divisor.unsafe_get(denominator_len - 1)
  let divisor_next = divisor.unsafe_get(denominator_len - 2)
  let mut offset = quotient_len - 1
  while offset >= 0 {
    let high = dividend.unsafe_get(offset + denominator_len)
    let next = dividend.unsafe_get(offset + denominator_len - 1)
    let after = dividend.unsafe_get(offset + denominator_len - 2)
    let mut trial = 0UL
    let mut trial_remainder = 0UL
    // the remainder estimate leaves 64 bits once it overflows: stop correcting
    let mut remainder_overflow = false
    if high >= divisor_top {
      trial = 0xFFFF_FFFF_FFFF_FFFFUL
      trial_remainder = next + divisor_top
      remainder_overflow = trial_remainder < next
    } else {
      trial = binary_fast_div_wide(high, next, divisor_top)
      trial_remainder = next - trial * divisor_top
    }
    while !remainder_overflow {
      let product_high = bin_coeff_mul_high(trial, divisor_next)
      let product_low = trial * divisor_next
      if product_high > trial_remainder ||
        (product_high == trial_remainder && product_low > after) {
        trial -= 1UL
        trial_remainder += divisor_top
        remainder_overflow = trial_remainder < divisor_top
      } else {
        break
      }
    }
    // dividend[offset ..= offset + n] -= trial * divisor
    let mut carry = 0UL
    let mut borrow = 0UL
    let trial_low = trial & bin_coeff_limb_mask
    let trial_high = trial >> 32
    for index in 0..<denominator_len {
      let digit = divisor.unsafe_get(index)
      let product_low = trial * digit
      let digit_low = digit & bin_coeff_limb_mask
      let digit_high = digit >> 32
      let cross = trial_high * digit_low + ((trial_low * digit_low) >> 32)
      let mut product_high = trial_high * digit_high +
        (cross >> 32) +
        ((trial_low * digit_high + (cross & bin_coeff_limb_mask)) >> 32)
      let low = product_low + carry
      if low < product_low {
        product_high += 1UL
      }
      carry = product_high
      let current = dividend.unsafe_get(offset + index)
      let difference = current - low
      let borrow_one = if current < low { 1UL } else { 0UL }
      let result = difference - borrow
      let borrow_two = if difference < borrow { 1UL } else { 0UL }
      dividend.unsafe_set(offset + index, result)
      borrow = borrow_one + borrow_two
    }
    let high_index = offset + denominator_len
    let current_high = dividend.unsafe_get(high_index)
    let high_difference = current_high - carry
    let high_borrow_one = if current_high < carry { 1UL } else { 0UL }
    let high_result = high_difference - borrow
    let high_borrow_two = if high_difference < borrow { 1UL } else { 0UL }
    dividend.unsafe_set(high_index, high_result)
    if high_borrow_one + high_borrow_two != 0UL {
      // the estimate was one too large: add the divisor back
      trial -= 1UL
      let mut add_carry = 0UL
      for index in 0..<denominator_len {
        let value = dividend.unsafe_get(offset + index)
        let sum = value + divisor.unsafe_get(index)
        let carry_one = if sum < value { 1UL } else { 0UL }
        let total = sum + add_carry
        let carry_two = if total < sum { 1UL } else { 0UL }
        dividend.unsafe_set(offset + index, total)
        add_carry = carry_one + carry_two
      }
      dividend.unsafe_set(
        high_index,
        dividend.unsafe_get(high_index) + add_carry,
      )
    }
    quotient.unsafe_set(offset, trial)
    offset -= 1
  }
}

///|
/// Whether `bin_coeff_div_scaled_quotient` handles `dividend * 2^scale` over
/// `divisor`: a divisor of 2 to 95 limbs (Knuth's algorithm; a one-limb divisor
/// or the Burnikel-Ziegler range goes to the general division) and a numerator
/// of at least the divisor's width.
pub fn bin_coeff_div_scaled_ok(
  dividend : Coeff,
  scale : Int32,
  divisor : Coeff,
) -> Bool {
  let denominator_len = bin_coeff_word_len(divisor)
  denominator_len >= 2 &&
  denominator_len < bin_coeff_bz_division_min_words &&
  scale >= 0 &&
  !dividend.is_zero() &&
  dividend.bit_length() + scale >= divisor.bit_length()
}

///|
/// `2 * q + s` for the quotient `q` of `dividend * 2^scale` by `divisor` and
/// `s = 1` when the division leaves a remainder, else `s = 0`: the inexact flag
/// travels as the lowest bit of the result, so that no option or tuple is
/// returned (each would be a heap object). Requires
/// `bin_coeff_div_scaled_ok`. The shift by `scale` and the normalising shift
/// are one pass into the array that the quotient loop works on, and no
/// remainder value is built: the remainder is zero exactly when the low limbs
/// of the working array are.
pub fn bin_coeff_div_scaled_quotient(
  dividend : Coeff,
  scale : Int32,
  divisor : Coeff,
) -> Coeff {
  let denominator_len = bin_coeff_word_len(divisor)
  let numerator_bits = dividend.bit_length() + scale
  let numerator_len = (numerator_bits + 63) / 64
  let normalization_shift = 64 -
    bin_coeff_u64_bits(bin_coeff_word(divisor, denominator_len - 1))
  let work = bin_coeff_words_shifted(
    dividend,
    scale + normalization_shift,
    numerator_len + 1,
  )
  let normalized = bin_coeff_words_shifted(
    divisor, normalization_shift, denominator_len,
  )
  let quotient_len = numerator_len - denominator_len + 1
  let quotient = FixedArray::make(quotient_len + 1, 0UL)
  bin_coeff_knuth_words_core(
    work, normalized, denominator_len, quotient, quotient_len,
  )
  let mut index = 0
  while index < denominator_len && work.unsafe_get(index) == 0UL {
    index += 1
  }
  // (q << 1) | s, in place from the top limb
  let mut position = quotient_len
  while position > 0 {
    quotient.unsafe_set(
      position,
      (quotient.unsafe_get(position) << 1) |
      (quotient.unsafe_get(position - 1) >> 63),
    )
    position -= 1
  }
  quotient.unsafe_set(
    0,
    (quotient.unsafe_get(0) << 1) |
    (if index < denominator_len { 1UL } else { 0UL }),
  )
  bin_coeff_from_words(quotient, quotient_len + 1)
}
