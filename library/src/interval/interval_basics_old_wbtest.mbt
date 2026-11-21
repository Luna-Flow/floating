// Test-only copies of the pre-#378 interval basics (equivalence oracle).

///|
fn old_division_bounds(
  numerator : @binary.Binary,
  denominator : @binary.Binary,
  precision : Int32,
) -> (@binary.Binary, @binary.Binary) {
  let downward = @binary.BinaryContext::new(
    precision~,
    rounding=@binary.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @binary.BinaryContext::new(
    precision~,
    rounding=@binary.BinaryRoundingMode::RoundTowardPositive,
  )
  (
    numerator.div_ctx(denominator, downward).0,
    numerator.div_ctx(denominator, upward).0,
  )
}

///|
fn old_extended_division_bounds(
  numerator : @binary.Binary,
  denominator : @binary.Binary,
  precision : Int32,
) -> (@binary.Binary, @binary.Binary) {
  if numerator.is_zero() || denominator.classify() == FpClass::Infinity {
    let zero = @binary.Binary::zero(precision~)
    return (zero, zero)
  }
  if numerator.classify() == FpClass::Infinity {
    let negative = numerator.sign() != denominator.sign()
    let infinity = @binary.Binary::inf(negative~, precision~)
    return (infinity, infinity)
  }
  old_division_bounds(numerator, denominator, precision)
}

///|
fn old_quotient_interval_nonzero_denominator(
  numerator : Interval,
  denominator : Interval,
  precision : Int32,
) -> Interval {
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
  store_interval(lower, upper, precision)
}

///|
fn old_multiplication_bounds(
  a : Interval,
  b : Interval,
  precision : Int32,
) -> (@binary.Binary, @binary.Binary) {
  if a.is_common_interval() && b.is_common_interval() {
    let a_nonnegative = a.lo_.is_zero() || a.lo_.sign() == Sign::Positive
    let a_nonpositive = a.hi_.is_zero() || a.hi_.sign() == Sign::Negative
    let b_nonnegative = b.lo_.is_zero() || b.lo_.sign() == Sign::Positive
    let b_nonpositive = b.hi_.is_zero() || b.hi_.sign() == Sign::Negative
    if a_nonnegative && b_nonnegative {
      return (
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonpositive && b_nonpositive {
      return (
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonnegative && b_nonpositive {
      return (
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonpositive && b_nonnegative {
      return (
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    let lower_left = extended_mul(
      a.lo_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
    let lower_right = extended_mul(
      a.hi_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
    let upper_left = extended_mul(
      a.lo_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    )
    let upper_right = extended_mul(
      a.hi_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
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
  let (d1, d2, d3, d4) = products(BinaryRoundingMode::RoundTowardNegative)
  let (u1, u2, u3, u4) = products(BinaryRoundingMode::RoundTowardPositive)
  (
    bin_min(bin_min(d1, d2), bin_min(d3, d4)),
    bin_max(bin_max(u1, u2), bin_max(u3, u4)),
  )
}

///|
fn old_pown_positive(
  value : Interval,
  exponent : Int32,
  precision : Int32,
) -> Interval {
  let lo_power = pown_endpoint(
    value.lo_,
    exponent,
    precision,
    @binary.BinaryRoundingMode::RoundTowardNegative,
  )
  let hi_power = pown_endpoint(
    value.hi_,
    exponent,
    precision,
    @binary.BinaryRoundingMode::RoundTowardPositive,
  )
  if pown_exponent_is_odd(exponent) {
    return store_interval(lo_power, hi_power, precision)
  }
  if value.contains_zero() {
    let lo_power_upper = pown_endpoint(
      value.lo_,
      exponent,
      precision,
      @binary.BinaryRoundingMode::RoundTowardPositive,
    )
    return store_interval(
      @binary.Binary::zero(precision~),
      bin_max(lo_power_upper, hi_power),
      precision,
    )
  }
  if value.hi_.sign() == Sign::Negative {
    store_interval(
      pown_endpoint(
        value.hi_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardNegative,
      ),
      pown_endpoint(
        value.lo_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  } else {
    store_interval(lo_power, hi_power, precision)
  }
}
