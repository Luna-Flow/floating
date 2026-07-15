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
fn decimal_exact_dyadic_endpoint(value : @bin_float.BinFloat) -> Decimal? {
  guard value.classify() == FpClass::Finite else { return None }
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
  let lower = decimal_exact_dyadic_endpoint(interval.lower_bound())
  let upper = decimal_exact_dyadic_endpoint(interval.upper_bound())
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
fn decimal_certified_power_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_binary_result(base, exponent, ctx, "power", fn(
    left,
    right,
  ) {
    left.try_pow_interval(right)
  })
}
