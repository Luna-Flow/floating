///|
let gda_coeff_bz_recursive_threshold = 16

///|
fn gda_coeff_owned(value : GdaCoeff) -> GdaCoeff {
  gda_coeff_from_unit_accumulator(
    gda_coeff_copy_limbs(value),
    gda_coeff_unit_len(value),
  )
}

///|
fn gda_coeff_div_rem_power_limbs(
  value : GdaCoeff,
  shift : Int,
) -> (GdaCoeff, GdaCoeff) {
  guard shift >= 0 else {
    abort("decimal coefficient base-power division shift is negative")
  }
  if shift == 0 {
    return (value, gda_coeff_zero())
  }
  let length = gda_coeff_unit_len(value)
  if shift >= length {
    return (gda_coeff_zero(), value)
  }
  (
    gda_coeff_slice(value, shift, length - shift),
    gda_coeff_slice(value, 0, shift),
  )
}

///|
fn gda_coeff_bz_max_quotient(block_len : Int) -> GdaCoeff {
  guard block_len > 0 else {
    abort("Burnikel-Ziegler quotient block length must be positive")
  }
  gda_coeff_from_unit_accumulator(
    Array::make(block_len, (gda_coeff_base - 1).reinterpret_as_uint()),
    block_len,
  )
}

///|
fn gda_coeff_div_3n_2n_bz(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
  half_len : Int,
  arena : GdaCoeffScratchArena,
  depth : Int,
) -> (GdaCoeff, GdaCoeff) {
  if half_len <= gda_coeff_bz_recursive_threshold || depth >= 64 {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let mark = arena.mark()
  let numerator0 = arena.save(
    gda_coeff_slice_arena(numerator, 0, half_len, arena),
  )
  let numerator1 = arena.save(
    gda_coeff_slice_arena(numerator, half_len, half_len, arena),
  )
  let numerator2 = arena.save(
    gda_coeff_slice_arena(numerator, half_len * 2, half_len, arena),
  )
  let denominator0 = arena.save(
    gda_coeff_slice_arena(denominator, 0, half_len, arena),
  )
  let denominator1 = arena.save(
    gda_coeff_slice_arena(denominator, half_len, half_len, arena),
  )
  let upper = gda_coeff_magnitude_add_repr(
    gda_coeff_shift_limbs(numerator2, half_len),
    numerator1,
  )
  let (initial_quotient, upper_remainder) = if gda_coeff_compare_repr(
      numerator2, denominator1,
    ) <
    0 {
    gda_coeff_div_2n_1n_bz(upper, denominator1, half_len, arena, depth + 1)
  } else {
    let quotient = gda_coeff_bz_max_quotient(half_len)
    let product = gda_coeff_multiply_repr(quotient, denominator1)
    (quotient, gda_coeff_magnitude_sub_repr(upper, product))
  }
  let mut quotient = initial_quotient
  let mut combined = gda_coeff_magnitude_add_repr(
    gda_coeff_shift_limbs(upper_remainder, half_len),
    numerator0,
  )
  let lower_product = gda_coeff_multiply_repr(initial_quotient, denominator0)
  let mut corrections = 0
  while gda_coeff_compare_repr(combined, lower_product) < 0 {
    if quotient.is_zero() || corrections >= 2 {
      arena.rewind(mark)
      return gda_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    quotient = gda_coeff_magnitude_sub_unit(quotient, 1)
    combined = gda_coeff_magnitude_add_repr(combined, denominator)
    corrections += 1
  }
  let mut remainder = gda_coeff_magnitude_sub_repr(combined, lower_product)
  while gda_coeff_compare_repr(remainder, denominator) >= 0 {
    if corrections >= 3 ||
      gda_coeff_compare_repr(quotient, gda_coeff_bz_max_quotient(half_len)) >= 0 {
      arena.rewind(mark)
      return gda_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    quotient = gda_coeff_magnitude_add_unit(quotient, 1)
    remainder = gda_coeff_magnitude_sub_repr(remainder, denominator)
    corrections += 1
  }
  let result = (gda_coeff_owned(quotient), gda_coeff_owned(remainder))
  arena.rewind(mark)
  result
}

///|
fn gda_coeff_div_2n_1n_bz(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
  block_len : Int,
  arena : GdaCoeffScratchArena,
  depth : Int,
) -> (GdaCoeff, GdaCoeff) {
  if block_len <= gda_coeff_bz_recursive_threshold ||
    (block_len & 1) != 0 ||
    depth >= 64 {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let mark = arena.mark()
  let half_len = block_len / 2
  let low = arena.save(gda_coeff_slice_arena(numerator, 0, half_len, arena))
  let upper = arena.save(
    gda_coeff_slice_arena(numerator, half_len, half_len * 3, arena),
  )
  let (upper_quotient, upper_remainder) = gda_coeff_div_3n_2n_bz(
    upper,
    denominator,
    half_len,
    arena,
    depth + 1,
  )
  let lower_numerator = gda_coeff_magnitude_add_repr(
    gda_coeff_shift_limbs(upper_remainder, half_len),
    low,
  )
  let (lower_quotient, remainder) = gda_coeff_div_3n_2n_bz(
    lower_numerator,
    denominator,
    half_len,
    arena,
    depth + 1,
  )
  let quotient = gda_coeff_magnitude_add_repr(
    gda_coeff_shift_limbs(upper_quotient, half_len),
    lower_quotient,
  )
  let result = (gda_coeff_owned(quotient), gda_coeff_owned(remainder))
  arena.rewind(mark)
  result
}

///|
fn gda_coeff_div_rem_bz_repr(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff) {
  guard !denominator.is_zero() else {
    abort("Burnikel-Ziegler division expects denominator > 0")
  }
  if gda_coeff_compare_repr(numerator, denominator) < 0 {
    return (gda_coeff_zero(), numerator)
  }
  let denominator_len = gda_coeff_unit_len(denominator)
  let mut block_len = 1
  while block_len < denominator_len {
    block_len *= 2
  }
  let padding = block_len - denominator_len
  let normalized_denominator = gda_coeff_shift_limbs(denominator, padding)
  if gda_coeff_unit_len(normalized_denominator) != block_len ||
    gda_coeff_limb_at(normalized_denominator, block_len - 1) == 0U {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let normalized_numerator = gda_coeff_shift_limbs(numerator, padding)
  let numerator_len = gda_coeff_unit_len(normalized_numerator)
  let block_count = (numerator_len + block_len - 1) / block_len
  let arena = gda_coeff_scratch_arena_new()
  let mut quotient = gda_coeff_zero()
  let mut remainder = gda_coeff_zero()
  let mut block_index = block_count
  while block_index > 0 {
    block_index -= 1
    let block = gda_coeff_slice(
      normalized_numerator,
      block_index * block_len,
      block_len,
    )
    let combined = gda_coeff_magnitude_add_repr(
      gda_coeff_shift_limbs(remainder, block_len),
      block,
    )
    if gda_coeff_unit_len(combined) > block_len * 2 {
      return gda_coeff_div_rem_knuth_repr(numerator, denominator)
    }
    let (quotient_block, next_remainder) = gda_coeff_div_2n_1n_bz(
      combined, normalized_denominator, block_len, arena, 0,
    )
    quotient = gda_coeff_magnitude_add_repr(
      gda_coeff_shift_limbs(quotient, block_len),
      quotient_block,
    )
    remainder = next_remainder
  }
  let (restored_remainder, discarded) = gda_coeff_div_rem_power_limbs(
    remainder, padding,
  )
  if !discarded.is_zero() {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  if gda_coeff_compare_repr(restored_remainder, denominator) >= 0 {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  let product = gda_coeff_multiply_repr(quotient, denominator)
  if gda_coeff_compare_repr(product, numerator) > 0 ||
    gda_coeff_compare_repr(
      gda_coeff_magnitude_add_repr(product, restored_remainder),
      numerator,
    ) !=
    0 {
    return gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
  (quotient, restored_remainder)
}

///|
fn gda_coeff_div_rem_newton_try(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff)? {
  guard !denominator.is_zero() else {
    abort("Newton reciprocal division expects denominator > 0")
  }
  if gda_coeff_compare_repr(numerator, denominator) < 0 {
    return Some((gda_coeff_zero(), numerator))
  }
  let denominator_len = gda_coeff_unit_len(denominator)
  let numerator_len = gda_coeff_unit_len(numerator)
  let scale_limbs = numerator_len + 1
  let scale = gda_coeff_shift_limbs(gda_coeff_from_int(1), scale_limbs)
  let twice_scale = gda_coeff_multiply_by_unit_repr(scale, 2)
  let top = gda_coeff_limb_at(denominator, denominator_len - 1)
  let seed_scale = scale_limbs - denominator_len + 1
  let seed_numerator = gda_coeff_shift_limbs(gda_coeff_from_int(1), seed_scale)
  let seed_denominator = gda_coeff_magnitude_add_unit(
    gda_coeff_from_int(top.reinterpret_as_int()),
    1,
  )
  let (seed, _) = gda_coeff_div_rem_knuth_repr(seed_numerator, seed_denominator)
  if seed.is_zero() {
    return None
  }
  let mut reciprocal = seed
  let mut iterations = 0
  while iterations < 64 {
    let product = gda_coeff_multiply_repr(denominator, reciprocal)
    if gda_coeff_compare_repr(product, scale) > 0 {
      return None
    }
    let correction = gda_coeff_magnitude_sub_repr(twice_scale, product)
    let next_product = gda_coeff_multiply_repr(reciprocal, correction)
    let (next_reciprocal, _) = gda_coeff_div_rem_power_limbs(
      next_product, scale_limbs,
    )
    if gda_coeff_compare_repr(next_reciprocal, reciprocal) < 0 {
      return None
    }
    if gda_coeff_compare_repr(next_reciprocal, reciprocal) == 0 {
      break
    }
    reciprocal = next_reciprocal
    iterations += 1
  }
  if iterations >= 64 {
    return None
  }
  let estimate_product = gda_coeff_multiply_repr(numerator, reciprocal)
  let (estimated, _) = gda_coeff_div_rem_power_limbs(
    estimate_product, scale_limbs,
  )
  let mut quotient = estimated
  let mut product = gda_coeff_multiply_repr(quotient, denominator)
  let mut corrections = 0
  let correction_limit = denominator_len * 2 + 8
  while gda_coeff_compare_repr(product, numerator) > 0 {
    if quotient.is_zero() || corrections >= correction_limit {
      return None
    }
    quotient = gda_coeff_magnitude_sub_unit(quotient, 1)
    product = gda_coeff_magnitude_sub_repr(product, denominator)
    corrections += 1
  }
  let mut remainder = gda_coeff_magnitude_sub_repr(numerator, product)
  while gda_coeff_compare_repr(remainder, denominator) >= 0 {
    if corrections >= correction_limit {
      return None
    }
    quotient = gda_coeff_magnitude_add_unit(quotient, 1)
    product = gda_coeff_magnitude_add_repr(product, denominator)
    remainder = gda_coeff_magnitude_sub_repr(remainder, denominator)
    corrections += 1
  }
  if gda_coeff_compare_repr(product, numerator) > 0 ||
    gda_coeff_compare_repr(remainder, denominator) >= 0 ||
    gda_coeff_compare_repr(
      gda_coeff_magnitude_add_repr(product, remainder),
      numerator,
    ) !=
    0 {
    return None
  }
  Some((quotient, remainder))
}

///|
fn gda_coeff_div_rem_burnikel_ziegler(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff) {
  gda_coeff_div_rem_bz_repr(numerator, denominator)
}

///|
fn gda_coeff_div_rem_newton(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff) {
  match gda_coeff_div_rem_newton_try(numerator, denominator) {
    Some(result) => result
    None => gda_coeff_div_rem_burnikel_ziegler(numerator, denominator)
  }
}

///|
#warnings("-unused_value")
priv enum GdaCoeffDivAlgorithm {
  Word
  Knuth
  BurnikelZiegler
  Newton
} derive(Eq)

///|
fn gda_coeff_division_algorithm(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> GdaCoeffDivAlgorithm {
  let length = gda_coeff_unit_len(denominator)
  if length == 1 {
    Word
  } else if gda_coeff_unit_len(numerator) - length + 1 <= 1 {
    Knuth
  } else if gda_coeff_newton_enabled && length >= gda_coeff_newton_threshold {
    Newton
  } else if gda_coeff_bz_profitable(denominator) {
    BurnikelZiegler
  } else {
    Knuth
  }
}

///|
fn gda_coeff_bz_profitable(denominator : GdaCoeff) -> Bool {
  let length = gda_coeff_unit_len(denominator)
  let mut block_length = 1
  while block_length < length {
    block_length *= 2
  }
  let threshold = if block_length <= 4096 {
    gda_coeff_burnikel_ziegler_threshold
  } else if block_length <= 8192 {
    gda_coeff_burnikel_ziegler_threshold_8k
  } else if block_length <= 16384 {
    gda_coeff_burnikel_ziegler_threshold_16k
  } else {
    gda_coeff_burnikel_ziegler_threshold_large
  }
  length >= threshold
}
