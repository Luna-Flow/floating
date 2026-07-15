///|
fn certified_atan_small_series(
  argument : CertifiedRat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  guard rat_sign(argument) >= 0 &&
    rat_compare(argument, rat_from_fraction_int(1, 2)) <= 0 else {
    abort("certified atan series requires 0 <= x <= 1/2")
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
  let argument_bounds = rat_dyadic_bounds(argument, precision)
  let squared_lower = directed_mul(
    argument_bounds.0,
    argument_bounds.0,
    downward,
  )
  let squared_upper = directed_mul(argument_bounds.1, argument_bounds.1, upward)
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  let mut term_lower = argument_bounds.0
  let mut term_upper = argument_bounds.1
  let mut sum_lower = @bin_float.BinFloat::zero(precision~)
  let mut sum_upper = sum_lower
  let mut denominator = 1
  let mut positive = true
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
    positive = !positive
    denominator = next_denominator
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
fn certified_atan_rational_with_pi(
  argument : CertifiedRat,
  work_bits : Int,
  pi_lower : CertifiedRat,
  pi_upper : CertifiedRat,
) -> (CertifiedRat, CertifiedRat) {
  if rat_sign(argument) < 0 {
    let (lower, upper) = certified_atan_rational_with_pi(
      rat_neg(argument),
      work_bits,
      pi_lower,
      pi_upper,
    )
    return (rat_neg(upper), rat_neg(lower))
  }
  if rat_is_zero(argument) {
    let zero = rat_from_int(0)
    return (zero, zero)
  }
  let one = rat_from_int(1)
  if rat_compare(argument, one) > 0 {
    let (inverse_lower, inverse_upper) = certified_atan_rational_with_pi(
      rat_div(one, argument),
      work_bits,
      pi_lower,
      pi_upper,
    )
    return (
      rat_sub(rat_div_int(pi_lower, 2), inverse_upper),
      rat_sub(rat_div_int(pi_upper, 2), inverse_lower),
    )
  }
  if rat_compare(argument, rat_from_fraction_int(1, 2)) >= 0 {
    let reduced = rat_div(rat_sub(argument, one), rat_add(argument, one))
    let (reduced_lower, reduced_upper) = certified_atan_rational_with_pi(
      reduced, work_bits, pi_lower, pi_upper,
    )
    return (
      rat_add(rat_div_int(pi_lower, 4), reduced_lower),
      rat_add(rat_div_int(pi_upper, 4), reduced_upper),
    )
  }
  certified_atan_small_series(argument, work_bits)
}

///|
fn certified_atan_endpoint(
  value : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if value.classify() == FpClass::Infinity {
    let (pi_lower, pi_upper) = certified_pi_rational(precision + 80)
    let lower = rat_div_int(pi_lower, 2)
    let upper = rat_div_int(pi_upper, 2)
    return if value.sign() == Sign::Negative {
      (
        rat_dyadic_bounds(rat_neg(upper), precision).0,
        rat_dyadic_bounds(rat_neg(lower), precision).1,
      )
    } else {
      (
        rat_dyadic_bounds(lower, precision).0,
        rat_dyadic_bounds(upper, precision).1,
      )
    }
  }
  let mut budget = certified_refinement_budget(precision + 64)
  while budget.available() {
    let (pi_lower, pi_upper) = certified_pi_rational(budget.precision() + 16)
    let (lower, upper) = certified_atan_rational_with_pi(
      rat_from_finite_bin(value),
      budget.precision(),
      pi_lower,
      pi_upper,
    )
    match unique_directed_bounds(lower, upper, precision) {
      Some(bounds) => return bounds
      None => budget = budget.next()
    }
  }
  let half_pi = certified_pi_interval(precision).div(
    BallFloat::from_int(2, precision~),
  )
  if value.sign() == Sign::Negative {
    (half_pi.hi_.neg(), @bin_float.BinFloat::zero(precision~))
  } else {
    (@bin_float.BinFloat::zero(precision~), half_pi.hi_)
  }
}

///|
pub fn BallFloat::atan_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let lower = certified_atan_endpoint(self.lo_, self.precision_)
  let upper = certified_atan_endpoint(self.hi_, self.precision_)
  store_interval(lower.0, upper.1, self.precision_)
}

///|
fn certified_asin_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let one_bin = @bin_float.BinFloat::one(precision~)
  let minus_one_bin = one_bin.neg()
  if value.compare(one_bin) == 0 || value.compare(minus_one_bin) == 0 {
    let half_pi = certified_pi_interval(precision).div(
      BallFloat::from_int(2, precision~),
    )
    return if value.sign() == Sign::Negative { half_pi.neg() } else { half_pi }
  }
  let point = BallFloat::exact(value, precision~)
  let one = BallFloat::from_int(1, precision~)
  point.div(one.sub(point.square()).sqrt_interval()).atan_interval()
}

///|
pub fn BallFloat::asin_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let one = @bin_float.BinFloat::one(precision=self.precision_)
  let domain = self.intersection(
    store_interval(one.neg(), one, self.precision_),
  )
  if domain.is_empty() {
    return domain
  }
  let work = self.precision_ + 64
  let lower = certified_asin_point(domain.lo_, work)
  let upper = certified_asin_point(domain.hi_, work)
  quantize_interval(lower.lo_, upper.hi_, self.precision_)
}

///|
fn certified_acos_point(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let one_bin = @bin_float.BinFloat::one(precision~)
  if value.compare(one_bin) == 0 {
    return BallFloat::from_int(0, precision~)
  }
  if value.compare(one_bin.neg()) == 0 {
    return certified_pi_interval(precision)
  }
  let half_pi = certified_pi_interval(precision).div(
    BallFloat::from_int(2, precision~),
  )
  if value.is_zero() {
    return half_pi
  }
  half_pi.sub(certified_asin_point(value, precision))
}

///|
pub fn BallFloat::acos_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let one = @bin_float.BinFloat::one(precision=self.precision_)
  let domain = self.intersection(
    store_interval(one.neg(), one, self.precision_),
  )
  if domain.is_empty() {
    return domain
  }
  let work = self.precision_ + 64
  let lower = certified_acos_point(domain.hi_, work)
  let upper = certified_acos_point(domain.lo_, work)
  quantize_interval(lower.lo_, upper.hi_, self.precision_)
}

///|
fn include_angle_hull(current : BallFloat, candidate : BallFloat) -> BallFloat {
  if candidate.is_empty() {
    current
  } else if current.is_empty() {
    candidate
  } else {
    current.convex_hull(candidate)
  }
}

///|
pub fn BallFloat::atan2_interval(
  self : BallFloat,
  abscissa : BallFloat,
) -> BallFloat {
  let precision = Int::max(self.precision_, abscissa.precision_)
  match self.try_atan2_interval(abscissa) {
    Ok(result) => result
    Err(_) => {
      let pi = certified_pi_interval(precision)
      store_interval(pi.hi_.neg(), pi.hi_, precision)
    }
  }
}
