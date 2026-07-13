///|
// Package-local signed wrapper for coefficient algorithms whose intermediate
// values may be negative. DecCoeff itself always remains non-negative.

///|
priv struct SignedDecCoeff {
  negative : Bool
  magnitude : DecCoeff
}

///|
fn signed_dec_coeff(negative : Bool, magnitude : DecCoeff) -> SignedDecCoeff {
  { negative: negative && !magnitude.is_zero(), magnitude }
}

///|
fn signed_dec_coeff_zero() -> SignedDecCoeff {
  signed_dec_coeff(false, dec_coeff_zero())
}

///|
fn SignedDecCoeff::neg(self : SignedDecCoeff) -> SignedDecCoeff {
  signed_dec_coeff(!self.negative, self.magnitude)
}

///|
fn SignedDecCoeff::add(
  self : SignedDecCoeff,
  other : SignedDecCoeff,
) -> SignedDecCoeff {
  let (negative, magnitude) = dec_coeff_signed_add_repr(
    self.negative,
    self.magnitude,
    other.negative,
    other.magnitude,
  )
  signed_dec_coeff(negative, magnitude)
}

///|
fn SignedDecCoeff::sub(
  self : SignedDecCoeff,
  other : SignedDecCoeff,
) -> SignedDecCoeff {
  self.add(other.neg())
}

///|
fn signed_dec_coeff_from_int_product(
  value : Int,
  magnitude : DecCoeff,
) -> SignedDecCoeff {
  let absolute = dec_coeff_from_int_magnitude(value)
  signed_dec_coeff(value < 0, dec_coeff_multiply_repr(absolute, magnitude))
}

///|
fn SignedDecCoeff::round_power10_half_even(
  self : SignedDecCoeff,
  shift : Int,
) -> SignedDecCoeff {
  if shift <= 0 {
    return signed_dec_coeff(
      self.negative,
      dec_coeff_shift_power10_repr(self.magnitude, -shift),
    )
  }
  signed_dec_coeff(
    self.negative,
    round_positive_decimal_div_pow10_repr(
      self.magnitude,
      shift,
      self.negative,
      DecimalRoundingMode::HalfEven,
    ).0,
  )
}
