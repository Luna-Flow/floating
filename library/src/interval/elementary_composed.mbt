///|
/// `[RD(pi), RU(pi)]` at `precision` bits from the cached binary-splitting
/// constant of `bin_float`: `atan(+inf)` is `pi/2` served from that cache, and
/// scaling by 2 is exact (unbounded exponent range).
fn certified_pi_interval(precision : Int32) -> Interval {
  let infinity = @bin_float.BinFloat::inf(Sign::Positive, precision~)
  let exact = @bin_float.BinaryContext::new(precision~)
  let two = @bin_float.BinFloat::from_int(2, precision=2)
  let bound = fn(rounding) {
    let context = @bin_float.BinaryContext::new(precision~, rounding~)
    match infinity.try_atan_ctx(context) {
      Ok(result) => result.0.mul_ctx(two, exact).0
      Err(error) => abort(error.message)
    }
  }
  store_interval(
    bound(@bin_float.BinaryRoundingMode::RoundTowardNegative),
    bound(@bin_float.BinaryRoundingMode::RoundTowardPositive),
    precision,
  )
}

///|
fn pi_scaled_index_range(value : Interval) -> (SignedBinCoeff, SignedBinCoeff) {
  let lower = rat_mul_int(rat_from_finite_bin(value.lo_), 2)
  let upper = rat_mul_int(rat_from_finite_bin(value.hi_), 2)
  (rat_ceil(lower), rat_floor(upper))
}

///|
fn pi_scaled_endpoint_index(value : @bin_float.BinFloat) -> SignedBinCoeff? {
  let scaled = rat_mul_int(rat_from_finite_bin(value), 2)
  if coeff_compare(scaled.den, coeff_one()) == 0 {
    Some(scaled.num)
  } else {
    None
  }
}

///|
fn signed_index_is_odd(index : SignedBinCoeff) -> Bool {
  let residue = signed_coeff_mod4(index)
  residue == 1 || residue == 3
}

///|
fn first_odd_index_at_or_above(index : SignedBinCoeff) -> SignedBinCoeff {
  if signed_index_is_odd(index) {
    index
  } else {
    signed_coeff_add(index, signed_coeff_from_int(1))
  }
}

///|
pub fn Interval::rootn(self : Interval, degree : Int32) -> Interval {
  match self.try_rootn(degree) {
    Ok(result) => result
    Err(_) =>
      if degree == 0 {
        // degree 0 is outside the domain of Table 10.5 (q is a nonzero integer): no point, so the empty set
        Interval::empty(precision=self.precision_)
      } else if degree % 2 == 0 {
        store_interval(
          @bin_float.BinFloat::zero(precision=self.precision_),
          pos_inf(self.precision_),
          self.precision_,
        )
      } else {
        whole_real(self.precision_)
      }
  }
}

///|
pub fn Interval::hypot(self : Interval, other : Interval) -> Interval {
  match self.try_hypot(other) {
    Ok(result) => result
    Err(_) => self.sqr().add(other.sqr()).sqrt()
  }
}

///|
pub fn Interval::sinpi(self : Interval) -> Interval {
  match self.try_sinpi() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
pub fn Interval::cospi(self : Interval) -> Interval {
  match self.try_cospi() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
pub fn Interval::tanpi(self : Interval) -> Interval {
  match self.try_tanpi() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
pub fn Interval::try_exp2(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp2_ctx(context)
  })
}

///|
pub fn Interval::try_exp10(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp10_ctx(context)
  })
}

///|
pub fn Interval::try_log2(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  if self.hi_.compare(zero) <= 0 {
    return Ok(empty_interval(self.precision_))
  }
  let restricted = self.intersection(
    store_interval(zero, pos_inf(self.precision_), self.precision_),
  )
  restricted.try_certified_monotone(true, fn(value, context) {
    value.try_log2_ctx(context)
  })
}

///|
pub fn Interval::try_log10(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  if self.hi_.compare(zero) <= 0 {
    return Ok(empty_interval(self.precision_))
  }
  let restricted = self.intersection(
    store_interval(zero, pos_inf(self.precision_), self.precision_),
  )
  restricted.try_certified_monotone(true, fn(value, context) {
    value.try_log10_ctx(context)
  })
}

///|
pub fn Interval::try_rootn(
  self : Interval,
  degree : Int32,
) -> Result[Interval, @def.ArithmeticError] {
  guard degree != 0 else {
    return Err(
      @def.ArithmeticError::domain_error("rootn degree must not be zero"),
    )
  }
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  let evaluate = fn(
    value : @bin_float.BinFloat,
    context : @bin_float.BinaryContext,
  ) {
    value.try_rootn_ctx(degree, context)
  }
  if degree > 0 {
    if degree % 2 == 0 {
      if self.hi_.compare(zero) < 0 {
        return Ok(empty_interval(self.precision_))
      }
      let restricted = self.intersection(
        store_interval(zero, pos_inf(self.precision_), self.precision_),
      )
      return restricted.try_certified_monotone(true, evaluate)
    }
    return self.try_certified_monotone(true, evaluate)
  }
  if self.contains_zero() && degree % 2 != 0 {
    return Ok(whole_real(self.precision_))
  }
  if degree % 2 == 0 {
    if self.hi_.compare(zero) <= 0 {
      return Ok(empty_interval(self.precision_))
    }
    let restricted = self.intersection(
      store_interval(zero, pos_inf(self.precision_), self.precision_),
    )
    return restricted.try_certified_monotone(false, evaluate)
  }
  self.try_certified_monotone(false, evaluate)
}

///|
pub fn Interval::try_hypot(
  self : Interval,
  other : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return Ok(empty_interval(precision))
  }
  let left = self.abs()
  let right = other.abs()
  let downward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  left.lo_
  .try_hypot_ctx(right.lo_, downward)
  .bind(fn(lower) {
    left.hi_
    .try_hypot_ctx(right.hi_, upward)
    .map(fn(upper) { store_interval(lower.0, upper.0, precision) })
  })
}

///|
fn try_pow_point_bounds(
  base : @bin_float.BinFloat,
  exponent : @bin_float.BinFloat,
  precision : Int32,
) -> Result[(@bin_float.BinFloat, @bin_float.BinFloat), @def.ArithmeticError] {
  let base = canonical_interval_endpoint(base, precision)
  let downward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  base
  .try_pow_ctx(exponent, downward)
  .bind(fn(lower) {
    base.try_pow_ctx(exponent, upward).map(fn(upper) { (lower.0, upper.0) })
  })
}

///|
pub fn Interval::try_pow(
  self : Interval,
  exponent : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  let precision = Int32::max(self.precision_, exponent.precision_)
  if self.is_empty() || exponent.is_empty() {
    return Ok(empty_interval(precision))
  }
  let zero = @bin_float.BinFloat::zero(precision~)
  let one = @bin_float.BinFloat::one(precision~)
  let nonnegative = self.intersection(
    store_interval(zero, pos_inf(precision), precision),
  )
  if nonnegative.is_empty() {
    return Ok(empty_interval(precision))
  }
  if nonnegative.hi_.is_zero() {
    if exponent.hi_.sign() != Sign::Positive {
      return Ok(empty_interval(precision))
    }
    return Ok(zero_radius_interval(zero, precision))
  }
  try_pow_point_bounds(nonnegative.lo_, exponent.lo_, precision).bind(fn(
    lower_lower,
  ) {
    try_pow_point_bounds(nonnegative.lo_, exponent.hi_, precision).bind(fn(
      lower_upper,
    ) {
      try_pow_point_bounds(nonnegative.hi_, exponent.lo_, precision).bind(fn(
        upper_lower,
      ) {
        try_pow_point_bounds(nonnegative.hi_, exponent.hi_, precision).map(fn(
          upper_upper,
        ) {
          let mut lower = bin_min(
            bin_min(lower_lower.0, lower_upper.0),
            bin_min(upper_lower.0, upper_upper.0),
          )
          let mut upper = bin_max(
            bin_max(lower_lower.1, lower_upper.1),
            bin_max(upper_lower.1, upper_upper.1),
          )
          if nonnegative.contains_zero() {
            if exponent.hi_.sign() == Sign::Positive {
              lower = bin_min(lower, zero)
            }
            if exponent.lo_.sign() == Sign::Negative {
              upper = pos_inf(precision)
            }
          }
          if nonnegative.lo_.compare(one) <= 0 &&
            nonnegative.hi_.compare(one) >= 0 {
            lower = bin_min(lower, one)
            upper = bin_max(upper, one)
          }
          if exponent.lo_.sign() != Sign::Positive &&
            exponent.hi_.sign() != Sign::Negative {
            lower = bin_min(lower, one)
            upper = bin_max(upper, one)
          }
          store_interval(lower, upper, precision)
        })
      })
    })
  })
}

///|
pub fn Interval::try_sinpi(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  self.try_sine_like_hull(pi_scaled_index_range(self), 0, fn(value, context) {
    value.try_sinpi_ctx(context)
  })
}

///|
pub fn Interval::try_cospi(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  self.try_sine_like_hull(pi_scaled_index_range(self), 1, fn(value, context) {
    value.try_cospi_ctx(context)
  })
}

///|
pub fn Interval::try_tanpi(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(whole_real(self.precision_))
  }
  let indices = pi_scaled_index_range(self)
  let first_pole = first_odd_index_at_or_above(indices.0)
  let has_pole = signed_coeff_compare(first_pole, indices.1) <= 0
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  if !has_pole {
    return self.lo_
      .try_tanpi_ctx(downward)
      .bind(fn(lower) {
        self.hi_
        .try_tanpi_ctx(upward)
        .map(fn(upper) { store_interval(lower.0, upper.0, self.precision_) })
      })
  }
  let lower_index = pi_scaled_endpoint_index(self.lo_)
  let upper_index = pi_scaled_endpoint_index(self.hi_)
  let pole_at_lower = match lower_index {
    Some(index) => signed_coeff_compare(index, first_pole) == 0
    None => false
  }
  let pole_at_upper = match upper_index {
    Some(index) => signed_coeff_compare(index, first_pole) == 0
    None => false
  }
  if pole_at_lower && pole_at_upper {
    return Ok(empty_interval(self.precision_))
  }
  let next_pole = signed_coeff_add(first_pole, signed_coeff_from_int(2))
  if pole_at_lower && signed_coeff_compare(next_pole, indices.1) > 0 {
    return self.hi_
      .try_tanpi_ctx(upward)
      .map(fn(upper) {
        store_interval(neg_inf(self.precision_), upper.0, self.precision_)
      })
  }
  if pole_at_upper {
    return self.lo_
      .try_tanpi_ctx(downward)
      .map(fn(lower) {
        store_interval(lower.0, pos_inf(self.precision_), self.precision_)
      })
  }
  Ok(whole_real(self.precision_))
}

///|
/// Total: the `try_sinh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::sinh(self : Interval) -> Interval {
  match self.try_sinh() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// Total: the `try_cosh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::cosh(self : Interval) -> Interval {
  match self.try_cosh() {
    Ok(result) => result
    Err(_) =>
      store_interval(
        @bin_float.BinFloat::one(precision=self.precision_),
        pos_inf(self.precision_),
        self.precision_,
      )
  }
}

///|
/// Total: the `try_tanh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::tanh(self : Interval) -> Interval {
  match self.try_tanh() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
/// Total: the `try_asinh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::asinh(self : Interval) -> Interval {
  match self.try_asinh() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// Total: the `try_acosh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::acosh(self : Interval) -> Interval {
  match self.try_acosh() {
    Ok(result) => result
    Err(_) =>
      store_interval(
        @bin_float.BinFloat::zero(precision=self.precision_),
        pos_inf(self.precision_),
        self.precision_,
      )
  }
}

///|
/// Total: the `try_atanh` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::atanh(self : Interval) -> Interval {
  match self.try_atanh() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// `[-pi/2, pi/2]` as an enclosure that needs no kernel at the target precision:
/// pi is evaluated at no more than 64 bits and rounded outward.
fn half_pi_range(precision : Int32) -> Interval {
  let pi = pi_range(precision)
  let bound = pi.hi_.with_precision(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let half = Interval::exact(bound, precision~).div(
    Interval::from_int(2, precision~),
  )
  store_interval(half.hi_.neg(), half.hi_, precision)
}

///|
/// `[0, pi]` at `precision` bits, from a constant of at most 64 bits.
fn pi_range(precision : Int32) -> Interval {
  let pi = certified_pi_interval(Int32::min(precision, 64))
  store_interval(
    @bin_float.BinFloat::zero(precision~),
    pi.hi_.with_precision(
      precision,
      @bin_float.BinaryRoundingMode::RoundTowardPositive,
    ),
    precision,
  )
}
