///|
// Package-local signed wrapper for coefficient algorithms whose intermediate
// values may be negative. DecCoeff itself always remains non-negative.

///|
pub(all) struct SignedDecCoeff {
  negative : Bool
  magnitude : DecCoeff
}

///|
pub fn signed_dec_coeff(
  negative : Bool,
  magnitude : DecCoeff,
) -> SignedDecCoeff {
  { negative: negative && !magnitude.is_zero(), magnitude, }
}

///|
pub fn signed_dec_coeff_zero() -> SignedDecCoeff {
  signed_dec_coeff(false, dec_coeff_zero())
}

///|
pub fn SignedDecCoeff::neg(self : SignedDecCoeff) -> SignedDecCoeff {
  signed_dec_coeff(!self.negative, self.magnitude)
}

///|
pub fn SignedDecCoeff::add(
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
pub fn SignedDecCoeff::sub(
  self : SignedDecCoeff,
  other : SignedDecCoeff,
) -> SignedDecCoeff {
  self.add(other.neg())
}

///|
pub fn signed_dec_coeff_from_int_product(
  value : Int32,
  magnitude : DecCoeff,
) -> SignedDecCoeff {
  let absolute = dec_coeff_from_int_magnitude(value)
  signed_dec_coeff(value < 0, dec_coeff_multiply_repr(absolute, magnitude))
}
