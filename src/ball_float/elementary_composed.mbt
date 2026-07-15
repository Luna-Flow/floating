///|
fn certified_pi_interval(precision : Int) -> BallFloat {
  let (lower, upper) = certified_pi_rational(precision + 64)
  store_interval(
    rat_dyadic_bounds(lower, precision).0,
    rat_dyadic_bounds(upper, precision).1,
    precision,
  )
}

///|
fn BallFloat::try_pi_scaled_endpoint_bounds(
  self : BallFloat,
  evaluate : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> Result[
  (
    @bin_float.BinFloat,
    @bin_float.BinFloat,
    @bin_float.BinFloat,
    @bin_float.BinFloat,
  ),
  @def.ArithmeticError,
] {
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  evaluate(self.lo_, downward).bind(fn(lower_down) {
    evaluate(self.lo_, upward).bind(fn(lower_up) {
      evaluate(self.hi_, downward).bind(fn(upper_down) {
        evaluate(self.hi_, upward).map(fn(upper_up) {
          (lower_down.0, lower_up.0, upper_down.0, upper_up.0)
        })
      })
    })
  })
}

///|
fn pi_scaled_index_range(value : BallFloat) -> (SignedBinCoeff, SignedBinCoeff) {
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
pub fn BallFloat::rootn(self : BallFloat, degree : Int) -> BallFloat {
  if self.is_empty() || degree == 0 || degree == -2147483647 - 1 {
    return BallFloat::empty(precision=self.precision_)
  }
  if degree < 0 {
    return self.rootn(-degree).reciprocal()
  }
  if degree == 1 {
    return self
  }
  if degree == 2 {
    return self.sqrt_interval()
  }
  let exponent = BallFloat::from_int(1, precision=self.precision_).div(
    BallFloat::from_int(degree, precision=self.precision_),
  )
  if degree % 2 == 0 {
    return self.pow_interval(exponent)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  let nonnegative = self.intersection(
    store_interval(zero, pos_inf(self.precision_), self.precision_),
  )
  let nonpositive = self.intersection(
    store_interval(neg_inf(self.precision_), zero, self.precision_),
  )
  let positive_result = nonnegative.pow_interval(exponent)
  let negative_result = nonpositive.neg().pow_interval(exponent).neg()
  if positive_result.is_empty() {
    negative_result
  } else if negative_result.is_empty() {
    positive_result
  } else {
    negative_result.convex_hull(positive_result)
  }
}

///|
pub fn BallFloat::hypot(self : BallFloat, other : BallFloat) -> BallFloat {
  match self.try_hypot(other) {
    Ok(result) => result
    Err(_) => self.square().add(other.square()).sqrt_interval()
  }
}

///|
pub fn BallFloat::sinpi_interval(self : BallFloat) -> BallFloat {
  match self.try_sinpi_interval() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
pub fn BallFloat::cospi_interval(self : BallFloat) -> BallFloat {
  match self.try_cospi_interval() {
    Ok(result) => result
    Err(_) => unit_interval(self.precision_)
  }
}

///|
pub fn BallFloat::tanpi_interval(self : BallFloat) -> BallFloat {
  match self.try_tanpi_interval() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
pub fn BallFloat::try_exp2_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp2_ctx(context)
  })
}

///|
pub fn BallFloat::try_exp10_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp10_ctx(context)
  })
}

///|
pub fn BallFloat::try_log2_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
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
pub fn BallFloat::try_log10_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
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
pub fn BallFloat::try_rootn(
  self : BallFloat,
  degree : Int,
) -> Result[BallFloat, @def.ArithmeticError] {
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
pub fn BallFloat::try_hypot(
  self : BallFloat,
  other : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return Ok(empty_interval(precision))
  }
  let left = self.abs()
  let right = other.abs()
  let downward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    precision,
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
  precision : Int,
) -> Result[(@bin_float.BinFloat, @bin_float.BinFloat), @def.ArithmeticError] {
  let downward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  base
  .try_pow_ctx(exponent, downward)
  .bind(fn(lower) {
    base.try_pow_ctx(exponent, upward).map(fn(upper) { (lower.0, upper.0) })
  })
}

///|
pub fn BallFloat::try_pow_interval(
  self : BallFloat,
  exponent : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  let precision = Int::max(self.precision_, exponent.precision_)
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
pub fn BallFloat::try_sinpi_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  self
  .try_pi_scaled_endpoint_bounds(fn(value, context) {
    value.try_sinpi_ctx(context)
  })
  .map(fn(bounds) {
    let indices = pi_scaled_index_range(self)
    let lower = if index_range_contains_residue(indices.0, indices.1, 3) {
      @bin_float.BinFloat::from_int(-1, precision=self.precision_)
    } else {
      bin_min(bounds.0, bounds.2)
    }
    let upper = if index_range_contains_residue(indices.0, indices.1, 1) {
      @bin_float.BinFloat::one(precision=self.precision_)
    } else {
      bin_max(bounds.1, bounds.3)
    }
    store_interval(lower, upper, self.precision_)
  })
}

///|
pub fn BallFloat::try_cospi_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  self
  .try_pi_scaled_endpoint_bounds(fn(value, context) {
    value.try_cospi_ctx(context)
  })
  .map(fn(bounds) {
    let indices = pi_scaled_index_range(self)
    let lower = if index_range_contains_residue(indices.0, indices.1, 2) {
      @bin_float.BinFloat::from_int(-1, precision=self.precision_)
    } else {
      bin_min(bounds.0, bounds.2)
    }
    let upper = if index_range_contains_residue(indices.0, indices.1, 0) {
      @bin_float.BinFloat::one(precision=self.precision_)
    } else {
      bin_max(bounds.1, bounds.3)
    }
    store_interval(lower, upper, self.precision_)
  })
}

///|
pub fn BallFloat::try_tanpi_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(whole_real(self.precision_))
  }
  let indices = pi_scaled_index_range(self)
  let first_pole = first_odd_index_at_or_above(indices.0)
  let has_pole = signed_coeff_compare(first_pole, indices.1) <= 0
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
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
fn certified_sinh_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let point = BallFloat::exact(value, precision~)
  let two = BallFloat::from_int(2, precision~)
  point.exp_interval().sub(point.neg().exp_interval()).div(two)
}

///|
pub fn BallFloat::sinh_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let work = self.precision_ + 192
  let lower = if self.lo_.classify() == FpClass::Infinity {
    neg_inf(work)
  } else {
    certified_sinh_point(self.lo_, work).lo_
  }
  let upper = if self.hi_.classify() == FpClass::Infinity {
    pos_inf(work)
  } else {
    certified_sinh_point(self.hi_, work).hi_
  }
  quantize_interval(lower, upper, self.precision_)
}

///|
fn certified_cosh_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let point = BallFloat::exact(value, precision~)
  let two = BallFloat::from_int(2, precision~)
  point.exp_interval().add(point.neg().exp_interval()).div(two)
}

///|
pub fn BallFloat::cosh_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let work = self.precision_ + 192
  let lower = if self.contains_zero() {
    @bin_float.BinFloat::one(precision=work)
  } else if self.hi_.sign() == Sign::Negative {
    certified_cosh_point(self.hi_, work).lo_
  } else {
    certified_cosh_point(self.lo_, work).lo_
  }
  let outer_endpoint = if self.contains_zero() {
    if self.lo_.abs().compare(self.hi_.abs()) >= 0 {
      self.lo_
    } else {
      self.hi_
    }
  } else if self.hi_.sign() == Sign::Negative {
    self.lo_
  } else {
    self.hi_
  }
  let upper = if outer_endpoint.classify() == FpClass::Infinity {
    pos_inf(work)
  } else {
    certified_cosh_point(outer_endpoint, work).hi_
  }
  quantize_interval(lower, upper, self.precision_)
}

///|
fn certified_tanh_nonnegative_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let point = BallFloat::exact(value, precision~)
  let one = BallFloat::from_int(1, precision~)
  let two = BallFloat::from_int(2, precision~)
  let exponential = point.mul(two).exp_interval()
  exponential.sub(one).div(exponential.add(one))
}

///|
fn certified_tanh_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  if value.classify() == FpClass::Infinity {
    let limit = if value.sign() == Sign::Negative {
      @bin_float.BinFloat::from_int(-1, precision~)
    } else {
      @bin_float.BinFloat::one(precision~)
    }
    return store_interval(limit, limit, precision)
  }
  if value.sign() == Sign::Negative {
    certified_tanh_nonnegative_point(value.neg(), precision).neg()
  } else {
    certified_tanh_nonnegative_point(value, precision)
  }
}

///|
pub fn BallFloat::tanh_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let work = self.precision_ + 192
  let lower = certified_tanh_point(self.lo_, work)
  let upper = certified_tanh_point(self.hi_, work)
  quantize_interval(lower.lo_, upper.hi_, self.precision_).intersection(
    store_interval(
      @bin_float.BinFloat::from_int(-1, precision=self.precision_),
      @bin_float.BinFloat::one(precision=self.precision_),
      self.precision_,
    ),
  )
}

///|
fn certified_asinh_nonnegative(value : BallFloat) -> BallFloat {
  let one = BallFloat::from_int(1, precision=value.precision_)
  value.add(value.square().add(one).sqrt_interval()).ln_interval()
}

///|
pub fn BallFloat::asinh_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let work = self.precision_ + 192
  let evaluate = fn(endpoint : @bin_float.BinFloat) {
    if endpoint.sign() == Sign::Negative {
      certified_asinh_nonnegative(
        BallFloat::exact(endpoint.neg(), precision=work),
      ).neg()
    } else {
      certified_asinh_nonnegative(BallFloat::exact(endpoint, precision=work))
    }
  }
  let lower = if self.lo_.classify() == FpClass::Infinity {
    neg_inf(work)
  } else {
    evaluate(self.lo_).lo_
  }
  let upper = if self.hi_.classify() == FpClass::Infinity {
    pos_inf(work)
  } else {
    evaluate(self.hi_).hi_
  }
  quantize_interval(lower, upper, self.precision_)
}

///|
pub fn BallFloat::acosh_interval(self : BallFloat) -> BallFloat {
  let one = BallFloat::from_int(1, precision=self.precision_)
  let domain = self.intersection(
    store_interval(one.lo_, pos_inf(self.precision_), self.precision_),
  )
  if domain.is_empty() {
    return domain
  }
  let work = self.precision_ + 192
  let evaluate = fn(endpoint : @bin_float.BinFloat) {
    let point = BallFloat::exact(endpoint, precision=work)
    let work_one = BallFloat::from_int(1, precision=work)
    point.add(point.square().sub(work_one).sqrt_interval()).ln_interval()
  }
  let lower = evaluate(domain.lo_)
  let upper = if domain.hi_.classify() == FpClass::Infinity {
    pos_inf(work)
  } else {
    evaluate(domain.hi_).hi_
  }
  quantize_interval(lower.lo_, upper, self.precision_)
}

///|
pub fn BallFloat::atanh_interval(self : BallFloat) -> BallFloat {
  let one = BallFloat::from_int(1, precision=self.precision_)
  let minus_one = @bin_float.BinFloat::from_int(-1, precision=self.precision_)
  let domain = self.intersection(
    store_interval(minus_one, one.hi_, self.precision_),
  )
  if domain.is_empty() {
    return domain
  }
  let negative_endpoint = domain.lo_.compare(minus_one) == 0
  let positive_endpoint = domain.hi_.compare(one.hi_) == 0
  if domain.is_singleton() && (negative_endpoint || positive_endpoint) {
    return BallFloat::empty(precision=self.precision_)
  }
  let work = self.precision_ + 192
  let evaluate = fn(endpoint : @bin_float.BinFloat) {
    let point = BallFloat::exact(endpoint, precision=work)
    let work_one = BallFloat::from_int(1, precision=work)
    let two = BallFloat::from_int(2, precision=work)
    work_one.add(point).div(work_one.sub(point)).ln_interval().div(two)
  }
  let lower = if negative_endpoint {
    neg_inf(work)
  } else {
    evaluate(domain.lo_).lo_
  }
  let upper = if positive_endpoint {
    pos_inf(work)
  } else {
    evaluate(domain.hi_).hi_
  }
  quantize_interval(lower, upper, self.precision_)
}
