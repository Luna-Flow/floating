///|
fn binary_certification_failure(
  operation : String,
  stage : @def.CertificationStage,
  reason : @def.CertificationFailureReason,
  target_precision : Int,
  work_precision : Int,
  refinements : Int,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation, stage, reason, target_precision, work_precision, refinements,
    ),
  )
}

///|
fn binary_refinement_failure_for(
  operation : String,
  context : BinaryContext,
  budget : CertifiedRefinementBudget,
) -> @def.ArithmeticError {
  @internal.certified_failure(
    operation,
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    context.precision,
    budget,
  )
}

///|
fn binary_refinement_failure_state(
  operation : String,
  context : BinaryContext,
  work_precision : Int,
  refinements : Int,
) -> @def.ArithmeticError {
  binary_certification_failure(
    operation,
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    context.precision,
    work_precision,
    refinements,
  )
}

///|
fn binary_range_failure_state(
  operation : String,
  context : BinaryContext,
  work_precision : Int,
  refinements : Int,
) -> @def.ArithmeticError {
  binary_certification_failure(
    operation,
    @def.CertificationStage::RangeReduction,
    @def.CertificationFailureReason::RangeNotCertified,
    context.precision,
    work_precision,
    refinements,
  )
}

///|
fn binary_certified_target_rounding(
  lower : BinFloat,
  upper : BinFloat,
  context : BinaryContext,
) -> (BinFloat, Bool, BinaryFlags) {
  let (lower_value, lower_flags) = lower.round_ctx(context)
  let (upper_value, upper_flags) = upper.round_ctx(context)
  (
    lower_value,
    lower_value == upper_value && lower_flags == upper_flags,
    if lower_flags == upper_flags {
      lower_flags
    } else {
      lower_flags.combine(upper_flags)
    },
  )
}

///|
fn binary_exp_small_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower = value.with_precision(work_precision, RoundingMode::TowardNegative)
  let upper = value.with_precision(work_precision, RoundingMode::TowardPositive)
  let eighth = BinFloat::make(BinCoeff::one(), -3, work_precision)
  guard lower.compare(eighth.neg()) >= 0 && upper.compare(eighth) <= 0 else {
    return None
  }
  if upper.sign() == Sign::Negative {
    match binary_exp_small_bounds(lower.neg(), work_precision) {
      Some(positive) =>
        Some(
          (
            BinFloat::one(precision=work_precision).div_ctx(
              positive.1,
              downward,
            ).0,
            BinFloat::one(precision=work_precision).div_ctx(positive.0, upward).0,
          ),
        )
      None => None
    }
  } else {
    let one = BinFloat::one(precision=work_precision)
    let mut term_lower = one
    let mut term_upper = one
    let mut sum_lower = one
    let mut sum_upper = one
    let threshold = BinFloat::make(
      BinCoeff::one(),
      -(work_precision + 8),
      work_precision,
    )
    let mut index = 0
    while index < 10000 {
      index += 1
      let index_value = BinFloat::from_int(index, precision=work_precision)
      term_lower = term_lower.mul_ctx(lower, downward).0.div_ctx(
          index_value, downward,
        ).0
      term_upper = term_upper.mul_ctx(upper, upward).0.div_ctx(
          index_value, upward,
        ).0
      sum_lower = sum_lower.add_ctx(term_lower, downward).0
      sum_upper = sum_upper.add_ctx(term_upper, upward).0
      if term_upper.compare(threshold) < 0 {
        let tail = term_upper.mul_ctx(
            BinFloat::from_int(2, precision=work_precision),
            upward,
          ).0
        return Some((sum_lower, sum_upper.add_ctx(tail, upward).0))
      }
    }
    None
  }
}

///|
fn binary_exp_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let mut lower = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let mut upper = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let eighth = BinFloat::make(BinCoeff::one(), -3, work_precision)
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  let mut reductions = 0
  while (lower.compare(eighth.neg()) < 0 || upper.compare(eighth) > 0) &&
        reductions < 4096 {
    lower = lower.mul_ctx(half, downward).0
    upper = upper.mul_ctx(half, upward).0
    reductions += 1
  }
  guard lower.compare(eighth.neg()) >= 0 && upper.compare(eighth) <= 0 else {
    return None
  }
  match
    (
      binary_exp_small_bounds(lower, work_precision),
      binary_exp_small_bounds(upper, work_precision),
    ) {
    (Some(lower_bounds), Some(upper_bounds)) => {
      let mut result_lower = lower_bounds.0
      let mut result_upper = upper_bounds.1
      for _ in 0..<reductions {
        result_lower = result_lower.mul_ctx(result_lower, downward).0
        result_upper = result_upper.mul_ctx(result_upper, upward).0
      }
      Some((result_lower, result_upper))
    }
    _ => None
  }
}

///|
fn binary_ln_unit_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let two = BinFloat::from_int(2, precision=work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  guard lower_value.compare(one) >= 0 && upper_value.compare(two) <= 0 else {
    return None
  }
  let z_lower = lower_value.sub_ctx(one, downward).0.div_ctx(
      upper_value.add_ctx(one, upward).0,
      downward,
    ).0
  let z_upper = upper_value.sub_ctx(one, upward).0.div_ctx(
      lower_value.add_ctx(one, downward).0,
      upward,
    ).0
  let square_lower = z_lower.mul_ctx(z_lower, downward).0
  let square_upper = z_upper.mul_ctx(z_upper, upward).0
  let mut term_lower = z_lower
  let mut term_upper = z_upper
  let mut sum_lower = BinFloat::zero(precision=work_precision)
  let mut sum_upper = sum_lower
  let mut denominator = 1
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 8),
    work_precision,
  )
  while denominator < 20000 {
    let denominator_value = BinFloat::from_int(
      denominator,
      precision=work_precision,
    )
    let piece_lower = term_lower.div_ctx(denominator_value, downward).0
    let piece_upper = term_upper.div_ctx(denominator_value, upward).0
    sum_lower = sum_lower.add_ctx(piece_lower, downward).0
    sum_upper = sum_upper.add_ctx(piece_upper, upward).0
    denominator += 2
    term_lower = term_lower.mul_ctx(square_lower, downward).0
    term_upper = term_upper.mul_ctx(square_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let first_omitted = term_upper.div_ctx(
          BinFloat::from_int(denominator, precision=work_precision),
          upward,
        ).0
      let geometric_denominator = one.sub_ctx(square_upper, downward).0
      let tail = first_omitted.div_ctx(geometric_denominator, upward).0.mul_ctx(
          two, upward,
        ).0
      let lower = sum_lower.mul_ctx(two, downward).0
      let upper = sum_upper.mul_ctx(two, upward).0
      return Some((lower, upper.add_ctx(tail, upward).0))
    }
  }
  None
}

///|
fn binary_ln10_bounds(work_precision : Int) -> (BinFloat, BinFloat)? {
  let two = BinFloat::from_int(2, precision=work_precision)
  let five_quarters = BinFloat::make(
    BinCoeff::from_uint64(5UL),
    -2,
    work_precision,
  )
  match
    (
      binary_ln_unit_bounds(two, work_precision),
      binary_ln_unit_bounds(five_quarters, work_precision),
    ) {
    (Some(two_bounds), Some(part_bounds)) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let three = BinFloat::from_int(3, precision=work_precision)
      Some(
        (
          part_bounds.0.add_ctx(
            two_bounds.0.mul_ctx(three, downward).0,
            downward,
          ).0,
          part_bounds.1.add_ctx(two_bounds.1.mul_ctx(three, upward).0, upward).0,
        ),
      )
    }
    _ => None
  }
}

///|
fn binary_ln_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && value.sign() == Sign::Positive else {
    return None
  }
  let coefficient_bits = value.coefficient().bit_length()
  let normalized = BinFloat::make(
    value.coefficient(),
    -(coefficient_bits - 1),
    Int::max(work_precision, coefficient_bits),
  )
  match
    (
      binary_ln_unit_bounds(normalized, work_precision),
      binary_ln_unit_bounds(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
    ) {
    (Some(unit), Some(ln2)) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let exponent = value.exponent2() + coefficient_bits - 1
      let exponent_value = BinFloat::from_int(
        exponent,
        precision=work_precision,
      )
      if exponent >= 0 {
        Some(
          (
            unit.0.add_ctx(ln2.0.mul_ctx(exponent_value, downward).0, downward).0,
            unit.1.add_ctx(ln2.1.mul_ctx(exponent_value, upward).0, upward).0,
          ),
        )
      } else {
        let magnitude = exponent_value.neg()
        Some(
          (
            unit.0.sub_ctx(ln2.1.mul_ctx(magnitude, upward).0, downward).0,
            unit.1.sub_ctx(ln2.0.mul_ctx(magnitude, downward).0, upward).0,
          ),
        )
      }
    }
    _ => None
  }
}

///|
fn binary_product_bounds(
  left : (BinFloat, BinFloat),
  right : (BinFloat, BinFloat),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (BinFloat, BinFloat) {
  let lower_candidates = [
    left.0.mul_ctx(right.0, downward).0,
    left.0.mul_ctx(right.1, downward).0,
    left.1.mul_ctx(right.0, downward).0,
    left.1.mul_ctx(right.1, downward).0,
  ]
  let upper_candidates = [
    left.0.mul_ctx(right.0, upward).0,
    left.0.mul_ctx(right.1, upward).0,
    left.1.mul_ctx(right.0, upward).0,
    left.1.mul_ctx(right.1, upward).0,
  ]
  let mut lower = lower_candidates[0]
  let mut upper = upper_candidates[0]
  for candidate in lower_candidates[1:] {
    if candidate.compare(lower) < 0 {
      lower = candidate
    }
  }
  for candidate in upper_candidates[1:] {
    if candidate.compare(upper) > 0 {
      upper = candidate
    }
  }
  (lower, upper)
}

///|
fn binary_quotient_bounds(
  numerator : (BinFloat, BinFloat),
  denominator : (BinFloat, BinFloat),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (BinFloat, BinFloat)? {
  guard denominator.0.compare(BinFloat::zero()) > 0 else { return None }
  let lower_candidates = [
    numerator.0.div_ctx(denominator.0, downward).0,
    numerator.0.div_ctx(denominator.1, downward).0,
    numerator.1.div_ctx(denominator.0, downward).0,
    numerator.1.div_ctx(denominator.1, downward).0,
  ]
  let upper_candidates = [
    numerator.0.div_ctx(denominator.0, upward).0,
    numerator.0.div_ctx(denominator.1, upward).0,
    numerator.1.div_ctx(denominator.0, upward).0,
    numerator.1.div_ctx(denominator.1, upward).0,
  ]
  let mut lower = lower_candidates[0]
  let mut upper = upper_candidates[0]
  for candidate in lower_candidates[1:] {
    if candidate.compare(lower) < 0 {
      lower = candidate
    }
  }
  for candidate in upper_candidates[1:] {
    if candidate.compare(upper) > 0 {
      upper = candidate
    }
  }
  Some((lower, upper))
}

///|
fn binary_expm1_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let two = BinFloat::from_int(2, precision=work_precision)
  let eighth = BinFloat::make(BinCoeff::one(), -3, work_precision)
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  let mut lower = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let mut upper = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let negative = upper.compare(BinFloat::zero()) < 0
  if negative {
    match binary_expm1_bounds(value.neg(), work_precision) {
      Some(positive) => {
        let lower_ratio = positive.1.div_ctx(
            one.add_ctx(positive.1, downward).0,
            upward,
          ).0
        let upper_ratio = positive.0.div_ctx(
            one.add_ctx(positive.0, upward).0,
            downward,
          ).0
        return Some((lower_ratio.neg(), upper_ratio.neg()))
      }
      None => return None
    }
  }
  guard lower.compare(BinFloat::zero()) >= 0 else { return None }
  let mut reductions = 0
  while upper.compare(eighth) > 0 && reductions < 4096 {
    lower = lower.mul_ctx(half, downward).0
    upper = upper.mul_ctx(half, upward).0
    reductions += 1
  }
  guard upper.compare(eighth) <= 0 else { return None }
  let mut term_lower = lower
  let mut term_upper = upper
  let mut sum_lower = lower
  let mut sum_upper = upper
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  let mut certified = false
  while index < 10000 {
    index += 1
    let divisor = BinFloat::from_int(index, precision=work_precision)
    term_lower = term_lower.mul_ctx(lower, downward).0.div_ctx(
        divisor, downward,
      ).0
    term_upper = term_upper.mul_ctx(upper, upward).0.div_ctx(divisor, upward).0
    sum_lower = sum_lower.add_ctx(term_lower, downward).0
    sum_upper = sum_upper.add_ctx(term_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let next_upper = term_upper.mul_ctx(upper, upward).0.div_ctx(
          BinFloat::from_int(index + 1, precision=work_precision),
          upward,
        ).0
      let ratio = upper.div_ctx(
          BinFloat::from_int(index + 2, precision=work_precision),
          upward,
        ).0
      let tail = next_upper.div_ctx(one.sub_ctx(ratio, downward).0, upward).0
      sum_upper = sum_upper.add_ctx(tail, upward).0
      certified = true
      break
    }
  }
  guard certified else { return None }
  let mut result = (sum_lower, sum_upper)
  for _ in 0..<reductions {
    result = binary_product_bounds(
      result,
      (result.0.add_ctx(two, downward).0, result.1.add_ctx(two, upward).0),
      downward,
      upward,
    )
  }
  Some(result)
}

///|
fn binary_atanh_small_positive_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower = value.with_precision(work_precision, RoundingMode::TowardNegative)
  let upper = value.with_precision(work_precision, RoundingMode::TowardPositive)
  let one = BinFloat::one(precision=work_precision)
  let third = one.div_ctx(
      BinFloat::from_int(3, precision=work_precision),
      upward,
    ).0
  guard lower.compare(BinFloat::zero()) >= 0 && upper.compare(third) <= 0 else {
    return None
  }
  let square_lower = lower.mul_ctx(lower, downward).0
  let square_upper = upper.mul_ctx(upper, upward).0
  let mut power_lower = lower
  let mut power_upper = upper
  let mut sum_lower = lower
  let mut sum_upper = upper
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut denominator = 1
  while denominator < 20000 {
    denominator += 2
    power_lower = power_lower.mul_ctx(square_lower, downward).0
    power_upper = power_upper.mul_ctx(square_upper, upward).0
    let divisor = BinFloat::from_int(denominator, precision=work_precision)
    let term_lower = power_lower.div_ctx(divisor, downward).0
    let term_upper = power_upper.div_ctx(divisor, upward).0
    sum_lower = sum_lower.add_ctx(term_lower, downward).0
    sum_upper = sum_upper.add_ctx(term_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let next_power = power_upper.mul_ctx(square_upper, upward).0
      let next_term = next_power.div_ctx(
          BinFloat::from_int(denominator + 2, precision=work_precision),
          upward,
        ).0
      let tail = next_term.div_ctx(
          one.sub_ctx(square_upper, downward).0,
          upward,
        ).0
      return Some((sum_lower, sum_upper.add_ctx(tail, upward).0))
    }
  }
  None
}

///|
fn binary_atanh_small_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  if value.is_negative() {
    match binary_atanh_small_positive_bounds(value.neg(), work_precision) {
      Some(positive) => Some((positive.1.neg(), positive.0.neg()))
      None => None
    }
  } else {
    binary_atanh_small_positive_bounds(value, work_precision)
  }
}

///|
fn binary_log1p_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let two = BinFloat::from_int(2, precision=work_precision)
  let lower_input = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_input = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  if lower_input.compare(half.neg()) >= 0 && upper_input.compare(half) <= 0 {
    let denominator = (
      two.add_ctx(lower_input, downward).0,
      two.add_ctx(upper_input, upward).0,
    )
    let ratio = binary_quotient_bounds(
      (lower_input, upper_input),
      denominator,
      downward,
      upward,
    )
    guard ratio is Some((ratio_lower, ratio_upper)) else { return None }
    match
      (
        binary_atanh_small_bounds(ratio_lower, work_precision),
        binary_atanh_small_bounds(ratio_upper, work_precision),
      ) {
      (Some(lower_bounds), Some(upper_bounds)) =>
        return Some(
          (
            lower_bounds.0.mul_ctx(two, downward).0,
            upper_bounds.1.mul_ctx(two, upward).0,
          ),
        )
      _ => return None
    }
  }
  let lower_argument = one.add_ctx(lower_input, downward).0
  let upper_argument = one.add_ctx(upper_input, upward).0
  guard lower_argument.compare(BinFloat::zero()) > 0 else { return None }
  match
    (
      binary_ln_bounds(lower_argument, work_precision),
      binary_ln_bounds(upper_argument, work_precision),
    ) {
    (Some(lower), Some(upper)) => Some((lower.0, upper.1))
    _ => None
  }
}

///|
fn binary_exp2_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  match
    (
      binary_ln_bounds(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
      Some(
        (
          value.with_precision(work_precision, RoundingMode::TowardNegative),
          value.with_precision(work_precision, RoundingMode::TowardPositive),
        ),
      ),
    ) {
    (Some(log_two), Some(value_bounds)) => {
      let scaled = binary_product_bounds(
        value_bounds, log_two, downward, upward,
      )
      match
        (
          binary_exp_bounds(scaled.0, work_precision),
          binary_exp_bounds(scaled.1, work_precision),
        ) {
        (Some(lower), Some(upper)) => Some((lower.0, upper.1))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn binary_log2_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  match
    (
      binary_ln_bounds(value, work_precision),
      binary_ln_bounds(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
    ) {
    (Some(numerator), Some(denominator)) =>
      binary_quotient_bounds(numerator, denominator, downward, upward)
    _ => None
  }
}

///|
pub fn BinFloat::try_exp_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.negative {
            BinFloat::zero(precision=context.precision)
          } else {
            BinFloat::inf(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((BinFloat::one(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_exp_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_certification_failure(
                "exp",
                @def.CertificationStage::RangeReduction,
                @def.CertificationFailureReason::RangeNotCertified,
                context.precision,
                work,
                attempt,
              ),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("exp", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::exp_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_exp_ctx(context).unwrap()
}

///|
pub fn BinFloat::exp(self : BinFloat) -> BinFloat {
  self.exp_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_expm1_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.is_negative() {
            BinFloat::one(precision=context.precision).neg()
          } else {
            BinFloat::inf(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() => Ok(self.round_ctx(context))
    FpClass::Finite => {
      let mut budget = CertifiedRefinementBudget::new(context.precision + 64)
      while budget.available() {
        match binary_expm1_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(binary_refinement_failure_for("expm1", context, budget))
    }
  }
}

///|
pub fn BinFloat::expm1_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_expm1_ctx(context).unwrap()
}

///|
pub fn BinFloat::expm1(self : BinFloat) -> BinFloat {
  self.expm1_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_log1p_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.is_negative() =>
      Ok((BinFloat::nan(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let one = BinFloat::one(precision=self.precision())
      if self.compare(one.neg()) < 0 {
        return Err(@def.ArithmeticError::domain_error("log1p requires x >= -1"))
      }
      if self.compare(one.neg()) == 0 {
        return Ok(
          (
            BinFloat::inf(Sign::Negative, precision=context.precision),
            binary_division_by_zero_flags(),
          ),
        )
      }
      if self.is_zero() {
        return Ok(self.round_ctx(context))
      }
      let mut budget = CertifiedRefinementBudget::new(context.precision + 64)
      while budget.available() {
        match binary_log1p_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(binary_refinement_failure_for("log1p", context, budget))
    }
  }
}

///|
pub fn BinFloat::log1p_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_log1p_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified log1p evaluation failed")
  }
}

///|
pub fn BinFloat::log1p(self : BinFloat) -> BinFloat {
  self.log1p_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_exp2_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.is_negative() {
            BinFloat::zero(precision=context.precision)
          } else {
            BinFloat::inf(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((BinFloat::one(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      match binary_exact_bounded_int(self) {
        Some(exponent) => {
          let exact = BinFloat::make(BinCoeff::one(), exponent, 1)
          return Ok(exact.round_ctx(context))
        }
        None => ()
      }
      let mut budget = CertifiedRefinementBudget::new(context.precision + 64)
      while budget.available() {
        match binary_exp2_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(binary_refinement_failure_for("exp2", context, budget))
    }
  }
}

///|
pub fn BinFloat::exp2_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_exp2_ctx(context).unwrap()
}

///|
pub fn BinFloat::exp2(self : BinFloat) -> BinFloat {
  self.exp2_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_log2_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.is_negative() =>
      Ok((BinFloat::nan(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          BinFloat::inf(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.is_negative() =>
      Err(@def.ArithmeticError::domain_error("log2 requires a positive value"))
    FpClass::Finite if self.compare(BinFloat::one(precision=self.precision())) ==
      0 => Ok((BinFloat::zero(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      if self.coefficient().compare(BinCoeff::one()) == 0 {
        let exact = BinFloat::from_int(self.exponent2(), precision=64)
        return Ok(exact.round_ctx(context))
      }
      let mut budget = CertifiedRefinementBudget::new(context.precision + 64)
      while budget.available() {
        match binary_log2_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(binary_refinement_failure_for("log2", context, budget))
    }
  }
}

///|
pub fn BinFloat::log2_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_log2_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified log2 evaluation failed")
  }
}

///|
pub fn BinFloat::log2(self : BinFloat) -> BinFloat {
  self.log2_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_exp10_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.negative {
            BinFloat::zero(precision=context.precision)
          } else {
            BinFloat::inf(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((BinFloat::one(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      match binary_exact_bounded_int(self) {
        Some(exponent) if exponent >= 0 && exponent <= 4096 => {
          let coefficient = BinCoeff::from_uint64(5UL).pow_nat(
            exponent.reinterpret_as_uint(),
          )
          let exact = BinFloat::make(
            coefficient,
            exponent,
            Int::max(1, coefficient.bit_length()),
          )
          return Ok(exact.round_ctx(context))
        }
        _ => ()
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_ln10_bounds(work) {
          Some(ln10) => {
            let downward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardPositive,
            )
            let lower_input = self.with_precision(
              work,
              RoundingMode::TowardNegative,
            )
            let upper_input = self.with_precision(
              work,
              RoundingMode::TowardPositive,
            )
            let candidates = [
              lower_input.mul_ctx(ln10.0, downward).0,
              lower_input.mul_ctx(ln10.1, downward).0,
              upper_input.mul_ctx(ln10.0, upward).0,
              upper_input.mul_ctx(ln10.1, upward).0,
            ]
            let mut lower = candidates[0]
            let mut upper = candidates[0]
            for candidate in candidates[1:] {
              if candidate.compare(lower) < 0 {
                lower = candidate
              }
              if candidate.compare(upper) > 0 {
                upper = candidate
              }
            }
            match
              (binary_exp_bounds(lower, work), binary_exp_bounds(upper, work)) {
              (Some(lower_bounds), Some(upper_bounds)) => {
                let (result, unique, flags) = binary_certified_target_rounding(
                  lower_bounds.0,
                  upper_bounds.1,
                  context,
                )
                if unique {
                  return Ok((result, flags))
                }
              }
              _ =>
                return Err(
                  binary_range_failure_state("exp10", context, work, attempt),
                )
            }
          }
          None =>
            return Err(
              binary_range_failure_state("exp10", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("exp10", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::exp10_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_exp10_ctx(context).unwrap()
}

///|
pub fn BinFloat::exp10(self : BinFloat) -> BinFloat {
  self.exp10_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_log10_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.negative =>
      Ok((BinFloat::nan(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          BinFloat::inf(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.negative =>
      Err(@def.ArithmeticError::domain_error("log10 requires a positive value"))
    FpClass::Finite if self.compare(BinFloat::one(precision=self.precision())) ==
      0 => Ok((BinFloat::zero(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      let decimal_exponent = self.exponent2()
      if decimal_exponent > 0 && decimal_exponent <= 4096 {
        let expected_coefficient = BinCoeff::from_uint64(5UL).pow_nat(
          decimal_exponent.reinterpret_as_uint(),
        )
        if self.coefficient().compare(expected_coefficient) == 0 {
          let exact = BinFloat::from_int(decimal_exponent, precision=64)
          return Ok(exact.round_ctx(context))
        }
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match (binary_ln_bounds(self, work), binary_ln10_bounds(work)) {
          (Some(numerator), Some(denominator)) => {
            let downward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardPositive,
            )
            let lower_candidates = [
              numerator.0.div_ctx(denominator.0, downward).0,
              numerator.0.div_ctx(denominator.1, downward).0,
              numerator.1.div_ctx(denominator.0, downward).0,
              numerator.1.div_ctx(denominator.1, downward).0,
            ]
            let upper_candidates = [
              numerator.0.div_ctx(denominator.0, upward).0,
              numerator.0.div_ctx(denominator.1, upward).0,
              numerator.1.div_ctx(denominator.0, upward).0,
              numerator.1.div_ctx(denominator.1, upward).0,
            ]
            let mut lower = lower_candidates[0]
            let mut upper = upper_candidates[0]
            for candidate in lower_candidates[1:] {
              if candidate.compare(lower) < 0 {
                lower = candidate
              }
            }
            for candidate in upper_candidates[1:] {
              if candidate.compare(upper) > 0 {
                upper = candidate
              }
            }
            let (result, unique, flags) = binary_certified_target_rounding(
              lower, upper, context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          _ =>
            return Err(
              binary_range_failure_state("log10", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("log10", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::log10_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_log10_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified log10 evaluation failed")
  }
}

///|
pub fn BinFloat::log10(self : BinFloat) -> BinFloat {
  self.log10_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
/// Certified fused evaluation of `ln(exp(x))`.
///
/// This is an additive composition operation, not a replacement for the
/// IEEE `exp` and `ln` operations.  For the certified finite range the exact
/// composition is `x`, so only the final target rounding is performed.
pub fn BinFloat::try_exp_ln_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.negative =>
      Ok(
        (
          BinFloat::inf(Sign::Negative, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let eighth = BinFloat::make(BinCoeff::one(), -3, self.precision())
      guard self.compare(eighth.neg()) >= 0 && self.compare(eighth) <= 0 else {
        return Err(
          binary_certification_failure(
            "exp_ln",
            @def.CertificationStage::RangeReduction,
            @def.CertificationFailureReason::RangeNotCertified,
            context.precision,
            context.precision,
            0,
          ),
        )
      }
      Ok(self.round_ctx(context))
    }
  }
}

///|
pub fn BinFloat::exp_ln_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_exp_ln_ctx(context).unwrap()
}

///|
pub fn BinFloat::exp_ln(self : BinFloat) -> BinFloat {
  self.exp_ln_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_ln_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Finite if self.compare(BinFloat::one(precision=self.precision())) ==
      0 => Ok((BinFloat::zero(precision=context.precision), BinaryFlags::new()))
    FpClass::Infinity if self.negative =>
      Ok((BinFloat::nan(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          BinFloat::inf(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.negative =>
      Err(@def.ArithmeticError::domain_error("ln requires a positive value"))
    FpClass::Finite => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_ln_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_certification_failure(
                "ln",
                @def.CertificationStage::RangeReduction,
                @def.CertificationFailureReason::RangeNotCertified,
                context.precision,
                work,
                attempt,
              ),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("ln", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::ln_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_ln_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified ln evaluation failed")
  }
}

///|
pub fn BinFloat::ln(self : BinFloat) -> BinFloat {
  self.ln_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_hypot_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  if self.class == FpClass::Infinity || other.class == FpClass::Infinity {
    return Ok(
      (
        BinFloat::inf(Sign::Positive, precision=context.precision),
        if self.is_signaling_nan() || other.is_signaling_nan() {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      ),
    )
  }
  match binary_nan_pair(self, other, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  let left_exponent = self.exponent2().to_int64() * 2L
  let right_exponent = other.exponent2().to_int64() * 2L
  guard left_exponent >= -2147483648L &&
    left_exponent <= 2147483647L &&
    right_exponent >= -2147483648L &&
    right_exponent <= 2147483647L else {
    return Err(
      binary_certification_failure(
        "hypot",
        @def.CertificationStage::RangeReduction,
        @def.CertificationFailureReason::RangeNotCertified,
        context.precision,
        context.precision,
        0,
      ),
    )
  }
  let left_square = self.coefficient().mul(self.coefficient())
  let right_square = other.coefficient().mul(other.coefficient())
  let common_exponent = Int::min(
    left_exponent.to_int(),
    right_exponent.to_int(),
  )
  let left_shift = left_exponent.to_int() - common_exponent
  let right_shift = right_exponent.to_int() - common_exponent
  guard left_shift <= 1_000_000 && right_shift <= 1_000_000 else {
    return Err(
      binary_certification_failure(
        "hypot",
        @def.CertificationStage::RangeReduction,
        @def.CertificationFailureReason::RefinementBudgetExhausted,
        context.precision,
        context.precision,
        0,
      ),
    )
  }
  let sum = left_square
    .shift_left(left_shift)
    .add(right_square.shift_left(right_shift))
  let exact_sum = BinFloat::make(
    sum,
    common_exponent,
    Int::max(1, sum.bit_length()),
  )
  Ok(exact_sum.sqrt_ctx(context))
}

///|
pub fn BinFloat::hypot_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_hypot_ctx(other, context).unwrap()
}

///|
pub fn BinFloat::hypot(self : BinFloat, other : BinFloat) -> BinFloat {
  self.hypot_ctx(
    other,
    BinaryContext::unbounded(Int::max(self.precision(), other.precision())),
  ).0
}

///|
pub fn BinFloat::pown_ctx(
  self : BinFloat,
  exponent : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.pow_int_ctx(exponent, context)
}

///|
pub fn BinFloat::pown(
  self : BinFloat,
  exponent : Int,
) -> Result[BinFloat, @def.ArithmeticError] {
  self.pow_int(exponent)
}

///|
fn binary_rootn_positive_bounds(
  value : BinFloat,
  degree : Int,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  match binary_ln_bounds(value, work_precision) {
    None => None
    Some(logarithm) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let divisor = BinFloat::from_int(degree, precision=work_precision)
      let candidates = [
        logarithm.0.div_ctx(divisor, downward).0,
        logarithm.0.div_ctx(divisor, upward).0,
        logarithm.1.div_ctx(divisor, downward).0,
        logarithm.1.div_ctx(divisor, upward).0,
      ]
      let mut lower = candidates[0]
      let mut upper = candidates[0]
      for candidate in candidates[1:] {
        if candidate.compare(lower) < 0 {
          lower = candidate
        }
        if candidate.compare(upper) > 0 {
          upper = candidate
        }
      }
      match
        (
          binary_exp_bounds(lower, work_precision),
          binary_exp_bounds(upper, work_precision),
        ) {
        (Some(lower_exp), Some(upper_exp)) => Some((lower_exp.0, upper_exp.1))
        _ => None
      }
    }
  }
}

///|
fn binary_exact_nth_root_coefficient(
  coefficient : BinCoeff,
  degree : Int,
) -> BinCoeff? {
  guard degree > 1 && degree <= 64 && coefficient.bit_length() <= 4096 else {
    return None
  }
  if coefficient.compare(BinCoeff::one()) == 0 {
    return Some(BinCoeff::one())
  }
  let root_bits = (coefficient.bit_length() + degree - 1) / degree
  let mut lower = BinCoeff::zero()
  let mut upper = BinCoeff::one().shift_left(root_bits)
  let one = BinCoeff::one()
  while upper.sub_checked(lower).unwrap().compare(one) > 0 {
    let midpoint = lower.add(upper).shift_right(1)
    let power = midpoint.pow_nat(degree.reinterpret_as_uint())
    if power.compare(coefficient) <= 0 {
      lower = midpoint
    } else {
      upper = midpoint
    }
  }
  if lower.pow_nat(degree.reinterpret_as_uint()).compare(coefficient) == 0 {
    Some(lower)
  } else {
    None
  }
}

///|
fn binary_exact_rootn(value : BinFloat, degree : Int) -> BinFloat? {
  guard degree > 1 && value.exponent2() % degree == 0 else { return None }
  match binary_exact_nth_root_coefficient(value.coefficient(), degree) {
    Some(coefficient) =>
      Some(
        BinFloat::make(
          coefficient,
          value.exponent2() / degree,
          Int::max(1, coefficient.bit_length()),
          negative=value.is_negative(),
        ),
      )
    None => None
  }
}

///|
pub fn BinFloat::try_rootn_ctx(
  self : BinFloat,
  degree : Int,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  guard degree != 0 else {
    return Err(
      @def.ArithmeticError::domain_error("rootn degree must not be zero"),
    )
  }
  let degree64 = degree.to_int64()
  guard degree64 >= -1_000_000_000L && degree64 <= 1_000_000_000L else {
    return Err(
      binary_certification_failure(
        "rootn",
        @def.CertificationStage::RangeReduction,
        @def.CertificationFailureReason::RangeNotCertified,
        context.precision,
        context.precision,
        0,
      ),
    )
  }
  let magnitude_degree = if degree < 0 { -degree } else { degree }
  let odd = magnitude_degree % 2 != 0
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => {
      let negative = self.negative && odd
      if degree < 0 {
        Ok(
          (
            if negative {
              BinFloat::negative_zero(precision=context.precision)
            } else {
              BinFloat::zero(precision=context.precision)
            },
            BinaryFlags::new(),
          ),
        )
      } else {
        Ok(
          (
            BinFloat::inf(
              if negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision=context.precision,
            ),
            BinaryFlags::new(),
          ),
        )
      }
    }
    FpClass::Finite if self.is_zero() => {
      let negative = self.negative && odd
      if degree < 0 {
        Ok(
          (
            BinFloat::inf(
              if negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision=context.precision,
            ),
            binary_division_by_zero_flags(),
          ),
        )
      } else {
        Ok(
          (
            if negative {
              BinFloat::negative_zero(precision=context.precision)
            } else {
              BinFloat::zero(precision=context.precision)
            },
            BinaryFlags::new(),
          ),
        )
      }
    }
    FpClass::Finite if self.negative && !odd =>
      Err(
        @def.ArithmeticError::domain_error(
          "rootn even degree requires a non-negative value",
        ),
      )
    FpClass::Finite => {
      let positive = self.abs()
      if magnitude_degree == 1 {
        if degree < 0 {
          return Ok(
            BinFloat::one(precision=context.precision).div_ctx(self, context),
          )
        }
        return Ok(self.round_ctx(context))
      }
      if degree > 0 {
        match binary_exact_rootn(self, degree) {
          Some(exact) => return Ok(exact.round_ctx(context))
          None => ()
        }
      }
      let mut work = Int::max(context.precision + 64, positive.precision() + 16)
      let mut attempt = 0
      while attempt < 12 {
        match binary_rootn_positive_bounds(positive, magnitude_degree, work) {
          Some(bounds) => {
            let signed_bounds = if self.negative {
              (bounds.1.neg(), bounds.0.neg())
            } else {
              bounds
            }
            let adjusted = if degree < 0 {
              let downward = BinaryContext::unbounded(
                work,
                rounding=RoundTowardNegative,
              )
              let upward = BinaryContext::unbounded(
                work,
                rounding=RoundTowardPositive,
              )
              let one = BinFloat::one(precision=work)
              (
                one.div_ctx(signed_bounds.1, downward).0,
                one.div_ctx(signed_bounds.0, upward).0,
              )
            } else {
              signed_bounds
            }
            let (result, unique, flags) = binary_certified_target_rounding(
              adjusted.0,
              adjusted.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("rootn", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("rootn", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::rootn_ctx(
  self : BinFloat,
  degree : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_rootn_ctx(degree, context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified rootn evaluation failed")
  }
}

///|
pub fn BinFloat::rootn(self : BinFloat, degree : Int) -> BinFloat {
  self.rootn_ctx(degree, BinaryContext::unbounded(self.precision())).0
}

///|
fn binary_exact_bounded_int(value : BinFloat) -> Int? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() {
    return Some(0)
  }
  guard value.exponent2() >= 0 &&
    value.exponent2() <= 30 &&
    value.coefficient().bit_length() + value.exponent2() <= 31 else {
    return None
  }
  match value.coefficient().shift_left(value.exponent2()).to_uint64() {
    Some(magnitude) => {
      let integer = magnitude.reinterpret_as_int64().to_int()
      Some(if value.is_negative() { -integer } else { integer })
    }
    None => None
  }
}

///|
fn binary_exact_unit_fraction_degree(value : BinFloat) -> Int? {
  guard value.classify() == FpClass::Finite &&
    value.coefficient().compare(BinCoeff::one()) == 0 &&
    value.exponent2() < 0 &&
    value.exponent2() >= -29 else {
    return None
  }
  let degree = 1 << -value.exponent2()
  Some(if value.is_negative() { -degree } else { degree })
}

///|
pub fn BinFloat::try_pow_ctx(
  self : BinFloat,
  exponent : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  if exponent.classify() == FpClass::Finite && exponent.is_zero() {
    return Ok((BinFloat::one(precision=context.precision), BinaryFlags::new()))
  }
  if self.classify() == FpClass::Finite &&
    self.compare(BinFloat::one(precision=self.precision())) == 0 {
    return Ok((BinFloat::one(precision=context.precision), BinaryFlags::new()))
  }
  match binary_exact_bounded_int(exponent) {
    Some(integer) => return Ok(self.pown_ctx(integer, context))
    None => ()
  }
  match binary_exact_unit_fraction_degree(exponent) {
    Some(degree) => return self.try_rootn_ctx(degree, context)
    None => ()
  }
  match binary_nan_pair(self, exponent, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  if self.classify() == FpClass::Finite && self.is_negative() {
    return Err(
      @def.ArithmeticError::domain_error(
        "pow requires a non-negative base for non-integer exponents",
      ),
    )
  }
  if self.classify() == FpClass::Finite && self.is_zero() {
    if exponent.sign() == Sign::Negative {
      return Ok(
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    }
    return Ok((BinFloat::zero(precision=context.precision), BinaryFlags::new()))
  }
  if self.classify() == FpClass::Infinity {
    return Ok(
      (
        if exponent.sign() == Sign::Negative {
          BinFloat::zero(precision=context.precision)
        } else {
          BinFloat::inf(Sign::Positive, precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  if exponent.classify() == FpClass::Infinity {
    let one = BinFloat::one(precision=self.precision())
    let comparison = self.compare(one)
    if comparison == 0 {
      return Ok(
        (BinFloat::one(precision=context.precision), BinaryFlags::new()),
      )
    }
    let grows = (comparison > 0) == (exponent.sign() == Sign::Positive)
    return Ok(
      (
        if grows {
          BinFloat::inf(Sign::Positive, precision=context.precision)
        } else {
          BinFloat::zero(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  let mut work = Int::max(
    context.precision + 64,
    Int::max(self.precision(), exponent.precision()) + 16,
  )
  let mut attempt = 0
  while attempt < 12 {
    match binary_ln_bounds(self, work) {
      Some(logarithm) => {
        let downward = BinaryContext::unbounded(
          work,
          rounding=RoundTowardNegative,
        )
        let upward = BinaryContext::unbounded(
          work,
          rounding=RoundTowardPositive,
        )
        let exponent_lower = exponent.with_precision(
          work,
          RoundingMode::TowardNegative,
        )
        let exponent_upper = exponent.with_precision(
          work,
          RoundingMode::TowardPositive,
        )
        let lower_candidates = [
          logarithm.0.mul_ctx(exponent_lower, downward).0,
          logarithm.0.mul_ctx(exponent_upper, downward).0,
          logarithm.1.mul_ctx(exponent_lower, downward).0,
          logarithm.1.mul_ctx(exponent_upper, downward).0,
        ]
        let upper_candidates = [
          logarithm.0.mul_ctx(exponent_lower, upward).0,
          logarithm.0.mul_ctx(exponent_upper, upward).0,
          logarithm.1.mul_ctx(exponent_lower, upward).0,
          logarithm.1.mul_ctx(exponent_upper, upward).0,
        ]
        let mut lower = lower_candidates[0]
        let mut upper = upper_candidates[0]
        for candidate in lower_candidates[1:] {
          if candidate.compare(lower) < 0 {
            lower = candidate
          }
        }
        for candidate in upper_candidates[1:] {
          if candidate.compare(upper) > 0 {
            upper = candidate
          }
        }
        match (binary_exp_bounds(lower, work), binary_exp_bounds(upper, work)) {
          (Some(lower_exp), Some(upper_exp)) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              lower_exp.0,
              upper_exp.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          _ =>
            return Err(
              binary_range_failure_state("pow", context, work, attempt),
            )
        }
      }
      None =>
        return Err(binary_range_failure_state("pow", context, work, attempt))
    }
    work += Int::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("pow", context, work, attempt))
}

///|
pub fn BinFloat::pow_ctx(
  self : BinFloat,
  exponent : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_pow_ctx(exponent, context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified pow evaluation failed")
  }
}

///|
pub fn BinFloat::pow(self : BinFloat, exponent : BinFloat) -> BinFloat {
  self.pow_ctx(
    exponent,
    BinaryContext::unbounded(Int::max(self.precision(), exponent.precision())),
  ).0
}

///|
priv enum BinaryHyperbolicOperation {
  Sinh
  Cosh
  Tanh
}

///|
fn BinaryHyperbolicOperation::name(self : BinaryHyperbolicOperation) -> String {
  match self {
    Sinh => "sinh"
    Cosh => "cosh"
    Tanh => "tanh"
  }
}

///|
fn binary_hyperbolic_bounds(
  value : BinFloat,
  operation : BinaryHyperbolicOperation,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  match
    (
      binary_exp_bounds(value, work_precision),
      binary_exp_bounds(value.neg(), work_precision),
    ) {
    (Some(positive_exp), Some(negative_exp)) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
      let sinh = (
        positive_exp.0.sub_ctx(negative_exp.1, downward).0.mul_ctx(
          half, downward,
        ).0,
        positive_exp.1.sub_ctx(negative_exp.0, upward).0.mul_ctx(half, upward).0,
      )
      let cosh = (
        positive_exp.0.add_ctx(negative_exp.0, downward).0.mul_ctx(
          half, downward,
        ).0,
        positive_exp.1.add_ctx(negative_exp.1, upward).0.mul_ctx(half, upward).0,
      )
      match operation {
        BinaryHyperbolicOperation::Sinh => Some(sinh)
        BinaryHyperbolicOperation::Cosh => Some(cosh)
        BinaryHyperbolicOperation::Tanh => {
          let lower_candidates = [
            sinh.0.div_ctx(cosh.0, downward).0,
            sinh.0.div_ctx(cosh.1, downward).0,
            sinh.1.div_ctx(cosh.0, downward).0,
            sinh.1.div_ctx(cosh.1, downward).0,
          ]
          let upper_candidates = [
            sinh.0.div_ctx(cosh.0, upward).0,
            sinh.0.div_ctx(cosh.1, upward).0,
            sinh.1.div_ctx(cosh.0, upward).0,
            sinh.1.div_ctx(cosh.1, upward).0,
          ]
          let mut lower = lower_candidates[0]
          let mut upper = upper_candidates[0]
          for candidate in lower_candidates[1:] {
            if candidate.compare(lower) < 0 {
              lower = candidate
            }
          }
          for candidate in upper_candidates[1:] {
            if candidate.compare(upper) > 0 {
              upper = candidate
            }
          }
          Some((lower, upper))
        }
      }
    }
    _ => None
  }
}

///|
fn BinFloat::try_hyperbolic_ctx(
  self : BinFloat,
  operation : BinaryHyperbolicOperation,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          match operation {
            BinaryHyperbolicOperation::Sinh =>
              BinFloat::inf(self.sign(), precision=context.precision)
            BinaryHyperbolicOperation::Cosh =>
              BinFloat::inf(Sign::Positive, precision=context.precision)
            BinaryHyperbolicOperation::Tanh =>
              if self.is_negative() {
                BinFloat::one(precision=context.precision).neg()
              } else {
                BinFloat::one(precision=context.precision)
              }
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          match operation {
            BinaryHyperbolicOperation::Cosh =>
              BinFloat::one(precision=context.precision)
            _ =>
              if self.is_negative_zero() {
                BinFloat::negative_zero(precision=context.precision)
              } else {
                BinFloat::zero(precision=context.precision)
              }
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let mut work = Int::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while attempt < 12 {
        match binary_hyperbolic_bounds(self, operation, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state(
                operation.name(),
                context,
                work,
                attempt,
              ),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(
        binary_refinement_failure_state(
          operation.name(),
          context,
          work,
          attempt,
        ),
      )
    }
  }
}

///|
pub fn BinFloat::try_sinh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Sinh, context)
}

///|
pub fn BinFloat::sinh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_sinh_ctx(context).unwrap()
}

///|
pub fn BinFloat::sinh(self : BinFloat) -> BinFloat {
  self.sinh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_cosh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Cosh, context)
}

///|
pub fn BinFloat::cosh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_cosh_ctx(context).unwrap()
}

///|
pub fn BinFloat::cosh(self : BinFloat) -> BinFloat {
  self.cosh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_tanh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Tanh, context)
}

///|
pub fn BinFloat::tanh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_tanh_ctx(context).unwrap()
}

///|
pub fn BinFloat::tanh(self : BinFloat) -> BinFloat {
  self.tanh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
priv enum BinaryInverseHyperbolicOperation {
  Asinh
  Acosh
  Atanh
} derive(Eq)

///|
fn BinaryInverseHyperbolicOperation::name(
  self : BinaryInverseHyperbolicOperation,
) -> String {
  match self {
    Asinh => "asinh"
    Acosh => "acosh"
    Atanh => "atanh"
  }
}

///|
fn binary_asinh_positive_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  match
    (
      lower_value.try_hypot_ctx(one, downward),
      upper_value.try_hypot_ctx(one, upward),
    ) {
    (Ok(lower_hypot), Ok(upper_hypot)) => {
      let lower_argument = lower_value.add_ctx(lower_hypot.0, downward).0
      let upper_argument = upper_value.add_ctx(upper_hypot.0, upward).0
      match
        (
          binary_ln_bounds(lower_argument, work_precision),
          binary_ln_bounds(upper_argument, work_precision),
        ) {
        (Some(lower_log), Some(upper_log)) => Some((lower_log.0, upper_log.1))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn binary_acosh_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let lower_minus = lower_value.sub_ctx(one, downward).0
  let upper_minus = upper_value.sub_ctx(one, upward).0
  let lower_plus = lower_value.add_ctx(one, downward).0
  let upper_plus = upper_value.add_ctx(one, upward).0
  let lower_product = lower_minus.sqrt_ctx(downward).0.mul_ctx(
      lower_plus.sqrt_ctx(downward).0,
      downward,
    ).0
  let upper_product = upper_minus.sqrt_ctx(upward).0.mul_ctx(
      upper_plus.sqrt_ctx(upward).0,
      upward,
    ).0
  let lower_argument = lower_value.add_ctx(lower_product, downward).0
  let upper_argument = upper_value.add_ctx(upper_product, upward).0
  match
    (
      binary_ln_bounds(lower_argument, work_precision),
      binary_ln_bounds(upper_argument, work_precision),
    ) {
    (Some(lower_log), Some(upper_log)) => Some((lower_log.0, upper_log.1))
    _ => None
  }
}

///|
fn binary_atanh_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let lower_numerator = one.add_ctx(lower_value, downward).0
  let upper_numerator = one.add_ctx(upper_value, upward).0
  let lower_denominator = one.sub_ctx(upper_value, downward).0
  let upper_denominator = one.sub_ctx(lower_value, upward).0
  let lower_ratio = lower_numerator.div_ctx(upper_denominator, downward).0
  let upper_ratio = upper_numerator.div_ctx(lower_denominator, upward).0
  match
    (
      binary_ln_bounds(lower_ratio, work_precision),
      binary_ln_bounds(upper_ratio, work_precision),
    ) {
    (Some(lower_log), Some(upper_log)) =>
      Some(
        (
          lower_log.0.mul_ctx(half, downward).0,
          upper_log.1.mul_ctx(half, upward).0,
        ),
      )
    _ => None
  }
}

///|
fn BinFloat::try_inverse_hyperbolic_ctx(
  self : BinFloat,
  operation : BinaryInverseHyperbolicOperation,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      match operation {
        BinaryInverseHyperbolicOperation::Asinh =>
          Ok(
            (
              BinFloat::inf(self.sign(), precision=context.precision),
              BinaryFlags::new(),
            ),
          )
        BinaryInverseHyperbolicOperation::Acosh if !self.is_negative() =>
          Ok(
            (
              BinFloat::inf(Sign::Positive, precision=context.precision),
              BinaryFlags::new(),
            ),
          )
        _ =>
          Err(
            @def.ArithmeticError::domain_error(
              "inverse hyperbolic input is outside the real domain",
            ),
          )
      }
    FpClass::Finite if self.is_zero() =>
      match operation {
        BinaryInverseHyperbolicOperation::Asinh
        | BinaryInverseHyperbolicOperation::Atanh =>
          Ok(
            (
              if self.is_negative_zero() {
                BinFloat::negative_zero(precision=context.precision)
              } else {
                BinFloat::zero(precision=context.precision)
              },
              BinaryFlags::new(),
            ),
          )
        BinaryInverseHyperbolicOperation::Acosh =>
          Err(
            @def.ArithmeticError::domain_error(
              "acosh requires a value greater than or equal to one",
            ),
          )
      }
    FpClass::Finite => {
      let one = BinFloat::one(precision=self.precision())
      match operation {
        BinaryInverseHyperbolicOperation::Acosh if self.compare(one) < 0 =>
          return Err(
            @def.ArithmeticError::domain_error(
              "acosh requires a value greater than or equal to one",
            ),
          )
        BinaryInverseHyperbolicOperation::Atanh if self.abs().compare(one) > 0 =>
          return Err(
            @def.ArithmeticError::domain_error(
              "atanh requires an absolute value no greater than one",
            ),
          )
        BinaryInverseHyperbolicOperation::Atanh if self.abs().compare(one) == 0 =>
          return Ok(
            (
              BinFloat::inf(self.sign(), precision=context.precision),
              binary_division_by_zero_flags(),
            ),
          )
        _ => ()
      }
      if operation == BinaryInverseHyperbolicOperation::Acosh &&
        self.compare(one) == 0 {
        return Ok(
          (BinFloat::zero(precision=context.precision), BinaryFlags::new()),
        )
      }
      let mut work = Int::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while attempt < 12 {
        let bounds = match operation {
          BinaryInverseHyperbolicOperation::Asinh =>
            match binary_asinh_positive_bounds(self.abs(), work) {
              Some(positive) =>
                Some(
                  if self.is_negative() {
                    (positive.1.neg(), positive.0.neg())
                  } else {
                    positive
                  },
                )
              None => None
            }
          BinaryInverseHyperbolicOperation::Acosh =>
            binary_acosh_bounds(self, work)
          BinaryInverseHyperbolicOperation::Atanh =>
            binary_atanh_bounds(self, work)
        }
        match bounds {
          Some(interval) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              interval.0,
              interval.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state(
                operation.name(),
                context,
                work,
                attempt,
              ),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(
        binary_refinement_failure_state(
          operation.name(),
          context,
          work,
          attempt,
        ),
      )
    }
  }
}

///|
pub fn BinFloat::try_asinh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Asinh,
    context,
  )
}

///|
pub fn BinFloat::asinh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_asinh_ctx(context).unwrap()
}

///|
pub fn BinFloat::asinh(self : BinFloat) -> BinFloat {
  self.asinh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_acosh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Acosh,
    context,
  )
}

///|
pub fn BinFloat::acosh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_acosh_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified acosh evaluation failed")
  }
}

///|
pub fn BinFloat::acosh(self : BinFloat) -> BinFloat {
  self.acosh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_atanh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Atanh,
    context,
  )
}

///|
pub fn BinFloat::atanh_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_atanh_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified atanh evaluation failed")
  }
}

///|
pub fn BinFloat::atanh(self : BinFloat) -> BinFloat {
  self.atanh_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
fn binary_atan_small_positive_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  guard lower_value.sign() == Sign::Positive && upper_value.compare(half) <= 0 else {
    return None
  }
  if upper_value.is_zero() {
    return Some((lower_value, upper_value))
  }
  let square_lower = lower_value.mul_ctx(lower_value, downward).0
  let square_upper = upper_value.mul_ctx(upper_value, upward).0
  let mut power_lower = lower_value
  let mut power_upper = upper_value
  let mut sum_lower = lower_value
  let mut sum_upper = upper_value
  let mut bracket_lower = BinFloat::zero(precision=work_precision)
  let mut bracket_upper = upper_value
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  while index < 20000 {
    power_lower = power_lower.mul_ctx(square_lower, downward).0
    power_upper = power_upper.mul_ctx(square_upper, upward).0
    let denominator = BinFloat::from_int(
      2 * index + 1,
      precision=work_precision,
    )
    let piece_lower = power_lower.div_ctx(denominator, downward).0
    let piece_upper = power_upper.div_ctx(denominator, upward).0
    if index % 2 == 1 {
      sum_lower = sum_lower.sub_ctx(piece_upper, downward).0
      sum_upper = sum_upper.sub_ctx(piece_lower, upward).0
      bracket_lower = sum_lower
    } else {
      sum_lower = sum_lower.add_ctx(piece_lower, downward).0
      sum_upper = sum_upper.add_ctx(piece_upper, upward).0
      bracket_upper = sum_upper
    }
    if index % 2 == 1 && piece_upper.compare(threshold) < 0 {
      return Some((bracket_lower, bracket_upper))
    }
    index += 1
  }
  None
}

///|
fn binary_atan_small_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  if value.is_negative() {
    match binary_atan_small_positive_bounds(value.neg(), work_precision) {
      Some(positive) => Some((positive.1.neg(), positive.0.neg()))
      None => None
    }
  } else {
    binary_atan_small_positive_bounds(value, work_precision)
  }
}

///|
fn binary_atan_finite_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  if value.is_zero() {
    let zero = value.with_precision(work_precision, RoundingMode::ToNearestEven)
    return Some((zero, zero))
  }
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  if value.abs().compare(half) <= 0 {
    return binary_atan_small_bounds(value, work_precision)
  }
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  match
    (
      lower_value.try_hypot_ctx(one, downward),
      upper_value.try_hypot_ctx(one, upward),
    ) {
    (Ok(lower_hypot), Ok(upper_hypot)) => {
      let lower_denominator = one.add_ctx(lower_hypot.0, downward).0
      let upper_denominator = one.add_ctx(upper_hypot.0, upward).0
      let lower_ratio = lower_value.div_ctx(
          if lower_value.is_negative() {
            lower_denominator
          } else {
            upper_denominator
          },
          downward,
        ).0
      let upper_ratio = upper_value.div_ctx(
          if upper_value.is_negative() {
            upper_denominator
          } else {
            lower_denominator
          },
          upward,
        ).0
      match
        (
          binary_atan_finite_bounds(lower_ratio, work_precision),
          binary_atan_finite_bounds(upper_ratio, work_precision),
        ) {
        (Some(lower_atan), Some(upper_atan)) => {
          let two = BinFloat::from_int(2, precision=work_precision)
          Some(
            (
              lower_atan.0.mul_ctx(two, downward).0,
              upper_atan.1.mul_ctx(two, upward).0,
            ),
          )
        }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn binary_pi_bounds(work_precision : Int) -> (BinFloat, BinFloat)? {
  match
    binary_atan_finite_bounds(
      BinFloat::one(precision=work_precision),
      work_precision,
    ) {
    Some(quarter_pi) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let four = BinFloat::from_int(4, precision=work_precision)
      Some(
        (
          quarter_pi.0.mul_ctx(four, downward).0,
          quarter_pi.1.mul_ctx(four, upward).0,
        ),
      )
    }
    None => None
  }
}

///|
pub fn BinFloat::try_atan_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_pi_bounds(work) {
          Some(pi) => {
            let downward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardPositive,
            )
            let half = BinFloat::make(BinCoeff::one(), -1, work)
            let bounds = if self.is_negative() {
              (
                pi.1.mul_ctx(half, upward).0.neg(),
                pi.0.mul_ctx(half, downward).0.neg(),
              )
            } else {
              (pi.0.mul_ctx(half, downward).0, pi.1.mul_ctx(half, upward).0)
            }
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("atan", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("atan", context, work, attempt))
    }
    FpClass::Finite if self.is_zero() => Ok(self.round_ctx(context))
    FpClass::Finite => {
      let mut work = Int::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while attempt < 12 {
        match binary_atan_finite_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("atan", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("atan", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::atan_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_atan_ctx(context).unwrap()
}

///|
pub fn BinFloat::atan(self : BinFloat) -> BinFloat {
  self.atan_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
fn binary_asin_bounds(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let lower_square = if lower_value.compare(BinFloat::zero()) <= 0 &&
    upper_value.compare(BinFloat::zero()) >= 0 {
    BinFloat::zero(precision=work_precision)
  } else {
    let left = lower_value.mul_ctx(lower_value, downward).0
    let right = upper_value.mul_ctx(upper_value, downward).0
    if left.compare(right) < 0 {
      left
    } else {
      right
    }
  }
  let upper_left = lower_value.mul_ctx(lower_value, upward).0
  let upper_right = upper_value.mul_ctx(upper_value, upward).0
  let upper_square = if upper_left.compare(upper_right) > 0 {
    upper_left
  } else {
    upper_right
  }
  let lower_argument = one.sub_ctx(upper_square, downward).0
  let upper_argument = one.sub_ctx(lower_square, upward).0
  let lower_root = lower_argument.sqrt_ctx(downward).0
  let upper_root = upper_argument.sqrt_ctx(upward).0
  let lower_candidates = [
    lower_value.div_ctx(lower_root, downward).0,
    lower_value.div_ctx(upper_root, downward).0,
    upper_value.div_ctx(lower_root, downward).0,
    upper_value.div_ctx(upper_root, downward).0,
  ]
  let upper_candidates = [
    lower_value.div_ctx(lower_root, upward).0,
    lower_value.div_ctx(upper_root, upward).0,
    upper_value.div_ctx(lower_root, upward).0,
    upper_value.div_ctx(upper_root, upward).0,
  ]
  let mut ratio_lower = lower_candidates[0]
  let mut ratio_upper = upper_candidates[0]
  for candidate in lower_candidates[1:] {
    if candidate.compare(ratio_lower) < 0 {
      ratio_lower = candidate
    }
  }
  for candidate in upper_candidates[1:] {
    if candidate.compare(ratio_upper) > 0 {
      ratio_upper = candidate
    }
  }
  match
    (
      binary_atan_finite_bounds(ratio_lower, work_precision),
      binary_atan_finite_bounds(ratio_upper, work_precision),
    ) {
    (Some(lower_atan), Some(upper_atan)) => Some((lower_atan.0, upper_atan.1))
    _ => None
  }
}

///|
pub fn BinFloat::try_asin_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Err(
        @def.ArithmeticError::domain_error("asin requires an input in [-1, 1]"),
      )
    FpClass::Finite => {
      let one = BinFloat::one(precision=self.precision())
      if self.abs().compare(one) > 0 {
        return Err(
          @def.ArithmeticError::domain_error(
            "asin requires an input in [-1, 1]",
          ),
        )
      }
      if self.is_zero() {
        return Ok(self.round_ctx(context))
      }
      if self.abs().compare(one) == 0 {
        let mut work = context.precision + 64
        let mut attempt = 0
        while attempt < 12 {
          match binary_pi_bounds(work) {
            Some(pi) => {
              let downward = BinaryContext::unbounded(
                work,
                rounding=RoundTowardNegative,
              )
              let upward = BinaryContext::unbounded(
                work,
                rounding=RoundTowardPositive,
              )
              let half = BinFloat::make(BinCoeff::one(), -1, work)
              let bounds = if self.is_negative() {
                (
                  pi.1.mul_ctx(half, upward).0.neg(),
                  pi.0.mul_ctx(half, downward).0.neg(),
                )
              } else {
                (pi.0.mul_ctx(half, downward).0, pi.1.mul_ctx(half, upward).0)
              }
              let (result, unique, flags) = binary_certified_target_rounding(
                bounds.0,
                bounds.1,
                context,
              )
              if unique {
                return Ok((result, flags))
              }
            }
            None =>
              return Err(
                binary_range_failure_state("asin", context, work, attempt),
              )
          }
          work += Int::max(32, work / 2)
          attempt += 1
        }
        return Err(
          binary_refinement_failure_state("asin", context, work, attempt),
        )
      }
      let mut work = Int::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while attempt < 12 {
        match binary_asin_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("asin", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("asin", context, work, attempt))
    }
  }
}

///|
pub fn BinFloat::asin_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_asin_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified asin evaluation failed")
  }
}

///|
pub fn BinFloat::asin(self : BinFloat) -> BinFloat {
  self.asin_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_acos_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  if self.classify() == FpClass::Finite {
    let one = BinFloat::one(precision=self.precision())
    if self.abs().compare(one) == 0 {
      if self.compare(one) == 0 {
        return Ok(
          (BinFloat::zero(precision=context.precision), BinaryFlags::new()),
        )
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_pi_bounds(work) {
          Some(pi) => {
            let downward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = BinaryContext::unbounded(
              work,
              rounding=RoundTowardPositive,
            )
            let (result, unique, flags) = binary_certified_target_rounding(
              pi.0.round_ctx(downward).0,
              pi.1.round_ctx(upward).0,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("acos", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      return Err(
        binary_refinement_failure_state("acos", context, work, attempt),
      )
    }
  }
  let mut work = Int::max(context.precision + 64, self.precision() + 16)
  let mut attempt = 0
  while attempt < 12 {
    match (binary_asin_bounds(self, work), binary_pi_bounds(work)) {
      (Some(asin_bounds), Some(pi)) => {
        let downward = BinaryContext::unbounded(
          work,
          rounding=RoundTowardNegative,
        )
        let upward = BinaryContext::unbounded(
          work,
          rounding=RoundTowardPositive,
        )
        let half = BinFloat::make(BinCoeff::one(), -1, work)
        let lower = pi.0.mul_ctx(half, downward).0.sub_ctx(
            asin_bounds.1,
            downward,
          ).0
        let upper = pi.1.mul_ctx(half, upward).0.sub_ctx(asin_bounds.0, upward).0
        let (result, unique, flags) = binary_certified_target_rounding(
          lower, upper, context,
        )
        if unique {
          return Ok((result, flags))
        }
      }
      _ =>
        return Err(binary_range_failure_state("acos", context, work, attempt))
    }
    work += Int::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("acos", context, work, attempt))
}

///|
pub fn BinFloat::acos_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.try_acos_ctx(context) {
    Ok(result) => result
    Err(error) if error.is_domain_error() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    Err(_) => abort("certified acos evaluation failed")
  }
}

///|
pub fn BinFloat::acos(self : BinFloat) -> BinFloat {
  self.acos_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
fn binary_pi_fraction_bounds(
  numerator : Int,
  denominator_shift : Int,
  negative : Bool,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  match binary_pi_bounds(work_precision) {
    Some(pi) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let factor = BinFloat::make(
        BinCoeff::from_uint64(numerator.reinterpret_as_uint().to_uint64()),
        -denominator_shift,
        work_precision,
      )
      let positive = (
        pi.0.mul_ctx(factor, downward).0,
        pi.1.mul_ctx(factor, upward).0,
      )
      Some(
        if negative {
          (positive.1.neg(), positive.0.neg())
        } else {
          positive
        },
      )
    }
    None => None
  }
}

///|
fn binary_atan2_finite_bounds(
  ordinate : BinFloat,
  abscissa : BinFloat,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let ordinate_lower = ordinate.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let ordinate_upper = ordinate.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let abscissa_lower = abscissa.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let abscissa_upper = abscissa.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let lower_candidates = [
    ordinate_lower.div_ctx(abscissa_lower, downward).0,
    ordinate_lower.div_ctx(abscissa_upper, downward).0,
    ordinate_upper.div_ctx(abscissa_lower, downward).0,
    ordinate_upper.div_ctx(abscissa_upper, downward).0,
  ]
  let upper_candidates = [
    ordinate_lower.div_ctx(abscissa_lower, upward).0,
    ordinate_lower.div_ctx(abscissa_upper, upward).0,
    ordinate_upper.div_ctx(abscissa_lower, upward).0,
    ordinate_upper.div_ctx(abscissa_upper, upward).0,
  ]
  let mut ratio_lower = lower_candidates[0]
  let mut ratio_upper = upper_candidates[0]
  for candidate in lower_candidates[1:] {
    if candidate.compare(ratio_lower) < 0 {
      ratio_lower = candidate
    }
  }
  for candidate in upper_candidates[1:] {
    if candidate.compare(ratio_upper) > 0 {
      ratio_upper = candidate
    }
  }
  match
    (
      binary_atan_finite_bounds(ratio_lower, work_precision),
      binary_atan_finite_bounds(ratio_upper, work_precision),
    ) {
    (Some(lower_atan), Some(upper_atan)) =>
      if abscissa.sign() == Sign::Positive {
        Some((lower_atan.0, upper_atan.1))
      } else {
        match binary_pi_bounds(work_precision) {
          Some(pi) =>
            if ordinate.sign() == Sign::Negative {
              Some(
                (
                  lower_atan.0.sub_ctx(pi.1, downward).0,
                  upper_atan.1.sub_ctx(pi.0, upward).0,
                ),
              )
            } else {
              Some(
                (
                  lower_atan.0.add_ctx(pi.0, downward).0,
                  upper_atan.1.add_ctx(pi.1, upward).0,
                ),
              )
            }
          None => None
        }
      }
    _ => None
  }
}

///|
pub fn BinFloat::try_atan2_ctx(
  self : BinFloat,
  abscissa : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_pair(self, abscissa, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  let self_infinite = self.classify() == FpClass::Infinity
  let abscissa_infinite = abscissa.classify() == FpClass::Infinity
  let fraction = if self_infinite && abscissa_infinite {
    Some((if abscissa.is_negative() { 3 } else { 1 }, 2, self.is_negative()))
  } else if self_infinite || abscissa.is_zero() {
    Some((1, 1, self.is_negative()))
  } else if abscissa_infinite && abscissa.is_negative() {
    Some((1, 0, self.is_negative()))
  } else {
    None
  }
  match fraction {
    Some((numerator, shift, negative)) => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while attempt < 12 {
        match binary_pi_fraction_bounds(numerator, shift, negative, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("atan2", context, work, attempt),
            )
        }
        work += Int::max(32, work / 2)
        attempt += 1
      }
      return Err(
        binary_refinement_failure_state("atan2", context, work, attempt),
      )
    }
    None => ()
  }
  if abscissa_infinite && !abscissa.is_negative() {
    return Ok(
      (
        if self.is_negative() {
          BinFloat::negative_zero(precision=context.precision)
        } else {
          BinFloat::zero(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  if self.is_zero() && abscissa.sign() == Sign::Positive {
    return Ok(
      (
        if self.is_negative_zero() {
          BinFloat::negative_zero(precision=context.precision)
        } else {
          BinFloat::zero(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  let mut work = Int::max(
    context.precision + 64,
    Int::max(self.precision(), abscissa.precision()) + 16,
  )
  let mut attempt = 0
  while attempt < 12 {
    match binary_atan2_finite_bounds(self, abscissa, work) {
      Some(bounds) => {
        let (result, unique, flags) = binary_certified_target_rounding(
          bounds.0,
          bounds.1,
          context,
        )
        if unique {
          return Ok((result, flags))
        }
      }
      None =>
        return Err(binary_range_failure_state("atan2", context, work, attempt))
    }
    work += Int::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("atan2", context, work, attempt))
}

///|
pub fn BinFloat::atan2_ctx(
  self : BinFloat,
  abscissa : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_atan2_ctx(abscissa, context).unwrap()
}

///|
pub fn BinFloat::atan2(self : BinFloat, abscissa : BinFloat) -> BinFloat {
  self.atan2_ctx(
    abscissa,
    BinaryContext::unbounded(Int::max(self.precision(), abscissa.precision())),
  ).0
}

///|
priv enum BinaryTrigonometricOperation {
  Sin
  Cos
  Tan
} derive(Eq)

///|
fn BinaryTrigonometricOperation::name(
  self : BinaryTrigonometricOperation,
) -> String {
  match self {
    Sin => "sin"
    Cos => "cos"
    Tan => "tan"
  }
}

///|
fn binary_sin_cos_series(
  value : BinFloat,
  cosine : Bool,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let negative = value.is_negative()
  let argument = if negative { value.neg() } else { value }
  let argument_lower = argument.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let argument_upper = argument.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let square_lower = argument_lower.mul_ctx(argument_lower, downward).0
  let square_upper = argument_upper.mul_ctx(argument_upper, upward).0
  let mut term_lower = if cosine {
    BinFloat::one(precision=work_precision)
  } else {
    argument_lower
  }
  let mut term_upper = if cosine {
    BinFloat::one(precision=work_precision)
  } else {
    argument_upper
  }
  let mut sum_lower = term_lower
  let mut sum_upper = term_upper
  let mut bracket_lower = term_lower
  let mut bracket_upper = term_upper
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  while index < 20000 {
    if cosine {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          BinFloat::from_int(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          BinFloat::from_int(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          upward,
        ).0
    } else {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          BinFloat::from_int(
            2 * index * (2 * index + 1),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          BinFloat::from_int(
            2 * index * (2 * index + 1),
            precision=work_precision,
          ),
          upward,
        ).0
    }
    if index % 2 == 1 {
      sum_lower = sum_lower.sub_ctx(term_upper, downward).0
      sum_upper = sum_upper.sub_ctx(term_lower, upward).0
      bracket_lower = sum_lower
    } else {
      sum_lower = sum_lower.add_ctx(term_lower, downward).0
      sum_upper = sum_upper.add_ctx(term_upper, upward).0
      bracket_upper = sum_upper
    }
    if index % 2 == 1 && term_upper.compare(threshold) < 0 {
      if cosine || !negative {
        return Some((bracket_lower, bracket_upper))
      }
      return Some((bracket_upper.neg(), bracket_lower.neg()))
    }
    index += 1
  }
  None
}

///|
fn binary_floor_integer(value : BinFloat) -> BinFloat? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() || value.exponent2() >= 0 {
    return Some(value)
  }
  let shift = -value.exponent2()
  let magnitude = value.coefficient()
  let quotient = if shift >= magnitude.bit_length() {
    BinCoeff::zero()
  } else {
    magnitude.shift_right(shift)
  }
  let has_remainder = if shift >= magnitude.bit_length() {
    !magnitude.is_zero()
  } else {
    quotient.shift_left(shift).compare(magnitude) != 0
  }
  let floor_magnitude = if value.is_negative() && has_remainder {
    quotient.add(BinCoeff::one())
  } else {
    quotient
  }
  let integer = BinFloat::make(
    floor_magnitude,
    0,
    Int::max(1, floor_magnitude.bit_length()),
  )
  Some(if value.is_negative() { integer.neg() } else { integer })
}

///|
fn binary_integer_mod4(value : BinFloat) -> Int? {
  guard value.classify() == FpClass::Finite &&
    (value.is_zero() || value.exponent2() >= 0) else {
    return None
  }
  let magnitude_residue = if value.is_zero() || value.exponent2() >= 2 {
    0
  } else if value.exponent2() == 1 {
    if value.coefficient().test_bit(0) {
      2
    } else {
      0
    }
  } else {
    (if value.coefficient().test_bit(0) { 1 } else { 0 }) +
    (if value.coefficient().test_bit(1) { 2 } else { 0 })
  }
  Some(
    if value.is_negative() && magnitude_residue != 0 {
      4 - magnitude_residue
    } else {
      magnitude_residue
    },
  )
}

///|
fn binary_trigonometric_reduction(
  value : BinFloat,
  half_pi : (BinFloat, BinFloat),
  work_precision : Int,
) -> ((BinFloat, BinFloat), Int)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let input_bounds = (
    value.with_precision(work_precision, RoundingMode::TowardNegative),
    value.with_precision(work_precision, RoundingMode::TowardPositive),
  )
  let quotient = binary_quotient_bounds(input_bounds, half_pi, downward, upward)
  guard quotient is Some((quotient_lower, quotient_upper)) else { return None }
  let half = BinFloat::make(BinCoeff::one(), -1, work_precision)
  let lower_integer = binary_floor_integer(
    quotient_lower.add_ctx(half, downward).0,
  )
  let upper_integer = binary_floor_integer(
    quotient_upper.add_ctx(half, upward).0,
  )
  guard lower_integer is Some(quadrant_integer) &&
    upper_integer is Some(upper_quadrant) &&
    quadrant_integer.compare(upper_quadrant) == 0 else {
    return None
  }
  let quadrant = binary_integer_mod4(quadrant_integer)
  guard quadrant is Some(residue) else { return None }
  let product = binary_product_bounds(
    (quadrant_integer, quadrant_integer),
    half_pi,
    downward,
    upward,
  )
  Some(
    (
      (
        input_bounds.0.sub_ctx(product.1, downward).0,
        input_bounds.1.sub_ctx(product.0, upward).0,
      ),
      residue,
    ),
  )
}

///|
fn binary_trigonometric_bounds(
  value : BinFloat,
  operation : BinaryTrigonometricOperation,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let pi = binary_pi_bounds(work_precision).unwrap()
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let half_pi = (
    pi.0.mul_ctx(BinFloat::make(BinCoeff::one(), -1, work_precision), downward).0,
    pi.1.mul_ctx(BinFloat::make(BinCoeff::one(), -1, work_precision), upward).0,
  )
  let quarter_pi = (
    half_pi.0.mul_ctx(
      BinFloat::make(BinCoeff::one(), -1, work_precision),
      downward,
    ).0,
    half_pi.1.mul_ctx(
      BinFloat::make(BinCoeff::one(), -1, work_precision),
      upward,
    ).0,
  )
  let reduction = binary_trigonometric_reduction(value, half_pi, work_precision)
  guard reduction is Some(((lower, upper), quadrant)) else { return None }
  guard lower.compare(quarter_pi.0.neg()) >= 0 &&
    upper.compare(quarter_pi.1) <= 0 else {
    return None
  }
  binary_reduced_trigonometric_bounds(
    lower, upper, quadrant, operation, work_precision,
  )
}

///|
fn binary_reduced_trigonometric_bounds(
  lower : BinFloat,
  upper : BinFloat,
  quadrant : Int,
  operation : BinaryTrigonometricOperation,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
  let one = BinFloat::one(precision=work_precision)
  guard lower.compare(upper) <= 0 &&
    lower.compare(one.neg()) >= 0 &&
    upper.compare(one) <= 0 else {
    return None
  }
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let sin_lower = binary_sin_cos_series(lower, false, work_precision).unwrap()
  let sin_upper = binary_sin_cos_series(upper, false, work_precision).unwrap()
  let cos_lower = binary_sin_cos_series(lower, true, work_precision).unwrap()
  let cos_upper = binary_sin_cos_series(upper, true, work_precision).unwrap()
  let sin_bounds = (sin_lower.0, sin_upper.1)
  let zero = BinFloat::zero(precision=work_precision)
  let cos_bounds = if lower.compare(zero) <= 0 && upper.compare(zero) >= 0 {
    (
      if cos_lower.0.compare(cos_upper.0) < 0 {
        cos_lower.0
      } else {
        cos_upper.0
      },
      BinFloat::one(precision=work_precision),
    )
  } else if upper.compare(zero) <= 0 {
    (cos_lower.0, cos_upper.1)
  } else {
    (cos_upper.0, cos_lower.1)
  }
  let mapped = match quadrant % 4 {
    0 => (sin_bounds, cos_bounds)
    1 =>
      ((cos_bounds.0, cos_bounds.1), (sin_bounds.1.neg(), sin_bounds.0.neg()))
    2 =>
      (
        (sin_bounds.1.neg(), sin_bounds.0.neg()),
        (cos_bounds.1.neg(), cos_bounds.0.neg()),
      )
    _ =>
      ((cos_bounds.1.neg(), cos_bounds.0.neg()), (sin_bounds.0, sin_bounds.1))
  }
  match operation {
    BinaryTrigonometricOperation::Sin => Some(mapped.0)
    BinaryTrigonometricOperation::Cos => Some(mapped.1)
    BinaryTrigonometricOperation::Tan => {
      guard !(mapped.1.0.compare(BinFloat::zero()) <= 0 &&
        mapped.1.1.compare(BinFloat::zero()) >= 0) else {
        return None
      }
      let candidates = [
        mapped.0.0.div_ctx(mapped.1.0, downward).0,
        mapped.0.0.div_ctx(mapped.1.1, downward).0,
        mapped.0.1.div_ctx(mapped.1.0, downward).0,
        mapped.0.1.div_ctx(mapped.1.1, downward).0,
      ]
      let upper_candidates = [
        mapped.0.0.div_ctx(mapped.1.0, upward).0,
        mapped.0.0.div_ctx(mapped.1.1, upward).0,
        mapped.0.1.div_ctx(mapped.1.0, upward).0,
        mapped.0.1.div_ctx(mapped.1.1, upward).0,
      ]
      let mut result_lower = candidates[0]
      let mut result_upper = upper_candidates[0]
      for candidate in candidates[1:] {
        if candidate.compare(result_lower) < 0 {
          result_lower = candidate
        }
      }
      for candidate in upper_candidates[1:] {
        if candidate.compare(result_upper) > 0 {
          result_upper = candidate
        }
      }
      Some((result_lower, result_upper))
    }
  }
}

///|
fn BinFloat::try_trigonometric_ctx(
  self : BinFloat,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Err(
        @def.ArithmeticError::domain_error("trigonometric input is not finite"),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          if operation == BinaryTrigonometricOperation::Cos {
            BinFloat::one(precision=context.precision)
          } else {
            self.round_ctx(context).0
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let adjusted_exponent = self.exponent2().to_int64() +
        self.coefficient().bit_length().to_int64()
      let required = context.precision.to_int64() +
        Int64::max(0L, adjusted_exponent) +
        96L
      guard required <= 1_000_000L else {
        return Err(
          binary_certification_failure(
            operation.name(),
            @def.CertificationStage::RangeReduction,
            @def.CertificationFailureReason::ResourceLimit,
            context.precision,
            1_000_000,
            0,
          ),
        )
      }
      let mut budget = CertifiedRefinementBudget::new(
        Int::max(required.to_int(), self.precision() + 16),
      )
      let mut certified_range = false
      while budget.available() && budget.precision() <= 1_000_000 {
        match binary_trigonometric_bounds(self, operation, budget.precision()) {
          Some(bounds) => {
            certified_range = true
            let (result, unique, flags) = binary_certified_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(
        @internal.certified_failure(
          operation.name(),
          if certified_range {
            @def.CertificationStage::TargetRounding
          } else {
            @def.CertificationStage::RangeReduction
          },
          if certified_range {
            @def.CertificationFailureReason::RefinementBudgetExhausted
          } else {
            @def.CertificationFailureReason::RangeNotCertified
          },
          context.precision,
          budget,
        ),
      )
    }
  }
}

///|
pub fn BinFloat::try_sin_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Sin, context)
}

///|
pub fn BinFloat::sin_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_sin_ctx(context).unwrap()
}

///|
pub fn BinFloat::sin(self : BinFloat) -> BinFloat {
  self.sin_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_cos_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Cos, context)
}

///|
pub fn BinFloat::cos_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_cos_ctx(context).unwrap()
}

///|
pub fn BinFloat::cos(self : BinFloat) -> BinFloat {
  self.cos_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_tan_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Tan, context)
}

///|
pub fn BinFloat::tan_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_tan_ctx(context).unwrap()
}

///|
pub fn BinFloat::tan(self : BinFloat) -> BinFloat {
  self.tan_ctx(BinaryContext::unbounded(self.precision())).0
}
