///|
fn bin_coeff_bz_radix_minus_one(limbs : Int) -> BinCoeff {
  BinCoeff::one()
  .shift_left(limbs * bin_coeff_limb_bits)
  .sub_checked(BinCoeff::one())
  .unwrap()
}

///|
fn bin_coeff_bz_div_3n_2n(
  numerator : BinCoeff,
  denominator : BinCoeff,
  half_limbs : Int,
) -> (BinCoeff, BinCoeff) {
  if numerator.compare(denominator) < 0 {
    return (BinCoeff::zero(), numerator)
  }
  let half_bits = half_limbs * bin_coeff_limb_bits
  let denominator_low = bin_coeff_slice(denominator, 0, half_limbs)
  let denominator_high = bin_coeff_slice(denominator, half_limbs, half_limbs)
  let numerator_low = bin_coeff_slice(numerator, 0, half_limbs)
  let numerator_upper = numerator.shift_right(half_bits)
  let numerator_middle = bin_coeff_slice(numerator_upper, 0, half_limbs)
  let numerator_high = numerator_upper.shift_right(half_bits)
  let (initial_quotient, high_remainder) = if numerator_high.compare(
      denominator_high,
    ) <
    0 {
    bin_coeff_bz_div_2n_1n(
      numerator_high.shift_left(half_bits).add(numerator_middle),
      denominator_high,
      half_limbs,
    )
  } else {
    let quotient = bin_coeff_bz_radix_minus_one(half_limbs)
    let remainder = numerator_high
      .sub_checked(denominator_high)
      .unwrap()
      .shift_left(half_bits)
      .add(numerator_middle)
      .add(denominator_high)
    (quotient, remainder)
  }
  let mut quotient = initial_quotient
  let combined = high_remainder.shift_left(half_bits).add(numerator_low)
  let mut remainder = bin_coeff_signed_scratch(false, combined).sub(
    bin_coeff_signed_scratch(false, quotient.mul(denominator_low)),
  )
  let denominator_signed = bin_coeff_signed_scratch(false, denominator)
  let mut corrections = 0
  while remainder.negative {
    quotient = quotient.sub_checked(BinCoeff::one()).unwrap()
    remainder = remainder.add(denominator_signed)
    corrections += 1
    guard corrections <= 2 else {
      abort("Burnikel-Ziegler quotient estimate exceeded correction bound")
    }
  }
  let mut remainder_magnitude = remainder.magnitude
  while remainder_magnitude.compare(denominator) >= 0 {
    quotient = quotient.add(BinCoeff::one())
    remainder_magnitude = remainder_magnitude.sub_checked(denominator).unwrap()
  }
  (quotient, remainder_magnitude)
}

///|
fn bin_coeff_bz_div_2n_1n(
  numerator : BinCoeff,
  denominator : BinCoeff,
  divisor_limbs : Int,
) -> (BinCoeff, BinCoeff) {
  if numerator.compare(denominator) < 0 {
    return (BinCoeff::zero(), numerator)
  }
  if divisor_limbs <= 32 {
    return bin_coeff_div_rem_knuth(numerator, denominator)
  }
  let half_limbs = divisor_limbs / 2
  let half_bits = half_limbs * bin_coeff_limb_bits
  let numerator_low = bin_coeff_slice(numerator, 0, half_limbs)
  let numerator_upper = numerator.shift_right(half_bits)
  let (upper_quotient, upper_remainder) = bin_coeff_bz_div_3n_2n(
    numerator_upper, denominator, half_limbs,
  )
  let combined = upper_remainder.shift_left(half_bits).add(numerator_low)
  let (lower_quotient, remainder) = bin_coeff_bz_div_3n_2n(
    combined, denominator, half_limbs,
  )
  (upper_quotient.shift_left(half_bits).add(lower_quotient), remainder)
}

///|
fn bin_coeff_div_rem_burnikel_ziegler(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff) {
  let denominator_len = bin_coeff_limb_len(denominator)
  let mut normalized_limbs = 1
  while normalized_limbs < denominator_len {
    normalized_limbs *= 2
  }
  let normalization_shift = normalized_limbs * bin_coeff_limb_bits -
    denominator.bit_length()
  let normalized_denominator = denominator.shift_left(normalization_shift)
  let normalized_numerator = numerator.shift_left(normalization_shift)
  let block_bits = normalized_limbs * bin_coeff_limb_bits
  let numerator_len = bin_coeff_limb_len(normalized_numerator)
  let block_count = (numerator_len + normalized_limbs - 1) / normalized_limbs
  let mut quotient = BinCoeff::zero()
  let mut remainder = BinCoeff::zero()
  let mut block_index = block_count - 1
  while true {
    let block = bin_coeff_slice(
      normalized_numerator,
      block_index * normalized_limbs,
      normalized_limbs,
    )
    let combined = remainder.shift_left(block_bits).add(block)
    let (quotient_digit, next_remainder) = bin_coeff_bz_div_2n_1n(
      combined, normalized_denominator, normalized_limbs,
    )
    quotient = quotient.shift_left(block_bits).add(quotient_digit)
    remainder = next_remainder
    if block_index == 0 {
      break
    }
    block_index -= 1
  }
  (quotient, remainder.shift_right(normalization_shift))
}

///|
fn bin_coeff_newton_reciprocal(
  denominator : BinCoeff,
  scale_bits : Int,
) -> BinCoeff {
  let denominator_bits = denominator.bit_length()
  let seed_bits = 30
  let top_shift = denominator_bits - seed_bits
  let top = denominator.shift_right(top_shift).to_uint64().unwrap()
  let seed_scale = scale_bits - top_shift
  let mut reciprocal = BinCoeff::one()
    .shift_left(seed_scale)
    .div_rem_checked(BinCoeff::from_uint64(top + 1UL))
    .unwrap().0
  let scale = BinCoeff::one().shift_left(scale_bits)
  let double_scale = scale.shift_left(1)
  let mut iterations = 0
  while true {
    let product = denominator.mul(reciprocal)
    guard product.compare(double_scale) < 0 else {
      abort("Newton reciprocal escaped its lower-bound invariant")
    }
    let correction = double_scale.sub_checked(product).unwrap()
    let next = reciprocal.mul(correction).shift_right(scale_bits)
    if next.compare(reciprocal) <= 0 {
      break
    }
    reciprocal = next
    iterations += 1
    guard iterations <= 64 else { abort("Newton reciprocal did not converge") }
  }
  let mut product = denominator.mul(reciprocal)
  while true {
    let next_product = product.add(denominator)
    if next_product.compare(scale) > 0 {
      break
    }
    reciprocal = reciprocal.add(BinCoeff::one())
    product = next_product
  }
  while product.compare(scale) > 0 {
    reciprocal = reciprocal.sub_checked(BinCoeff::one()).unwrap()
    product = product.sub_checked(denominator).unwrap()
  }
  reciprocal
}

///|
fn bin_coeff_div_rem_newton(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff) {
  let scale_bits = numerator.bit_length() + 1
  let reciprocal = bin_coeff_newton_reciprocal(denominator, scale_bits)
  let mut quotient = numerator.mul(reciprocal).shift_right(scale_bits)
  let mut product = quotient.mul(denominator)
  while product.compare(numerator) > 0 {
    quotient = quotient.sub_checked(BinCoeff::one()).unwrap()
    product = product.sub_checked(denominator).unwrap()
  }
  let mut remainder = numerator.sub_checked(product).unwrap()
  let mut corrections = 0
  while remainder.compare(denominator) >= 0 {
    quotient = quotient.add(BinCoeff::one())
    remainder = remainder.sub_checked(denominator).unwrap()
    corrections += 1
    guard corrections <= 2 else {
      abort("Newton quotient exceeded correction bound")
    }
  }
  (quotient, remainder)
}

///|
fn bin_coeff_short_div_high_product(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff)? {
  let bit_gap = numerator.bit_length() - denominator.bit_length()
  if bit_gap < 0 || bit_gap > 16 {
    return None
  }
  let mut low = 0UL
  let mut high = 1UL << (bit_gap + 1)
  while low + 1UL < high {
    let middle = (low + high) >> 1
    let product = denominator.mul(BinCoeff::from_uint64(middle))
    if product.compare(numerator) <= 0 {
      low = middle
    } else {
      high = middle
    }
  }
  let quotient = BinCoeff::from_uint64(low)
  let product = denominator.mul(quotient)
  Some((quotient, numerator.sub_checked(product).unwrap()))
}
