///|
fn bin_coeff_mod(value : BinCoeff, modulus : BinCoeff) -> BinCoeff {
  value.div_rem_checked(modulus).unwrap().1
}

///|
/// `2^exponent mod modulus` by square-and-multiply, for exponents up to the
/// Int range without materializing `2^exponent`.
fn bin_coeff_pow2_mod(exponent : Int, modulus : BinCoeff) -> BinCoeff {
  let mut result = bin_coeff_mod(BinCoeff::one(), modulus)
  let mut base = bin_coeff_mod(BinCoeff::from_uint64(2UL), modulus)
  let mut remaining = exponent
  while remaining > 0 {
    if remaining % 2 == 1 {
      result = bin_coeff_mod(result.mul(base), modulus)
    }
    base = bin_coeff_mod(base.square(), modulus)
    remaining = remaining / 2
  }
  result
}

///|
/// IEEE 754 remainder: `self - divisor * n` where `n` is the integer nearest
/// `self / divisor`, ties to even. The exact remainder is rounded under
/// `context`, which leaves it unchanged whenever it fits the context
/// precision, as it always does for operands of one IEEE format. A zero
/// result has the sign of `self`.
pub fn BinFloat::remainder_ctx(
  self : BinFloat,
  divisor : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_nan_pair(self, divisor, context.precision) {
    Some(result) => return result
    None => ()
  }
  if self.class == FpClass::Infinity ||
    (divisor.class == FpClass::Finite && divisor.coefficient_.is_zero()) {
    return (BinFloat::nan(precision=context.precision), binary_invalid_flags())
  }
  if divisor.class == FpClass::Infinity || self.coefficient_.is_zero() {
    return self.round_ctx(context)
  }
  let top = binary_exact_top(self.coefficient_, self.exponent2)
  let divisor_top = binary_exact_top(divisor.coefficient_, divisor.exponent2)
  // |self| < 2^(top + 1) <= |divisor| / 2: the nearest multiple is zero.
  if top.to_int64() + 1L < divisor_top.to_int64() {
    return self.round_ctx(context)
  }
  // Scale both magnitudes by 2^-e, e = min exponent: X = dividend, Y = divisor.
  let (dividend_mod_twice, modulus, exponent) = if self.exponent2 >=
    divisor.exponent2 {
    // X = cx * 2^(ex - ey) can be astronomically large; reduce it modulo 2Y.
    let modulus = divisor.coefficient_
    let twice = modulus.shift_left(1)
    let reduced = bin_coeff_mod(
      bin_coeff_mod(self.coefficient_, twice).mul(
        bin_coeff_pow2_mod(self.exponent2 - divisor.exponent2, twice),
      ),
      twice,
    )
    (reduced, modulus, divisor.exponent2)
  } else {
    // ey - ex <= bits(cx) here, because top >= divisor_top - 1.
    let modulus = divisor.coefficient_.shift_left(
      divisor.exponent2 - self.exponent2,
    )
    (
      bin_coeff_mod(self.coefficient_, modulus.shift_left(1)),
      modulus,
      self.exponent2,
    )
  }
  // X mod 2Y gives both X mod Y and the parity of floor(X / Y).
  let quotient_odd = dividend_mod_twice.compare(modulus) >= 0
  let remainder = if quotient_odd {
    dividend_mod_twice.sub_checked(modulus).unwrap()
  } else {
    dividend_mod_twice
  }
  let half_comparison = remainder.shift_left(1).compare(modulus)
  let round_up = half_comparison > 0 || (half_comparison == 0 && quotient_odd)
  let (negative, magnitude) = if round_up {
    (!self.negative, modulus.sub_checked(remainder).unwrap())
  } else {
    (self.negative, remainder)
  }
  if magnitude.is_zero() {
    return (finite_zero(self.negative, context.precision), BinaryFlags::new())
  }
  binary_round_dyadic(negative, magnitude, exponent, context)
}

///|
/// `remainder_ctx` in an unbounded nearest-even context at the larger operand
/// precision.
pub fn BinFloat::remainder(self : BinFloat, divisor : BinFloat) -> BinFloat {
  self.remainder_ctx(
    divisor,
    BinaryContext::unbounded(Int::max(self.precision_, divisor.precision_)),
  ).0
}
