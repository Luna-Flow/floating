///|
// Differential tests of Knuth's division and of the scaled quotient against
// the previous implementation (four `Array[UInt64]` scratch arrays, wide
// accumulators converted afterwards, a defensive correction branch), kept here
// as private reference code. Results are compared bit for bit, representation
// included.

///|
let div_diff_cases : Int32 = 300

///|
/// the same for the classes of 24 limbs and more, whose reference is slow
let div_diff_cases_large : Int32 = 300

///|
fn reference_div_rem_knuth_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  let remainder_len = dec_coeff_unit_len(numerator)
  let denominator_len = dec_coeff_unit_len(denominator)
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return (dec_coeff_zero(), numerator)
  }
  if denominator_len == 1 {
    let (quotient, residue) = dec_coeff_div_rem_by_unit_repr(
      numerator,
      dec_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return (quotient, dec_coeff_from_int(residue))
  }
  let max_shift = remainder_len - denominator_len
  let quotient = Array::make(max_shift + 1, 0UL)
  let normalized_denominator = Array::make(denominator_len + 1, 0UL)
  let normalized_numerator = Array::make(remainder_len + 1, 0UL)
  let normalization = dec_coeff_wide_base /
    (dec_coeff_limb_at(denominator, denominator_len - 1).to_uint64() + 1UL)
  ignore(
    dec_coeff_wide_multiply_coeff_by_unit_into(
      denominator, normalization, normalized_denominator,
    ),
  )
  ignore(
    dec_coeff_wide_multiply_coeff_by_unit_into(
      numerator, normalization, normalized_numerator,
    ),
  )
  let top = normalized_denominator[denominator_len - 1]
  let second_top = normalized_denominator[denominator_len - 2]
  let mut shift = max_shift
  while true {
    let upper = normalized_numerator[shift + denominator_len]
    let next = normalized_numerator[shift + denominator_len - 1]
    let mut quotient_digit = (upper * dec_coeff_wide_base + next) / top
    let mut remainder_digit = (upper * dec_coeff_wide_base + next) % top
    if quotient_digit >= dec_coeff_wide_base {
      let excess = quotient_digit - (dec_coeff_wide_base - 1UL)
      quotient_digit = dec_coeff_wide_base - 1UL
      remainder_digit += excess * top
    }
    while remainder_digit < dec_coeff_wide_base &&
          quotient_digit * second_top >
          dec_coeff_wide_base * remainder_digit +
          normalized_numerator[shift + denominator_len - 2] {
      quotient_digit -= 1UL
      remainder_digit += top
      if remainder_digit >= dec_coeff_wide_base {
        break
      }
    }
    let mut carry = 0UL
    let mut borrow = 0UL
    for index in 0..<denominator_len {
      let product = normalized_denominator[index] * quotient_digit + carry
      let product_digit = product % dec_coeff_wide_base
      carry = product / dec_coeff_wide_base
      let subtrahend = product_digit + borrow
      let target = shift + index
      if normalized_numerator[target] < subtrahend {
        normalized_numerator[target] = normalized_numerator[target] +
          dec_coeff_wide_base -
          subtrahend
        borrow = 1UL
      } else {
        normalized_numerator[target] = normalized_numerator[target] - subtrahend
        borrow = 0UL
      }
    }
    let top_target = shift + denominator_len
    let top_subtrahend = carry + borrow
    let mut negative = false
    if normalized_numerator[top_target] < top_subtrahend {
      normalized_numerator[top_target] = normalized_numerator[top_target] +
        dec_coeff_wide_base -
        top_subtrahend
      negative = true
    } else {
      normalized_numerator[top_target] = normalized_numerator[top_target] -
        top_subtrahend
    }
    if negative {
      quotient_digit -= 1UL
      let mut add_carry = 0UL
      for index in 0..<denominator_len {
        let target = shift + index
        let sum = normalized_numerator[target] +
          normalized_denominator[index] +
          add_carry
        if sum >= dec_coeff_wide_base {
          normalized_numerator[target] = sum - dec_coeff_wide_base
          add_carry = 1UL
        } else {
          normalized_numerator[target] = sum
          add_carry = 0UL
        }
      }
      normalized_numerator[top_target] = normalized_numerator[top_target] +
        add_carry
      if normalized_numerator[top_target] >= dec_coeff_wide_base {
        normalized_numerator[top_target] -= dec_coeff_wide_base
      }
    }
    quotient[shift] = quotient_digit
    if shift == 0 {
      break
    }
    shift -= 1
  }
  let remainder_units = Array::make(denominator_len, 0UL)
  let mut residue = 0UL
  let mut index = denominator_len - 1
  while true {
    let current = residue * dec_coeff_wide_base + normalized_numerator[index]
    remainder_units[index] = current / normalization
    residue = current % normalization
    if index == 0 {
      break
    }
    index -= 1
  }
  let quotient_len = dec_coeff_wide_trim_units(quotient, quotient.length())
  let remainder_len = dec_coeff_wide_trim_units(
    remainder_units,
    remainder_units.length(),
  )
  if residue != 0UL {
    let mut corrected_quotient = dec_coeff_from_wide_accumulator(
      quotient, quotient_len,
    )
    let mut product = dec_coeff_multiply_repr(corrected_quotient, denominator)
    let mut corrections = 0
    while dec_coeff_compare_repr(product, numerator) > 0 {
      guard !corrected_quotient.is_zero() else {
        abort("Knuth quotient correction underflowed")
      }
      corrected_quotient = dec_coeff_magnitude_sub_unit(corrected_quotient, 1)
      product = dec_coeff_magnitude_sub_repr(product, denominator)
      corrections += 1
      guard corrections <= denominator_len * 2 + 8 else {
        abort("Knuth quotient correction exceeded guard")
      }
    }
    let mut corrected_remainder = dec_coeff_magnitude_sub_repr(
      numerator, product,
    )
    while dec_coeff_compare_repr(corrected_remainder, denominator) >= 0 {
      corrected_quotient = dec_coeff_magnitude_add_unit(corrected_quotient, 1)
      corrected_remainder = dec_coeff_magnitude_sub_repr(
        corrected_remainder, denominator,
      )
      corrections += 1
      guard corrections <= denominator_len * 2 + 8 else {
        abort("Knuth remainder correction exceeded guard")
      }
    }
    return (corrected_quotient, corrected_remainder)
  }
  (
    dec_coeff_from_wide_accumulator(quotient, quotient_len),
    dec_coeff_from_wide_accumulator(remainder_units, remainder_len),
  )
}

///|
fn div_diff_check(numerator : DecCoeff, denominator : DecCoeff) -> Unit raise {
  let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
    numerator, denominator,
  )
  let (expected_quotient, expected_remainder) = reference_div_rem_knuth_repr(
    numerator, denominator,
  )
  if !sqrt_diff_same(quotient, expected_quotient) ||
    !sqrt_diff_same(remainder, expected_remainder) {
    fail(
      "Knuth division differs for \{numerator.to_string()} / \{denominator.to_string()}",
    )
  }
}

///|
fn div_diff_scaled_check(
  coefficient : DecCoeff,
  shift : Int32,
  denominator : DecCoeff,
) -> Unit raise {
  let actual = dec_coeff_div_scaled_inexact(coefficient, shift, denominator)
  let (quotient, finite) = dec_coeff_round_div_expansion(
    dec_coeff_shift_power10_repr(coefficient, shift),
    denominator,
    false,
    DecCoeffRounding::ZeroFiveUp,
  )
  let expected = if finite { dec_coeff_zero() } else { quotient }
  if !sqrt_diff_same(actual, expected) {
    fail(
      "scaled quotient differs for \{coefficient.to_string()} * 10^\{shift} / \{denominator.to_string()}",
    )
  }
}

///|
fn div_diff_class(
  numerator_limbs : Int32,
  denominator_limbs : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  let cases = if numerator_limbs >= 24 {
    div_diff_cases_large
  } else {
    div_diff_cases
  }
  for iteration in 0..<cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let numerator = round_diff_value(state, numerator_limbs, nines)
    let denominator = round_diff_value(state, denominator_limbs, nines)
    div_diff_check(numerator, denominator)
    // an exact multiple, and one off it
    let multiple = dec_coeff_multiply_repr(denominator, numerator)
    div_diff_check(multiple, denominator)
    div_diff_check(dec_coeff_magnitude_add_unit(multiple, 1), denominator)
    if !multiple.is_zero() {
      div_diff_check(dec_coeff_magnitude_sub_unit(multiple, 1), denominator)
    }
    // the scaled quotient: random scale, the divisor of the class
    let coefficient = round_diff_value(state, numerator_limbs, nines)
    let shift = (sqrt_diff_next(state) % 40UL).to_int()
    div_diff_scaled_check(coefficient, shift, denominator)
    // divisors with factors 2 and 5, and a finite expansion
    let twos = (sqrt_diff_next(state) % 12UL).to_int()
    let fives = (sqrt_diff_next(state) % 8UL).to_int()
    let mut composite = denominator
    for _ in 0..<twos {
      composite = dec_coeff_multiply_by_unit_repr(composite, 2)
    }
    for _ in 0..<fives {
      composite = dec_coeff_multiply_by_unit_repr(composite, 5)
    }
    div_diff_scaled_check(coefficient, shift, composite)
    div_diff_scaled_check(
      dec_coeff_multiply_repr(coefficient, denominator),
      shift,
      composite,
    )
    div_diff_scaled_check(coefficient, shift, dec_coeff_power10_repr(twos + 9))
  }
}

///|
test "Knuth division equals the reference, 2 by 2 limbs" {
  div_diff_class(2, 2, 0x9E3779B97F4A7C15UL)
}

///|
test "Knuth division equals the reference, 4 by 2 limbs" {
  div_diff_class(4, 2, 0xD1B54A32D192ED03UL)
}

///|
test "Knuth division equals the reference, 4 by 3 limbs" {
  div_diff_class(4, 3, 0x2545F4914F6CDD1DUL)
}

///|
test "Knuth division equals the reference, 8 by 4 limbs" {
  div_diff_class(8, 4, 0x94D049BB133111EBUL)
}

///|
test "Knuth division equals the reference, 12 by 6 limbs" {
  div_diff_class(12, 6, 0xBF58476D1CE4E5B9UL)
}

///|
test "Knuth division equals the reference, 24 by 12 limbs" {
  div_diff_class(24, 12, 0x6A09E667F3BCC909UL)
}

///|
test "Knuth division equals the reference, 112 by 56 limbs" {
  div_diff_class(112, 56, 0xBB67AE8584CAA73BUL)
}

///|
test "Knuth division equals the reference, 224 by 112 limbs" {
  div_diff_class(224, 112, 0x3C6EF372FE94F82BUL)
}

///|
test "Knuth division equals the reference on powers of ten and nines" {
  for digits in 10..<400 {
    let power = dec_coeff_power10_repr(digits)
    let nines = dec_coeff_magnitude_sub_unit(power, 1)
    for
      denominator in [
        dec_coeff_power10_repr(digits / 2 + 9),
        dec_coeff_magnitude_sub_unit(dec_coeff_power10_repr(digits / 2 + 9), 1),
        dec_coeff_magnitude_add_unit(dec_coeff_power10_repr(digits / 3 + 9), 1),
      ] {
      for numerator in [power, nines, dec_coeff_multiply_by_unit_repr(power, 7)] {
        if dec_coeff_compare_repr(numerator, denominator) >= 0 &&
          dec_coeff_unit_len(denominator) > 1 {
          div_diff_check(numerator, denominator)
        }
        div_diff_scaled_check(numerator, digits % 25, denominator)
      }
    }
  }
}
