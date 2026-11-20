///|
fn decimal_certified_work_precision(
  value : Decimal,
  ctx : DecimalContext,
) -> Int32 {
  let digits = if value.class == FpClass::Finite {
    value.coefficient.digits10()
  } else {
    1
  }
  let target = decimal_math_target_precision(ctx)
  let need = Int32::max(digits, target)
  // `need` decimal digits are `need log2 10 < 3.3219281 need` bits; 31 bits of
  // guard cover the loss of one evaluation. The schedule grows the precision by
  // a factor of 1.5 when an enclosure does not decide, so a start that is too low
  // costs an attempt, not a result: the results are those of correct rounding at
  // any starting precision.
  Int32::max(64, (need.to_int64() * 3_321_929L / 1_000_000L).to_int() + 31)
}

///|
fn decimal_to_certified_ball(
  value : Decimal,
  precision : Int32,
) -> @ball_float.BallFloat {
  let (lower, upper) = value.to_bin_float_bounds(precision)
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
        decimal_int_from_int64_clamped(ctx.e_max.to_int64() + 2L),
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
      digits10(magnitude),
    ),
  )
}

///|
/// Truncates `magnitude * 10^exponent10` to at most `digits` digits, towards
/// zero, or away from zero when `up` is set. The result brackets the input on
/// the chosen side.
fn decimal_directed_trim(
  magnitude : BigInt,
  exponent10 : Int64,
  digits : Int32,
  up : Bool,
) -> (BigInt, Int64) {
  let present = digits10(magnitude)
  if present <= digits {
    return (magnitude, exponent10)
  }
  let drop = present - digits
  let divisor = pow10(drop)
  let mut quotient = magnitude / divisor
  if up && !(magnitude % divisor).is_zero() {
    quotient = quotient + BigInt::from_int(1)
  }
  (quotient, exponent10 + drop.to_int64())
}

///|
/// `base^count` as a `digits`-digit decimal that is a lower bound (or, with
/// `up`, an upper bound) of the exact power, by binary powering with a directed
/// trim after every product: O(log count) products of `digits`-digit numbers.
fn decimal_directed_power(
  base : Int32,
  count : Int32,
  digits : Int32,
  up : Bool,
) -> (BigInt, Int64) {
  let mut result = (BigInt::from_int(1), 0L)
  let mut bit = 30
  while bit >= 0 && count >> bit == 0 {
    bit = bit - 1
  }
  while bit >= 0 {
    let squared = decimal_directed_trim(
      result.0 * result.0,
      result.1 + result.1,
      digits,
      up,
    )
    result = squared
    if ((count >> bit) & 1) == 1 {
      result = decimal_directed_trim(
        result.0 * BigInt::from_int(base),
        result.1,
        digits,
        up,
      )
    }
    bit = bit - 1
  }
  result
}

///|
/// Like `decimal_exact_dyadic_endpoint`, but a finite in-range endpoint is
/// rounded outward (`upper`: up, otherwise down) to about `digits` digits, so
/// the cost does not depend on the size of its binary exponent. Special,
/// zero and out-of-range endpoints are converted as before.
fn decimal_outward_dyadic_endpoint(
  value : @bin_float.BinFloat,
  ctx : DecimalContext,
  digits : Int32,
  upper : Bool,
) -> Decimal? {
  if value.classify() != FpClass::Finite ||
    value.is_zero() ||
    decimal_out_of_range_endpoint(value, ctx) is Some(_) {
    return decimal_exact_dyadic_endpoint(value, ctx)
  }
  // Magnitude direction: the upper endpoint grows away from zero when positive,
  // the lower one when negative.
  let up = upper != value.is_negative()
  let coefficient = BigInt::from_octets(value.coefficient().to_bytes_be())
  let exponent2 = value.exponent2()
  // Four guard digits keep the accumulated trimming error far below `digits`.
  let work = digits + 4
  let (magnitude, exponent10) = if exponent2 >= 0 {
    let (factor, factor_exponent) = decimal_directed_power(
      2, exponent2, work, up,
    )
    (coefficient * factor, factor_exponent)
  } else {
    let (factor, factor_exponent) = decimal_directed_power(
      5,
      -exponent2,
      work,
      up,
    )
    (coefficient * factor, factor_exponent - (-exponent2).to_int64())
  }
  let (magnitude, exponent10) = decimal_directed_trim(
    magnitude, exponent10, digits, up,
  )
  guard exponent10 >= -2147483647L && exponent10 <= 2147483647L else {
    return decimal_exact_dyadic_endpoint(value, ctx)
  }
  Some(
    finite_with_exponent(
      value.is_negative(),
      magnitude,
      exponent10.to_int(),
      digits10(magnitude),
    ),
  )
}

///|
/// The endpoints of a non-empty enclosure as decimals for the rounding
/// comparison: exact for a degenerate (binary-exact) interval, otherwise
/// rounded outward (the lower down, the upper up) to about `digits` digits,
/// `digits` following the width of the binary coefficients, so a refined
/// interval is never widened beyond about one binary unit in its last place
/// and the cost does not depend on the size of the binary exponents. Rounding
/// the endpoints outward keeps the enclosure, and so its rounding to the
/// context, sound by monotonicity. `ctx` decides which endpoints are out of
/// range and replaced by representatives.
fn decimal_certified_endpoints(
  interval : @ball_float.BallFloat,
  ctx : DecimalContext,
) -> (Decimal?, Decimal?) {
  let lower_bound = interval.lower_bound()
  let upper_bound = interval.upper_bound()
  if lower_bound == upper_bound {
    // A degenerate (binary-exact) interval stays exact: rounding it outward
    // could only lose a certification.
    return (
      decimal_exact_dyadic_endpoint(lower_bound, ctx),
      decimal_exact_dyadic_endpoint(upper_bound, ctx),
    )
  }
  let bits = Int32::max(
    lower_bound.coefficient().bit_length(),
    upper_bound.coefficient().bit_length(),
  )
  let digits = Int32::max(
    decimal_math_target_precision(ctx) + 12,
    bits * 3 / 10 + 4,
  )
  (
    decimal_outward_dyadic_endpoint(lower_bound, ctx, digits, false),
    decimal_outward_dyadic_endpoint(upper_bound, ctx, digits, true),
  )
}

///|
fn decimal_certified_target(
  interval : @ball_float.BallFloat,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard !interval.is_empty() else { return None }
  let target_ctx = decimal_math_result_ctx(ctx)
  let (lower, upper) = decimal_certified_endpoints(interval, target_ctx)
  guard lower is Some(lower) && upper is Some(upper) else { return None }
  let lower_result = decimal_apply_finite_ctx(lower, target_ctx)
  let upper_result = decimal_apply_finite_ctx(upper, target_ctx)
  if lower_result.0.total_order_compare(upper_result.0) == 0 &&
    lower_result.1 == upper_result.1 {
    Some(lower_result)
  } else {
    None
  }
}

///|
/// Rounds a proven one-sided enclosure around an exact decimal anchor. Both
/// rounded endpoints lie strictly on the known side of the anchor, which
/// matters for directed rounding at the anchor itself.
fn decimal_tiny_argument_result(
  anchor : Decimal,
  above : Bool,
  error_exponent : Int64,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 &&
    anchor.class == FpClass::Finite &&
    !anchor.coefficient.is_zero() else {
    return None
  }
  let anchor_adjusted = adjusted_exponent(anchor).to_int64()
  let precision = ctx.precision.to_int64()
  guard error_exponent < anchor_adjusted - precision - 3L else { return None }
  let endpoint_exponent = Int64::max(
    error_exponent,
    anchor_adjusted - precision - 8L,
  )
  guard endpoint_exponent >= -2147483647L && endpoint_exponent <= 2147483647L else {
    return None
  }
  let offset = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(1),
    endpoint_exponent.to_int(),
    1,
  )
  let inner_exponent = endpoint_exponent - 4L
  guard inner_exponent >= -2147483647L else { return None }
  let inner_offset = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(1),
    inner_exponent.to_int(),
    1,
  )
  let (lower, upper) = if above {
    (
      anchor.add_ctx(inner_offset, decimal_exact_work_context()).0,
      anchor.add_ctx(offset, decimal_exact_work_context()).0,
    )
  } else {
    (
      anchor.sub_ctx(offset, decimal_exact_work_context()).0,
      anchor.sub_ctx(inner_offset, decimal_exact_work_context()).0,
    )
  }
  guard lower.class == FpClass::Finite && upper.class == FpClass::Finite else {
    return None
  }
  let target_ctx = decimal_math_result_ctx(ctx)
  let lower_result = decimal_apply_finite_ctx(lower, target_ctx)
  let upper_result = decimal_apply_finite_ctx(upper, target_ctx)
  guard lower_result.0.total_order_compare(upper_result.0) == 0 else {
    return None
  }
  let lower_status = { ..lower_result.1, rounded: false, inexact: false, }
  let upper_status = { ..upper_result.1, rounded: false, inexact: false, }
  guard lower_status == upper_status else { return None }
  let selected = if above { upper_result } else { lower_result }
  Some((selected.0, { ..selected.1, rounded: true, inexact: true, }))
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
  extra_bits~ : Int32 = 0,
  exact_evaluate~ : ((Int32) -> Result[
    @ball_float.BallFloat,
    @def.ArithmeticError,
  ])? = None,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    decimal_certified_work_precision(value, ctx) + extra_bits,
    limit=ctx.refinement_limit,
  )
  while budget.available() {
    let evaluated = match exact_evaluate {
      Some(exact) => exact(budget.precision())
      None => evaluate(decimal_to_certified_ball(value, budget.precision()))
    }
    match evaluated {
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
  guard_bits~ : Int32 = 0,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    Int32::max(
      decimal_certified_work_precision(left, ctx),
      decimal_certified_work_precision(right, ctx),
    ) +
    guard_bits,
    limit=ctx.refinement_limit,
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
  // Only values with exp(x) below 10^(etiny - 2) reach this function (x <=
  // -3 (1 - etiny)). Rounded to the precision with an unbounded exponent range
  // such a value stays below 10^(etiny - 1) <= 10^(e_min - 1), so it is tiny
  // under both tininess options of the context (before rounding, the rule of
  // IEEE 754-2019 7.5 for decimal formats, and the non-standard
  // `AfterRounding`), also when `precision = 1` and etiny equals e_min (#333).
  let tiny = tiny_for_underflow(ctx, (minimum_exponent - 1).to_int64())
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
/// The base `b` of the exponentials `b^x` whose far-out-of-range results are
/// decided by `decimal_exponential_coarse_extreme_result`.
priv enum DecimalExponentialBase {
  Natural
  Two
  Ten
}

///|
/// An integer `k >= 1/log10(b)`: `b^x < 10^-n` for `x <= -k n` and
/// `b^x >= 10^n` for `x >= k n` (`n >= 0`), since `b^x = 10^(x log10 b)`.
/// `1/log10(e) = 2.3026`, `1/log10(2) = 3.3220` and `1/log10(10) = 1`.
fn DecimalExponentialBase::range_factor(self : DecimalExponentialBase) -> Int32 {
  match self {
    Natural => 3
    Two => 4
    Ten => 1
  }
}

///|
/// Decides `b^x` (`b = e`, 2 or 10, `x` finite and nonzero) when the result is
/// certainly out of the representable range, before the certified loop. The
/// enclosure of such a result is `[0, tiny]` (or `[huge, inf]`) once its binary
/// exponent leaves the exponent range of the ball arithmetic, and the two
/// endpoints then round differently (an exact 0 without flags against the
/// smallest subnormal with the underflow flags), so the loop could never
/// agree (#363). One function serves `exp`, `exp2` and `exp10`.
///
/// Proof. Let `k = range_factor(b)`, so `k >= 1 / log10 b`.
/// - Underflow. For `x <= -k (1 - etiny)` we have `b^x = 10^(x log10 b) <=
///   10^(etiny - 1)`, which is below half of the smallest subnormal
///   `10^etiny`. Rounded to the precision with an unbounded exponent range it
///   stays at most `10^(etiny - 1) <= 10^(e_min - 1)` (etiny <= e_min), so the
///   result is tiny before and after rounding, IEEE 754-2019 7.5. Every
///   rounding direction then gives 0 (towards zero, to nearest) or the
///   smallest subnormal (away from zero, ZeroFiveUp, IEEE 754-2019 4.3 and
///   7.5: the rounded result is inexact, so underflow and inexact are raised).
/// - Overflow. For `x >= k (e_max + 1)`, `b^x >= 10^(e_max + 1)`, which is
///   above the largest finite number `(10^p - 1) 10^(e_max - p + 1) <
///   10^(e_max + 1)` in every rounding direction, so the overflow result of
///   IEEE 754-2019 7.4 applies.
/// The comparison is exact (decimal against decimal), so the margin to the true
/// boundary (`k` against `1 / log10 b`) is the whole slack; arguments between
/// the true boundary and the threshold fall through (`None`) to the loop. The
/// threshold is at most `4 (1 - etiny)` with `etiny >= -1999998` (the math
/// context limit), far below the ball exponent limit, so the loop is sound on
/// the undecided range.
fn decimal_exponential_coarse_extreme_result(
  base : DecimalExponentialBase,
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let factor = base.range_factor()
  if value.negative && etiny(ctx) <= 0 {
    let guard_coefficient = dec_coeff_multiply_repr(
      dec_coeff_from_nonnegative_int(abs_int(etiny(ctx) - 1)),
      dec_coeff_from_int(factor),
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
          Down | Floor | HalfEven | HalfUp | HalfDown =>
            decimal_exp_underflow_zero_result(ctx)
        },
      )
    }
  }
  if !value.negative && ctx.e_max >= 0 {
    let guard_coefficient = dec_coeff_multiply_repr(
      dec_coeff_from_nonnegative_int(ctx.e_max + 1),
      dec_coeff_from_int(factor),
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
/// `exp(x)`, `exp2(x)` or `exp10(x)` of a tiny `x`: with `|x| < 10^top`
/// (`top = exponent10 + digits10 <= 0`), `b^x - 1` has the sign of `x` and
/// `|b^x - 1| <= |x| ln b e^(|x| ln b) < 10^(top + 1)` for `b <= 10` and
/// `|x| < 10^-1` (`ln b < 2.31`, `e^0.231 < 1.3`, `2.31 * 1.3 < 10`), so the result is `1` plus or minus
/// less than `10^(top + 1)`, one-sided next to the representable 1. The
/// one-sided rounding of `decimal_tiny_argument_result` applies once
/// `top + 1` is below `-(p + 3)`; otherwise `None` and the loop decides.
fn decimal_exp_tiny_result(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let top = value.exponent10.to_int64() +
    value.coefficient.digits10().to_int64()
  guard top <= -1L else { return None }
  decimal_tiny_argument_result(
    Decimal::from_int(1, precision=ctx.precision),
    !value.negative,
    top + 1L,
    ctx,
  )
}

///|
fn decimal_certified_exp_result(
  value : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_exponential_coarse_extreme_result(Natural, value, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  match decimal_exp_tiny_result(value, ctx) {
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
  decimal_range_from_log2_bracket(result_low, result_high, ctx)
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
  // The enclosure decides an exact power only when the value is representable
  // in binary, so `4^1.5` is returned exactly but `32^0.2` is not. Deciding it
  // in decimal first covers the rest.
  match decimal_power_exact_rational_result(base, exponent, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  // x^y = exp(y ln x) for x > 0, composed in interval arithmetic: one `ln`, one
  // product and one `exp` enclosure instead of the eight correctly rounded
  // binary powers of `try_pow_interval` (#352). The composition loses about
  // log2 |y ln x| bits of relative accuracy, added as guard bits so the
  // refinement loop starts at a sufficient precision. Correct rounding makes
  // the delivered result independent of the enclosure's width.
  guard !base.negative && !base.coefficient.is_zero() else {
    return decimal_certified_binary_result(base, exponent, ctx, "power", fn(
      left,
      right,
    ) {
      left.try_pow_interval(right)
    })
  }
  decimal_certified_binary_result(
    base,
    exponent,
    ctx,
    "power",
    fn(left, right) {
      left.try_ln_interval().bind(fn(log) { right.mul(log).try_exp_interval() })
    },
    guard_bits=decimal_power_guard_bits(base, exponent),
  )
}

///|
/// Bound of `ceil(log2 |exponent * ln base|)` from the adjusted exponents:
/// |ln base| <= ln(10) (|adjusted(base)| + 1) and |exponent| < 10^(adjusted + 1).
fn decimal_power_guard_bits(base : Decimal, exponent : Decimal) -> Int32 {
  let base_adjusted = adjusted_exponent64(base)
  let base_adjusted = if base_adjusted < 0L {
    -base_adjusted
  } else {
    base_adjusted
  }
  let exponent_adjusted = adjusted_exponent64(exponent)
  // log2(10) < 3.33, log2(ln 10 * (a + 1)) < 2 + bit_length(a + 1)
  let exponent_bits = (exponent_adjusted + 1L) * 10L / 3L + 1L
  let base_bits = 2L + 64L - (base_adjusted + 1L).clz().to_int64()
  let total = exponent_bits + base_bits
  if total < 0L {
    0
  } else if total > 100000L {
    100000
  } else {
    total.to_int()
  }
}
