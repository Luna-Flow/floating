///|
// Package-local signed wrapper for coefficient algorithms whose intermediate
// values may be negative. GdaCoeff itself always remains non-negative.

///|
priv struct SignedGdaCoeff {
  negative : Bool
  magnitude : GdaCoeff
}

///|
fn signed_gda_coeff(negative : Bool, magnitude : GdaCoeff) -> SignedGdaCoeff {
  { negative: negative && !magnitude.is_zero(), magnitude }
}

///|
fn signed_gda_coeff_zero() -> SignedGdaCoeff {
  signed_gda_coeff(false, gda_coeff_zero())
}

///|
fn SignedGdaCoeff::neg(self : SignedGdaCoeff) -> SignedGdaCoeff {
  signed_gda_coeff(!self.negative, self.magnitude)
}

///|
fn SignedGdaCoeff::add(
  self : SignedGdaCoeff,
  other : SignedGdaCoeff,
) -> SignedGdaCoeff {
  let (negative, magnitude) = gda_coeff_signed_add_repr(
    self.negative,
    self.magnitude,
    other.negative,
    other.magnitude,
  )
  signed_gda_coeff(negative, magnitude)
}

///|
fn SignedGdaCoeff::sub(
  self : SignedGdaCoeff,
  other : SignedGdaCoeff,
) -> SignedGdaCoeff {
  self.add(other.neg())
}

///|
fn signed_gda_coeff_from_int_product(
  value : Int,
  magnitude : GdaCoeff,
) -> SignedGdaCoeff {
  let absolute = gda_coeff_from_int_magnitude(value)
  signed_gda_coeff(value < 0, gda_coeff_multiply_repr(absolute, magnitude))
}

///|
fn SignedGdaCoeff::round_power10_half_even(
  self : SignedGdaCoeff,
  shift : Int,
) -> SignedGdaCoeff {
  if shift <= 0 {
    return signed_gda_coeff(
      self.negative,
      gda_coeff_shift_power10_repr(self.magnitude, -shift),
    )
  }
  signed_gda_coeff(
    self.negative,
    round_positive_decimal_div_pow10_repr(
      self.magnitude,
      shift,
      self.negative,
      DecimalRoundingMode::HalfEven,
    ).0,
  )
}
