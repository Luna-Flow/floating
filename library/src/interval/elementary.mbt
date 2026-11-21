///|
// Exact rational arithmetic used only by certified elementary-function kernels.
priv struct CertifiedRat {
  num : SignedBinCoeff
  den : @bin_float.BinCoeff
}

///|
fn certified_rat_coeff(
  num : SignedBinCoeff,
  den : @bin_float.BinCoeff,
) -> CertifiedRat {
  guard !coeff_is_zero(den) else {
    abort("certified rational denominator must be non-zero")
  }
  if signed_coeff_is_zero(num) {
    return { num, den: coeff_one(), }
  }
  let divisor = coeff_gcd(signed_coeff_magnitude(num), den)
  {
    num: signed_coeff_div_exact(num, divisor),
    den: coeff_div_exact(den, divisor),
  }
}

///|
fn rat_from_int(value : Int32) -> CertifiedRat {
  { num: signed_coeff_from_int(value), den: coeff_one(), }
}

///|
fn rat_sign(value : CertifiedRat) -> Int32 {
  signed_coeff_sign(value.num)
}

///|
fn rat_mul(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  let left_cross = coeff_gcd(signed_coeff_magnitude(left.num), right.den)
  let right_cross = coeff_gcd(signed_coeff_magnitude(right.num), left.den)
  {
    num: signed_coeff_mul(
      signed_coeff_div_exact(left.num, left_cross),
      signed_coeff_div_exact(right.num, right_cross),
    ),
    den: coeff_mul(
      coeff_div_exact(left.den, right_cross),
      coeff_div_exact(right.den, left_cross),
    ),
  }
}

///|
fn rat_mul_int(value : CertifiedRat, multiplier : Int32) -> CertifiedRat {
  rat_mul(value, rat_from_int(multiplier))
}

///|
fn rat_div(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  guard !signed_coeff_is_zero(right.num) else {
    abort("certified rational division by zero")
  }
  let numerator_cross = coeff_gcd(
    signed_coeff_magnitude(left.num),
    signed_coeff_magnitude(right.num),
  )
  let denominator_cross = coeff_gcd(left.den, right.den)
  let numerator = signed_coeff_mul_magnitude(
    signed_coeff_div_exact(left.num, numerator_cross),
    coeff_div_exact(right.den, denominator_cross),
  )
  let numerator = if signed_coeff_sign(right.num) < 0 {
    signed_coeff_neg(numerator)
  } else {
    numerator
  }
  {
    num: numerator,
    den: coeff_mul(
      coeff_div_exact(left.den, denominator_cross),
      coeff_div_exact(signed_coeff_magnitude(right.num), numerator_cross),
    ),
  }
}

///|
fn rat_from_finite_bin(value : @bin_float.BinFloat) -> CertifiedRat {
  guard value.classify() == FpClass::Finite else {
    abort("certified rational conversion requires a finite value")
  }
  if value.exponent2() >= 0 {
    certified_rat_coeff(
      signed_coeff_from_parts(
        value.sign() == Sign::Negative,
        coeff_shift_left(value.coefficient(), value.exponent2()),
      ),
      coeff_one(),
    )
  } else {
    certified_rat_coeff(
      signed_coeff_from_parts(value.is_negative(), value.coefficient()),
      coeff_shift_left(coeff_one(), -value.exponent2()),
    )
  }
}

///|
/// Total: the `try_exp` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::exp(self : Interval) -> Interval {
  match self.try_exp() {
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
/// Total: the `try_exp2` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::exp2(self : Interval) -> Interval {
  match self.try_exp2() {
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
/// Total: the `try_exp10` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::exp10(self : Interval) -> Interval {
  match self.try_exp10() {
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
/// Certified interval for exp(x) - 1.
pub fn Interval::expm1(self : Interval) -> Interval {
  match self.try_expm1() {
    Ok(result) => result
    Err(_) =>
      store_interval(
        @bin_float.BinFloat::from_int(-1, precision=self.precision_),
        pos_inf(self.precision_),
        self.precision_,
      )
  }
}

///|
/// Total: the `try_ln` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::ln(self : Interval) -> Interval {
  match self.try_ln() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// Total: the `try_log2` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::log2(self : Interval) -> Interval {
  match self.try_log2() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// Total: the `try_log10` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn Interval::log10(self : Interval) -> Interval {
  match self.try_log10() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
/// Certified interval for ln(1 + x).
pub fn Interval::log1p(self : Interval) -> Interval {
  match self.try_log1p() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
fn interval_range_resource_failure(
  operation : String,
  precision : Int32,
  required_work_precision : Int32,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation,
      @def.CertificationStage::RangeReduction,
      @def.CertificationFailureReason::ResourceLimit,
      precision,
      required_work_precision,
      0,
    ),
  )
}

///|
pub fn Interval::try_exp(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  // A point interval: one certified enclosure gives both directed ends.
  if !self.is_empty() && self.lo_.compare(self.hi_) == 0 {
    return self.lo_
      .try_exp_directed_pair(self.precision_)
      .map(fn(pair) { store_interval(pair.0, pair.1, self.precision_) })
  }
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
pub fn Interval::try_expm1(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lower = if is_neg_inf(self.lo_) {
    Ok(@bin_float.BinFloat::from_int(-1, precision=self.precision_))
  } else {
    self.lo_.try_expm1_ctx(downward).map(fn(result) { result.0 })
  }
  let upper = if is_pos_inf(self.hi_) {
    Ok(pos_inf(self.precision_))
  } else {
    self.hi_.try_expm1_ctx(upward).map(fn(result) { result.0 })
  }
  lower.bind(fn(lower_bound) {
    upper.map(fn(upper_bound) {
      store_interval(lower_bound, upper_bound, self.precision_)
    })
  })
}

///|
pub fn Interval::try_ln(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  if self.hi_.compare(zero) <= 0 {
    return Ok(empty_interval(self.precision_))
  }
  // A point interval of a positive value: one certified enclosure gives both ends.
  if self.lo_.compare(self.hi_) == 0 {
    return self.lo_
      .try_ln_directed_pair(self.precision_)
      .map(fn(pair) { store_interval(pair.0, pair.1, self.precision_) })
  }
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let upper = self.hi_.try_ln_ctx(upward)
  if self.lo_.compare(zero) <= 0 {
    return upper.map(fn(result) {
      store_interval(neg_inf(self.precision_), result.0, self.precision_)
    })
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  self.lo_
  .try_ln_ctx(downward)
  .bind(fn(lower) {
    upper.map(fn(upper_result) {
      store_interval(lower.0, upper_result.0, self.precision_)
    })
  })
}

///|
pub fn Interval::try_log1p(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let minus_one = @bin_float.BinFloat::from_int(-1, precision=self.precision_)
  if self.hi_.compare(minus_one) < 0 {
    return Ok(empty_interval(self.precision_))
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lower = if self.lo_.compare(minus_one) <= 0 {
    Ok(neg_inf(self.precision_))
  } else {
    self.lo_.try_log1p_ctx(downward).map(fn(result) { result.0 })
  }
  let upper = if is_pos_inf(self.hi_) {
    Ok(pos_inf(self.precision_))
  } else {
    self.hi_.try_log1p_ctx(upward).map(fn(result) { result.0 })
  }
  lower.bind(fn(lower_bound) {
    upper.map(fn(upper_bound) {
      store_interval(lower_bound, upper_bound, self.precision_)
    })
  })
}

///|
/// `sin`, `cos` or `tan` of an interval that is one nonzero point: no critical
/// point or pole lies inside it (the point is a dyadic rational, `pi` is
/// irrational), so the enclosure is the directed evaluations at the point. This
/// skips the rational critical-index computation, which costs about as much as
/// the evaluation itself for an argument of millions of bits.
fn Interval::try_trig_point_interval(
  self : Interval,
  evaluate : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> Result[Interval, @def.ArithmeticError]? {
  if self.lo_.is_zero() || self.lo_.compare(self.hi_) != 0 {
    return None
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  Some(
    evaluate(self.lo_, downward).bind(fn(lower) {
      evaluate(self.lo_, upward).map(fn(upper) {
        store_interval(lower.0, upper.0, self.precision_)
      })
    }),
  )
}

///|
pub fn Interval::try_sin(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_work_limit_exceeded(self) else {
    return Err(
      interval_range_resource_failure("sin", self.precision_, initial_work),
    )
  }
  if self.try_trig_point_interval(fn(value, context) {
      value.try_sin_ctx(context)
    })
    is Some(result) {
    return result.map(Interval::with_canonical_zero_endpoints)
  }
  self
  .try_sine_like_hull(trig_critical_indices(self), 0, fn(value, context) {
    value.try_sin_ctx(context)
  })
  .map(Interval::with_canonical_zero_endpoints)
}

///|
pub fn Interval::try_cos(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_work_limit_exceeded(self) else {
    return Err(
      interval_range_resource_failure("cos", self.precision_, initial_work),
    )
  }
  if self.try_trig_point_interval(fn(value, context) {
      value.try_cos_ctx(context)
    })
    is Some(result) {
    return result.map(Interval::with_canonical_zero_endpoints)
  }
  self
  .try_sine_like_hull(trig_critical_indices(self), 1, fn(value, context) {
    value.try_cos_ctx(context)
  })
  .map(Interval::with_canonical_zero_endpoints)
}

///|
pub fn Interval::try_tan(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(whole_real(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_work_limit_exceeded(self) else {
    return Err(
      interval_range_resource_failure("tan", self.precision_, initial_work),
    )
  }
  // A pole `pi/2 + k pi` (odd quarter-turn index) inside the interval makes
  // the hull the whole line; otherwise tangent is increasing on the arc.
  // A point (a nonzero dyadic rational) is no pole: the rational index
  // computation is skipped, as for sin and cos.
  let is_point = !self.lo_.is_zero() && self.lo_.compare(self.hi_) == 0
  if !is_point {
    let indices = trig_critical_indices(self)
    if index_range_contains_residue(indices.0, indices.1, 1) ||
      index_range_contains_residue(indices.0, indices.1, 3) {
      return Ok(whole_real(self.precision_))
    }
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  self.lo_
  .try_tan_ctx(downward)
  .bind(fn(lower) {
    self.hi_
    .try_tan_ctx(upward)
    .map(fn(upper) {
      store_interval(
        canonical_interval_endpoint(lower.0, self.precision_),
        canonical_interval_endpoint(upper.0, self.precision_),
        self.precision_,
      )
    })
  })
}

///|
