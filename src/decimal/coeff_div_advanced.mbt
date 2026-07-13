///|
let dec_coeff_bz_recursive_threshold = 16

///|
fn dec_coeff_owned(value : DecCoeff) -> DecCoeff {
  dec_coeff_from_unit_accumulator(
    dec_coeff_copy_limbs(value),
    dec_coeff_unit_len(value),
  )
}

///|
fn dec_coeff_div_rem_power_limbs(
  value : DecCoeff,
  shift : Int,
) -> (DecCoeff, DecCoeff) {
  guard shift >= 0 else {
    abort("decimal coefficient base-power division shift is negative")
  }
  if shift == 0 {
    return (value, dec_coeff_zero())
  }
  let length = dec_coeff_unit_len(value)
  if shift >= length {
    return (dec_coeff_zero(), value)
  }
  (
    dec_coeff_slice(value, shift, length - shift),
    dec_coeff_slice(value, 0, shift),
  )
}

///|
fn dec_coeff_bz_max_quotient(block_len : Int) -> DecCoeff {
  guard block_len > 0 else {
    abort("Burnikel-Ziegler quotient block length must be positive")
  }
  dec_coeff_from_unit_accumulator(
    Array::make(block_len, (dec_coeff_base - 1).reinterpret_as_uint()),
    block_len,
  )
}

///|
fn dec_coeff_div_3n_2n_bz(
  numerator : DecCoeff,
  denominator : DecCoeff,
  half_len : Int,
  arena : DecCoeffScratchArena,
  depth : Int,
) -> (DecCoeff, DecCoeff) {
  if half_len <= dec_coeff_bz_recursive_threshold || depth >= 64 {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let mark = arena.mark()
  let numerator0 = arena.save(
    dec_coeff_slice_arena(numerator, 0, half_len, arena),
  )
  let numerator1 = arena.save(
    dec_coeff_slice_arena(numerator, half_len, half_len, arena),
  )
  let numerator2 = arena.save(
    dec_coeff_slice_arena(numerator, half_len * 2, half_len, arena),
  )
  let denominator0 = arena.save(
    dec_coeff_slice_arena(denominator, 0, half_len, arena),
  )
  let denominator1 = arena.save(
    dec_coeff_slice_arena(denominator, half_len, half_len, arena),
  )
  let upper = dec_coeff_magnitude_add_repr(
    dec_coeff_shift_limbs(numerator2, half_len),
    numerator1,
  )
  let (initial_quotient, upper_remainder) = if dec_coeff_compare_repr(
      numerator2, denominator1,
    ) <
    0 {
    dec_coeff_div_2n_1n_bz(upper, denominator1, half_len, arena, depth + 1)
  } else {
    let quotient = dec_coeff_bz_max_quotient(half_len)
    let product = dec_coeff_multiply_repr(quotient, denominator1)
    (quotient, dec_coeff_magnitude_sub_repr(upper, product))
  }
  let mut quotient = initial_quotient
  let mut combined = dec_coeff_magnitude_add_repr(
    dec_coeff_shift_limbs(upper_remainder, half_len),
    numerator0,
  )
  let lower_product = dec_coeff_multiply_repr(initial_quotient, denominator0)
  let mut corrections = 0
  while dec_coeff_compare_repr(combined, lower_product) < 0 {
    if quotient.is_zero() || corrections >= 2 {
      arena.rewind(mark)
      return dec_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    quotient = dec_coeff_magnitude_sub_unit(quotient, 1)
    combined = dec_coeff_magnitude_add_repr(combined, denominator)
    corrections += 1
  }
  let mut remainder = dec_coeff_magnitude_sub_repr(combined, lower_product)
  while dec_coeff_compare_repr(remainder, denominator) >= 0 {
    if corrections >= 3 ||
      dec_coeff_compare_repr(quotient, dec_coeff_bz_max_quotient(half_len)) >= 0 {
      arena.rewind(mark)
      return dec_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    quotient = dec_coeff_magnitude_add_unit(quotient, 1)
    remainder = dec_coeff_magnitude_sub_repr(remainder, denominator)
    corrections += 1
  }
  let result = (dec_coeff_owned(quotient), dec_coeff_owned(remainder))
  arena.rewind(mark)
  result
}

///|
fn dec_coeff_div_2n_1n_bz(
  numerator : DecCoeff,
  denominator : DecCoeff,
  block_len : Int,
  arena : DecCoeffScratchArena,
  depth : Int,
) -> (DecCoeff, DecCoeff) {
  if block_len <= dec_coeff_bz_recursive_threshold ||
    (block_len & 1) != 0 ||
    depth >= 64 {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let mark = arena.mark()
  let half_len = block_len / 2
  let low = arena.save(dec_coeff_slice_arena(numerator, 0, half_len, arena))
  let upper = arena.save(
    dec_coeff_slice_arena(numerator, half_len, half_len * 3, arena),
  )
  let (upper_quotient, upper_remainder) = dec_coeff_div_3n_2n_bz(
    upper,
    denominator,
    half_len,
    arena,
    depth + 1,
  )
  let lower_numerator = dec_coeff_magnitude_add_repr(
    dec_coeff_shift_limbs(upper_remainder, half_len),
    low,
  )
  let (lower_quotient, remainder) = dec_coeff_div_3n_2n_bz(
    lower_numerator,
    denominator,
    half_len,
    arena,
    depth + 1,
  )
  let quotient = dec_coeff_magnitude_add_repr(
    dec_coeff_shift_limbs(upper_quotient, half_len),
    lower_quotient,
  )
  let result = (dec_coeff_owned(quotient), dec_coeff_owned(remainder))
  arena.rewind(mark)
  result
}

///|
fn dec_coeff_div_rem_bz_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  guard !denominator.is_zero() else {
    abort("Burnikel-Ziegler division expects denominator > 0")
  }
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return (dec_coeff_zero(), numerator)
  }
  let denominator_len = dec_coeff_unit_len(denominator)
  let mut block_len = 1
  while block_len < denominator_len {
    block_len *= 2
  }
  let padding = block_len - denominator_len
  let normalized_denominator = dec_coeff_shift_limbs(denominator, padding)
  if dec_coeff_unit_len(normalized_denominator) != block_len ||
    dec_coeff_limb_at(normalized_denominator, block_len - 1) == 0U {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let normalized_numerator = dec_coeff_shift_limbs(numerator, padding)
  let numerator_len = dec_coeff_unit_len(normalized_numerator)
  let block_count = (numerator_len + block_len - 1) / block_len
  let arena = dec_coeff_scratch_arena_new(192)
  let mut quotient = dec_coeff_zero()
  let mut remainder = dec_coeff_zero()
  let mut block_index = block_count
  while block_index > 0 {
    block_index -= 1
    let block = dec_coeff_slice(
      normalized_numerator,
      block_index * block_len,
      block_len,
    )
    let combined = dec_coeff_magnitude_add_repr(
      dec_coeff_shift_limbs(remainder, block_len),
      block,
    )
    if dec_coeff_unit_len(combined) > block_len * 2 {
      return dec_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    let (quotient_block, next_remainder) = dec_coeff_div_2n_1n_bz(
      combined, normalized_denominator, block_len, arena, 0,
    )
    quotient = dec_coeff_magnitude_add_repr(
      dec_coeff_shift_limbs(quotient, block_len),
      quotient_block,
    )
    remainder = next_remainder
  }
  let (restored_remainder, discarded) = dec_coeff_div_rem_power_limbs(
    remainder, padding,
  )
  if !discarded.is_zero() {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  if dec_coeff_compare_repr(restored_remainder, denominator) >= 0 {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let product = dec_coeff_multiply_repr(quotient, denominator)
  if dec_coeff_compare_repr(product, numerator) > 0 ||
    dec_coeff_compare_repr(
      dec_coeff_magnitude_add_repr(product, restored_remainder),
      numerator,
    ) !=
    0 {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  (quotient, restored_remainder)
}

///|
fn dec_coeff_div_rem_newton_try(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff)? {
  guard !denominator.is_zero() else {
    abort("Newton reciprocal division expects denominator > 0")
  }
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return Some((dec_coeff_zero(), numerator))
  }
  let denominator_len = dec_coeff_unit_len(denominator)
  let numerator_len = dec_coeff_unit_len(numerator)
  let scale_limbs = numerator_len + 1
  let scale = dec_coeff_shift_limbs(dec_coeff_from_int(1), scale_limbs)
  let twice_scale = dec_coeff_multiply_by_unit_repr(scale, 2)
  let top = dec_coeff_limb_at(denominator, denominator_len - 1)
  let seed_scale = scale_limbs - denominator_len + 1
  let seed_numerator = dec_coeff_shift_limbs(dec_coeff_from_int(1), seed_scale)
  let seed_denominator = dec_coeff_magnitude_add_unit(
    dec_coeff_from_int(top.reinterpret_as_int()),
    1,
  )
  let (seed, _) = dec_coeff_div_rem_knuth_repr(seed_numerator, seed_denominator)
  if seed.is_zero() {
    return None
  }
  let mut reciprocal = seed
  let mut iterations = 0
  while iterations < 64 {
    let product = dec_coeff_multiply_repr(denominator, reciprocal)
    if dec_coeff_compare_repr(product, scale) > 0 {
      return None
    }
    let correction = dec_coeff_magnitude_sub_repr(twice_scale, product)
    let next_product = dec_coeff_multiply_repr(reciprocal, correction)
    let (next_reciprocal, _) = dec_coeff_div_rem_power_limbs(
      next_product, scale_limbs,
    )
    if dec_coeff_compare_repr(next_reciprocal, reciprocal) < 0 {
      return None
    }
    if dec_coeff_compare_repr(next_reciprocal, reciprocal) == 0 {
      break
    }
    reciprocal = next_reciprocal
    iterations += 1
  }
  if iterations >= 64 {
    return None
  }
  let estimate_product = dec_coeff_multiply_repr(numerator, reciprocal)
  let (estimated, _) = dec_coeff_div_rem_power_limbs(
    estimate_product, scale_limbs,
  )
  let mut quotient = estimated
  let mut product = dec_coeff_multiply_repr(quotient, denominator)
  let mut corrections = 0
  let correction_limit = denominator_len * 2 + 8
  while dec_coeff_compare_repr(product, numerator) > 0 {
    if quotient.is_zero() || corrections >= correction_limit {
      return None
    }
    quotient = dec_coeff_magnitude_sub_unit(quotient, 1)
    product = dec_coeff_magnitude_sub_repr(product, denominator)
    corrections += 1
  }
  let mut remainder = dec_coeff_magnitude_sub_repr(numerator, product)
  while dec_coeff_compare_repr(remainder, denominator) >= 0 {
    if corrections >= correction_limit {
      return None
    }
    quotient = dec_coeff_magnitude_add_unit(quotient, 1)
    product = dec_coeff_magnitude_add_repr(product, denominator)
    remainder = dec_coeff_magnitude_sub_repr(remainder, denominator)
    corrections += 1
  }
  if dec_coeff_compare_repr(product, numerator) > 0 ||
    dec_coeff_compare_repr(remainder, denominator) >= 0 ||
    dec_coeff_compare_repr(
      dec_coeff_magnitude_add_repr(product, remainder),
      numerator,
    ) !=
    0 {
    return None
  }
  Some((quotient, remainder))
}

///|
fn dec_coeff_div_rem_burnikel_ziegler(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  dec_coeff_div_rem_bz_repr(numerator, denominator)
}

///|
fn dec_coeff_div_rem_newton(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  match dec_coeff_div_rem_newton_try(numerator, denominator) {
    Some(result) => result
    None => dec_coeff_div_rem_burnikel_ziegler(numerator, denominator)
  }
}

///|
#warnings("-unused_value")
priv enum DecCoeffDivAlgorithm {
  Word
  Knuth
  BurnikelZiegler
  Newton
} derive(Eq)

///|
fn dec_coeff_division_algorithm(denominator : DecCoeff) -> DecCoeffDivAlgorithm {
  let length = dec_coeff_unit_len(denominator)
  if length == 1 {
    Word
  } else if dec_coeff_newton_enabled && length >= dec_coeff_newton_threshold {
    Newton
  } else if dec_coeff_bz_profitable(denominator) {
    BurnikelZiegler
  } else {
    Knuth
  }
}

///|
fn dec_coeff_bz_profitable(denominator : DecCoeff) -> Bool {
  let length = dec_coeff_unit_len(denominator)
  let mut block_length = 1
  while block_length < length {
    block_length *= 2
  }
  let threshold = if block_length <= 4096 {
    dec_coeff_burnikel_ziegler_threshold
  } else if block_length <= 8192 {
    dec_coeff_burnikel_ziegler_threshold_8k
  } else if block_length <= 16384 {
    dec_coeff_burnikel_ziegler_threshold_16k
  } else {
    dec_coeff_burnikel_ziegler_threshold_large
  }
  length >= threshold
}
