///|
priv struct SignedBinCoeff {
  negative : Bool
  magnitude : @binary.BinCoeff
}

///|
fn coeff_one() -> @binary.BinCoeff {
  @binary.BinCoeff::one()
}

///|
fn coeff_is_zero(value : @binary.BinCoeff) -> Bool {
  value.is_zero()
}

///|
fn coeff_compare(left : @binary.BinCoeff, right : @binary.BinCoeff) -> Int32 {
  left.compare(right)
}

///|
fn coeff_gcd(
  left : @binary.BinCoeff,
  right : @binary.BinCoeff,
) -> @binary.BinCoeff {
  // gcd(a, 2^k) = 2^min(v2(a), k): a trailing-zero count instead of a
  // general big-integer gcd. Rationals built from binary floats have
  // power-of-two denominators, so this is the common case.
  if coeff_is_zero(left) || coeff_is_zero(right) {
    return @binary.BinCoeff::from_kernel(
      left.to_kernel().gcd(right.to_kernel()),
    )
  }
  if right.to_kernel().ctz() == right.bit_length() - 1 {
    return @binary.BinCoeff::from_kernel(
      @bin_kernel.Coeff::one().shift_left(
        Int32::min(left.to_kernel().ctz(), right.to_kernel().ctz()),
      ),
    )
  }
  if left.to_kernel().ctz() == left.bit_length() - 1 {
    return @binary.BinCoeff::from_kernel(
      @bin_kernel.Coeff::one().shift_left(
        Int32::min(left.to_kernel().ctz(), right.to_kernel().ctz()),
      ),
    )
  }
  @binary.BinCoeff::from_kernel(left.to_kernel().gcd(right.to_kernel()))
}

///|
fn coeff_mul(
  left : @binary.BinCoeff,
  right : @binary.BinCoeff,
) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(left.to_kernel().mul(right.to_kernel()))
}

///|
fn coeff_shift_left(
  value : @binary.BinCoeff,
  shift : Int32,
) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(value.to_kernel().shift_left(shift))
}

///|
fn coeff_add(
  left : @binary.BinCoeff,
  right : @binary.BinCoeff,
) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(left.to_kernel().add(right.to_kernel()))
}

///|
/// `left - right` for `left >= right`; a smaller `left` aborts.
fn coeff_sub(
  left : @binary.BinCoeff,
  right : @binary.BinCoeff,
) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(
    left.to_kernel().sub_checked(right.to_kernel()).unwrap(),
  )
}

///|
fn coeff_shift_right(
  value : @binary.BinCoeff,
  shift : Int32,
) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(value.to_kernel().shift_right(shift))
}

///|
fn coeff_test_bit(value : @binary.BinCoeff, index : Int32) -> Bool {
  value.to_kernel().test_bit(index)
}

///|
fn coeff_increment(value : @binary.BinCoeff) -> @binary.BinCoeff {
  @binary.BinCoeff::from_kernel(value.to_kernel().add(@bin_kernel.Coeff::one()))
}

///|
fn coeff_div_rem(
  numerator : @binary.BinCoeff,
  denominator : @binary.BinCoeff,
) -> (@binary.BinCoeff, @binary.BinCoeff) {
  let (quotient, remainder) = numerator
    .to_kernel()
    .div_rem_checked(denominator.to_kernel())
    .unwrap()
  (
    @binary.BinCoeff::from_kernel(quotient),
    @binary.BinCoeff::from_kernel(remainder),
  )
}

///|
fn coeff_div_exact(
  numerator : @binary.BinCoeff,
  denominator : @binary.BinCoeff,
) -> @binary.BinCoeff {
  let (quotient, remainder) = coeff_div_rem(numerator, denominator)
  guard remainder.is_zero() else { abort("coefficient division is not exact") }
  quotient
}

///|
fn coeff_mod_int(value : @binary.BinCoeff, divisor : Int32) -> Int32 {
  guard divisor > 0 else { abort("coefficient modulus must be positive") }
  value
  .to_kernel()
  .div_rem_checked(@bin_kernel.Coeff::from_uint64(divisor.to_uint64()))
  .unwrap().1
  .to_uint64()
  .unwrap()
  .to_int()
}

///|
fn signed_coeff_from_parts(
  negative : Bool,
  magnitude : @binary.BinCoeff,
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
  signed_coeff_from_parts(negative, @binary.BinCoeff::from_uint64(magnitude))
}

///|
fn signed_coeff_magnitude(value : SignedBinCoeff) -> @binary.BinCoeff {
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
  multiplier : @binary.BinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_mul(value.magnitude, multiplier),
  )
}

///|
fn signed_coeff_div_exact(
  value : SignedBinCoeff,
  divisor : @binary.BinCoeff,
) -> SignedBinCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_div_exact(value.magnitude, divisor),
  )
}
