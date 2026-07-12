///|
priv struct SignedBinCoeff {
  negative : Bool
  magnitude : @bin_float.BinCoeff
} derive(Eq)

///|
fn coeff_one() -> @bin_float.BinCoeff {
  @bin_float.BinCoeff::one()
}

///|
fn coeff_from_nonnegative_int(value : Int) -> @bin_float.BinCoeff {
  guard value >= 0 else {
    abort("coefficient constructor requires a non-negative integer")
  }
  @bin_float.BinCoeff::from_uint64(value.to_uint64())
}

///|
fn coeff_is_zero(value : @bin_float.BinCoeff) -> Bool {
  value.is_zero()
}

///|
fn coeff_bits(value : @bin_float.BinCoeff) -> Int {
  value.bit_length()
}

///|
fn coeff_compare(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> Int {
  left.compare(right)
}

///|
fn coeff_gcd(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  left.gcd(right)
}

///|
fn coeff_mul(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  left.mul(right)
}

///|
fn coeff_shift_left(
  value : @bin_float.BinCoeff,
  shift : Int,
) -> @bin_float.BinCoeff {
  value.shift_left(shift)
}

///|
fn coeff_increment(value : @bin_float.BinCoeff) -> @bin_float.BinCoeff {
  value.add(@bin_float.BinCoeff::one())
}

///|
fn coeff_div_rem(
  numerator : @bin_float.BinCoeff,
  denominator : @bin_float.BinCoeff,
) -> (@bin_float.BinCoeff, @bin_float.BinCoeff) {
  numerator.div_rem_checked(denominator).unwrap()
}

///|
fn coeff_div_exact(
  numerator : @bin_float.BinCoeff,
  denominator : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  let (quotient, remainder) = coeff_div_rem(numerator, denominator)
  guard remainder.is_zero() else { abort("coefficient division is not exact") }
  quotient
}

///|
fn coeff_to_uint64(value : @bin_float.BinCoeff) -> UInt64? {
  value.to_uint64()
}

///|
fn coeff_mod_int(value : @bin_float.BinCoeff, divisor : Int) -> Int {
  guard divisor > 0 else { abort("coefficient modulus must be positive") }
  value
  .div_rem_checked(@bin_float.BinCoeff::from_uint64(divisor.to_uint64()))
  .unwrap().1
  .to_uint64()
  .unwrap()
  .to_int()
}

///|
fn signed_coeff_from_parts(
  negative : Bool,
  magnitude : @bin_float.BinCoeff,
) -> SignedBinCoeff {
  { negative: negative && !magnitude.is_zero(), magnitude }
}

///|
fn signed_coeff_from_int(value : Int) -> SignedBinCoeff {
  let negative = value < 0
  let magnitude = if negative {
    (-(value + 1)).to_uint64() + 1UL
  } else {
    value.to_uint64()
  }
  signed_coeff_from_parts(negative, @bin_float.BinCoeff::from_uint64(magnitude))
}

///|
fn signed_coeff_magnitude(value : SignedBinCoeff) -> @bin_float.BinCoeff {
  value.magnitude
}

///|
fn signed_coeff_sign(value : SignedBinCoeff) -> Int {
  if value.magnitude.is_zero() {
    0
  } else if value.negative {
    -1
  } else {
    1
  }
}

///|
fn signed_coeff_is_zero(value : SignedBinCoeff) -> Bool {
  value.magnitude.is_zero()
}

///|
fn signed_coeff_neg(value : SignedBinCoeff) -> SignedBinCoeff {
  signed_coeff_from_parts(!value.negative, value.magnitude)
}

///|
fn signed_coeff_abs(value : SignedBinCoeff) -> SignedBinCoeff {
  signed_coeff_from_parts(false, value.magnitude)
}

///|
fn signed_coeff_compare(left : SignedBinCoeff, right : SignedBinCoeff) -> Int {
  let left_sign = signed_coeff_sign(left)
  let right_sign = signed_coeff_sign(right)
  if left_sign != right_sign {
    return if left_sign < right_sign { -1 } else { 1 }
  }
  if left_sign == 0 {
    return 0
  }
  let comparison = left.magnitude.compare(right.magnitude)
  if left_sign < 0 {
    -comparison
  } else {
    comparison
  }
}

///|
fn signed_coeff_add(
  left : SignedBinCoeff,
  right : SignedBinCoeff,
) -> SignedBinCoeff {
  if left.negative == right.negative {
    return signed_coeff_from_parts(
      left.negative,
      left.magnitude.add(right.magnitude),
    )
  }
  let comparison = left.magnitude.compare(right.magnitude)
  if comparison == 0 {
    signed_coeff_from_int(0)
  } else if comparison > 0 {
    signed_coeff_from_parts(
      left.negative,
      left.magnitude.sub_checked(right.magnitude).unwrap(),
    )
  } else {
    signed_coeff_from_parts(
      right.negative,
      right.magnitude.sub_checked(left.magnitude).unwrap(),
    )
  }
}

///|
fn signed_coeff_sub(
  left : SignedBinCoeff,
  right : SignedBinCoeff,
) -> SignedBinCoeff {
  signed_coeff_add(left, signed_coeff_neg(right))
}

///|
fn signed_coeff_mul(
  left : SignedBinCoeff,
  right : SignedBinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(
    left.negative != right.negative,
    left.magnitude.mul(right.magnitude),
  )
}

///|
fn signed_coeff_mul_magnitude(
  value : SignedBinCoeff,
  multiplier : @bin_float.BinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(value.negative, value.magnitude.mul(multiplier))
}

///|
fn signed_coeff_div_exact(
  value : SignedBinCoeff,
  divisor : @bin_float.BinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_div_exact(value.magnitude, divisor),
  )
}
