///|
fn bin_coeff_bz_radix_minus_one(words : Int32) -> Coeff {
  Coeff::one().shift_left(words * 64).sub_checked(Coeff::one()).unwrap()
}

///|
fn bin_coeff_bz_div_3n_2n(
  numerator : Coeff,
  denominator : Coeff,
  half_words : Int32,
) -> (Coeff, Coeff) {
  if numerator.compare(denominator) < 0 {
    return (Coeff::zero(), numerator)
  }
  let half_bits = half_words * 64
  let denominator_low = bin_coeff_word_slice(denominator, 0, half_words)
  let denominator_high = bin_coeff_word_slice(
    denominator, half_words, half_words,
  )
  let numerator_low = bin_coeff_word_slice(numerator, 0, half_words)
  let numerator_upper = numerator.shift_right(half_bits)
  let numerator_middle = bin_coeff_word_slice(numerator_upper, 0, half_words)
  let numerator_high = numerator_upper.shift_right(half_bits)
  let (initial_quotient, high_remainder) = if numerator_high.compare(
      denominator_high,
    ) <
    0 {
    bin_coeff_bz_div_2n_1n(
      numerator_high.shift_left(half_bits).add(numerator_middle),
      denominator_high,
      half_words,
    )
  } else {
    let quotient = bin_coeff_bz_radix_minus_one(half_words)
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
    quotient = quotient.sub_checked(Coeff::one()).unwrap()
    remainder = remainder.add(denominator_signed)
    corrections += 1
    guard corrections <= 2 else {
      abort("Burnikel-Ziegler quotient estimate exceeded correction bound")
    }
  }
  let mut remainder_magnitude = remainder.magnitude
  while remainder_magnitude.compare(denominator) >= 0 {
    quotient = quotient.add(Coeff::one())
    remainder_magnitude = remainder_magnitude.sub_checked(denominator).unwrap()
  }
  (quotient, remainder_magnitude)
}

///|
fn bin_coeff_bz_div_2n_1n(
  numerator : Coeff,
  denominator : Coeff,
  divisor_words : Int32,
) -> (Coeff, Coeff) {
  if numerator.compare(denominator) < 0 {
    return (Coeff::zero(), numerator)
  }
  if divisor_words <= bin_coeff_bz_leaf_words || divisor_words % 2 != 0 {
    return bin_coeff_div_rem_knuth(numerator, denominator)
  }
  let half_words = divisor_words / 2
  let half_bits = half_words * 64
  let numerator_low = bin_coeff_word_slice(numerator, 0, half_words)
  let numerator_upper = numerator.shift_right(half_bits)
  let (upper_quotient, upper_remainder) = bin_coeff_bz_div_3n_2n(
    numerator_upper, denominator, half_words,
  )
  let combined = upper_remainder.shift_left(half_bits).add(numerator_low)
  let (lower_quotient, remainder) = bin_coeff_bz_div_3n_2n(
    combined, denominator, half_words,
  )
  (upper_quotient.shift_left(half_bits).add(lower_quotient), remainder)
}

///|
/// The length `n` in limbs to which `bin_coeff_div_rem_burnikel_ziegler`
/// extends a divisor of `s` limbs. Burnikel and Ziegler, "Fast Recursive
/// Division" (MPI-I-98-1-022, 1998), Algorithm 3 (D_{r/s}), steps 1 and 2: `m`
/// is the number of division blocks, a power of two (the depth `log2 m` of the
/// recursion), `j = ceil(s / m)` the length of a block and `n = j m`; the
/// divisor is extended to `n` limbs on the right, which wastes less than `m`
/// limbs, instead of to the next power of two, which wastes up to `s`
/// (section 2.3: the report's `DIV_LIMIT` is the block length at which the
/// recursion ends in school division, `bin_coeff_bz_leaf_words` here). `m` is
/// the least power of two with `ceil(s / m) <= bin_coeff_bz_leaf_words`
/// (the report writes `m DIV_LIMIT > s`; the two differ only when
/// `s = m DIV_LIMIT`, where the block then has exactly `DIV_LIMIT` limbs and
/// the leaf test `<=` of `bin_coeff_bz_div_2n_1n` stops there). The splits of
/// `bin_coeff_bz_div_2n_1n` and `bin_coeff_bz_div_3n_2n` halve `n` exactly
/// `log2 m` times before the leaf, so every length they halve is even.
fn bin_coeff_bz_padded_words(divisor_words : Int32) -> Int32 {
  let mut blocks = 1
  while (divisor_words + blocks - 1) / blocks > bin_coeff_bz_leaf_words {
    blocks *= 2
  }
  (divisor_words + blocks - 1) / blocks * blocks
}

///|
fn bin_coeff_div_rem_burnikel_ziegler(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  let denominator_len = bin_coeff_word_len(denominator)
  let normalized_words = bin_coeff_bz_padded_words(denominator_len)
  let normalization_shift = normalized_words * 64 - denominator.bit_length()
  let normalized_denominator = denominator.shift_left(normalization_shift)
  let normalized_numerator = numerator.shift_left(normalization_shift)
  let block_bits = normalized_words * 64
  let numerator_len = bin_coeff_word_len(normalized_numerator)
  let block_count = (numerator_len + normalized_words - 1) / normalized_words
  let mut quotient = Coeff::zero()
  let mut remainder = Coeff::zero()
  let mut block_index = block_count - 1
  while true {
    let block = bin_coeff_word_slice(
      normalized_numerator,
      block_index * normalized_words,
      normalized_words,
    )
    let combined = remainder.shift_left(block_bits).add(block)
    let (quotient_digit, next_remainder) = bin_coeff_bz_div_2n_1n(
      combined, normalized_denominator, normalized_words,
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
  denominator : Coeff,
  scale_bits : Int32,
) -> Coeff {
  let denominator_bits = denominator.bit_length()
  let seed_bits = 30
  let top_shift = denominator_bits - seed_bits
  let top = denominator.shift_right(top_shift).to_uint64().unwrap()
  let seed_scale = scale_bits - top_shift
  let mut reciprocal = Coeff::one()
    .shift_left(seed_scale)
    .div_rem_checked(Coeff::from_uint64(top + 1UL))
    .unwrap().0
  let scale = Coeff::one().shift_left(scale_bits)
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
    reciprocal = reciprocal.add(Coeff::one())
    product = next_product
  }
  while product.compare(scale) > 0 {
    reciprocal = reciprocal.sub_checked(Coeff::one()).unwrap()
    product = product.sub_checked(denominator).unwrap()
  }
  reciprocal
}

///|
fn bin_coeff_div_rem_newton(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  let scale_bits = numerator.bit_length() + 1
  let reciprocal = bin_coeff_newton_reciprocal(denominator, scale_bits)
  let mut quotient = numerator.mul(reciprocal).shift_right(scale_bits)
  let mut product = quotient.mul(denominator)
  while product.compare(numerator) > 0 {
    quotient = quotient.sub_checked(Coeff::one()).unwrap()
    product = product.sub_checked(denominator).unwrap()
  }
  let mut remainder = numerator.sub_checked(product).unwrap()
  let mut corrections = 0
  while remainder.compare(denominator) >= 0 {
    quotient = quotient.add(Coeff::one())
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
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff)? {
  let bit_gap = numerator.bit_length() - denominator.bit_length()
  if bit_gap < 0 || bit_gap > 16 {
    return None
  }
  let mut low = 0UL
  let mut high = 1UL << (bit_gap + 1)
  while low + 1UL < high {
    let middle = (low + high) >> 1
    let product = denominator.mul(Coeff::from_uint64(middle))
    if product.compare(numerator) <= 0 {
      low = middle
    } else {
      high = middle
    }
  }
  let quotient = Coeff::from_uint64(low)
  let product = denominator.mul(quotient)
  Some((quotient, numerator.sub_checked(product).unwrap()))
}
