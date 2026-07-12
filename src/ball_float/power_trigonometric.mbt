///|
priv struct TrigRatBounds {
  sin_lower : CertifiedRat
  sin_upper : CertifiedRat
  cos_lower : CertifiedRat
  cos_upper : CertifiedRat
}

///|
fn rat_minimum(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  if rat_compare(left, right) <= 0 {
    left
  } else {
    right
  }
}

///|
fn rat_maximum(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  if rat_compare(left, right) >= 0 {
    left
  } else {
    right
  }
}

///|
fn rat_mul_signed_coeff(
  value : CertifiedRat,
  multiplier : SignedBinCoeff,
) -> CertifiedRat {
  certified_rat_coeff(signed_coeff_mul(value.num, multiplier), value.den)
}

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
fn signed_coeff_mod4(value : SignedBinCoeff) -> Int {
  let remainder = coeff_mod_int(signed_coeff_magnitude(value), 4)
  if signed_coeff_sign(value) < 0 && remainder != 0 {
    4 - remainder
  } else {
    remainder
  }
}

///|
fn negate_rat_bounds(
  lower : CertifiedRat,
  upper : CertifiedRat,
) -> (CertifiedRat, CertifiedRat) {
  (rat_neg(upper), rat_neg(lower))
}

///|
fn directed_context(
  precision : Int,
  rounding : @bin_float.BinaryRoundingMode,
) -> @bin_float.BinaryContext {
  @bin_float.BinaryContext::unbounded(precision, rounding~)
}

///|
fn directed_add(
  left : @bin_float.BinFloat,
  right : @bin_float.BinFloat,
  context : @bin_float.BinaryContext,
) -> @bin_float.BinFloat {
  left.add_ctx(right, context).0
}

///|
fn directed_sub(
  left : @bin_float.BinFloat,
  right : @bin_float.BinFloat,
  context : @bin_float.BinaryContext,
) -> @bin_float.BinFloat {
  left.sub_ctx(right, context).0
}

///|
fn directed_mul(
  left : @bin_float.BinFloat,
  right : @bin_float.BinFloat,
  context : @bin_float.BinaryContext,
) -> @bin_float.BinFloat {
  left.mul_ctx(right, context).0
}

///|
fn directed_div(
  left : @bin_float.BinFloat,
  right : @bin_float.BinFloat,
  context : @bin_float.BinaryContext,
) -> @bin_float.BinFloat {
  left.div_ctx(right, context).0
}

///|
fn certified_atan_inverse_series(
  inverse : Int,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  let precision = work_bits + 32
  let downward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let one = @bin_float.BinFloat::one(precision~)
  let divisor = @bin_float.BinFloat::from_int(inverse, precision~)
  let argument_lower = directed_div(one, divisor, downward)
  let argument_upper = directed_div(one, divisor, upward)
  let squared_lower = directed_mul(argument_lower, argument_lower, downward)
  let squared_upper = directed_mul(argument_upper, argument_upper, upward)
  let mut term_lower = argument_lower
  let mut term_upper = argument_upper
  let mut denominator = 1
  let mut positive = true
  let mut sum_lower = @bin_float.BinFloat::zero(precision~)
  let mut sum_upper = sum_lower
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  while denominator < 200000 {
    if positive {
      sum_lower = directed_add(sum_lower, term_lower, downward)
      sum_upper = directed_add(sum_upper, term_upper, upward)
    } else {
      sum_lower = directed_sub(sum_lower, term_upper, downward)
      sum_upper = directed_sub(sum_upper, term_lower, upward)
    }
    let next_denominator = denominator + 2
    let current = @bin_float.BinFloat::from_int(denominator, precision~)
    let next = @bin_float.BinFloat::from_int(next_denominator, precision~)
    term_lower = directed_div(
      directed_mul(
        directed_mul(term_lower, squared_lower, downward),
        current,
        downward,
      ),
      next,
      downward,
    )
    term_upper = directed_div(
      directed_mul(
        directed_mul(term_upper, squared_upper, upward),
        current,
        upward,
      ),
      next,
      upward,
    )
    denominator = next_denominator
    positive = !positive
    if term_upper.compare(threshold) < 0 {
      let lower = if positive {
        sum_lower
      } else {
        directed_sub(sum_lower, term_upper, downward)
      }
      let upper = if positive {
        directed_add(sum_upper, term_upper, upward)
      } else {
        sum_upper
      }
      return (rat_from_finite_bin(lower), rat_from_finite_bin(upper))
    }
  }
  abort("certified atan series did not converge")
}

///|
fn certified_pi_rational(work_bits : Int) -> (CertifiedRat, CertifiedRat) {
  let (atan5_lower, atan5_upper) = certified_atan_inverse_series(5, work_bits)
  let (atan239_lower, atan239_upper) = certified_atan_inverse_series(
    239, work_bits,
  )
  (
    rat_sub(rat_mul_int(atan5_lower, 16), rat_mul_int(atan239_upper, 4)),
    rat_sub(rat_mul_int(atan5_upper, 16), rat_mul_int(atan239_lower, 4)),
  )
}

///|
fn certified_sin_series(
  argument : CertifiedRat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  if rat_sign(argument) < 0 {
    let (lower, upper) = certified_sin_series(rat_neg(argument), work_bits)
    return negate_rat_bounds(lower, upper)
  }
  guard rat_compare(argument, rat_from_int(1)) <= 0 else {
    abort("certified sin series requires an argument in [-1, 1]")
  }
  if rat_is_zero(argument) {
    let zero = rat_from_int(0)
    return (zero, zero)
  }
  let precision = work_bits + 32
  let downward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let argument_lower = rat_dyadic_bounds(argument, precision).0
  let argument_upper = rat_dyadic_bounds(argument, precision).1
  let squared_lower = directed_mul(argument_lower, argument_lower, downward)
  let squared_upper = directed_mul(argument_upper, argument_upper, upward)
  let mut term_lower = argument_lower
  let mut term_upper = argument_upper
  let mut sum_lower = argument_lower
  let mut sum_upper = argument_upper
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  let mut index = 0
  let mut positive = false
  while index < 100000 {
    let first = 2 * index + 2
    let second = first + 1
    let first_bin = @bin_float.BinFloat::from_int(first, precision~)
    let second_bin = @bin_float.BinFloat::from_int(second, precision~)
    term_lower = directed_div(
      directed_div(
        directed_mul(term_lower, squared_lower, downward),
        first_bin,
        downward,
      ),
      second_bin,
      downward,
    )
    term_upper = directed_div(
      directed_div(
        directed_mul(term_upper, squared_upper, upward),
        first_bin,
        upward,
      ),
      second_bin,
      upward,
    )
    if term_upper.compare(threshold) < 0 {
      let lower = if positive {
        sum_lower
      } else {
        directed_sub(sum_lower, term_upper, downward)
      }
      let upper = if positive {
        directed_add(sum_upper, term_upper, upward)
      } else {
        sum_upper
      }
      return (rat_from_finite_bin(lower), rat_from_finite_bin(upper))
    }
    if positive {
      sum_lower = directed_add(sum_lower, term_lower, downward)
      sum_upper = directed_add(sum_upper, term_upper, upward)
    } else {
      sum_lower = directed_sub(sum_lower, term_upper, downward)
      sum_upper = directed_sub(sum_upper, term_lower, upward)
    }
    positive = !positive
    index += 1
  }
  abort("certified sin series did not converge")
}

///|
fn certified_cos_series(
  argument : CertifiedRat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  let magnitude = rat_abs(argument)
  guard rat_compare(magnitude, rat_from_int(1)) <= 0 else {
    abort("certified cos series requires an argument in [-1, 1]")
  }
  if rat_is_zero(magnitude) {
    let one = rat_from_int(1)
    return (one, one)
  }
  let precision = work_bits + 32
  let downward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let argument_lower = rat_dyadic_bounds(magnitude, precision).0
  let argument_upper = rat_dyadic_bounds(magnitude, precision).1
  let squared_lower = directed_mul(argument_lower, argument_lower, downward)
  let squared_upper = directed_mul(argument_upper, argument_upper, upward)
  let one = @bin_float.BinFloat::one(precision~)
  let mut term_lower = one
  let mut term_upper = one
  let mut sum_lower = one
  let mut sum_upper = one
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  let mut index = 0
  let mut positive = false
  while index < 100000 {
    let first = 2 * index + 1
    let second = first + 1
    let first_bin = @bin_float.BinFloat::from_int(first, precision~)
    let second_bin = @bin_float.BinFloat::from_int(second, precision~)
    term_lower = directed_div(
      directed_div(
        directed_mul(term_lower, squared_lower, downward),
        first_bin,
        downward,
      ),
      second_bin,
      downward,
    )
    term_upper = directed_div(
      directed_div(
        directed_mul(term_upper, squared_upper, upward),
        first_bin,
        upward,
      ),
      second_bin,
      upward,
    )
    if term_upper.compare(threshold) < 0 {
      let lower = if positive {
        sum_lower
      } else {
        directed_sub(sum_lower, term_upper, downward)
      }
      let upper = if positive {
        directed_add(sum_upper, term_upper, upward)
      } else {
        sum_upper
      }
      return (rat_from_finite_bin(lower), rat_from_finite_bin(upper))
    }
    if positive {
      sum_lower = directed_add(sum_lower, term_lower, downward)
      sum_upper = directed_add(sum_upper, term_upper, upward)
    } else {
      sum_lower = directed_sub(sum_lower, term_upper, downward)
      sum_upper = directed_sub(sum_upper, term_lower, upward)
    }
    positive = !positive
    index += 1
  }
  abort("certified cos series did not converge")
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
fn certified_trig_endpoint_rationals(
  value : @bin_float.BinFloat,
  work_bits : Int,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> TrigRatBounds? {
  guard value.classify() == FpClass::Finite else { return None }
  let source = rat_from_finite_bin(value)
  let (quotient_lower, quotient_upper) = trig_quotient_bounds(
    source, pi_lower, pi_upper,
  )
  let half = rat_from_fraction_int(1, 2)
  let quadrant_lower = rat_floor(rat_add(quotient_lower, half))
  let quadrant_upper = rat_floor(rat_add(quotient_upper, half))
  guard quadrant_lower == quadrant_upper else { return None }
  let quadrant = quadrant_lower
  let lower_pi = rat_div_int(rat_mul_signed_coeff(pi_lower, quadrant), 2)
  let upper_pi = rat_div_int(rat_mul_signed_coeff(pi_upper, quadrant), 2)
  let (reduced_lower, reduced_upper) = if signed_coeff_sign(quadrant) < 0 {
    (rat_sub(source, lower_pi), rat_sub(source, upper_pi))
  } else {
    (rat_sub(source, upper_pi), rat_sub(source, lower_pi))
  }
  guard rat_compare(reduced_lower, reduced_upper) <= 0 else { return None }
  let (sin_left_lower, _) = certified_sin_series(reduced_lower, work_bits)
  let (_, sin_right_upper) = certified_sin_series(reduced_upper, work_bits)
  let (cos_left_lower, cos_left_upper) = certified_cos_series(
    reduced_lower, work_bits,
  )
  let (cos_right_lower, cos_right_upper) = certified_cos_series(
    reduced_upper, work_bits,
  )
  let reduced_sin_lower = sin_left_lower
  let reduced_sin_upper = sin_right_upper
  let reduced_cos_lower = rat_minimum(cos_left_lower, cos_right_lower)
  let reduced_cos_upper = if rat_sign(reduced_lower) <= 0 &&
    rat_sign(reduced_upper) >= 0 {
    rat_from_int(1)
  } else {
    rat_maximum(cos_left_upper, cos_right_upper)
  }
  match signed_coeff_mod4(quadrant) {
    0 =>
      Some({
        sin_lower: reduced_sin_lower,
        sin_upper: reduced_sin_upper,
        cos_lower: reduced_cos_lower,
        cos_upper: reduced_cos_upper,
      })
    1 => {
      let (cosine_lower, cosine_upper) = negate_rat_bounds(
        reduced_sin_lower, reduced_sin_upper,
      )
      Some({
        sin_lower: reduced_cos_lower,
        sin_upper: reduced_cos_upper,
        cos_lower: cosine_lower,
        cos_upper: cosine_upper,
      })
    }
    2 => {
      let (sine_lower, sine_upper) = negate_rat_bounds(
        reduced_sin_lower, reduced_sin_upper,
      )
      let (cosine_lower, cosine_upper) = negate_rat_bounds(
        reduced_cos_lower, reduced_cos_upper,
      )
      Some({
        sin_lower: sine_lower,
        sin_upper: sine_upper,
        cos_lower: cosine_lower,
        cos_upper: cosine_upper,
      })
    }
    _ => {
      let (sine_lower, sine_upper) = negate_rat_bounds(
        reduced_cos_lower, reduced_cos_upper,
      )
      Some({
        sin_lower: sine_lower,
        sin_upper: sine_upper,
        cos_lower: reduced_sin_lower,
        cos_upper: reduced_sin_upper,
      })
    }
  }
}

///|
fn unique_directed_bounds(
  lower : CertifiedRat,
  upper : CertifiedRat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  let lower_from_lower = rat_dyadic_bounds(lower, precision).0
  let lower_from_upper = rat_dyadic_bounds(upper, precision).0
  let upper_from_lower = rat_dyadic_bounds(lower, precision).1
  let upper_from_upper = rat_dyadic_bounds(upper, precision).1
  if lower_from_lower.compare(lower_from_upper) == 0 &&
    upper_from_lower.compare(upper_from_upper) == 0 {
    Some((lower_from_lower, upper_from_upper))
  } else {
    None
  }
}

///|
fn trig_initial_work(value : @bin_float.BinFloat, precision : Int) -> Int {
  let magnitude_bits = if value.is_zero() {
    0
  } else {
    Int::max(0, value.exponent2() + value.coefficient().bit_length())
  }
  precision + magnitude_bits + 96
}

///|
fn certified_sin_cos_endpoint_bounds(
  value : @bin_float.BinFloat,
  precision : Int,
  work_bits : Int,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
)? {
  match
    certified_trig_endpoint_rationals(value, work_bits, pi_lower, pi_upper) {
    Some(bounds) =>
      match
        (
          unique_directed_bounds(bounds.sin_lower, bounds.sin_upper, precision),
          unique_directed_bounds(bounds.cos_lower, bounds.cos_upper, precision),
        ) {
        (Some(sine), Some(cosine)) => Some((sine.0, sine.1, cosine.0, cosine.1))
        _ => None
      }
    None => None
  }
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
fn certified_sin_cos_interval_bounds(
  value : BallFloat,
) -> (
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  @bin_float.BinFloat,
  SignedBinCoeff,
  SignedBinCoeff,
)? {
  let mut work = Int::max(
    trig_initial_work(value.lo_, value.precision_),
    trig_initial_work(value.hi_, value.precision_),
  )
  for _ in 0..<8 {
    let (pi_lower, pi_upper) = certified_pi_rational(work + 16)
    match
      (
        certified_sin_cos_endpoint_bounds(
          value.lo_,
          value.precision_,
          work,
          pi_lower,
          pi_upper,
        ),
        certified_sin_cos_endpoint_bounds(
          value.hi_,
          value.precision_,
          work,
          pi_lower,
          pi_upper,
        ),
        critical_index_range_at_work(value, pi_lower, pi_upper),
      ) {
      (Some(lower), Some(upper), Some(indices)) =>
        return Some(
          (
            lower.0,
            lower.1,
            lower.2,
            lower.3,
            upper.0,
            upper.1,
            upper.2,
            upper.3,
            indices.0,
            indices.1,
          ),
        )
      _ => ()
    }
    work *= 2
  }
  None
}

///|
fn index_range_contains_residue(
  lower : SignedBinCoeff,
  upper : SignedBinCoeff,
  residue : Int,
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
fn trig_cutoff_exceeded(value : BallFloat) -> Bool {
  if !value.is_bounded() || value.is_empty() {
    return false
  }
  let magnitude = value.magnitude()
  if magnitude.is_zero() {
    return false
  }
  let adjusted = magnitude.exponent2() +
    magnitude.coefficient().bit_length() -
    1
  adjusted > Int::max(65536, 4 * value.precision_)
}

///|
fn unit_interval(precision : Int) -> BallFloat {
  store_interval(
    @bin_float.BinFloat::from_int(-1, precision~),
    @bin_float.BinFloat::one(precision~),
    precision,
  )
}

///|
pub fn BallFloat::sin_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if !self.is_bounded() || trig_cutoff_exceeded(self) {
    return unit_interval(self.precision_)
  }
  guard certified_sin_cos_interval_bounds(self) is Some(bounds) else {
    return unit_interval(self.precision_)
  }
  let lower_bound = if index_range_contains_residue(bounds.8, bounds.9, 3) {
    @bin_float.BinFloat::from_int(-1, precision=self.precision_)
  } else {
    bin_min(bounds.0, bounds.4)
  }
  let upper_bound = if index_range_contains_residue(bounds.8, bounds.9, 1) {
    @bin_float.BinFloat::one(precision=self.precision_)
  } else {
    bin_max(bounds.1, bounds.5)
  }
  store_interval(lower_bound, upper_bound, self.precision_)
}

///|
pub fn BallFloat::cos_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if !self.is_bounded() || trig_cutoff_exceeded(self) {
    return unit_interval(self.precision_)
  }
  guard certified_sin_cos_interval_bounds(self) is Some(bounds) else {
    return unit_interval(self.precision_)
  }
  let lower_bound = if index_range_contains_residue(bounds.8, bounds.9, 2) {
    @bin_float.BinFloat::from_int(-1, precision=self.precision_)
  } else {
    bin_min(bounds.2, bounds.6)
  }
  let upper_bound = if index_range_contains_residue(bounds.8, bounds.9, 0) {
    @bin_float.BinFloat::one(precision=self.precision_)
  } else {
    bin_max(bounds.3, bounds.7)
  }
  store_interval(lower_bound, upper_bound, self.precision_)
}

///|
fn rat_quotient_interval(
  numerator_lower : CertifiedRat,
  numerator_upper : CertifiedRat,
  denominator_lower : CertifiedRat,
  denominator_upper : CertifiedRat,
) -> (CertifiedRat, CertifiedRat)? {
  guard rat_sign(denominator_upper) < 0 || rat_sign(denominator_lower) > 0 else {
    return None
  }
  let first = rat_div(numerator_lower, denominator_lower)
  let second = rat_div(numerator_lower, denominator_upper)
  let third = rat_div(numerator_upper, denominator_lower)
  let fourth = rat_div(numerator_upper, denominator_upper)
  Some(
    (
      rat_minimum(rat_minimum(first, second), rat_minimum(third, fourth)),
      rat_maximum(rat_maximum(first, second), rat_maximum(third, fourth)),
    ),
  )
}

///|
fn certified_tan_endpoint_bounds(
  value : @bin_float.BinFloat,
  precision : Int,
  work_bits : Int,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  match
    certified_trig_endpoint_rationals(value, work_bits, pi_lower, pi_upper) {
    Some(bounds) =>
      match
        rat_quotient_interval(
          bounds.sin_lower,
          bounds.sin_upper,
          bounds.cos_lower,
          bounds.cos_upper,
        ) {
        Some(quotient) =>
          unique_directed_bounds(quotient.0, quotient.1, precision)
        None => None
      }
    None => None
  }
}

///|
fn certified_tan_interval_bounds(
  value : BallFloat,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  let mut work = Int::max(
    trig_initial_work(value.lo_, value.precision_),
    trig_initial_work(value.hi_, value.precision_),
  )
  for _ in 0..<8 {
    let (pi_lower, pi_upper) = certified_pi_rational(work + 16)
    guard critical_index_range_at_work(value, pi_lower, pi_upper)
      is Some(indices) else {
      return None
    }
    if index_range_contains_residue(indices.0, indices.1, 1) ||
      index_range_contains_residue(indices.0, indices.1, 3) {
      return None
    }
    match
      (
        certified_tan_endpoint_bounds(
          value.lo_,
          value.precision_,
          work,
          pi_lower,
          pi_upper,
        ),
        certified_tan_endpoint_bounds(
          value.hi_,
          value.precision_,
          work,
          pi_lower,
          pi_upper,
        ),
      ) {
      (Some(lower), Some(upper)) => return Some((lower.0, upper.1))
      _ => ()
    }
    work *= 2
  }
  None
}

///|
pub fn BallFloat::tan_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if !self.is_bounded() || trig_cutoff_exceeded(self) {
    return whole_real(self.precision_)
  }
  guard certified_tan_interval_bounds(self) is Some(bounds) else {
    return whole_real(self.precision_)
  }
  store_interval(bounds.0, bounds.1, self.precision_)
}

///|
fn pow_positive_endpoint(
  base : @bin_float.BinFloat,
  exponent : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let zero = @bin_float.BinFloat::zero(precision~)
  let one = @bin_float.BinFloat::one(precision~)
  if exponent.is_zero() || base.compare(one) == 0 {
    return (one, one)
  }
  if base.classify() == FpClass::Infinity {
    if exponent.sign() == Sign::Negative {
      return (zero, zero)
    }
    let infinity = pos_inf(precision)
    return (infinity, infinity)
  }
  if exponent.classify() == FpClass::Infinity {
    let below_one = base.compare(one) < 0
    let tends_to_zero = if exponent.sign() == Sign::Negative {
      !below_one
    } else {
      below_one
    }
    let limit = if tends_to_zero { zero } else { pos_inf(precision) }
    return (limit, limit)
  }
  let positive_one = @bin_float.BinFloat::from_int(1, precision~)
  let negative_one = @bin_float.BinFloat::from_int(-1, precision~)
  if exponent.compare(positive_one) == 0 {
    let exact = lower_round_bound(base, precision)
    return (exact, exact)
  }
  if exponent.compare(negative_one) == 0 {
    let reciprocal = BallFloat::exact(base, precision~).reciprocal()
    return (reciprocal.lo_, reciprocal.hi_)
  }
  let logarithm = certified_ln_endpoint_bounds(base, precision)
  let logarithm_interval = store_interval(logarithm.0, logarithm.1, precision)
  let exponent_interval = quantize_interval(exponent, exponent, precision)
  let result = exp_interval_at_precision(
    logarithm_interval * exponent_interval,
    precision,
  )
  (result.lo_, result.hi_)
}

///|
fn include_pow_candidate(
  candidate : (@bin_float.BinFloat, @bin_float.BinFloat),
  lower : @bin_float.BinFloat,
  upper : @bin_float.BinFloat,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  (bin_min(lower, candidate.0), bin_max(upper, candidate.1))
}

///|
fn pow_interval_at_precision(
  base : BallFloat,
  exponent : BallFloat,
  precision : Int,
) -> BallFloat {
  let precision = Int::max(1, precision)
  if base.is_empty() || exponent.is_empty() {
    return empty_interval(precision)
  }
  let nonnegative = base.intersection(
    store_interval(
      @bin_float.BinFloat::zero(precision~),
      pos_inf(precision),
      precision,
    ),
  )
  if nonnegative.is_empty() {
    return empty_interval(precision)
  }
  if nonnegative.hi_.is_zero() {
    if exponent.hi_.sign() == Sign::Negative || exponent.hi_.is_zero() {
      return empty_interval(precision)
    }
    return zero_radius_interval(
      @bin_float.BinFloat::zero(precision~),
      precision,
    )
  }
  let work = precision + 192
  let one = @bin_float.BinFloat::one(precision=work)
  let zero = @bin_float.BinFloat::zero(precision=work)
  let lower_base = lower_round_bound(nonnegative.lo_, work)
  let upper_base = upper_round_bound(nonnegative.hi_, work)
  let lower_exponent = lower_round_bound(exponent.lo_, work)
  let upper_exponent = upper_round_bound(exponent.hi_, work)
  let first = pow_positive_endpoint(upper_base, lower_exponent, work)
  let mut lower = first.0
  let mut upper = first.1
  let upper_corner = pow_positive_endpoint(upper_base, upper_exponent, work)
  let upper_bounds = include_pow_candidate(upper_corner, lower, upper)
  lower = upper_bounds.0
  upper = upper_bounds.1
  if !lower_base.is_zero() {
    let lower_corner = pow_positive_endpoint(lower_base, lower_exponent, work)
    let lower_bounds = include_pow_candidate(lower_corner, lower, upper)
    lower = lower_bounds.0
    upper = lower_bounds.1
    let diagonal_corner = pow_positive_endpoint(
      lower_base, upper_exponent, work,
    )
    let diagonal_bounds = include_pow_candidate(diagonal_corner, lower, upper)
    lower = diagonal_bounds.0
    upper = diagonal_bounds.1
  } else {
    if upper_exponent.sign() == Sign::Positive {
      lower = zero
    }
    if lower_exponent.sign() == Sign::Negative {
      upper = pos_inf(work)
    }
  }
  if lower_base.compare(one) <= 0 && upper_base.compare(one) >= 0 {
    lower = bin_min(lower, one)
    upper = bin_max(upper, one)
  }
  if lower_exponent.sign() != Sign::Positive &&
    upper_exponent.sign() != Sign::Negative {
    lower = bin_min(lower, one)
    upper = bin_max(upper, one)
  }
  quantize_interval(lower, upper, precision)
}

///|
pub fn BallFloat::pow_interval(
  self : BallFloat,
  exponent : BallFloat,
) -> BallFloat {
  let precision = Int::max(self.precision_, exponent.precision_)
  pow_interval_at_precision(self, exponent, precision)
}
