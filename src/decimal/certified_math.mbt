///|
fn decimal_certified_work_precision(
  value : Decimal,
  ctx : DecimalContext,
) -> Int {
  let digits = if value.class == FpClass::Finite {
    value.coefficient.digits10()
  } else {
    1
  }
  let target = decimal_math_target_precision(ctx)
  Int::max(128, Int::max(digits, target) * 4 + 64)
}

///|
fn decimal_to_certified_ball(
  value : Decimal,
  precision : Int,
) -> @ball_float.BallFloat {
  let lower = value.to_bin_float(precision~, mode=RoundingMode::TowardNegative)
  let upper = value.to_bin_float(precision~, mode=RoundingMode::TowardPositive)
  @ball_float.BallFloat::from_bounds(lower, upper, precision~)
}

///|
fn decimal_certified_failure(
  operation : String,
  ctx : DecimalContext,
  budget : CertifiedRefinementBudget,
) -> @def.ArithmeticError {
  @internal.certified_failure(
    operation,
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    decimal_math_target_precision(ctx),
    budget,
  )
}

///|
/// 3.3220 > log2(10): bounds a binary exponent against a decimal one.
let decimal_log2_10_upper_ppm : Int64 = 3322000L

///|
/// A binary endpoint far outside the decimal range would expand to an exact
/// decimal with up to hundreds of millions of digits. Every value beyond
/// `10^(e_max + 2)` overflows, and every nonzero value below `10^(etiny - 2)`
/// is under half the smallest subnormal, so such endpoints are replaced by a
/// representative of the same sign that rounds to the same result and flags.
fn decimal_out_of_range_endpoint(
  value : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> Decimal? {
  if value.is_zero() {
    return None
  }
  // |value| lies in [2^top, 2^(top + 1)).
  let top = value.exponent2().to_int64() +
    (value.coefficient().bit_length() - 1).to_int64()
  let huge = ctx.e_max.to_int64() + 2L
  if top * 1000000L >= huge * decimal_log2_10_upper_ppm {
    return Some(
      finite_with_exponent(
        value.is_negative(),
        BigInt::from_int(1),
        huge.to_int(),
        1,
      ),
    )
  }
  let tiny = etiny(ctx).to_int64() - 2L
  if (top + 1L) * 1000000L <= tiny * decimal_log2_10_upper_ppm {
    return Some(
      finite_with_exponent(
        value.is_negative(),
        BigInt::from_int(1),
        tiny.to_int(),
        1,
      ),
    )
  }
  None
}

///|
fn decimal_exact_dyadic_endpoint(
  value : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> Decimal? {
  // Rounding is monotone, so an infinite endpoint can stand for any value
  // beyond the range: the enclosure certifies only if the finite endpoint
  // overflows in the same direction.
  if value.classify() == FpClass::Infinity {
    return Some(
      finite_with_exponent(
        value.is_negative(),
        BigInt::from_int(1),
        ctx.e_max + 2,
        1,
      ),
    )
  }
  guard value.classify() == FpClass::Finite else { return None }
  match decimal_out_of_range_endpoint(value, ctx) {
    Some(representative) => return Some(representative)
    None => ()
  }
  if value.is_zero() {
    return Some(
      if value.is_negative_zero() {
        Decimal::negative_zero(precision=1)
      } else {
        Decimal::zero(precision=1)
      },
    )
  }
  let coefficient = BigInt::from_octets(value.coefficient().to_bytes_be())
  let (magnitude, exponent10) = if value.exponent2() >= 0 {
    (coefficient << value.exponent2(), 0)
  } else {
    let shift = -value.exponent2()
    (coefficient * pow5(shift), -shift)
  }
  Some(
    finite_with_exponent(
      value.is_negative(),
      magnitude,
      exponent10,
      magnitude.to_string().length(),
    ),
  )
}

///|
fn decimal_certified_target(
  interval : @ball_float.BallFloat,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard !interval.is_empty() else { return None }
  let target_ctx = decimal_math_result_ctx(ctx)
  let lower = decimal_exact_dyadic_endpoint(interval.lower_bound(), target_ctx)
  let upper = decimal_exact_dyadic_endpoint(interval.upper_bound(), target_ctx)
  guard lower is Some(lower) && upper is Some(upper) else { return None }
  let lower_result = decimal_apply_finite_ctx(lower, target_ctx)
  let upper_result = decimal_apply_finite_ctx(upper, target_ctx)
  if lower_result.0.compare_total(upper_result.0) == 0 &&
    lower_result.1 == upper_result.1 {
    Some(lower_result)
  } else {
    None
  }
}

///|
fn decimal_certified_unary_result(
  value : Decimal,
  ctx : DecimalContext,
  operation : String,
  evaluate : (@ball_float.BallFloat) -> Result[
    @ball_float.BallFloat,
    @def.ArithmeticError,
  ],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    decimal_certified_work_precision(value, ctx),
  )
  while budget.available() {
    let input = decimal_to_certified_ball(value, budget.precision())
    match evaluate(input) {
      Ok(interval) =>
        match decimal_certified_target(interval, ctx) {
          Some(result) => return Ok(result)
          None => budget = budget.next()
        }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          budget = budget.next()
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure(operation, ctx, budget))
}

///|
fn decimal_certified_binary_result(
  left : Decimal,
  right : Decimal,
  ctx : DecimalContext,
  operation : String,
  evaluate : (@ball_float.BallFloat, @ball_float.BallFloat) -> Result[
    @ball_float.BallFloat,
    @def.ArithmeticError,
  ],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    Int::max(
      decimal_certified_work_precision(left, ctx),
      decimal_certified_work_precision(right, ctx),
    ),
  )
  while budget.available() {
    let left_interval = decimal_to_certified_ball(left, budget.precision())
    let right_interval = decimal_to_certified_ball(right, budget.precision())
    match evaluate(left_interval, right_interval) {
      Ok(interval) =>
        match decimal_certified_target(interval, ctx) {
          Some(result) => return Ok(result)
          None => budget = budget.next()
        }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          budget = budget.next()
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure(operation, ctx, budget))
}

///|
fn decimal_certified_exp_minimum_result(
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(dec_coeff_from_int(1), ctx)
  let minimum_exponent = etiny(ctx)
  let tiny = tiny_for_underflow(
    ctx,
    (minimum_exponent - 1).to_int64(),
    minimum_exponent.to_int64(),
  )
  (
    finite_with_exponent_repr(
      false,
      dec_coeff_from_int(1),
      minimum_exponent,
      precision,
    ),
    {
      ..DecimalFlags::new(),
      rounded: true,
      inexact: true,
      underflow: tiny,
      subnormal: tiny,
    },
  )
}

///|
fn decimal_certified_exp_coarse_extreme_result(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  if value.negative && etiny(ctx) <= 0 {
    let guard_coefficient = dec_coeff_multiply_repr(
      dec_coeff_from_nonnegative_int(abs_int(etiny(ctx) - 1)),
      dec_coeff_from_int(3),
    )
    let guard_value = finite_with_exponent_repr(
      true,
      guard_coefficient,
      0,
      guard_coefficient.digits10(),
    )
    if value.compare(guard_value) <= 0 {
      return Some(
        match ctx.decimal_rounding {
          Ceiling | Up | ZeroFiveUp => decimal_certified_exp_minimum_result(ctx)
          Down | Floor | HalfEven | HalfUp | HalfDown => {
            let clamped = match decimal_power_gda_integer_count(value) {
              Some(count) => count <= -1000
              None => false
            }
            decimal_exp_underflow_zero_result(ctx, clamped)
          }
        },
      )
    }
  }
  if !value.negative && ctx.e_max >= 0 {
    let guard_coefficient = dec_coeff_multiply_repr(
      dec_coeff_from_nonnegative_int(ctx.e_max + 1),
      dec_coeff_from_int(3),
    )
    let guard_value = finite_with_exponent_repr(
      false,
      guard_coefficient,
      0,
      guard_coefficient.digits10(),
    )
    if value.compare(guard_value) >= 0 {
      return Some(decimal_overflow_result(false, ctx))
    }
  }
  None
}

///|
fn decimal_certified_exp_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_certified_exp_coarse_extreme_result(value, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  decimal_certified_unary_result(value, ctx, "exp", fn(input) {
    input.try_exp_interval()
  })
}

///|
fn decimal_certified_ln_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_unary_result(value, ctx, "ln", fn(input) {
    input.try_ln_interval()
  })
}

///|
fn decimal_certified_log10_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_unary_result(value, ctx, "log10", fn(input) {
    input.try_log10_interval()
  })
}

///|
/// Decides `base^exponent` for a positive base when the result is certainly
/// beyond `10^(e_max + 2)` or below `10^(etiny - 2)`. Such results have
/// enclosures like `[0, tiny]` whose endpoints round with different flags, so
/// the certified loop could never agree on them.
fn decimal_power_out_of_range(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite &&
    exponent.class == FpClass::Finite &&
    !base.negative &&
    !base.coefficient.is_zero() &&
    !exponent.coefficient.is_zero() else {
    return None
  }
  let huge = ctx.e_max.to_int64() + 2L
  let tiny = etiny(ctx).to_int64() - 2L
  // |log10 base| <= |adjusted(base)| + 1 and |exponent| < 10^(adjusted + 1);
  // with a factor-of-two margin most calls stop here.
  let base_adjusted = adjusted_exponent(base).to_double().abs() + 1.0
  let exponent_adjusted = adjusted_exponent(exponent)
  if exponent_adjusted < 300 {
    let reach = base_adjusted *
      @math.pow(10.0, (exponent_adjusted + 1).to_double())
    let limit = Int64::min(huge, -tiny).to_double()
    if reach * 2.0 < limit {
      return None
    }
  }
  let work = 128
  let down = @bin_float.BinaryContext::unbounded(
    work,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::unbounded(
    work,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let base_low = base.to_bin_float(
    precision=work,
    mode=RoundingMode::TowardNegative,
  )
  let base_high = base.to_bin_float(
    precision=work,
    mode=RoundingMode::TowardPositive,
  )
  guard !base_low.is_zero() &&
    base_low.try_log2_ctx(down) is Ok((log_low, _)) &&
    base_high.try_log2_ctx(up) is Ok((log_high, _)) else {
    return None
  }
  let exponent_low = exponent.to_bin_float(
    precision=work,
    mode=RoundingMode::TowardNegative,
  )
  let exponent_high = exponent.to_bin_float(
    precision=work,
    mode=RoundingMode::TowardPositive,
  )
  let lows = [
    log_low.mul_ctx(exponent_low, down).0,
    log_low.mul_ctx(exponent_high, down).0,
    log_high.mul_ctx(exponent_low, down).0,
    log_high.mul_ctx(exponent_high, down).0,
  ]
  let highs = [
    log_low.mul_ctx(exponent_low, up).0,
    log_low.mul_ctx(exponent_high, up).0,
    log_high.mul_ctx(exponent_low, up).0,
    log_high.mul_ctx(exponent_high, up).0,
  ]
  let mut result_low = lows[0]
  let mut result_high = highs[0]
  for value in lows {
    if value.compare(result_low) < 0 {
      result_low = value
    }
  }
  for value in highs {
    if value.compare(result_high) > 0 {
      result_high = value
    }
  }
  // log2(10) < 3.322, so these bounds are conservative on both sides.
  let overflow_log2 = (huge * 3322L + 999L) / 1000L
  let tiny_log2 = (tiny * 3322L - 999L) / 1000L
  let one = BigInt::from_int(1)
  if result_low.compare(
      @bin_float.BinFloat::from_int(overflow_log2.to_int(), precision=work),
    ) >=
    0 {
    return Some(
      decimal_apply_finite_ctx(
        finite_with_exponent(false, one, huge.to_int(), 1),
        decimal_math_result_ctx(ctx),
      ),
    )
  }
  if result_high.compare(
      @bin_float.BinFloat::from_int(tiny_log2.to_int(), precision=work),
    ) <=
    0 {
    return Some(
      decimal_apply_finite_ctx(
        finite_with_exponent(false, one, tiny.to_int(), 1),
        decimal_math_result_ctx(ctx),
      ),
    )
  }
  None
}

///|
fn decimal_certified_power_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_power_out_of_range(base, exponent, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  decimal_certified_binary_result(base, exponent, ctx, "power", fn(
    left,
    right,
  ) {
    left.try_pow_interval(right)
  })
}
