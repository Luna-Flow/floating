///|
// Digit-wise logical helpers on coefficients (GDA 1.70 logical operations,
// shift and rotate), kept as exact functions of digit sequences.

///|
// GDA logical operations are digit-wise over coefficient digits in base 10;
// this mirrors decNumber-style repeated coefficient digit extraction.
pub fn logical_binary_digits_repr(
  lhs : DecCoeff,
  rhs : DecCoeff,
  precision : Int32,
  op : (Bool, Bool) -> Bool,
) -> DecCoeff {
  let lhs_digits = logical_coeff_digits_lsd(lhs, precision)
  let rhs_digits = logical_coeff_digits_lsd(rhs, precision)
  let result_digits : Array[Int32] = []
  for index in 0..<precision {
    let lhs_digit = lhs_digits[index] == 1
    let rhs_digit = rhs_digits[index] == 1
    let out_digit = op(lhs_digit, rhs_digit)
    result_digits.push(if out_digit { 1 } else { 0 })
  }
  logical_coeff_from_digits_lsd(result_digits)
}

///|
pub fn coefficient_shift_digits_repr(
  coefficient : DecCoeff,
  count : Int32,
  precision : Int32,
) -> DecCoeff {
  if coefficient.is_zero() {
    return coefficient
  }
  if count == 0 {
    return coefficient
  }
  let digits = logical_coeff_digits_lsd(coefficient, precision)
  let shifted : Array[Int32] = []
  if count > 0 {
    for index in 0..<precision {
      shifted.push(if index >= count { digits[index - count] } else { 0 })
    }
  } else {
    let shift = -count
    for index in 0..<precision {
      shifted.push(
        if index + shift < precision {
          digits[index + shift]
        } else {
          0
        },
      )
    }
  }
  logical_coeff_from_digits_lsd(shifted)
}

///|
pub fn coefficient_rotate_digits_repr(
  coefficient : DecCoeff,
  count : Int32,
  precision : Int32,
) -> DecCoeff {
  if coefficient.is_zero() {
    return coefficient
  }
  let digits = logical_coeff_digits_lsd(coefficient, precision)
  let mut shift = count % precision
  if shift < 0 {
    shift += precision
  }
  if shift == 0 {
    return coefficient
  }
  let rotated : Array[Int32] = []
  for index in 0..<precision {
    let source = (index - shift + precision) % precision
    rotated.push(digits[source])
  }
  logical_coeff_from_digits_lsd(rotated)
}

///|
pub fn logical_coeff_digits_lsd(
  coeff : DecCoeff,
  precision : Int32,
) -> Array[Int32] {
  let digits : Array[Int32] = []
  for index in 0..<precision {
    let limb_index = index / dec_coeff_dpun
    let digit_index = index % dec_coeff_dpun
    let limb = if limb_index < dec_coeff_unit_len(coeff) {
      dec_coeff_limb_at(coeff, limb_index)
    } else {
      0U
    }
    digits.push(
      (limb / dec_coeff_powers[digit_index].reinterpret_as_uint() % 10U).reinterpret_as_int(),
    )
  }
  digits
}

///|
pub fn logical_coeff_from_digits_lsd(digits : Array[Int32]) -> DecCoeff {
  let limbs : Array[UInt32] = []
  let mut index = 0
  while index < digits.length() {
    let end = Int32::min(index + dec_coeff_dpun, digits.length())
    let mut limb = 0U
    let mut power = 1U
    for digit_index in index..<end {
      limb += digits[digit_index].reinterpret_as_uint() * power
      power *= 10U
    }
    limbs.push(limb)
    index = end
  }
  dec_coeff_from_unit_accumulator(limbs, limbs.length())
}
