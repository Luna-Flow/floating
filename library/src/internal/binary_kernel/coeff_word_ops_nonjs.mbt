///|
pub fn binary_fast_bits(value : UInt64) -> Int32 {
  64 - value.reinterpret_as_int64().clz()
}

///|
/// High word of `value << shift`, `0 <= shift < 128`.
pub fn binary_fast_shl_high(value : UInt64, shift : Int32) -> UInt64 {
  if shift == 0 {
    0UL
  } else if shift < 64 {
    value >> (64 - shift)
  } else {
    value << (shift - 64)
  }
}

///|
/// Low word of `value << shift`, `0 <= shift < 128`.
pub fn binary_fast_shl_low(value : UInt64, shift : Int32) -> UInt64 {
  if shift < 64 {
    value << shift
  } else {
    0UL
  }
}

///|
/// High word of the 128-bit product of two words.
pub fn binary_fast_mul_high(left : UInt64, right : UInt64) -> UInt64 {
  let left_low = left & bin_coeff_limb_mask
  let left_high = left >> 32
  let right_low = right & bin_coeff_limb_mask
  let right_high = right >> 32
  let cross = left_high * right_low + ((left_low * right_low) >> 32)
  left_high * right_high +
  (cross >> 32) +
  ((left_low * right_high + (cross & bin_coeff_limb_mask)) >> 32)
}

///|
/// `floor((high * 2^64 + low) / divisor)` for `high < divisor` (Hacker's
/// Delight, `divlu`): the quotient fits one word.
pub fn binary_fast_div_wide(
  high : UInt64,
  low : UInt64,
  divisor : UInt64,
) -> UInt64 {
  let shift = 64 - binary_fast_bits(divisor)
  let normalized = divisor << shift
  let high_part = if shift == 0 {
    high
  } else {
    (high << shift) | (low >> (64 - shift))
  }
  let low_part = low << shift
  let divisor_high = normalized >> 32
  let divisor_low = normalized & bin_coeff_limb_mask
  let digit_high = low_part >> 32
  let digit_low = low_part & bin_coeff_limb_mask
  let mut quotient_high = high_part / divisor_high
  let mut remainder = high_part - quotient_high * divisor_high
  while quotient_high >= bin_coeff_limb_base ||
        quotient_high * divisor_low > ((remainder << 32) | digit_high) {
    quotient_high -= 1UL
    remainder += divisor_high
    if remainder >= bin_coeff_limb_base {
      break
    }
  }
  let middle = (high_part << 32) + digit_high - quotient_high * normalized
  let mut quotient_low = middle / divisor_high
  remainder = middle - quotient_low * divisor_high
  while quotient_low >= bin_coeff_limb_base ||
        quotient_low * divisor_low > ((remainder << 32) | digit_low) {
    quotient_low -= 1UL
    remainder += divisor_high
    if remainder >= bin_coeff_limb_base {
      break
    }
  }
  (quotient_high << 32) + quotient_low
}
