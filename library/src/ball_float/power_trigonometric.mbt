///|
fn rat_floor(value : CertifiedRat) -> SignedBinCoeff {
  let (quotient, remainder) = coeff_div_rem(
    signed_coeff_magnitude(value.num),
    value.den,
  )
  if rat_sign(value) < 0 {
    signed_coeff_from_parts(
      true,
      if coeff_is_zero(remainder) {
        quotient
      } else {
        coeff_increment(quotient)
      },
    )
  } else {
    signed_coeff_from_parts(false, quotient)
  }
}

///|
fn rat_ceil(value : CertifiedRat) -> SignedBinCoeff {
  let (quotient, remainder) = coeff_div_rem(
    signed_coeff_magnitude(value.num),
    value.den,
  )
  if rat_sign(value) > 0 && !coeff_is_zero(remainder) {
    signed_coeff_from_parts(false, coeff_increment(quotient))
  } else {
    signed_coeff_from_parts(rat_sign(value) < 0, quotient)
  }
}

///|
fn signed_coeff_mod4(value : SignedBinCoeff) -> Int32 {
  let remainder = coeff_mod_int(signed_coeff_magnitude(value), 4)
  if signed_coeff_sign(value) < 0 && remainder != 0 {
    4 - remainder
  } else {
    remainder
  }
}

///|
fn trig_quotient_bounds(
  value : CertifiedRat,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (CertifiedRat, CertifiedRat) {
  let twice = rat_mul_int(value, 2)
  if rat_sign(value) < 0 {
    (rat_div(twice, pi_lower), rat_div(twice, pi_upper))
  } else {
    (rat_div(twice, pi_upper), rat_div(twice, pi_lower))
  }
}

///|
fn trig_initial_work(value : @bin_float.BinFloat, precision : Int32) -> Int32 {
  let magnitude_bits = if value.is_zero() {
    0
  } else {
    Int32::max(0, value.exponent2() + value.coefficient().bit_length())
  }
  precision + magnitude_bits + 96
}

///|
fn critical_index_range_at_work(
  value : BallFloat,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (SignedBinCoeff, SignedBinCoeff)? {
  let (lower_quotient, _) = trig_quotient_bounds(
    rat_from_finite_bin(value.lo_),
    pi_lower,
    pi_upper,
  )
  let (_, upper_quotient) = trig_quotient_bounds(
    rat_from_finite_bin(value.hi_),
    pi_lower,
    pi_upper,
  )
  Some((rat_ceil(lower_quotient), rat_floor(upper_quotient)))
}

///|
/// Range of quarter-turn indices `k` with `k pi/2` inside `value`, from one
/// enclosure of `pi` taken from `certified_pi_interval` (so a cached `pi`
/// benefits this path). The enclosure has `work + 48` bits, which is tighter
/// than the `certified_pi_rational(work + 16)` of the refinement loop that
/// this replaces (its series stop at `2^-(work + 24)`, so its width is about
/// `2^-(work + 19)` against `2^-(work + 47)` here); the range is therefore
/// contained in the first-round range of the old code. The quotient bounds are
/// conservative, so the range can only be too large, never too small: an index
/// is reported only for `|x - k pi/2| < 2^-(precision + 140)` or closer to
/// an actual critical point. The rational form is kept because the quotient
/// and the ceiling and floor of it are exact there.
fn trig_critical_indices(value : BallFloat) -> (SignedBinCoeff, SignedBinCoeff) {
  let work = Int32::max(
    trig_initial_work(value.lo_, value.precision_),
    trig_initial_work(value.hi_, value.precision_),
  )
  let pi = certified_pi_interval(work + 48)
  critical_index_range_at_work(
    value,
    rat_from_finite_bin(pi.lo_),
    rat_from_finite_bin(pi.hi_),
  ).unwrap()
}

///|
fn index_range_contains_residue(
  lower : SignedBinCoeff,
  upper : SignedBinCoeff,
  residue : Int32,
) -> Bool {
  if signed_coeff_compare(lower, upper) > 0 {
    return false
  }
  if signed_coeff_compare(
      signed_coeff_sub(upper, lower),
      signed_coeff_from_int(3),
    ) >=
    0 {
    return true
  }
  let mut candidate = lower
  while signed_coeff_compare(candidate, upper) <= 0 {
    if signed_coeff_mod4(candidate) == residue {
      return true
    }
    candidate = signed_coeff_add(candidate, signed_coeff_from_int(1))
  }
  false
}

///|
/// Largest working precision (bits) of the argument reduction of the point
/// evaluations (`BinFloat::try_sin_ctx` and its siblings, which report a
/// resource limit beyond it).
let trig_work_limit : Int64 = 8_000_000L

///|
/// `true` when the reduction of the argument needs more working bits than
/// `trig_work_limit`: `precision + adjusted exponent + 96`.
fn trig_work_limit_exceeded(value : BallFloat) -> Bool {
  if !value.is_bounded() || value.is_empty() {
    return false
  }
  let magnitude = value.magnitude()
  if magnitude.is_zero() {
    return false
  }
  let adjusted = magnitude.exponent2().to_int64() +
    magnitude.coefficient().bit_length().to_int64() -
    1L
  Int64::max(0L, adjusted) + value.precision_.to_int64() + 96L > trig_work_limit
}

///|
fn unit_interval(precision : Int32) -> BallFloat {
  store_interval(
    @bin_float.BinFloat::from_int(-1, precision~),
    @bin_float.BinFloat::one(precision~),
    precision,
  )
}

///|
/// Total: the `try_sin_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::sin_interval(self : BallFloat) -> BallFloat {
  match self.try_sin_interval() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
/// Total: the `try_cos_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::cos_interval(self : BallFloat) -> BallFloat {
  match self.try_cos_interval() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
/// Total: the `try_tan_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::tan_interval(self : BallFloat) -> BallFloat {
  match self.try_tan_interval() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
pub fn BallFloat::pow_interval(
  self : BallFloat,
  exponent : BallFloat,
) -> BallFloat {
  let precision = Int32::max(self.precision_, exponent.precision_)
  match self.try_pow_interval(exponent) {
    Ok(result) => result
    Err(_) =>
      store_interval(
        @bin_float.BinFloat::zero(precision~),
        pos_inf(precision),
        precision,
      )
  }
}
