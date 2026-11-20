// Test-only copies of the pre-#378 interval basics (equivalence oracle).

///|
fn old_division_bounds(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let downward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  (
    numerator.div_ctx(denominator, downward).0,
    numerator.div_ctx(denominator, upward).0,
  )
}

///|
fn old_extended_division_bounds(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if numerator.is_zero() || denominator.classify() == FpClass::Infinity {
    let zero = @bin_float.BinFloat::zero(precision~)
    return (zero, zero)
  }
  if numerator.classify() == FpClass::Infinity {
    let sign = if numerator.sign() == denominator.sign() {
      Sign::Positive
    } else {
      Sign::Negative
    }
    let infinity = @bin_float.BinFloat::inf(sign, precision~)
    return (infinity, infinity)
  }
  old_division_bounds(numerator, denominator, precision)
}

///|
fn old_quotient_interval_nonzero_denominator(
  numerator : BallFloat,
  denominator : BallFloat,
  precision : Int32,
) -> BallFloat {
  let numerator_nonnegative = numerator.lo_.is_zero() ||
    numerator.lo_.sign() == Sign::Positive
  let numerator_nonpositive = numerator.hi_.is_zero() ||
    numerator.hi_.sign() == Sign::Negative
  let denominator_positive = denominator.lo_.sign() == Sign::Positive
  let lower = if denominator_positive {
    if numerator_nonnegative || numerator_nonpositive {
      old_extended_division_bounds(
        numerator.lo_,
        if numerator_nonnegative {
          denominator.hi_
        } else {
          denominator.lo_
        },
        precision,
      ).0
    } else {
      old_extended_division_bounds(numerator.lo_, denominator.lo_, precision).0
    }
  } else if numerator_nonnegative {
    old_extended_division_bounds(numerator.hi_, denominator.hi_, precision).0
  } else if numerator_nonpositive {
    old_extended_division_bounds(numerator.hi_, denominator.lo_, precision).0
  } else {
    old_extended_division_bounds(numerator.hi_, denominator.hi_, precision).0
  }
  let upper = if denominator_positive {
    if numerator_nonnegative {
      old_extended_division_bounds(numerator.hi_, denominator.lo_, precision).1
    } else if numerator_nonpositive {
      old_extended_division_bounds(numerator.hi_, denominator.hi_, precision).1
    } else {
      old_extended_division_bounds(numerator.hi_, denominator.lo_, precision).1
    }
  } else if numerator_nonnegative {
    old_extended_division_bounds(numerator.lo_, denominator.lo_, precision).1
  } else if numerator_nonpositive {
    old_extended_division_bounds(numerator.lo_, denominator.hi_, precision).1
  } else {
    old_extended_division_bounds(numerator.lo_, denominator.hi_, precision).1
  }
  quantize_interval(lower, upper, precision)
}

///|
fn old_multiplication_bounds(
  a : BallFloat,
  b : BallFloat,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if a.is_common_interval() && b.is_common_interval() {
    let a_nonnegative = a.lo_.is_zero() || a.lo_.sign() == Sign::Positive
    let a_nonpositive = a.hi_.is_zero() || a.hi_.sign() == Sign::Negative
    let b_nonnegative = b.lo_.is_zero() || b.lo_.sign() == Sign::Positive
    let b_nonpositive = b.hi_.is_zero() || b.hi_.sign() == Sign::Negative
    if a_nonnegative && b_nonnegative {
      return (
        extended_mul(a.lo_, b.lo_, precision, RoundingMode::TowardNegative),
        extended_mul(a.hi_, b.hi_, precision, RoundingMode::TowardPositive),
      )
    }
    if a_nonpositive && b_nonpositive {
      return (
        extended_mul(a.hi_, b.hi_, precision, RoundingMode::TowardNegative),
        extended_mul(a.lo_, b.lo_, precision, RoundingMode::TowardPositive),
      )
    }
    if a_nonnegative && b_nonpositive {
      return (
        extended_mul(a.hi_, b.lo_, precision, RoundingMode::TowardNegative),
        extended_mul(a.lo_, b.hi_, precision, RoundingMode::TowardPositive),
      )
    }
    if a_nonpositive && b_nonnegative {
      return (
        extended_mul(a.lo_, b.hi_, precision, RoundingMode::TowardNegative),
        extended_mul(a.hi_, b.lo_, precision, RoundingMode::TowardPositive),
      )
    }
    let lower_left = extended_mul(
      a.lo_,
      b.hi_,
      precision,
      RoundingMode::TowardNegative,
    )
    let lower_right = extended_mul(
      a.hi_,
      b.lo_,
      precision,
      RoundingMode::TowardNegative,
    )
    let upper_left = extended_mul(
      a.lo_,
      b.lo_,
      precision,
      RoundingMode::TowardPositive,
    )
    let upper_right = extended_mul(
      a.hi_,
      b.hi_,
      precision,
      RoundingMode::TowardPositive,
    )
    return (bin_min(lower_left, lower_right), bin_max(upper_left, upper_right))
  }
  let products = fn(mode) {
    (
      extended_mul(a.lo_, b.lo_, precision, mode),
      extended_mul(a.lo_, b.hi_, precision, mode),
      extended_mul(a.hi_, b.lo_, precision, mode),
      extended_mul(a.hi_, b.hi_, precision, mode),
    )
  }
  let (d1, d2, d3, d4) = products(RoundingMode::TowardNegative)
  let (u1, u2, u3, u4) = products(RoundingMode::TowardPositive)
  (
    bin_min(bin_min(d1, d2), bin_min(d3, d4)),
    bin_max(bin_max(u1, u2), bin_max(u3, u4)),
  )
}

///|
fn old_pown_positive(
  value : BallFloat,
  exponent : Int32,
  precision : Int32,
) -> BallFloat {
  let lo_power = pown_endpoint(
    value.lo_,
    exponent,
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let hi_power = pown_endpoint(
    value.hi_,
    exponent,
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  if pown_exponent_is_odd(exponent) {
    return quantize_interval(lo_power, hi_power, precision)
  }
  if value.contains_zero() {
    let lo_power_upper = pown_endpoint(
      value.lo_,
      exponent,
      precision,
      @bin_float.BinaryRoundingMode::RoundTowardPositive,
    )
    return quantize_interval(
      @bin_float.BinFloat::zero(precision~),
      bin_max(lo_power_upper, hi_power),
      precision,
    )
  }
  if value.hi_.sign() == Sign::Negative {
    quantize_interval(
      pown_endpoint(
        value.hi_,
        exponent,
        precision,
        @bin_float.BinaryRoundingMode::RoundTowardNegative,
      ),
      pown_endpoint(
        value.lo_,
        exponent,
        precision,
        @bin_float.BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  } else {
    quantize_interval(lo_power, hi_power, precision)
  }
}

///|
/// Directed square roots of a finite non-negative value at `precision` bits, the
/// former `@bin_float.sqrt_bounds_for_precision`.
fn old_sqrt_bounds(
  x : @bin_float.BinFloat,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let down = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::new(
    precision~,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  (x.sqrt_ctx(down).0, x.sqrt_ctx(up).0)
}

///|
fn BallFloat::old_sqrt_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if self.hi_.sign() == Sign::Negative {
    return empty_interval(self.precision_)
  }
  let lower = if self.lo_.sign() == Sign::Negative || self.lo_.is_zero() {
    @bin_float.BinFloat::zero(precision=self.precision_)
  } else {
    old_sqrt_bounds(self.lo_, self.precision_).0
  }
  let upper = if is_pos_inf(self.hi_) {
    pos_inf(self.precision_)
  } else {
    old_sqrt_bounds(self.hi_, self.precision_).1
  }
  quantize_interval(lower, upper, self.precision_)
}
