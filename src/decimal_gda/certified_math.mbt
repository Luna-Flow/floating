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
  let decimal_digits = Int::max(digits, target)
  if value.class == FpClass::Finite &&
    !value.negative &&
    adjusted_exponent(value) == 0 &&
    ctx.extended &&
    !ctx.clamp &&
    ctx.precision <= 64 &&
    ctx.e_min <= -999_999 &&
    ctx.e_max >= 999_999 {
    Int::max(80, (decimal_digits * 10 + 2) / 3 + 12)
  } else {
    Int::max(128, decimal_digits * 4 + 64)
  }
}

///|
fn decimal_certified_conservative_work_precision(
  value : Decimal,
  ctx : DecimalContext,
) -> Int {
  let digits = if value.class == FpClass::Finite {
    value.coefficient.digits10()
  } else {
    1
  }
  Int::max(128, Int::max(digits, decimal_math_target_precision(ctx)) * 4 + 64)
}

///|
fn decimal_candidate_work_precision(
  value : Decimal,
  ctx : DecimalContext,
  refinements : Int,
) -> Int {
  let digits = if value.class == FpClass::Finite {
    value.coefficient.digits10()
  } else {
    1
  }
  Int::max(digits, decimal_math_target_precision(ctx)) + 16 + refinements * 8
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
      digits10(magnitude),
    ),
  )
}

///|
fn decimal_certified_target(
  interval : @ball_float.BallFloat,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard !interval.is_empty() else { return None }
  let target_ctx = ctx
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
fn decimal_bounded_binary_interval(
  value : Decimal,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  guard value.class == FpClass::Finite else { return None }
  if value.coefficient.is_zero() {
    let zero = @bin_float.BinFloat::zero(precision~)
    return Some((zero, zero))
  }
  let coefficient = @bin_float.BinCoeff::from_bytes_be(
    value.coefficient.to_bigint().to_octets(),
  )
  let binary_precision = Int::max(precision, coefficient.bit_length() + 8)
  let downward = @bin_float.BinaryContext::unbounded(
    binary_precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    binary_precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let coefficient_value = @bin_float.BinFloat::make(
    coefficient, 0, binary_precision,
  )
  let ten = @bin_float.BinFloat::from_int(10, precision=binary_precision)
  let power_lower = ten.pow_int_ctx(value.exponent10, downward).0
  let power_upper = ten.pow_int_ctx(value.exponent10, upward).0
  let positive_lower = coefficient_value.mul_ctx(power_lower, downward).0
  let positive_upper = coefficient_value.mul_ctx(power_upper, upward).0
  if value.negative {
    Some((positive_upper.neg(), positive_lower.neg()))
  } else {
    Some((positive_lower, positive_upper))
  }
}

///|
fn decimal_exact_midpoint(left : Decimal, right : Decimal) -> Decimal? {
  guard left.class == FpClass::Finite && right.class == FpClass::Finite else {
    return None
  }
  let exact_ctx = decimal_exact_work_context()
  let (sum, sum_flags) = left.add_ctx(right, exact_ctx)
  guard !sum_flags.has_error() && sum.class == FpClass::Finite else {
    return None
  }
  let half = finite_with_exponent_repr(false, gda_coeff_from_int(5), -1, 1)
  let (midpoint, midpoint_flags) = sum.mul_ctx(half, exact_ctx)
  guard !midpoint_flags.has_error() && midpoint.class == FpClass::Finite else {
    return None
  }
  Some(midpoint)
}

///|
fn decimal_certified_half_even_candidate(
  interval : @ball_float.BallFloat,
  candidate : Decimal,
  source : Decimal,
  ctx : DecimalContext,
  work_precision : Int,
) -> (Decimal, DecimalFlags)? {
  let target_ctx = ctx
  let boundary_precision = Int::max(work_precision + 24, 104)
  if candidate.class == FpClass::Infinity {
    let overflow_boundary = decimal_bounded_binary_interval(
      decimal_power_overflow_boundary(target_ctx),
      boundary_precision,
    )
    guard overflow_boundary is Some(overflow_boundary) &&
      interval.lower_bound().compare(overflow_boundary.1) > 0 else {
      return None
    }
    return Some(decimal_overflow_result(false, target_ctx))
  }
  guard candidate.class == FpClass::Finite else { return None }
  let (rounded, rounded_flags0) = decimal_apply_finite_ctx(
    candidate, target_ctx,
  )
  if rounded.class == FpClass::Infinity || rounded_flags0.overflow {
    let overflow_boundary = decimal_bounded_binary_interval(
      decimal_power_overflow_boundary(target_ctx),
      boundary_precision,
    )
    guard overflow_boundary is Some(overflow_boundary) &&
      interval.lower_bound().compare(overflow_boundary.1) > 0 else {
      return None
    }
    return Some(decimal_overflow_result(false, target_ctx))
  }
  guard rounded.class == FpClass::Finite else { return None }
  if rounded.coefficient.is_zero() {
    let zero_boundary_value = decimal_power_zero_boundary(target_ctx)
    guard zero_boundary_value is Some(zero_boundary_value) else { return None }
    let zero_boundary = decimal_bounded_binary_interval(
      zero_boundary_value, boundary_precision,
    )
    guard zero_boundary is Some(zero_boundary) &&
      interval.upper_bound().compare(zero_boundary.0) < 0 else {
      return None
    }
    let clamped = match decimal_power_gda_integer_count(source) {
      Some(count) => count <= -1000
      None => false
    }
    return Some(decimal_exp_underflow_zero_result(target_ctx, clamped))
  }
  let rounding_cell = decimal_power_rounding_cell(
    candidate, rounded, target_ctx,
  )
  guard rounding_cell is Some((lower_boundary_value, upper_boundary_value)) else {
    return None
  }
  let lower_boundary = decimal_bounded_binary_interval(
    lower_boundary_value, boundary_precision,
  )
  let upper_boundary = decimal_bounded_binary_interval(
    upper_boundary_value, boundary_precision,
  )
  guard lower_boundary is Some(lower_boundary) &&
    upper_boundary is Some(upper_boundary) else {
    return None
  }
  guard interval.lower_bound().compare(lower_boundary.1) > 0 &&
    interval.upper_bound().compare(upper_boundary.0) < 0 else {
    return None
  }
  Some((rounded, { ..rounded_flags0, rounded: true, inexact: true }))
}

///|
fn decimal_ln_candidate(value : Decimal, work_precision : Int) -> Decimal {
  let work_ctx = decimal_math_work_ctx(work_precision)
  let constant_scale = work_ctx.precision + 12
  let (_, _, ln10_scaled) = decimal_transcendental_ln_constants(constant_scale)
  _decimal_ln_positive_finite_work_result_with_ln10(
    value, work_ctx, ln10_scaled,
  ).0
}

///|
fn decimal_exp_candidate(value : Decimal, work_precision : Int) -> Decimal {
  let work_ctx = decimal_math_work_ctx(Int::max(work_precision + 24, 96))
  let constant_scale = work_ctx.precision + 12
  let (_, _, ln10_scaled) = decimal_transcendental_ln_constants(constant_scale)
  _decimal_exp_finite_work_result_with_ln10(value, work_ctx, ln10_scaled).0
}

///|
fn decimal_ball_candidate(
  interval : @ball_float.BallFloat,
  ctx : DecimalContext,
) -> Decimal {
  Decimal::from_bin_float(
    interval.midpoint(),
    precision=decimal_math_target_precision(ctx) + 8,
  )
}

///|
priv struct DecimalCertifiedLn10Cache {
  precision : Int
  interval : @ball_float.BallFloat?
}

///|
let decimal_certified_ln10_cache : @ref.Ref[DecimalCertifiedLn10Cache] = @ref.new({
    precision: 0,
    interval: None,
  },
)

///|
fn decimal_certified_ln10_interval(
  precision : Int,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  let cached = decimal_certified_ln10_cache.val
  if cached.precision == precision && cached.interval is Some(interval) {
    return Ok(interval)
  }
  let input = @ball_float.BallFloat::from_int(10, precision~)
  input
  .try_ln_interval()
  .map(fn(interval) {
    decimal_certified_ln10_cache.val = { precision, interval: Some(interval) }
    interval
  })
}

///|
fn decimal_certified_finite_candidate(
  interval : @ball_float.BallFloat,
  candidate : Decimal,
  ctx : DecimalContext,
  work_precision : Int,
) -> (Decimal, DecimalFlags)? {
  guard candidate.class == FpClass::Finite else { return None }
  let (rounded, rounded_flags) = decimal_apply_finite_ctx(candidate, ctx)
  guard rounded.class == FpClass::Finite && !rounded_flags.overflow else {
    return None
  }
  let rounding_cell = decimal_power_rounding_cell(candidate, rounded, ctx)
  guard rounding_cell is Some((lower_value, upper_value)) else { return None }
  let boundary_precision = Int::max(work_precision + 24, 104)
  let lower = decimal_bounded_binary_interval(lower_value, boundary_precision)
  let upper = decimal_bounded_binary_interval(upper_value, boundary_precision)
  guard lower is Some(lower) && upper is Some(upper) else { return None }
  guard interval.lower_bound().compare(lower.1) > 0 &&
    interval.upper_bound().compare(upper.0) < 0 else {
    return None
  }
  Some(
    (
      rounded,
      {
        ..rounded_flags,
        rounded: true,
        inexact: true,
        underflow: rounded_flags.underflow || rounded_flags.subnormal,
      },
    ),
  )
}

///|
fn decimal_same_quantum_adjacent(left : Decimal, right : Decimal) -> Bool {
  guard left.class == FpClass::Finite &&
    right.class == FpClass::Finite &&
    left.negative == right.negative &&
    left.exponent10 == right.exponent10 else {
    return false
  }
  let comparison = gda_coeff_compare_repr(left.coefficient, right.coefficient)
  if comparison > 0 {
    gda_coeff_compare_repr(
      gda_coeff_magnitude_sub_unit(left.coefficient, 1),
      right.coefficient,
    ) ==
    0
  } else if comparison < 0 {
    gda_coeff_compare_repr(
      gda_coeff_magnitude_sub_unit(right.coefficient, 1),
      left.coefficient,
    ) ==
    0
  } else {
    false
  }
}

///|
fn decimal_ln_subset_result(
  value : Decimal,
  ctx : DecimalContext,
  certified : (Decimal, DecimalFlags),
) -> (Decimal, DecimalFlags) {
  guard !ctx.extended && certified.0.class == FpClass::Finite else {
    return certified
  }
  let target_precision = decimal_math_target_precision(ctx)
  let classic_precision = Int::max(
      value.coefficient.digits10(),
      Int::max(target_precision, 7),
    ) +
    8
  let candidate = decimal_ln_candidate(value, classic_precision)
  let check = decimal_ln_candidate(value, classic_precision + 2)
  guard candidate.class == FpClass::Finite && check.class == FpClass::Finite else {
    return certified
  }
  let classic = decimal_apply_finite_ctx(candidate, ctx).0
  let checked = decimal_apply_finite_ctx(check, ctx).0
  guard classic.compare_total(checked) == 0 &&
    decimal_same_quantum_adjacent(classic, certified.0) &&
    gda_coeff_compare_repr(classic.coefficient, certified.0.coefficient) > 0 else {
    return certified
  }
  (classic, certified.1)
}

///|
fn decimal_power_candidate(
  base : Decimal,
  exponent : Decimal,
  work_precision : Int,
) -> Decimal {
  let work_ctx = decimal_math_work_ctx(Int::max(work_precision + 24, 96))
  let constant_scale = work_ctx.precision + 12
  let (_, _, ln10_scaled) = decimal_transcendental_ln_constants(constant_scale)
  let (log_base, _) = _decimal_ln_positive_finite_work_result_with_ln10(
    base, work_ctx, ln10_scaled,
  )
  guard log_base.class == FpClass::Finite else { return log_base }
  let (scaled, _) = decimal_mul_finite_work(log_base, exponent, work_ctx)
  guard scaled.class == FpClass::Finite else { return scaled }
  _decimal_exp_finite_work_result_with_ln10(scaled, work_ctx, ln10_scaled).0
}

///|
fn decimal_bounded_ball(
  value : Decimal,
  precision : Int,
) -> @ball_float.BallFloat? {
  match decimal_bounded_binary_interval(value, precision) {
    Some((lower, upper)) =>
      Some(@ball_float.BallFloat::from_bounds(lower, upper, precision~))
    None => None
  }
}

///|
fn decimal_power_overflow_midpoint(ctx : DecimalContext) -> Decimal {
  let precision = decimal_math_target_precision(ctx)
  let twice_power = gda_coeff_multiply_by_unit_repr(
    gda_coeff_power10_repr(precision),
    2,
  )
  let midpoint_coefficient = gda_coeff_multiply_by_unit_repr(
    gda_coeff_magnitude_sub_unit(twice_power, 1),
    5,
  )
  finite_with_exponent_repr(
    false,
    midpoint_coefficient,
    ctx.e_max - precision,
    midpoint_coefficient.digits10(),
  )
}

///|
fn decimal_power_zero_midpoint(ctx : DecimalContext) -> Decimal {
  finite_with_exponent_repr(false, gda_coeff_from_int(5), etiny(ctx) - 1, 1)
}

///|
fn decimal_power_overflow_boundary(ctx : DecimalContext) -> Decimal {
  match ctx.decimal_rounding {
    HalfEven | HalfUp | HalfDown => decimal_power_overflow_midpoint(ctx)
    Down | Ceiling | Floor | Up | ZeroFiveUp => max_finite_for(ctx, false)
  }
}

///|
fn decimal_power_zero_boundary(ctx : DecimalContext) -> Decimal? {
  match ctx.decimal_rounding {
    HalfEven | HalfUp | HalfDown => Some(decimal_power_zero_midpoint(ctx))
    Down | Floor =>
      Some(
        decimal_next(
          finite_with_exponent_repr(
            false,
            gda_coeff_zero(),
            etiny(ctx),
            decimal_math_target_precision(ctx),
          ),
          ctx,
          true,
        ).0,
      )
    Ceiling | Up | ZeroFiveUp => None
  }
}

///|
fn decimal_power_rounding_cell(
  candidate : Decimal,
  rounded : Decimal,
  ctx : DecimalContext,
) -> (Decimal, Decimal)? {
  let previous = decimal_next(rounded, ctx, false).0
  let following = decimal_next(rounded, ctx, true).0
  match ctx.decimal_rounding {
    HalfEven | HalfUp | HalfDown => {
      let lower = decimal_exact_midpoint(previous, rounded)
      let upper = decimal_exact_midpoint(rounded, following)
      guard lower is Some(lower) && upper is Some(upper) else { return None }
      Some((lower, upper))
    }
    Floor => Some((rounded, following))
    Ceiling => Some((previous, rounded))
    Down =>
      if rounded.negative {
        Some((previous, rounded))
      } else {
        Some((rounded, following))
      }
    Up =>
      if rounded.negative {
        Some((rounded, following))
      } else {
        Some((previous, rounded))
      }
    ZeroFiveUp =>
      if candidate.compare(rounded) >= 0 {
        Some((rounded, following))
      } else {
        Some((previous, rounded))
      }
  }
}

///|
fn decimal_certified_power_log_candidate(
  base : Decimal,
  exponent : Decimal,
  candidate : Decimal,
  ctx : DecimalContext,
  work_precision : Int,
) -> Result[(Decimal, DecimalFlags)?, @def.ArithmeticError] {
  let target_ctx = ctx
  let boundary_precision = Int::max(work_precision + 24, 104)
  let base_ball = decimal_bounded_ball(base, boundary_precision)
  let exponent_ball = decimal_bounded_ball(exponent, boundary_precision)
  guard base_ball is Some(base_ball) && exponent_ball is Some(exponent_ball) else {
    return Ok(None)
  }
  let log_base = match base_ball.try_ln_interval() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let log_power = log_base.mul(exponent_ball)
  guard !log_power.is_empty() else { return Ok(None) }
  if candidate.class == FpClass::Infinity {
    let boundary = decimal_bounded_ball(
      decimal_power_overflow_boundary(target_ctx),
      boundary_precision,
    )
    guard boundary is Some(boundary) else { return Ok(None) }
    let log_boundary = match boundary.try_ln_interval() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if log_power.lower_bound().compare(log_boundary.upper_bound()) > 0 {
      return Ok(Some(decimal_overflow_result(false, target_ctx)))
    }
    return Ok(None)
  }
  guard candidate.class == FpClass::Finite else { return Ok(None) }
  let (rounded, rounded_flags0) = decimal_apply_finite_ctx(
    candidate, target_ctx,
  )
  if rounded.class == FpClass::Infinity {
    let boundary = decimal_bounded_ball(
      decimal_power_overflow_boundary(target_ctx),
      boundary_precision,
    )
    guard boundary is Some(boundary) else { return Ok(None) }
    let log_boundary = match boundary.try_ln_interval() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if log_power.lower_bound().compare(log_boundary.upper_bound()) > 0 {
      return Ok(Some(decimal_overflow_result(false, target_ctx)))
    }
    return Ok(None)
  }
  guard rounded.class == FpClass::Finite else { return Ok(None) }
  if rounded_flags0.overflow {
    let boundary = decimal_bounded_ball(
      decimal_power_overflow_boundary(target_ctx),
      boundary_precision,
    )
    guard boundary is Some(boundary) else { return Ok(None) }
    let log_boundary = match boundary.try_ln_interval() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if log_power.lower_bound().compare(log_boundary.upper_bound()) > 0 {
      return Ok(Some(decimal_overflow_result(false, target_ctx)))
    }
    return Ok(None)
  }
  if rounded.coefficient.is_zero() {
    let zero_boundary = decimal_power_zero_boundary(target_ctx)
    guard zero_boundary is Some(zero_boundary) else { return Ok(None) }
    let boundary = decimal_bounded_ball(zero_boundary, boundary_precision)
    guard boundary is Some(boundary) else { return Ok(None) }
    let log_boundary = match boundary.try_ln_interval() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if log_power.upper_bound().compare(log_boundary.lower_bound()) < 0 {
      return Ok(Some(decimal_power_underflow_zero_result(false, target_ctx)))
    }
    return Ok(None)
  }
  let rounding_cell = decimal_power_rounding_cell(
    candidate, rounded, target_ctx,
  )
  guard rounding_cell is Some((lower_boundary, upper_boundary)) &&
    !lower_boundary.negative &&
    !lower_boundary.coefficient.is_zero() else {
    return Ok(None)
  }
  let lower_ball = decimal_bounded_ball(lower_boundary, boundary_precision)
  let upper_ball = decimal_bounded_ball(upper_boundary, boundary_precision)
  guard lower_ball is Some(lower_ball) && upper_ball is Some(upper_ball) else {
    return Ok(None)
  }
  let log_lower = match lower_ball.try_ln_interval() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let log_upper = match upper_ball.try_ln_interval() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  guard !log_lower.is_empty() && !log_upper.is_empty() else { return Ok(None) }
  guard log_power.lower_bound().compare(log_lower.upper_bound()) > 0 &&
    log_power.upper_bound().compare(log_upper.lower_bound()) < 0 else {
    return Ok(None)
  }
  Ok(Some((rounded, { ..rounded_flags0, rounded: true, inexact: true })))
}

///|
fn decimal_certified_unary_candidate_result(
  value : Decimal,
  ctx : DecimalContext,
  operation : String,
  evaluate : (@ball_float.BallFloat) -> Result[
    @ball_float.BallFloat,
    @def.ArithmeticError,
  ],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let initial_precision = decimal_certified_work_precision(value, ctx)
  let conservative_precision = decimal_certified_conservative_work_precision(
    value, ctx,
  )
  let mut budget = CertifiedRefinementBudget::new(initial_precision)
  let mut fast_attempt = initial_precision < conservative_precision
  while budget.available() {
    let input = decimal_to_certified_ball(value, budget.precision())
    match evaluate(input) {
      Ok(interval) =>
        if fast_attempt {
          let approximation = decimal_ball_candidate(interval, ctx)
          match
            decimal_certified_finite_candidate(
              interval,
              approximation,
              ctx,
              budget.precision(),
            ) {
            Some(result) => return Ok(result)
            None => {
              budget = CertifiedRefinementBudget::new(conservative_precision)
              fast_attempt = false
            }
          }
        } else {
          match decimal_certified_target(interval, ctx) {
            Some(result) => return Ok(result)
            None => budget = budget.next()
          }
        }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          if fast_attempt {
            budget = CertifiedRefinementBudget::new(conservative_precision)
            fast_attempt = false
          } else {
            budget = budget.next()
          }
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure(operation, ctx, budget))
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
    let guard_coefficient = gda_coeff_multiply_repr(
      gda_coeff_from_nonnegative_int(abs_int(etiny(ctx) - 1)),
      gda_coeff_from_int(3),
    )
    let guard_value = finite_with_exponent_repr(
      true,
      guard_coefficient,
      0,
      guard_coefficient.digits10(),
    )
    if value.compare(guard_value) <= 0 {
      let clamped = match decimal_power_gda_integer_count(value) {
        Some(count) => count <= -1000
        None => false
      }
      return Some(decimal_exp_underflow_zero_result(ctx, clamped))
    }
  }
  if !value.negative && ctx.e_max >= 0 {
    let guard_coefficient = gda_coeff_multiply_repr(
      gda_coeff_from_nonnegative_int(ctx.e_max + 1),
      gda_coeff_from_int(3),
    )
    let guard_value = finite_with_exponent_repr(
      false,
      guard_coefficient,
      0,
      guard_coefficient.digits10(),
    )
    if value.compare(guard_value) >= 0 {
      return Some(decimal_overflow_result(false, decimal_math_result_ctx(ctx)))
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
  let initial_precision = decimal_certified_work_precision(value, ctx)
  let conservative_precision = decimal_certified_conservative_work_precision(
    value, ctx,
  )
  let mut budget = CertifiedRefinementBudget::new(initial_precision)
  let mut fast_attempt = initial_precision < conservative_precision
  while budget.available() {
    let input = decimal_to_certified_ball(value, budget.precision())
    match input.try_exp_interval() {
      Ok(interval) => {
        let candidate = if fast_attempt {
          decimal_ball_candidate(interval, ctx)
        } else {
          decimal_exp_candidate(value, budget.precision())
        }
        match
          decimal_certified_half_even_candidate(
            interval,
            candidate,
            value,
            ctx,
            budget.precision(),
          ) {
          Some(result) => return Ok(result)
          None =>
            if fast_attempt {
              budget = CertifiedRefinementBudget::new(conservative_precision)
              fast_attempt = false
            } else {
              match decimal_certified_target(interval, ctx) {
                Some(result) => return Ok(result)
                None => budget = budget.next()
              }
            }
        }
      }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          if fast_attempt {
            budget = CertifiedRefinementBudget::new(conservative_precision)
            fast_attempt = false
          } else {
            budget = budget.next()
          }
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure("exp", ctx, budget))
}

///|
fn decimal_certified_ln_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_unary_candidate_result(value, ctx, "ln", fn(input) {
    input.try_ln_interval()
  }).map(fn(result) { decimal_ln_subset_result(value, ctx, result) })
}

///|
fn decimal_certified_log10_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_unary_candidate_result(value, ctx, "log10", fn(input) {
    input
    .try_ln_interval()
    .bind(fn(natural_log) {
      decimal_certified_ln10_interval(input.lower_bound().precision()).map(fn(
        ln10,
      ) {
        natural_log.div(ln10)
      })
    })
  })
}

///|
fn decimal_certified_power_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    Int::max(
      decimal_certified_conservative_work_precision(base, ctx),
      decimal_certified_conservative_work_precision(exponent, ctx),
    ),
  )
  while budget.available() {
    let candidate = decimal_power_candidate(
      base,
      exponent,
      Int::max(
        decimal_candidate_work_precision(base, ctx, budget.refinements()),
        decimal_candidate_work_precision(exponent, ctx, budget.refinements()),
      ),
    )
    match
      decimal_certified_power_log_candidate(
        base,
        exponent,
        candidate,
        ctx,
        budget.precision(),
      ) {
      Ok(Some(result)) => return Ok(result)
      Ok(None) =>
        if budget.refinements() < 3 {
          budget = budget.next()
          continue
        }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) &&
          budget.refinements() < 3 {
          budget = budget.next()
          continue
        } else if error.certification_failure_detail() is None {
          return Err(error)
        }
    }
    let left = decimal_to_certified_ball(base, budget.precision())
    let right = decimal_to_certified_ball(exponent, budget.precision())
    match left.try_pow_interval(right) {
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
  Err(decimal_certified_failure("power", ctx, budget))
}
