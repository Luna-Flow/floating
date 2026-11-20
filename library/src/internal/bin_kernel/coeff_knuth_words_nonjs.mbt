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
/// The digit estimate of Knuth's algorithm D for `high >= divisor_top` (so
/// `high == divisor_top`): the digit is at most `B - 1`, and the correction
/// compares `trial * divisor_next` with the remainder estimate and `after`.
/// The loops used this estimate for every digit before the reciprocal
/// (`bin_knuth_digit_3by2`); it stays for this rare case, where the
/// three-by-two division does not apply (its precondition is `<high, next> <
/// <divisor_top, divisor_next>`). The test file keeps the old estimate for
/// `high < divisor_top` as the reference of the new one.
fn bin_knuth_digit_top(
  next : UInt64,
  after : UInt64,
  divisor_top : UInt64,
  divisor_next : UInt64,
) -> UInt64 {
  let mut trial = 0xFFFF_FFFF_FFFF_FFFFUL
  let mut trial_remainder = next + divisor_top
  // the remainder estimate leaves 64 bits once it overflows: stop correcting
  let mut remainder_overflow = trial_remainder < next
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
  trial
}

///|
/// The reciprocal of the two-word divisor `<d1, d0>` (`d1 >= 2^63`) for
/// `bin_knuth_digit_3by2`: `v = floor((B^3 - 1) / <d1, d0>) - B`, `B = 2^64`.
/// Möller and Granlund, "Improved division by invariant integers", IEEE
/// Transactions on Computers 60(2), 2011, Algorithm 6 (RECIPROCAL_WORD_3BY2), whose line 1 starts from a
/// single-word reciprocal `v` of `d1` with `B^2 - d1 <= (B + v) d1 < B^2`. Here
/// that `v` is the exact `floor((B^2 - 1) / d1) - B`, one division of
/// `<B - 1 - d1, B - 1>` by `d1` (the high word is below `d1` because
/// `d1 >= B / 2`), which satisfies it: `(B + v) d1` is the largest multiple of
/// `d1` not above `B^2 - 1`. Lines 2 to 9 add `d0` to `(B + v) d1` (a carry out
/// of the word is cancelled by subtracting `d1` once or twice from the
/// reciprocal, the test `p >= d1` on the wrapped low word `p` being the excess
/// over `B^2`), lines 10 to 15 add the product `v d0` to the result.
fn bin_knuth_reciprocal_3by2(d1 : UInt64, d0 : UInt64) -> UInt64 {
  let mut v = binary_fast_div_wide(
    0xFFFF_FFFF_FFFF_FFFFUL - d1,
    0xFFFF_FFFF_FFFF_FFFFUL,
    d1,
  )
  let mut p = d1 * v + d0
  if p < d0 {
    v -= 1UL
    if p >= d1 {
      v -= 1UL
      p -= d1
    }
    p -= d1
  }
  let t_low = v * d0
  let t_high = bin_coeff_mul_high(v, d0)
  p += t_high
  if p < t_high {
    v -= 1UL
    if p > d1 || (p == d1 && t_low >= d0) {
      v -= 1UL
    }
  }
  v
}

///|
/// `floor(<u2, u1, u0> / <d1, d0>)` for `d1 >= 2^63` and `<u2, u1> <
/// <d1, d0>` (the quotient fits one word), with the reciprocal `v =
/// bin_knuth_reciprocal_3by2(d1, d0)`. Möller and Granlund, "Improved division
/// by invariant integers", IEEE Transactions on Computers 60(2), 2011,
/// Algorithm 5 (DIV3BY2), Theorem 3: with `<q1, q0> = (B + v) u2 + u1`, the candidate `q1 + 1` has
/// the remainder `re = U - (q1 + 1) D` in `c - B^2 <= re < c` for `c = max(B^2 -
/// D, q0 B)`, so `re` is determined by its value modulo `B^2` and the
/// comparison of its high word with `q0`: if `r1 >= q0` the candidate is one
/// too large (`re` is negative, modulo `B^2` it is above `c`), and if `re >= D`
/// (rarely) it is one too small. The two adjustments are written without
/// branches on the unpredictable one.
fn bin_knuth_digit_3by2(
  u2 : UInt64,
  u1 : UInt64,
  u0 : UInt64,
  d1 : UInt64,
  d0 : UInt64,
  v : UInt64,
) -> UInt64 {
  // line 1 and 2: <q1, q0> = v * u2 + <u2, u1>
  let q_low_product = v * u2
  let q_low = q_low_product + u1
  let q_high = bin_coeff_mul_high(v, u2) +
    u2 +
    (if q_low < q_low_product { 1UL } else { 0UL })
  // lines 3 to 5: <r1, r0> = (<u1 - q1 d1, u0> - q1 d0 - <d1, d0>) mod B^2
  let t_low = d0 * q_high
  let t_high = bin_coeff_mul_high(d0, q_high)
  let r1_start = u1 - q_high * d1
  let r0_first = u0 - t_low
  let r1_first = r1_start - t_high - (if u0 < t_low { 1UL } else { 0UL })
  let mut r0 = r0_first - d0
  let mut r1 = r1_first - d1 - (if r0_first < d0 { 1UL } else { 0UL })
  let mut q = q_high + 1UL
  // lines 7 to 9: undo the increment when `r1 >= q0`
  let mask = 0UL - (if r1 >= q_low { 1UL } else { 0UL })
  q += mask
  let r0_sum = r0 + (d0 & mask)
  r1 = r1 + (d1 & mask) + (if r0_sum < r0 { 1UL } else { 0UL })
  r0 = r0_sum
  // lines 10 to 12: the unlikely second adjustment
  if r1 > d1 || (r1 == d1 && r0 >= d0) {
    q += 1UL
  }
  q
}

///|
/// One multiply-subtract row of the quotient loop: `dividend[offset + skip ..<
/// offset + n] -= trial * divisor[skip ..< n]` and the limb above it, where `n`
/// is `denominator_len`. Returns whether the row borrowed out of the limb
/// above (the digit estimate was one too large). `bin_limbs_submul_1` returns
/// the carry and the borrow folded into one limb, which is subtracted from the
/// limb above the row; the row borrows out exactly when that subtraction does.
fn bin_knuth_row(
  dividend : FixedArray[UInt64],
  offset : Int32,
  divisor : FixedArray[UInt64],
  skip : Int32,
  denominator_len : Int32,
  trial : UInt64,
) -> Bool {
  let length = denominator_len - skip
  // measured: the C row wins from a length of one limb (thresholds of 1, 3 and
  // 6 limbs on `div` and `sqrt` at 512 to 8,192 bits differ by under 2 percent,
  // 1 the best), so every row goes through the primitive
  let folded = bin_limbs_submul_1(
    dividend,
    offset + skip,
    divisor,
    skip,
    length,
    trial,
  )
  let high_index = offset + denominator_len
  let current = dividend.unsafe_get(high_index)
  dividend.unsafe_set(high_index, current - folded)
  current < folded
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
  let reciprocal = bin_knuth_reciprocal_3by2(divisor_top, divisor_next)
  let mut offset = quotient_len - 1
  while offset >= 0 {
    let high = dividend.unsafe_get(offset + denominator_len)
    let next = dividend.unsafe_get(offset + denominator_len - 1)
    let after = dividend.unsafe_get(offset + denominator_len - 2)
    let mut trial = 0UL
    if high < divisor_top {
      // the quotient of the top three limbs by the top two of the divisor
      trial = bin_knuth_digit_3by2(
        high, next, after, divisor_top, divisor_next, reciprocal,
      )
    } else {
      trial = bin_knuth_digit_top(next, after, divisor_top, divisor_next)
    }
    // dividend[offset ..= offset + n] -= trial * divisor, one row
    let high_index = offset + denominator_len
    if bin_knuth_row(dividend, offset, divisor, 0, denominator_len, trial) {
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
///
/// If the result is `Heap(words, len)`, `words` is an array
/// that no operand and no other value refers to (its length may exceed `len`),
/// which the caller may keep, hand on or modify. Results of up to 128 bits are
/// `Inline64` or `Inline128` and carry no array; `Coeff::zero()` is a shared
/// constant, recognised by `is_zero()`.
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

///|
/// Longest divisor, in limbs, that the short division handles; longer ones
/// are left to the exact division (Burnikel-Ziegler from 96 limbs).
let bin_coeff_short_division_max_words : Int32 = 256

///|
/// Extra bits that the caller adds to the scale of a short division, so that
/// the approximate quotient carries guard bits under the rounding position
/// (the error bound of `bin_coeff_div_short_quotient` is a few hundred units).
pub let bin_coeff_short_division_guard_bits : Int32 = 32

///|
/// Whether `bin_coeff_div_short_quotient` handles `dividend * 2^scale` over
/// `divisor`: a divisor of 2 to 256 limbs and a numerator at least as wide as
/// the divisor.
pub fn bin_coeff_div_short_ok(
  dividend : Coeff,
  scale : Int32,
  divisor : Coeff,
) -> Bool {
  let denominator_len = bin_coeff_word_len(divisor)
  denominator_len >= 2 &&
  denominator_len <= bin_coeff_short_division_max_words &&
  scale >= 0 &&
  !dividend.is_zero() &&
  dividend.bit_length() + scale >= divisor.bit_length()
}

///|
/// The quotient loop of Knuth's algorithm D with a truncated divisor ("short
/// division", the basecase of Harvey and Zimmermann's ShortDiv): the digit at
/// position `k` subtracts `q * D_k * B^k` where `D_k` is the divisor with its
/// lowest `max(0, denominator_len - 1 - k)` limbs set to zero. The digit
/// estimate, the correction and the add-back are those of
/// `bin_coeff_knuth_words_core`, with the add-back of `D_k`. The window stays
/// non-negative after every digit (the estimate is at most one above the digit
/// for the full divisor, and `D_k <= D`), so the digits satisfy
/// `N = Q * D + R - S` with `0 <= R` the final window and
/// `0 <= S < (denominator_len - 1) * B^denominator_len` the sum of the dropped
/// products `q_k * (D mod B^l_k) * B^k` (each below `B^denominator_len`, and
/// zero for `k >= denominator_len - 1`). The remainder `R` is left in
/// `dividend[0 ..= denominator_len]`.
fn bin_coeff_knuth_short_core(
  dividend : FixedArray[UInt64],
  divisor : FixedArray[UInt64],
  denominator_len : Int32,
  quotient : FixedArray[UInt64],
  quotient_len : Int32,
) -> Unit {
  let divisor_top = divisor.unsafe_get(denominator_len - 1)
  let divisor_next = divisor.unsafe_get(denominator_len - 2)
  let reciprocal = bin_knuth_reciprocal_3by2(divisor_top, divisor_next)
  let mut offset = quotient_len - 1
  while offset >= 0 {
    let high = dividend.unsafe_get(offset + denominator_len)
    let next = dividend.unsafe_get(offset + denominator_len - 1)
    let after = dividend.unsafe_get(offset + denominator_len - 2)
    let mut trial = 0UL
    if high < divisor_top {
      // the quotient of the top three limbs by the top two of the divisor
      trial = bin_knuth_digit_3by2(
        high, next, after, divisor_top, divisor_next, reciprocal,
      )
    } else {
      trial = bin_knuth_digit_top(next, after, divisor_top, divisor_next)
    }
    // dividend[offset + skip ..= offset + n] -= trial * divisor[skip ..< n], one row
    let skip = Int32::max(0, denominator_len - 1 - offset)
    let high_index = offset + denominator_len
    if bin_knuth_row(dividend, offset, divisor, skip, denominator_len, trial) {
      trial -= 1UL
      let mut add_carry = 0UL
      for index in skip..<denominator_len {
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
/// An approximate quotient `Q` of `dividend * 2^scale` by `divisor`, rounded
/// correctly if it is returned, else `Coeff::zero()` (the caller then divides
/// exactly). Requires `bin_coeff_div_short_ok`.
///
/// Error bound. With `N = dividend * 2^scale`, `D = divisor` (normalised by a
/// shift to `n` limbs with the top bit set, so `D >= B^n / 2`; `B = 2^64`) and
/// the digits of `bin_coeff_knuth_short_core`, `N / D - Q = (R - S) / D`, with
/// `0 <= S < (n - 1) B^n`, hence `S / D < 2 (n - 1)`, and `0 <= R`, so
/// `N / D > Q - 2 n`. The final window `R < (r1 * B + r0 + 1) * B^(n - 1)` for its
/// top two limbs `r1, r0`, and `D >= D_top * B^(n - 1)`, so
/// `N / D < Q + h` for `h = floor((r1 * B + r0) / D_top) + 2` (if `r1 < D_top`;
/// otherwise the function declines). So `N / D` lies in `(Q - 2 n, Q + h)`
/// whatever the quality of the digit estimates, which only moves `h`.
///
/// Rounding to `precision` bits: let `m = bit_length(Q) - precision - 1` (at
/// least `guard_bits` of them: else decline). The grid of halfway and
/// representable points has the spacing `2^m`, and no multiple of it lies in
/// `[Q - 2 n, Q + h]` exactly when `r = Q mod 2^m` satisfies `r > 2 n` and
/// `2^m - 1 - r >= h`. Then the rounded value of `N / D` (nearest, directed,
/// any mode) is that of `Q`, and the result is inexact; the power of two at
/// the top of `Q` is a multiple of the spacing, so the interval does not
/// straddle a change of the bit length. An exact quotient or a quotient near a
/// grid point fails the test and is divided exactly.
///
/// If the result is `Heap(words, len)`, `words` is an array
/// that no operand and no other value refers to (its length may exceed `len`),
/// which the caller may keep, hand on or modify. Results of up to 128 bits are
/// `Inline64` or `Inline128` and carry no array; `Coeff::zero()` is a shared
/// constant, recognised by `is_zero()`.
/// The shared zero is the "declined" answer.
pub fn bin_coeff_div_short_quotient(
  dividend : Coeff,
  scale : Int32,
  divisor : Coeff,
  precision : Int32,
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
  let quotient = FixedArray::make(quotient_len, 0UL)
  bin_coeff_knuth_short_core(
    work, normalized, denominator_len, quotient, quotient_len,
  )
  // the upper bound h of N / D - Q, from the top two limbs of the final window
  let top = normalized.unsafe_get(denominator_len - 1)
  let window_high = work.unsafe_get(denominator_len)
  if window_high >= top {
    return Coeff::zero()
  }
  let upper = binary_fast_div_wide(
      window_high,
      work.unsafe_get(denominator_len - 1),
      top,
    ) +
    2UL
  let lower = (2 * denominator_len).to_uint64()
  // the quotient limbs, trimmed
  let mut used = quotient_len
  while used > 0 && quotient.unsafe_get(used - 1) == 0UL {
    used -= 1
  }
  if used == 0 {
    return Coeff::zero()
  }
  let bits = (used - 1) * 64 + bin_coeff_u64_bits(quotient.unsafe_get(used - 1))
  let spacing_bits = bits - precision - 1
  if spacing_bits < bin_coeff_short_division_guard_bits {
    return Coeff::zero()
  }
  // r = Q mod 2^spacing_bits must exceed `lower`, and its complement within
  // spacing_bits bits must be at least `upper`
  let limbs = (spacing_bits + 63) / 64
  let top_bits = spacing_bits - (limbs - 1) * 64
  let top_mask = if top_bits == 64 {
    0xFFFF_FFFF_FFFF_FFFFUL
  } else {
    (1UL << top_bits) - 1UL
  }
  let mut remainder_above = false
  let mut complement_above = false
  for index in 1..<limbs {
    let word = if index == limbs - 1 {
      quotient.unsafe_get(index) & top_mask
    } else {
      quotient.unsafe_get(index)
    }
    let full = if index == limbs - 1 {
      top_mask
    } else {
      0xFFFF_FFFF_FFFF_FFFFUL
    }
    if word != 0UL {
      remainder_above = true
    }
    if full - word != 0UL {
      complement_above = true
    }
  }
  let word0 = if limbs == 1 {
    quotient.unsafe_get(0) & top_mask
  } else {
    quotient.unsafe_get(0)
  }
  let full0 = if limbs == 1 { top_mask } else { 0xFFFF_FFFF_FFFF_FFFFUL }
  let remainder_ok = remainder_above || word0 > lower
  let complement_ok = complement_above || full0 - word0 >= upper
  if !remainder_ok || !complement_ok {
    return Coeff::zero()
  }
  bin_coeff_from_words(quotient, quotient_len)
}
