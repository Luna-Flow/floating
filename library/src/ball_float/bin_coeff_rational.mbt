///|
#derive(Eq)
priv struct SignedBinCoeff {
  negative : Bool
  magnitude : @bin_float.BinCoeff
}

///|
fn coeff_one() -> @bin_float.BinCoeff {
  @bin_float.BinCoeff::one()
}

///|
fn coeff_from_nonnegative_int(value : Int32) -> @bin_float.BinCoeff {
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
fn coeff_bits(value : @bin_float.BinCoeff) -> Int32 {
  value.bit_length()
}

///|
fn coeff_compare(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> Int32 {
  left.compare(right)
}

///|
fn coeff_gcd(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  // gcd(a, 2^k) = 2^min(v2(a), k): a trailing-zero count instead of a
  // general big-integer gcd. Rationals built from binary floats have
  // power-of-two denominators, so this is the common case.
  if coeff_is_zero(left) || coeff_is_zero(right) {
    return @bin_float.BinCoeff(left.0.gcd(right.0))
  }
  if right.0.ctz() == right.bit_length() - 1 {
    return @bin_float.BinCoeff(
      @bin_kernel.Coeff::one().shift_left(
        Int32::min(left.0.ctz(), right.0.ctz()),
      ),
    )
  }
  if left.0.ctz() == left.bit_length() - 1 {
    return @bin_float.BinCoeff(
      @bin_kernel.Coeff::one().shift_left(
        Int32::min(left.0.ctz(), right.0.ctz()),
      ),
    )
  }
  @bin_float.BinCoeff(left.0.gcd(right.0))
}

///|
fn coeff_mul(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(left.0.mul(right.0))
}

///|
fn coeff_shift_left(
  value : @bin_float.BinCoeff,
  shift : Int32,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(value.0.shift_left(shift))
}

///|
fn coeff_add(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(left.0.add(right.0))
}

///|
/// `left - right` for `left >= right`; a smaller `left` aborts.
fn coeff_sub(
  left : @bin_float.BinCoeff,
  right : @bin_float.BinCoeff,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(left.0.sub_checked(right.0).unwrap())
}

///|
fn coeff_shift_right(
  value : @bin_float.BinCoeff,
  shift : Int32,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(value.0.shift_right(shift))
}

///|
fn coeff_test_bit(value : @bin_float.BinCoeff, index : Int32) -> Bool {
  value.0.test_bit(index)
}

///|
fn coeff_pow_nat(
  value : @bin_float.BinCoeff,
  exponent : UInt32,
) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(value.0.pow_nat(exponent))
}

///|
fn coeff_increment(value : @bin_float.BinCoeff) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff(value.0.add(@bin_kernel.Coeff::one()))
}

///|
fn coeff_div_rem(
  numerator : @bin_float.BinCoeff,
  denominator : @bin_float.BinCoeff,
) -> (@bin_float.BinCoeff, @bin_float.BinCoeff) {
  let (quotient, remainder) = numerator.0
    .div_rem_checked(denominator.0)
    .unwrap()
  (@bin_float.BinCoeff(quotient), @bin_float.BinCoeff(remainder))
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
fn coeff_mod_int(value : @bin_float.BinCoeff, divisor : Int32) -> Int32 {
  guard divisor > 0 else { abort("coefficient modulus must be positive") }
  value.0
  .div_rem_checked(@bin_kernel.Coeff::from_uint64(divisor.to_uint64()))
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
  { negative: negative && !magnitude.is_zero(), magnitude, }
}

///|
fn signed_coeff_from_int(value : Int32) -> SignedBinCoeff {
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
fn signed_coeff_sign(value : SignedBinCoeff) -> Int32 {
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
fn signed_coeff_compare(left : SignedBinCoeff, right : SignedBinCoeff) -> Int32 {
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
      coeff_add(left.magnitude, right.magnitude),
    )
  }
  let comparison = left.magnitude.compare(right.magnitude)
  if comparison == 0 {
    signed_coeff_from_int(0)
  } else if comparison > 0 {
    signed_coeff_from_parts(
      left.negative,
      coeff_sub(left.magnitude, right.magnitude),
    )
  } else {
    signed_coeff_from_parts(
      right.negative,
      coeff_sub(right.magnitude, left.magnitude),
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
    coeff_mul(left.magnitude, right.magnitude),
  )
}

///|
fn signed_coeff_mul_magnitude(
  value : SignedBinCoeff,
  multiplier : @bin_float.BinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_mul(value.magnitude, multiplier),
  )
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
