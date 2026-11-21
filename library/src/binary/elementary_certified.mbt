///|
fn binary_certification_failure(
  operation : String,
  stage : @def.CertificationStage,
  reason : @def.CertificationFailureReason,
  target_precision : Int32,
  work_precision : Int32,
  refinements : Int32,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation, stage, reason, target_precision, work_precision, refinements,
    ),
  )
}

///|
/// The error of a checked result whose flags say `not_computed` (S4): the
/// certification-failure kind, apart from the domain error of `invalid_operation`.
fn binary_not_computed_error(operation : String) -> @def.ArithmeticError {
  binary_certification_failure(
    operation,
    @def.CertificationStage::RangeReduction,
    @def.CertificationFailureReason::ResourceLimit,
    0,
    0,
    0,
  )
}

///|
/// Total form of a `try_*_ctx` result used by the non-`try` elementary APIs.
/// `Err` of a `try_` form is only a result that could not be computed (a
/// certification failure or a limit of the implementation): the plain form is a
/// quiet NaN with `not_computed`, and not with `invalid_operation`, which is raised
/// only for a case IEEE 754-2019 defines as invalid (a value in the `try_` forms
/// too); callers that need the reason use the `try_*` API.
fn binary_defined_or_nan(
  result : Result[(Binary, BinaryFlags), @def.ArithmeticError],
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  match result {
    Ok(value) => value
    Err(_) =>
      (
        Binary::nan_raw(precision=context.precision),
        binary_not_computed_flags(),
      )
  }
}

///|
/// The value of a domain case of an elementary function (S4): a quiet NaN with
/// `invalid_operation`, the result IEEE 754-2019 defines, in the `try_` forms as in
/// the plain ones. `Err` of a `try_` form is only for a result that could not be
/// computed.
fn binary_invalid_value(context : BinaryContext) -> (Binary, BinaryFlags) {
  (Binary::nan_raw(precision=context.precision), binary_invalid_flags())
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
  work_precision : Int32,
  refinements : Int32,
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
  work_precision : Int32,
  refinements : Int32,
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
  lower : Binary,
  upper : Binary,
  context : BinaryContext,
) -> (Binary, Bool, BinaryFlags) {
  let (lower_value, lower_flags) = lower.apply_ctx(context)
  let (upper_value, upper_flags) = upper.apply_ctx(context)
  (
    lower_value,
    lower_value.identical(upper_value) && lower_flags == upper_flags,
    if lower_flags == upper_flags {
      lower_flags
    } else {
      lower_flags.combine(upper_flags)
    },
  )
}

///|
/// Moves an enclosure endpoint that may be a rounding breakpoint of `context`
/// (a representable value or a midpoint, so at most `precision + 1` significant
/// bits) strictly inside the enclosure, by less than half the distance to the
/// next breakpoint. Only valid when the exact result is known to differ from
/// the endpoint.
fn binary_inexact_inner_endpoint(
  endpoint : Binary,
  toward_positive : Bool,
  context : BinaryContext,
) -> Binary {
  guard endpoint.classify() == FpClass::Finite && !endpoint.is_zero() else {
    return endpoint
  }
  // Coefficients are odd, so bit_length counts the significant bits.
  let coefficient = endpoint.coefficient_()
  guard coefficient.bit_length() <= context.precision + 1 else {
    return endpoint
  }
  // |endpoint| = c * 2^e has its leading bit at t = e + bits(c) - 1, and the
  // breakpoints next to it are at least 2^(t - precision - 1) apart. The offset
  // 2^(e - shift) with shift >= precision + 3 - bits(c) is at most
  // 2^(t - precision - 2), so no breakpoint lies between the endpoint and the
  // new point.
  let shift = Int32::max(1, context.precision + 3 - coefficient.bit_length())
  let scaled = coefficient.shift_left(shift)
  let grows = toward_positive != endpoint.is_sign_minus()
  let moved = if grows {
    scaled.add(Coeff::one())
  } else {
    scaled.sub_checked(Coeff::one()).unwrap()
  }
  // Built wide enough to be kept: a Binary of width w stores nothing below
  // 2^(e_min - (w - 1)), so every bit of the endpoint, down to its lowest bit
  // at 2^(e - shift), has to lie on that grid or `make` rounds it.
  let lowest = (endpoint.exponent2() - shift).to_int64()
  let width = Int64::max(
    moved.bit_length().to_int64(),
    binary_value_e_min.to_int64() - lowest + 1L,
  )
  guard width <= 1073741824L else { return endpoint }
  Binary::make_coeff(
    moved,
    endpoint.exponent2() - shift,
    Int32::max(1, width.to_int()),
    negative=endpoint.is_sign_minus(),
  )
}

///|
/// Decides a result that lies within `2^scale` of `anchor`, above it or below
/// it, and differs from it, when that distance is below the target spacing at
/// the anchor. This is the tiny-argument case of the elementary functions
/// (f(x) = x + O(x^3), or 1 + O(x^2)), where the Ziv loop would need a working
/// precision near |log2 x| to separate the result from the anchor. Returns
/// `None` when the enclosure does not decide the rounding.
fn binary_tiny_argument_result(
  anchor : Binary,
  above : Bool,
  scale : Int64,
  context : BinaryContext,
) -> (Binary, BinaryFlags)? {
  let anchor_top = anchor.exponent2().to_int64() +
    (anchor.coefficient_bits() - 1).to_int64()
  let precision = context.precision.to_int64()
  guard scale < anchor_top - precision - 3L else { return None }
  let offset_exponent = Int64::max(scale, anchor_top - precision - 8L)
  // A Binary of width w stores nothing below 2^(e_min - (w - 1)): the offset
  // 2^k is built wide enough to be kept, not flushed to zero or to 2^e_min
  // when the anchor is within a few bits of the implementation subnormal limit.
  let offset_width = Int64::max(
    1L,
    binary_value_e_min.to_int64() - offset_exponent + 2L,
  )
  guard offset_width <= 1073741824L else { return None }
  let offset = Binary::make_coeff(
    Coeff::one(),
    offset_exponent.to_int(),
    offset_width.to_int(),
  )
  // The sum keeps its bits below the subnormal grid of the working precision.
  let work = Int32::max(context.precision, anchor.precision()) +
    8 +
    offset_width.to_int()
  let (lower, upper) = if above {
    (
      anchor,
      anchor.add_ctx(
        offset,
        binary_working_context(work, rounding=RoundTowardPositive),
      ).0,
    )
  } else {
    (
      anchor.sub_ctx(
        offset,
        binary_working_context(work, rounding=RoundTowardNegative),
      ).0,
      anchor,
    )
  }
  let (result, unique, flags) = binary_certified_inexact_target_rounding(
    lower, upper, context,
  )
  if unique {
    Some((result, flags))
  } else {
    None
  }
}

///|
/// Exponent bound of a finite nonzero value: |x| < 2^(binary_top_bound(x)).
fn binary_top_bound(value : Binary) -> Int64 {
  value.exponent2().to_int64() + value.coefficient_bits().to_int64()
}

///|
/// Target rounding of an enclosure of a result that is known not to be
/// representable in `context`, such as a transcendental value at an input other
/// than its exact special cases. An endpoint that is itself representable then
/// cannot be the result; it is moved inside the enclosure first, so a result
/// within a tiny distance of a representable number (exp(2^-20000) next to 1,
/// sin(2^-6000) next to 2^-6000) is certified as soon as the enclosure is
/// narrower than the target spacing, instead of never.
fn binary_certified_inexact_target_rounding(
  lower : Binary,
  upper : Binary,
  context : BinaryContext,
) -> (Binary, Bool, BinaryFlags) {
  if lower.compare(upper) >= 0 {
    return binary_certified_target_rounding(lower, upper, context)
  }
  binary_certified_target_rounding(
    binary_inexact_inner_endpoint(lower, true, context),
    binary_inexact_inner_endpoint(upper, false, context),
    context,
  )
}

///|
fn binary_exp_small_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let eighth = Binary::make_coeff(Coeff::one(), -3, work_precision)
  guard lower.compare(eighth.neg()) >= 0 && upper.compare(eighth) <= 0 else {
    return None
  }
  if upper.signum() == Sign::Negative {
    match binary_exp_small_bounds(lower.neg(), work_precision) {
      Some(positive) =>
        Some(
          (
            Binary::one_raw(precision=work_precision).div_ctx(
              positive.1,
              downward,
            ).0,
            Binary::one_raw(precision=work_precision).div_ctx(
              positive.0,
              upward,
            ).0,
          ),
        )
      None => None
    }
  } else {
    let one = Binary::one_raw(precision=work_precision)
    let mut term_lower = one
    let mut term_upper = one
    let mut sum_lower = one
    let mut sum_upper = one
    let threshold = Binary::make_coeff(
      Coeff::one(),
      -(work_precision + 8),
      work_precision,
    )
    let mut index = 0
    while index < 10000 {
      index += 1
      let index_value = Binary::from_int_raw(index, precision=work_precision)
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
            Binary::from_int_raw(2, precision=work_precision),
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
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  if work_precision <= binary_exp_table_max_precision {
    match binary_exp_bounds_table(value, work_precision) {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  if work_precision >= binary_exp_burst_min_precision {
    match binary_exp_bounds_burst(value, work_precision) {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  binary_exp_bounds_series(value, work_precision)
}

///|
/// The enclosure of `exp` by the series (fixed point when the argument is
/// exact at the working precision, rounded floating point otherwise): the path
/// below the bit-burst threshold and the reference of its tests.
fn binary_exp_bounds_series(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match binary_exp_bounds_fixed(value, work_precision) {
    Some(bounds) => return Some(bounds)
    None => ()
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let mut lower = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let mut upper = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let eighth = Binary::make_coeff(Coeff::one(), -3, work_precision)
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
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
  // Only `lower_bounds.0` and `upper_bounds.1` are used. When both endpoints
  // are the same value (an argument that is exact at the working precision,
  // so every halving is exact too), one evaluation supplies both.
  let lower_series = binary_exp_small_bounds(lower, work_precision)
  let upper_series = if lower.compare(upper) == 0 {
    lower_series
  } else {
    binary_exp_small_bounds(upper, work_precision)
  }
  match (lower_series, upper_series) {
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
  value : Binary,
  work_precision : Int32,
  entry~ : Bool = false,
) -> (Binary, Binary)? {
  // The step of the outermost call may start lower than the nested ones: one
  // step on the table kernel beats the series from `binary_ln_entry_min_precision`
  // on, but a second step below it costs more than the series it replaces.
  let threshold = if entry {
    binary_ln_entry_min_precision
  } else {
    binary_ln_burst_min_precision
  }
  if entry && work_precision >= binary_ln_agm_min_precision {
    match binary_ln_unit_agm_bounds(value, work_precision) {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  if work_precision >= threshold {
    match binary_ln_unit_burst_bounds(value, work_precision) {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  binary_ln_unit_bounds_series(value, work_precision)
}

///|
/// The enclosure of `ln` for a number in `[1, 2]` by the series (fixed point
/// when the argument is exact at the working precision): the path below the
/// Newton-step threshold and the reference of its tests.
fn binary_ln_unit_bounds_series(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match binary_ln_unit_fixed_bounds(value, work_precision) {
    Some(bounds) => return Some(bounds)
    None => ()
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let two = Binary::from_int_raw(2, precision=work_precision)
  let lower_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
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
  let mut sum_lower = Binary::zero_raw(precision=work_precision)
  let mut sum_upper = sum_lower
  let mut denominator = 1
  let threshold = Binary::make_coeff(
    Coeff::one(),
    -(work_precision + 8),
    work_precision,
  )
  while denominator < 20000 {
    let denominator_value = Binary::from_int_raw(
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
          Binary::from_int_raw(denominator, precision=work_precision),
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
let binary_range_check_precision : Int32 = 128

///|
/// Certified bounds on `log2(e) = 1 / ln 2`.
fn binary_log2_e_bounds() -> (Binary, Binary)? {
  let work = binary_range_check_precision
  guard binary_ln2_bounds(work) is Some((ln2_low, ln2_high)) else {
    return None
  }
  let one = Binary::one_raw(precision=work)
  Some(
    (
      one.div_ctx(
        ln2_high,
        binary_working_context(work, rounding=RoundTowardNegative),
      ).0,
      one.div_ctx(
        ln2_low,
        binary_working_context(work, rounding=RoundTowardPositive),
      ).0,
    ),
  )
}

///|
/// Certified bounds on `log2(10) = ln 10 / ln 2`.
fn binary_log2_10_bounds() -> (Binary, Binary)? {
  let work = binary_range_check_precision
  guard binary_ln2_bounds(work) is Some((ln2_low, ln2_high)) &&
    binary_ln10_bounds(work) is Some((ln10_low, ln10_high)) else {
    return None
  }
  Some(
    (
      ln10_low.div_ctx(
        ln2_high,
        binary_working_context(work, rounding=RoundTowardNegative),
      ).0,
      ln10_high.div_ctx(
        ln2_low,
        binary_working_context(work, rounding=RoundTowardPositive),
      ).0,
    ),
  )
}

///|
/// Decides overflow or underflow before a Ziv loop for results whose base-2
/// logarithm lies in `[scale * x + offset, scale * x]`, with `scale > 0`
/// bracketed by `scale_bounds`. The loops evaluate in unbounded working
/// contexts and cannot certify a result that their own enclosures overflow, so
/// results certainly outside the context range are returned here.
fn binary_log2_linear_out_of_range(
  value : Binary,
  scale_bounds : () -> (Binary, Binary)?,
  scale_bits : Int32,
  offset : Int32,
  check_tiny : Bool,
  negative : Bool,
  context : BinaryContext,
) -> (Binary, BinaryFlags)? {
  let overflow_limit = context.range_e_max().to_int64() + 1L
  let tiny_limit = context.range_e_min().to_int64() -
    context.precision.to_int64()
  // |value| < 2^(top + 1) and scale < 2^scale_bits, so small arguments skip
  // the certified constants entirely.
  let top = value.exact_top()
  if top + 1 + scale_bits < 62 {
    let reach = 1L << (top + 1 + scale_bits)
    if reach < overflow_limit && -reach > tiny_limit {
      return None
    }
  }
  guard scale_bounds() is Some((scale_low, scale_high)) else { return None }
  let work = binary_range_check_precision
  let down = binary_working_context(work, rounding=RoundTowardNegative)
  let up = binary_working_context(work, rounding=RoundTowardPositive)
  let value_low = value.with_precision_raw(
    work,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let value_high = value.with_precision_raw(
    work,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let log_low = value_low.mul_ctx(
      if value_low.is_sign_minus() {
        scale_high
      } else {
        scale_low
      },
      down,
    ).0
  let log_high = value_high.mul_ctx(
      if value_high.is_sign_minus() {
        scale_low
      } else {
        scale_high
      },
      up,
    ).0
  let log_low = log_low.add_ctx(
      Binary::from_int_raw(offset, precision=work),
      down,
    ).0
  let overflow_log = Binary::from_int_raw(
    overflow_limit.to_int(),
    precision=work,
  )
  if log_low.compare(overflow_log) >= 0 {
    return Some(binary_overflow_result(negative, context))
  }
  let tiny_log = Binary::from_int_raw(tiny_limit.to_int(), precision=work)
  if check_tiny && log_high.compare(tiny_log) < 0 {
    return Some(binary_tiny_nonzero_result(negative, context))
  }
  None
}

///|
/// For `x <= -(p + 3) ln 2`, `expm1(x) = -1 + d` with `0 < d < 2^-(p + 3)`, so
/// the rounded result follows from the rounding direction alone. The general
/// enclosure divides by `1 + expm1(-x)`, which overflows for such `x`.
fn binary_expm1_negative_saturation(
  value : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags)? {
  let work = binary_range_check_precision
  let limit = Binary::from_int_raw(context.precision + 3, precision=work)
  // ln 2 > 1/2, so arguments above -(p + 3) / 2 cannot reach the threshold.
  let half = Binary::make_coeff(Coeff::one(), -1, work)
  if value.neg().compare(limit.mul(half)) < 0 {
    return None
  }
  guard binary_ln2_bounds(work) is Some((_, ln2_high)) else { return None }
  let threshold = limit.mul_ctx(
    ln2_high,
    binary_working_context(work, rounding=RoundTowardPositive),
  ).0.neg()
  if value.compare(threshold) > 0 {
    return None
  }
  let toward_zero = match context.rounding {
    RoundTowardZero | RoundTowardPositive => true
    RoundTiesToEven | RoundTiesToAway | RoundTowardNegative => false
  }
  let result = if toward_zero {
    finite_from_parts(
      true,
      Coeff::one()
      .shift_left(context.precision)
      .sub_checked(Coeff::one())
      .unwrap(),
      -context.precision,
      context.precision,
    )
  } else {
    Binary::one_raw(precision=context.precision).neg()
  }
  Some((result, binary_inexact_flags(false)))
}

///|
/// For `|x| > (p + 4) ln 2 / 2`, `1 - tanh|x| = 2 / (e^(2|x|) + 1) < 2 e^(-2|x|)
/// < 2^-(p + 3)`, less than a quarter of the spacing `2^-p` below 1, so
/// `tanh x` rounds to `+-1` or to the adjacent value `+-(1 - 2^-p)` by the
/// rounding direction alone. The general enclosure works with `e^(2|x|)`,
/// which leaves the exponent range long before that.
fn binary_tanh_saturation(
  value : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags)? {
  let work = binary_range_check_precision
  let limit = Binary::from_int_raw(context.precision + 4, precision=work)
  // ln 2 > 1/2, so arguments below (p + 4) / 4 cannot reach the threshold.
  let quarter = Binary::make_coeff(Coeff::one(), -2, work)
  let magnitude = value.abs()
  if magnitude.compare(limit.mul(quarter)) < 0 {
    return None
  }
  guard binary_ln2_bounds(work) is Some((_, ln2_high)) else { return None }
  let half = Binary::make_coeff(Coeff::one(), -1, work)
  let threshold = limit
    .mul(half)
    .mul_ctx(
      ln2_high,
      binary_working_context(work, rounding=RoundTowardPositive),
    ).0
  if magnitude.compare(threshold) <= 0 {
    return None
  }
  let negative = value.is_sign_minus()
  let toward_zero = match context.rounding {
    RoundTowardZero => true
    RoundTowardPositive => negative
    RoundTowardNegative => !negative
    RoundTiesToEven | RoundTiesToAway => false
  }
  let result = if toward_zero {
    finite_from_parts(
      negative,
      Coeff::one()
      .shift_left(context.precision)
      .sub_checked(Coeff::one())
      .unwrap(),
      -context.precision,
      context.precision,
    )
  } else {
    let one = Binary::one_raw(precision=context.precision)
    if negative {
      one.neg()
    } else {
      one
    }
  }
  Some((result, binary_inexact_flags(false)))
}

///|
fn binary_ln10_series_compute(work_precision : Int32) -> (Binary, Binary)? {
  let five_quarters = Binary::make_coeff(
    Coeff::from_uint64(5UL),
    -2,
    work_precision,
  )
  match
    (
      binary_ln2_bounds(work_precision),
      binary_ln_unit_bounds(five_quarters, work_precision),
    ) {
    (Some(two_bounds), Some(part_bounds)) => {
      let downward = binary_working_context(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = binary_working_context(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let three = Binary::from_int_raw(3, precision=work_precision)
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
  value : Binary,
  work_precision : Int32,
  series_only~ : Bool = false,
) -> (Binary, Binary)? {
  guard value.classify() == FpClass::Finite && value.signum() == Sign::Positive else {
    return None
  }
  let coefficient_bits = value.coefficient_bits()
  let normalized = Binary::make_coeff(
    value.coefficient_(),
    -(coefficient_bits - 1),
    Int32::max(work_precision, coefficient_bits),
  )
  let unit_bounds = if series_only {
    binary_ln_unit_bounds_series(normalized, work_precision)
  } else {
    binary_ln_unit_bounds(normalized, work_precision, entry=true)
  }
  match (unit_bounds, binary_ln2_bounds(work_precision)) {
    (Some(unit), Some(ln2)) => {
      let downward = binary_working_context(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = binary_working_context(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let exponent = value.exponent2() + coefficient_bits - 1
      let exponent_value = Binary::from_int_raw(
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
/// Enclosure of the product of two intervals. Each end is one directed
/// product, not a minimum over four: with `a` nonnegative the minimum over
/// `a in [a0, a1]`, `b in [b0, b1]` of `a b` is `a0 b0` if `b0 >= 0` and
/// `a1 b0` otherwise (the smallest `b` is the best choice, then the best `a`
/// for the sign of that `b`), and the maximum is `a1 b1` if `b1 >= 0` and
/// `a0 b1` otherwise. A nonpositive `a` is `-|a|`; a mixed `a` with a
/// sign-definite `b` swaps the roles; two mixed intervals take the four
/// corners. Directed rounding is monotone, so rounding the chosen exact
/// product equals the minimum or maximum of the four rounded products.
fn binary_product_bounds_general(
  left : (Binary, Binary),
  right : (Binary, Binary),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (Binary, Binary) {
  let (a0, a1) = left
  let (b0, b1) = right
  let lower_candidates = [
    a0.mul_ctx(b0, downward).0,
    a0.mul_ctx(b1, downward).0,
    a1.mul_ctx(b0, downward).0,
    a1.mul_ctx(b1, downward).0,
  ]
  let upper_candidates = [
    a0.mul_ctx(b0, upward).0,
    a0.mul_ctx(b1, upward).0,
    a1.mul_ctx(b0, upward).0,
    a1.mul_ctx(b1, upward).0,
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
fn binary_product_bounds(
  left : (Binary, Binary),
  right : (Binary, Binary),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (Binary, Binary) {
  let zero = Binary::zero_raw()
  let (a0, a1) = left
  let (b0, b1) = right
  let a_nonneg = a0.compare(zero) >= 0
  let a_nonpos = a1.compare(zero) <= 0
  let b_nonneg = b0.compare(zero) >= 0
  let b_nonpos = b1.compare(zero) <= 0
  let result = if a_nonneg {
    (
      (if b_nonneg { a0 } else { a1 }).mul_ctx(b0, downward).0,
      (if b1.compare(zero) >= 0 { a1 } else { a0 }).mul_ctx(b1, upward).0,
    )
  } else if a_nonpos {
    (
      (if b1.compare(zero) >= 0 { a0 } else { a1 }).mul_ctx(b1, downward).0,
      (if b_nonneg { a1 } else { a0 }).mul_ctx(b0, upward).0,
    )
  } else if b_nonneg {
    (
      (if a0.compare(zero) >= 0 { b0 } else { b1 }).mul_ctx(a0, downward).0,
      (if a1.compare(zero) >= 0 { b1 } else { b0 }).mul_ctx(a1, upward).0,
    )
  } else if b_nonpos {
    (
      (if a1.compare(zero) >= 0 { b0 } else { b1 }).mul_ctx(a1, downward).0,
      (if a0.compare(zero) >= 0 { b1 } else { b0 }).mul_ctx(a0, upward).0,
    )
  } else {
    return binary_product_bounds_general(left, right, downward, upward)
  }
  // The sign of a zero end depends on which of several equal candidates the
  // four-candidate form picked; keep that exact choice (a zero end is rare).
  if result.0.is_zero() || result.1.is_zero() {
    return binary_product_bounds_general(left, right, downward, upward)
  }
  result
}

///|
/// Enclosure of the quotient of an interval by a strictly positive interval.
/// For `d` in `[d0, d1]` with `0 < d0`, `n / d` is increasing in `n`, and for
/// `n >= 0` decreasing in `d` (increasing for `n < 0`): the minimum is
/// `n0 / d1` if `n0 >= 0` and `n0 / d0` otherwise; the maximum is `n1 / d0` if
/// `n1 >= 0` and `n1 / d1` otherwise.
fn binary_quotient_bounds_general(
  numerator : (Binary, Binary),
  denominator : (Binary, Binary),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (Binary, Binary) {
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
  (lower, upper)
}

///|
fn binary_quotient_bounds(
  numerator : (Binary, Binary),
  denominator : (Binary, Binary),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (Binary, Binary)? {
  let zero = Binary::zero_raw()
  guard denominator.0.compare(zero) > 0 else { return None }
  let lower = numerator.0.div_ctx(
      if numerator.0.compare(zero) >= 0 {
        denominator.1
      } else {
        denominator.0
      },
      downward,
    ).0
  let upper = numerator.1.div_ctx(
      if numerator.1.compare(zero) >= 0 {
        denominator.0
      } else {
        denominator.1
      },
      upward,
    ).0
  // The sign of a zero end depends on which of several equal candidates the
  // four-candidate form picked; keep that exact choice (a zero end is rare).
  if lower.is_zero() || upper.is_zero() {
    return Some(
      binary_quotient_bounds_general(numerator, denominator, downward, upward),
    )
  }
  Some((lower, upper))
}

///|
/// The enclosure of a monotone increasing `f` over `[lower, upper]` from the
/// lower end of `f(lower)` and the upper end of `f(upper)`; a point (`lower`
/// equal to `upper`) is evaluated once. `evaluate` is deterministic, so the
/// result is bit-identical to evaluating both ends.
fn binary_bounds_at_ends(
  lower : Binary,
  upper : Binary,
  evaluate : (Binary) -> (Binary, Binary)?,
) -> (Binary, Binary)? {
  if lower.compare(upper) == 0 {
    return evaluate(lower)
  }
  match (evaluate(lower), evaluate(upper)) {
    (Some(low), Some(high)) => Some((low.0, high.1))
    _ => None
  }
}

///|
fn binary_expm1_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let two = Binary::from_int_raw(2, precision=work_precision)
  let eighth = Binary::make_coeff(Coeff::one(), -3, work_precision)
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
  let mut lower = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let mut upper = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let negative = upper.compare(Binary::zero_raw()) < 0
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
  guard lower.compare(Binary::zero_raw()) >= 0 else { return None }
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
  let threshold = Binary::make_coeff(
    Coeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  let mut certified = false
  while index < 10000 {
    index += 1
    let divisor = Binary::from_int_raw(index, precision=work_precision)
    term_lower = term_lower.mul_ctx(lower, downward).0.div_ctx(
        divisor, downward,
      ).0
    term_upper = term_upper.mul_ctx(upper, upward).0.div_ctx(divisor, upward).0
    sum_lower = sum_lower.add_ctx(term_lower, downward).0
    sum_upper = sum_upper.add_ctx(term_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let next_upper = term_upper.mul_ctx(upper, upward).0.div_ctx(
          Binary::from_int_raw(index + 1, precision=work_precision),
          upward,
        ).0
      let ratio = upper.div_ctx(
          Binary::from_int_raw(index + 2, precision=work_precision),
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
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let third = one.div_ctx(
      Binary::from_int_raw(3, precision=work_precision),
      upward,
    ).0
  guard lower.compare(Binary::zero_raw()) >= 0 && upper.compare(third) <= 0 else {
    return None
  }
  let square_lower = lower.mul_ctx(lower, downward).0
  let square_upper = upper.mul_ctx(upper, upward).0
  let mut power_lower = lower
  let mut power_upper = upper
  let mut sum_lower = lower
  let mut sum_upper = upper
  let threshold = Binary::make_coeff(
    Coeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut denominator = 1
  while denominator < 20000 {
    denominator += 2
    power_lower = power_lower.mul_ctx(square_lower, downward).0
    power_upper = power_upper.mul_ctx(square_upper, upward).0
    let divisor = Binary::from_int_raw(denominator, precision=work_precision)
    let term_lower = power_lower.div_ctx(divisor, downward).0
    let term_upper = power_upper.div_ctx(divisor, upward).0
    sum_lower = sum_lower.add_ctx(term_lower, downward).0
    sum_upper = sum_upper.add_ctx(term_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let next_power = power_upper.mul_ctx(square_upper, upward).0
      let next_term = next_power.div_ctx(
          Binary::from_int_raw(denominator + 2, precision=work_precision),
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
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  if value.is_sign_minus() {
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
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let two = Binary::from_int_raw(2, precision=work_precision)
  let lower_input = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_input = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
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
  guard lower_argument.compare(Binary::zero_raw()) > 0 else { return None }
  binary_bounds_at_ends(lower_argument, upper_argument, fn(point) {
    binary_ln_bounds(point, work_precision)
  })
}

///|
fn binary_exp2_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  match
    (
      binary_ln2_bounds(work_precision),
      Some(
        (
          value.with_precision_raw(
            work_precision,
            BinaryRoundingMode::RoundTowardNegative,
          ),
          value.with_precision_raw(
            work_precision,
            BinaryRoundingMode::RoundTowardPositive,
          ),
        ),
      ),
    ) {
    (Some(log_two), Some(value_bounds)) => {
      let scaled = binary_product_bounds(
        value_bounds, log_two, downward, upward,
      )
      binary_bounds_at_ends(scaled.0, scaled.1, fn(point) {
        binary_exp_bounds(point, work_precision)
      })
    }
    _ => None
  }
}

///|
fn binary_log2_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  match
    (binary_ln_bounds(value, work_precision), binary_ln2_bounds(work_precision)) {
    (Some(numerator), Some(denominator)) =>
      binary_quotient_bounds(numerator, denominator, downward, upward)
    _ => None
  }
}

///|
/// Which side of an overflow threshold `count * ln 2` (`count * ln 2 / ln 10` when
/// `decimal`) the finite nonnegative argument lies: `Some(true)` when the result
/// is certainly at or above `2^(e_max + 1)`, `Some(false)` when it is certainly
/// below, `None` when the constants at `work_precision` do not decide it.
///
/// Which side is exact depends on the function; the argument `x` of the
/// exponential is compared with `T = count * ln 2` (never equal, `ln 2` is
/// irrational):
/// - `exp`, `exp10`, `pow`, `powr`, `compound`: the result is the exponential,
///   at or above `2^(e_max + 1)` exactly when `x >= T`: both sides exact, no
///   margin (`count = e_max + 1`; for `exp10` with `decimal`; for the powers the
///   argument is the enclosure of `y ln x`).
/// - `expm1`, `exp10m1`: `f = b^x - 1 < b^x`, so `x <= T` still gives a result
///   below the threshold (exact), but `x >= T` does not give `f >= 2^(e_max + 1)`:
///   `f` reaches it from `T' = log_b(2^(e_max + 1) + 1) = T + d`, `0 < d < 2^-(2^30)`.
///   `inexact_above` makes "at or above" require `x >= T_high + margin`.
/// - `sinh` (`count = e_max + 2`, `x` the magnitude): `f = (e^x / 2)(1 - e^(-2x))
///   < e^x / 2`: same as `expm1`, `inexact_above`.
/// - `cosh` (`count = e_max + 2`): `f = (e^x / 2)(1 + e^(-2x)) > e^x / 2`, so
///   `x >= T` gives `f >= 2^(e_max + 1)` (exact) but `x <= T` does not give
///   `f < 2^(e_max + 1)`: `inexact_below` makes "below" require
///   `x <= T_low - margin`.
/// The margin is `2^(top - w + 1)` with `top` the binary exponent bound of the
/// threshold (`2^(31 - w)` for the thresholds near `2^29.5`), at least one unit in
/// the last place of `T_high` at the working precision `w`; the difference `d`
/// of the unsafe functions is below `2^-(2^30)`, so the margin covers it while
/// `w < 2^29` (a larger working precision returns `None`, the safe failure).
/// Inside the margin the side is not decided and the loop refines (the margin
/// halves with every extra bit of `w`, while a float at distance `delta` from
/// `T` is decided once `2^(31 - w) < delta`).
fn binary_exp_overflow_side(
  value : Binary,
  work_precision : Int32,
  count~ : Int32 = binary_value_e_max + 1,
  decimal~ : Bool = false,
  inexact_above~ : Bool = false,
  inexact_below~ : Bool = false,
) -> Bool? {
  binary_exp_interval_overflow_side(
    value,
    value,
    work_precision,
    count~,
    decimal~,
    inexact_above~,
    inexact_below~,
  )
}

///|
/// `binary_exp_overflow_side` for an argument known to lie in `[lower, upper]`
/// (a product `y ln x` of two enclosures): `Some(true)` when all of it is at or
/// above the threshold, `Some(false)` when all of it is below, `None` when it
/// straddles the threshold (or its margin) at `work_precision`.
fn binary_exp_interval_overflow_side(
  lower : Binary,
  upper : Binary,
  work_precision : Int32,
  count~ : Int32 = binary_value_e_max + 1,
  decimal~ : Bool = false,
  inexact_above~ : Bool = false,
  inexact_below~ : Bool = false,
) -> Bool? {
  guard binary_ln2_bounds(work_precision) is Some((low, high)) else {
    return None
  }
  guard work_precision < 536870912 || !(inexact_above || inexact_below) else {
    return None
  }
  let down = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let up = binary_working_context(work_precision, rounding=RoundTowardPositive)
  let scale = Binary::from_int_raw(count, precision=work_precision)
  let (low, high) = if decimal {
    guard binary_ln10_bounds(work_precision) is Some((ten_low, ten_high)) else {
      return None
    }
    (low.div_ctx(ten_high, down).0, high.div_ctx(ten_low, up).0)
  } else {
    (low, high)
  }
  let threshold_low = low.mul_ctx(scale, down).0
  let threshold_high = high.mul_ctx(scale, up).0
  let margin = Binary::make_coeff(
    Coeff::one(),
    (binary_top_bound(threshold_high) - work_precision.to_int64() + 1L).to_int(),
    1,
  )
  let above = if inexact_above {
    threshold_high.add_ctx(margin, up).0
  } else {
    threshold_high
  }
  let below = if inexact_below {
    threshold_low.sub_ctx(margin, down).0
  } else {
    threshold_low
  }
  if lower.compare(above) >= 0 {
    Some(true)
  } else if upper.compare(below) <= 0 {
    Some(false)
  } else {
    None
  }
}

///|
/// The target rounding of an enclosure `[lower, upper]` of a result that is
/// finite in exact arithmetic but whose enclosure overflows the implementation
/// range (an end is infinite): the loops cannot certify such an enclosure at any
/// working precision when the argument lies closer to the overflow threshold than
/// the pre-check decides, because the finite end saturates at the largest finite
/// value of the working precision. `side` says which side of the threshold the
/// argument is on (`binary_exp_overflow_side`): at or above it the result
/// overflows in every direction (clause 7.4) and is returned at once; below it
/// the overflowed end is replaced by the largest finite value of the working
/// precision `w`, which rounds exactly as every value in `[that value,
/// 2^(e_max + 1))` does, value and flags, in every direction when `w >= p + 2`
/// (the breakpoints of a rounding to `p` bits next to `2^(e_max + 1)` are
/// `2^(e_max + 1) (1 - 2^-p)` and `2^(e_max + 1) (1 - 2^-(p + 1))`, both below
/// `Omax(w) = 2^(e_max + 1) (1 - 2^-w)`); undecided: not certified. `negative`
/// mirrors it for a result below zero (the lower end is `-inf`).
fn binary_certified_edge_rounding(
  lower : Binary,
  upper : Binary,
  context : BinaryContext,
  work : Int32,
  negative : Bool,
  side : () -> Bool?,
) -> (Binary, Bool, BinaryFlags) {
  let overflowed = if negative {
    lower.classify() == FpClass::Infinity && upper.classify() == FpClass::Finite
  } else {
    upper.classify() == FpClass::Infinity && lower.classify() == FpClass::Finite
  }
  if !overflowed {
    return binary_certified_inexact_target_rounding(lower, upper, context)
  }
  guard work >= context.precision + 2 else {
    return (lower, false, BinaryFlags::new())
  }
  match side() {
    Some(true) => {
      let (value, flags) = binary_overflow_result(negative, context)
      (value, true, flags)
    }
    Some(false) => {
      let largest = binary_max_finite(negative, binary_working_context(work))
      if negative {
        binary_certified_inexact_target_rounding(largest, upper, context)
      } else {
        binary_certified_inexact_target_rounding(lower, largest, context)
      }
    }
    None => (lower, false, BinaryFlags::new())
  }
}

///|
pub fn Binary::try_exp_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.negative() {
            Binary::zero_raw(precision=context.precision)
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((Binary::one_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      if binary_log2_linear_out_of_range(
          self, binary_log2_e_bounds, 2, 0, true, false, context,
        )
        is Some(result) {
        return Ok(result)
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_exp_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_edge_rounding(
              bounds.0,
              bounds.1,
              context,
              work,
              false,
              fn() { binary_exp_overflow_side(self, work) },
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("exp", context, work, attempt))
    }
  }
}

///|
/// The two directed roundings of a transcendental value from ONE certified
/// enclosure: `(round toward negative, round toward positive)` at `precision`,
/// what two calls `f(x, RoundTowardNegative)` and `f(x, RoundTowardPositive)`
/// return in their values. `bounds_at(work)` is the enclosure of the function at
/// the working precision `work` (the one the single-direction loop uses). The
/// loop is the one of `try_exp_ctx`/`try_ln_ctx` (start `precision + 64`, growth
/// `max(32, work / 2)`, the refinement limit of the contexts) and stops at the
/// first working precision at which BOTH directed roundings are unique, so each
/// end is the correctly rounded value of the exact result, the same value the
/// single-direction call returns at its own (possibly earlier) attempt: a
/// correctly rounded directed value does not depend on the working precision at
/// which its uniqueness was certified. `None` whenever the ordinary route must
/// decide: no enclosure, a refinement budget exhausted, or an overflow or
/// underflow flag in either end (the contexts then matter).
fn binary_directed_pair_from_bounds(
  precision : Int32,
  bounds_at : (Int32) -> (Binary, Binary)?,
) -> (Binary, Binary)? {
  let downward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let mut work = precision + 64
  let mut attempt = 0
  while @internal.certified_refinement_continues(
          downward.refinement_limit,
          attempt,
          work,
          precision,
        ) {
    guard bounds_at(work) is Some(bounds) else { return None }
    let (low, low_unique, low_flags) = binary_certified_inexact_target_rounding(
      bounds.0,
      bounds.1,
      downward,
    )
    let (high, high_unique, high_flags) = binary_certified_inexact_target_rounding(
      bounds.0,
      bounds.1,
      upward,
    )
    if low_unique && high_unique {
      if low_flags.overflow() ||
        low_flags.underflow() ||
        high_flags.overflow() ||
        high_flags.underflow() {
        return None
      }
      return Some((low, high))
    }
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  None
}

///|
/// `x.try_exp_directed_pair(p)` is the pair of values of `x.try_exp_ctx` at
/// precision `p` under `RoundTowardNegative` and under `RoundTowardPositive`,
/// with the error of the first of the two calls that fails. For a finite
/// nonzero `x` whose result is in range it takes both values from one certified
/// enclosure (a correctly rounded directed value does not depend on the working
/// precision at which it was certified), so it costs one evaluation instead of
/// two; every other operand is answered by the two calls themselves.
pub fn Binary::try_exp_directed_pair(
  self : Binary,
  precision : Int32,
) -> Result[(Binary, Binary), @def.ArithmeticError] {
  let downward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  if self.class() == FpClass::Finite &&
    !self.is_zero() &&
    binary_log2_linear_out_of_range(
      self, binary_log2_e_bounds, 2, 0, true, false, downward,
    )
    is None &&
    binary_log2_linear_out_of_range(
      self, binary_log2_e_bounds, 2, 0, true, false, upward,
    )
    is None &&
    binary_directed_pair_from_bounds(precision, fn(work) {
      binary_exp_bounds(self, work)
    })
    is Some(pair) {
    return Ok(pair)
  }
  self
  .try_exp_ctx(downward)
  .bind(fn(low) { self.try_exp_ctx(upward).map(fn(high) { (low.0, high.0) }) })
}

///|
/// `x.try_ln_directed_pair(p)` is the pair of values of `x.try_ln_ctx` at
/// precision `p` under `RoundTowardNegative` and under `RoundTowardPositive`,
/// with the error of the first of the two calls that fails. For a finite
/// positive `x` other than 1 it takes both values from one certified enclosure
/// (see `try_exp_directed_pair`); every other operand is answered by the two
/// calls themselves.
pub fn Binary::try_ln_directed_pair(
  self : Binary,
  precision : Int32,
) -> Result[(Binary, Binary), @def.ArithmeticError] {
  if self.class() == FpClass::Finite &&
    !self.is_zero() &&
    !self.negative() &&
    self.compare(Binary::one_raw(precision=self.precision())) != 0 &&
    binary_directed_pair_from_bounds(precision, fn(work) {
      binary_ln_bounds(self, work)
    })
    is Some(pair) {
    return Ok(pair)
  }
  let downward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  self
  .try_ln_ctx(downward)
  .bind(fn(low) { self.try_ln_ctx(upward).map(fn(high) { (low.0, high.0) }) })
}

///|
pub fn Binary::exp_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_exp_ctx(context), context)
}

///|
pub fn Binary::exp(self : Binary) -> Binary {
  self.exp_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_expm1_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.is_sign_minus() {
            Binary::one_raw(precision=context.precision).neg()
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() => Ok(self.apply_ctx(context))
    FpClass::Finite => {
      if self.is_sign_minus() &&
        binary_expm1_negative_saturation(self, context) is Some(result) {
        return Ok(result)
      }
      // For x >= 64, e^x - 1 >= e^(x - 2^-60) (e^(x - d) >= 1 / d once x - d >=
      // 60 ln 2), which decides the overflow window [e_max + 1, e_max + 2) in
      // log2 that the offset of the next check leaves open.
      if !self.is_sign_minus() &&
        self.compare(Binary::from_int_raw(64, precision=7)) >= 0 &&
        binary_log2_linear_out_of_range(
          self.sub_ctx(
            Binary::make_coeff(Coeff::one(), -60, 1),
            binary_working_context(
              binary_range_check_precision,
              rounding=RoundTowardNegative,
            ),
          ).0,
          binary_log2_e_bounds,
          2,
          0,
          false,
          false,
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      // expm1(x) >= exp(x) / 2 once it can overflow; it never underflows below -1.
      if !self.is_sign_minus() &&
        binary_log2_linear_out_of_range(
          self, binary_log2_e_bounds, 2, -1, false, false, context,
        )
        is Some(result) {
        return Ok(result)
      }
      if binary_tiny_argument_result(
          self,
          true,
          2L * binary_top_bound(self),
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      let mut budget = CertifiedRefinementBudget::new(
        context.precision + 64,
        limit=context.refinement_limit,
      )
      while budget.available() {
        match binary_expm1_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_edge_rounding(
              bounds.0,
              bounds.1,
              context,
              budget.precision(),
              false,
              fn() {
                binary_exp_overflow_side(
                  self,
                  budget.precision(),
                  inexact_above=true,
                )
              },
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
pub fn Binary::expm1_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_expm1_ctx(context), context)
}

///|
pub fn Binary::expm1(self : Binary) -> Binary {
  self.expm1_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_log1p_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.is_sign_minus() =>
      Ok((Binary::nan_raw(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          Binary::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let one = Binary::one_raw(precision=self.precision())
      if self.compare(one.neg()) < 0 {
        return Ok(binary_invalid_value(context))
      }
      if self.compare(one.neg()) == 0 {
        return Ok(
          (
            Binary::inf_raw(Sign::Negative, precision=context.precision),
            binary_division_by_zero_flags(),
          ),
        )
      }
      if self.is_zero() {
        return Ok(self.apply_ctx(context))
      }
      if binary_tiny_argument_result(
          self,
          false,
          2L * binary_top_bound(self),
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      let mut budget = CertifiedRefinementBudget::new(
        context.precision + 64,
        limit=context.refinement_limit,
      )
      while budget.available() {
        match binary_log1p_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
pub fn Binary::log1p_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_log1p_ctx(context), context)
}

///|
pub fn Binary::log1p(self : Binary) -> Binary {
  self.log1p_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_exp2_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.is_sign_minus() {
            Binary::zero_raw(precision=context.precision)
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((Binary::one_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      let unit = Binary::one_raw(precision=binary_range_check_precision)
      if binary_log2_linear_out_of_range(
          self,
          fn() { Some((unit, unit)) },
          1,
          0,
          true,
          false,
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      match binary_exact_bounded_int(self) {
        Some(exponent) =>
          // Round the dyadic 2^n directly: a one-bit Binary::make would
          // flush 2^n below 2^e_min to zero before the context sees it.
          return Ok(binary_round_dyadic(false, Coeff::one(), exponent, context))
        None => ()
      }
      let mut budget = CertifiedRefinementBudget::new(
        context.precision + 64,
        limit=context.refinement_limit,
      )
      while budget.available() {
        match binary_exp2_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
pub fn Binary::exp2_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_exp2_ctx(context), context)
}

///|
pub fn Binary::exp2(self : Binary) -> Binary {
  self.exp2_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_log2_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.is_sign_minus() =>
      Ok((Binary::nan_raw(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          Binary::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          Binary::inf_raw(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.is_sign_minus() => Ok(binary_invalid_value(context))
    FpClass::Finite if self.compare(Binary::one_raw(precision=self.precision())) ==
      0 =>
      Ok((Binary::zero_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      if self.coefficient_().compare(Coeff::one()) == 0 {
        let exact = Binary::from_int_raw(self.exponent2(), precision=64)
        return Ok(exact.apply_ctx(context))
      }
      let mut budget = CertifiedRefinementBudget::new(
        context.precision + 64,
        limit=context.refinement_limit,
      )
      while budget.available() {
        match binary_log2_bounds(self, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
pub fn Binary::log2_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_log2_ctx(context), context)
}

///|
pub fn Binary::log2(self : Binary) -> Binary {
  self.log2_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_exp10_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Ok(
        (
          if self.negative() {
            Binary::zero_raw(precision=context.precision)
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok((Binary::one_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      if binary_log2_linear_out_of_range(
          self, binary_log2_10_bounds, 2, 0, true, false, context,
        )
        is Some(result) {
        return Ok(result)
      }
      // 10^n = 5^n * 2^n is exact for an integer n >= 0. Past
      // max(4096, precision) the odd part 5^n has more than precision + 1 bits,
      // so the result is neither representable nor a rounding breakpoint.
      match binary_exact_bounded_int(self) {
        Some(exponent) if exponent >= 0 &&
          exponent <= Int32::max(4096, context.precision) => {
          let coefficient = Coeff::from_uint64(5UL).pow_nat(
            exponent.reinterpret_as_uint(),
          )
          let exact = Binary::make_coeff(
            coefficient,
            exponent,
            Int32::max(1, coefficient.bit_length()),
          )
          return Ok(exact.apply_ctx(context))
        }
        _ => ()
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_ln10_bounds(work) {
          Some(ln10) => {
            let downward = binary_working_context(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = binary_working_context(
              work,
              rounding=RoundTowardPositive,
            )
            let lower_input = self.with_precision_raw(
              work,
              BinaryRoundingMode::RoundTowardNegative,
            )
            let upper_input = self.with_precision_raw(
              work,
              BinaryRoundingMode::RoundTowardPositive,
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
              binary_bounds_at_ends(lower, upper, fn(point) {
                binary_exp_bounds(point, work)
              }) {
              Some(exp_bounds) => {
                let (result, unique, flags) = binary_certified_edge_rounding(
                  exp_bounds.0,
                  exp_bounds.1,
                  context,
                  work,
                  false,
                  fn() { binary_exp_overflow_side(self, work, decimal=true) },
                )
                if unique {
                  return Ok((result, flags))
                }
              }
              None =>
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("exp10", context, work, attempt))
    }
  }
}

///|
pub fn Binary::exp10_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_exp10_ctx(context), context)
}

///|
pub fn Binary::exp10(self : Binary) -> Binary {
  self.exp10_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_log10_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.negative() =>
      Ok((Binary::nan_raw(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          Binary::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          Binary::inf_raw(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.negative() => Ok(binary_invalid_value(context))
    FpClass::Finite if self.compare(Binary::one_raw(precision=self.precision())) ==
      0 =>
      Ok((Binary::zero_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Finite => {
      // x = 10^k = 5^k * 2^k needs an odd coefficient of more than k bits.
      let decimal_exponent = self.exponent2()
      if decimal_exponent > 0 && decimal_exponent < self.coefficient_bits() {
        let expected_coefficient = Coeff::from_uint64(5UL).pow_nat(
          decimal_exponent.reinterpret_as_uint(),
        )
        if self.coefficient_().compare(expected_coefficient) == 0 {
          let exact = Binary::from_int_raw(decimal_exponent, precision=64)
          return Ok(exact.apply_ctx(context))
        }
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match (binary_ln_bounds(self, work), binary_ln10_bounds(work)) {
          (Some(numerator), Some(denominator)) => {
            let downward = binary_working_context(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = binary_working_context(
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
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("log10", context, work, attempt))
    }
  }
}

///|
pub fn Binary::log10_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_log10_ctx(context), context)
}

///|
pub fn Binary::log10(self : Binary) -> Binary {
  self.log10_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_ln_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Finite if self.compare(Binary::one_raw(precision=self.precision())) ==
      0 =>
      Ok((Binary::zero_raw(precision=context.precision), BinaryFlags::new()))
    FpClass::Infinity if self.negative() =>
      Ok((Binary::nan_raw(precision=context.precision), binary_invalid_flags()))
    FpClass::Infinity =>
      Ok(
        (
          Binary::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          Binary::inf_raw(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        ),
      )
    FpClass::Finite if self.negative() => Ok(binary_invalid_value(context))
    FpClass::Finite => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_ln_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("ln", context, work, attempt))
    }
  }
}

///|
pub fn Binary::ln_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_ln_ctx(context), context)
}

///|
pub fn Binary::ln(self : Binary) -> Binary {
  self.ln_ctx(binary_working_context(self.precision())).0
}

///|
/// For finite nonzero `a` and `b` with `|b|` far below `|a|`, hypot(a, b) lies
/// in `(|a|, |a| + b^2 / (2|a|)]`. With `|a| = c * 2^e`, every rounding breakpoint
/// of the target precision is a multiple of `g = 2^min(e, top(a) - precision - 1)`,
/// and so is `|a|`; as long as `b^2 < 2 |a| g` no breakpoint lies in that range and
/// every such `b` rounds alike. `|b| < 2^(min(e, top(a) - precision - 1) - 3)`
/// is enough, and the smaller operand is then replaced by that power of two, so
/// the exact sum of squares stays small however far apart the exponents are.
fn binary_hypot_negligible_operand(
  left : Binary,
  right : Binary,
  context : BinaryContext,
) -> (Binary, Binary)? {
  guard left.classify() == FpClass::Finite &&
    right.classify() == FpClass::Finite &&
    !left.is_zero() &&
    !right.is_zero() else {
    return None
  }
  let left_top = left.exponent2().to_int64() +
    (left.coefficient_bits() - 1).to_int64()
  let right_top = right.exponent2().to_int64() +
    (right.coefficient_bits() - 1).to_int64()
  let (large, large_top, small_top) = if left_top >= right_top {
    (left, left_top, right_top)
  } else {
    (right, right_top, left_top)
  }
  let bound = Int64::min(
      large.exponent2().to_int64(),
      large_top - context.precision.to_int64() - 1L,
    ) -
    2L
  guard small_top < bound - 1L && bound >= -2147483648L else { return None }
  // A Binary of width w stores nothing below 2^(e_min - (w - 1)), so the
  // power of two is built wide enough to be kept, not flushed to zero or to
  // 2^e_min when it lies in the implementation subnormal range.
  let width = binary_value_e_min.to_int64() - (bound - 1L) + 2L
  guard width <= 1073741824L else { return None }
  let replacement = Binary::make_coeff(
    Coeff::one(),
    (bound - 1L).to_int(),
    Int64::max(1L, width).to_int(),
  )
  Some((large.abs(), replacement))
}

///|
pub fn Binary::try_hypot_ctx(
  self : Binary,
  other : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  // IEEE 754-2019 9.2: hypot(+-inf, qNaN) is +inf. A signaling NaN operand is
  // an invalid operation (7.2 a) with a quiet NaN result, even beside an
  // infinity, so it goes to the NaN handling below.
  if (self.class() == FpClass::Infinity || other.class() == FpClass::Infinity) &&
    !self.is_signaling_nan() &&
    !other.is_signaling_nan() {
    return Ok(
      (
        Binary::inf_raw(Sign::Positive, precision=context.precision),
        BinaryFlags::new(),
      ),
    )
  }
  match binary_nan_pair(self, other, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  match binary_hypot_negligible_operand(self, other, context) {
    Some(operands) => return operands.0.try_hypot_ctx(operands.1, context)
    None => ()
  }
  // |x|^2 + |y|^2 = T * 2^(2 m) with m the smaller exponent of the nonzero
  // operands: the exponent stays at the operands' own scale (it is halved by
  // the square root below), so operands near 2^+-2^30 do not leave the range
  // of the exponent field or of Binary::make.
  if self.is_zero() && other.is_zero() {
    return Ok(
      (Binary::zero_raw(precision=context.precision), BinaryFlags::new()),
    )
  }
  let left_exponent = if self.is_zero() {
    other.exponent2().to_int64()
  } else {
    self.exponent2().to_int64()
  }
  let right_exponent = if other.is_zero() {
    self.exponent2().to_int64()
  } else {
    other.exponent2().to_int64()
  }
  let half_exponent = Int64::min(left_exponent, right_exponent)
  let left_shift = (left_exponent - half_exponent) * 2L
  let right_shift = (right_exponent - half_exponent) * 2L
  guard left_shift <= 1_000_000L && right_shift <= 1_000_000L else {
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
  let left_square = self.coefficient_().mul(self.coefficient_())
  let right_square = other.coefficient_().mul(other.coefficient_())
  let sum = left_square
    .shift_left(left_shift.to_int())
    .add(right_square.shift_left(right_shift.to_int()))
  Ok(binary_round_sqrt_half_exponent(sum, half_exponent.to_int(), context))
}

///|
/// The correctly rounded square root of `magnitude * 2^(2 * half_exponent)`,
/// with the doubled exponent never formed: `binary_round_sqrt` with an exponent
/// that is even by construction, for sums of squares whose own exponent would
/// leave the 32-bit range.
fn binary_round_sqrt_half_exponent(
  magnitude : Coeff,
  half_exponent : Int32,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  let exact_top = binary_add_sat(
    binary_floor_div2(magnitude.bit_length() - 1),
    half_exponent,
  )
  if exact_top > context.range_e_max() {
    return binary_overflow_result(false, context)
  }
  let target_exponent = binary_target_exponent(exact_top, context)
  let scale = binary_mul_sat(2, binary_sub_sat(half_exponent, target_exponent))
  let (floor_root, exact, midpoint_comparison) = binary_sqrt_split(
    magnitude, scale,
  )
  let (round_bit, sticky) = binary_sqrt_round_bits(exact, midpoint_comparison)
  let unbounded_target = binary_sub_sat(exact_top, context.precision - 1)
  let unbounded_scale = binary_mul_sat(
    2,
    binary_sub_sat(half_exponent, unbounded_target),
  )
  let (unbounded_root, unbounded_exact, unbounded_midpoint_comparison) = if unbounded_scale ==
    scale {
    (floor_root, exact, midpoint_comparison)
  } else {
    binary_sqrt_split(magnitude, unbounded_scale)
  }
  let (unbounded_guard, unbounded_sticky) = binary_sqrt_round_bits(
    unbounded_exact, unbounded_midpoint_comparison,
  )
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_root,
    unbounded_guard,
    unbounded_sticky,
    false,
    context.rounding,
  )
  binary_round_pack(
    false,
    floor_root,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}

///|
pub fn Binary::hypot_ctx(
  self : Binary,
  other : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_hypot_ctx(other, context), context)
}

///|
pub fn Binary::hypot(self : Binary, other : Binary) -> Binary {
  self.hypot_ctx(
    other,
    binary_working_context(Int32::max(self.precision(), other.precision())),
  ).0
}

///|
fn binary_rootn_positive_bounds(
  value : Binary,
  degree : Int64,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match binary_ln_bounds(value, work_precision) {
    None => None
    Some(logarithm) => {
      let downward = binary_working_context(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = binary_working_context(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let divisor = Binary::make_coeff(
        Coeff::from_uint64(degree.reinterpret_as_uint64()),
        0,
        work_precision,
      )
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
      binary_bounds_at_ends(lower, upper, fn(point) {
        binary_exp_bounds(point, work_precision)
      })
    }
  }
}

///|
/// floor(value^(1 / degree)) for degree >= 2. Small roots are found by
/// bisection; larger ones by integer Newton steps from an overestimate taken
/// from the root of the leading bits, which needs a few full-size products and
/// divisions instead of one power per root bit.
fn binary_floor_nth_root(value : Coeff, degree : Int32) -> Coeff {
  let bits = value.bit_length()
  if bits <= degree {
    // value < 2^degree, so the root is 0 or 1.
    return if value.is_zero() { Coeff::zero() } else { Coeff::one() }
  }
  let exponent = degree.reinterpret_as_uint()
  // The root is below 2^root_bits.
  let root_bits = (bits + degree - 1) / degree
  if root_bits <= 64 {
    let one = Coeff::one()
    let mut lower = Coeff::zero()
    let mut upper = one.shift_left(root_bits)
    while upper.sub_checked(lower).unwrap().compare(one) > 0 {
      let midpoint = lower.add(upper).shift_right(1)
      if midpoint.pow_nat(exponent).compare(value) <= 0 {
        lower = midpoint
      } else {
        upper = midpoint
      }
    }
    return lower
  }
  // With high = floor((value >> (degree * half))^(1 / degree)), value is
  // below ((high + 1) * 2^half)^degree, so that start exceeds the root.
  let half = root_bits / 2
  let high = binary_floor_nth_root(value.shift_right(half * degree), degree)
  let mut root = high.add(Coeff::one()).shift_left(half)
  let previous_degree = Coeff::from_uint64((degree - 1).to_uint64())
  let divisor = Coeff::from_uint64(degree.to_uint64())
  // From any x above the root, y = floor(((degree - 1) x +
  // floor(value / x^(degree - 1))) / degree) satisfies root <= y < x (AM-GM),
  // and at x = root the step does not decrease.
  while true {
    let quotient = value.div_rem_checked(root.pow_nat(exponent - 1U)).unwrap().0
    let next = root
      .mul(previous_degree)
      .add(quotient)
      .div_rem_checked(divisor)
      .unwrap().0
    if next.compare(root) >= 0 {
      break
    }
    root = next
  }
  root
}

///|
/// The exact `degree`-th root of `coefficient`, if it is a perfect power. Even
/// degrees take exact square roots first, which stop at the first nonzero
/// remainder.
fn binary_exact_nth_root_coefficient(
  coefficient : Coeff,
  degree : Int32,
) -> Coeff? {
  guard degree > 1 else { return None }
  if coefficient.compare(Coeff::one()) == 0 {
    return Some(Coeff::one())
  }
  // A root r >= 2 has r^degree >= 2^degree, so a coefficient with at most
  // `degree` bits other than 1 is not a perfect power of that degree.
  guard degree < coefficient.bit_length() else { return None }
  let mut value = coefficient
  let mut remaining = degree
  while remaining % 2 == 0 {
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(value)
    guard remainder.is_zero() else { return None }
    value = root
    remaining = remaining / 2
  }
  if remaining == 1 || value.compare(Coeff::one()) == 0 {
    return Some(value)
  }
  guard remaining < value.bit_length() else { return None }
  let root = binary_floor_nth_root(value, remaining)
  if root.pow_nat(remaining.reinterpret_as_uint()).compare(value) == 0 {
    Some(root)
  } else {
    None
  }
}

///|
fn binary_exact_rootn_int64(value : Binary, degree : Int64) -> Binary? {
  guard degree > 1L && value.exponent2().to_int64() % degree == 0L else {
    return None
  }
  let coefficient = if degree <= 2147483647L {
    binary_exact_nth_root_coefficient(value.coefficient_(), degree.to_int())
  } else if value.coefficient_().compare(Coeff::one()) == 0 {
    Some(Coeff::one())
  } else {
    None
  }
  match coefficient {
    Some(coefficient) =>
      Some(
        Binary::make_coeff(
          coefficient,
          (value.exponent2().to_int64() / degree).to_int(),
          Int32::max(1, coefficient.bit_length()),
          negative=value.is_sign_minus(),
        ),
      )
    None => None
  }
}

///|
/// The certified Ziv loop of `rootn` through `exp(ln(x) / n)`: the path for
/// degrees too large for the integer root, and the reference of its tests.
fn binary_rootn_certified_loop(
  original : Binary,
  positive : Binary,
  degree : Int32,
  magnitude_degree : Int64,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  let mut work = Int32::max(context.precision + 64, positive.precision() + 16)
  let mut attempt = 0
  while @internal.certified_refinement_continues(
          context.refinement_limit,
          attempt,
          work,
          context.precision,
        ) {
    match binary_rootn_positive_bounds(positive, magnitude_degree, work) {
      Some(bounds) => {
        let signed_bounds = if original.negative() {
          (bounds.1.neg(), bounds.0.neg())
        } else {
          bounds
        }
        let adjusted = if degree < 0 {
          let downward = binary_working_context(
            work,
            rounding=RoundTowardNegative,
          )
          let upward = binary_working_context(
            work,
            rounding=RoundTowardPositive,
          )
          let one = Binary::one_raw(precision=work)
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
        return Err(binary_range_failure_state("rootn", context, work, attempt))
    }
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("rootn", context, work, attempt))
}

///|
pub fn Binary::try_rootn_ctx(
  self : Binary,
  degree : Int32,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  guard degree != 0 else { return Ok(binary_invalid_value(context)) }
  let degree64 = degree.to_int64()
  let magnitude_degree = if degree64 < 0L { -degree64 } else { degree64 }
  let odd = magnitude_degree % 2L != 0L
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity if self.negative() && !odd =>
      Ok(binary_invalid_value(context))
    FpClass::Infinity => {
      let negative = self.negative() && odd
      if degree < 0 {
        Ok(
          (
            if negative {
              Binary::negative_zero_raw(precision=context.precision)
            } else {
              Binary::zero_raw(precision=context.precision)
            },
            BinaryFlags::new(),
          ),
        )
      } else {
        Ok(
          (
            Binary::inf_raw(
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
      let negative = self.negative() && odd
      if degree < 0 {
        Ok(
          (
            Binary::inf_raw(
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
              Binary::negative_zero_raw(precision=context.precision)
            } else {
              Binary::zero_raw(precision=context.precision)
            },
            BinaryFlags::new(),
          ),
        )
      }
    }
    FpClass::Finite if self.negative() && !odd =>
      Ok(binary_invalid_value(context))
    FpClass::Finite => {
      let positive = self.abs()
      if magnitude_degree == 1 {
        if degree < 0 {
          return Ok(
            Binary::one_raw(precision=context.precision).div_ctx(self, context),
          )
        }
        return Ok(self.apply_ctx(context))
      }
      // An exact root r is returned as r, or as the correctly rounded 1 / r for
      // a negative degree; the Ziv loop below cannot certify an exact result.
      match binary_exact_rootn_int64(self, magnitude_degree) {
        Some(exact) =>
          return Ok(
            if degree > 0 {
              exact.apply_ctx(context)
            } else {
              Binary::one_raw(precision=context.precision).div_ctx(
                exact, context,
              )
            },
          )
        None => ()
      }
      if binary_rootn_integer_enabled(magnitude_degree, context.precision) {
        return Ok(binary_rootn_integer(self, degree, context))
      }
      binary_rootn_certified_loop(
        self, positive, degree, magnitude_degree, context,
      )
    }
  }
}

///|
pub fn Binary::rootn_ctx(
  self : Binary,
  degree : Int32,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_rootn_ctx(degree, context), context)
}

///|
pub fn Binary::rootn(self : Binary, degree : Int32) -> Binary {
  self.rootn_ctx(degree, binary_working_context(self.precision())).0
}

///|
fn binary_exact_bounded_int(value : Binary) -> Int32? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() {
    return Some(0)
  }
  guard value.exponent2() >= 0 &&
    value.exponent2() <= 30 &&
    value.coefficient_bits() + value.exponent2() <= 31 else {
    return None
  }
  match value.coefficient_().shift_left(value.exponent2()).to_uint64() {
    Some(magnitude) => {
      let integer = magnitude.reinterpret_as_int64().to_int()
      Some(if value.is_sign_minus() { -integer } else { integer })
    }
    None => None
  }
}

///|
fn binary_exact_unit_fraction_degree(value : Binary) -> Int32? {
  guard value.classify() == FpClass::Finite &&
    value.coefficient_().compare(Coeff::one()) == 0 &&
    value.exponent2() < 0 &&
    value.exponent2() >= -29 else {
    return None
  }
  let degree = 1 << -value.exponent2()
  Some(if value.is_sign_minus() { -degree } else { degree })
}

///|
/// Cheap filter for `pow`: |log2(base)| < |top(base)| + 1 and
/// |exponent| < 2^(top(exponent) + 1), so most calls cannot reach the limits.
fn binary_pow_may_leave_range(
  base : Binary,
  exponent : Binary,
  context : BinaryContext,
) -> Bool {
  let base_top = base.exact_top().to_int64()
  let exponent_top = binary_exact_top(
    exponent.coefficient_(),
    exponent.exponent2_(),
  )
  if exponent_top >= 30 {
    return true
  }
  let log_bound = (if base_top < 0L { -base_top } else { base_top }) + 1L
  let reach = log_bound * (1L << (exponent_top + 1))
  reach >= context.range_e_max().to_int64() + 1L ||
  -reach <= context.range_e_min().to_int64() - context.precision.to_int64()
}

///|
/// What `binary_pow_exactness` knows about `x^y` for a positive finite base
/// and a finite nonzero exponent that `pown` does not take.
priv enum BinaryPowExactness {
  /// The exact result, correctly rounded.
  Exact((Binary, BinaryFlags))
  /// The result is irrational, not dyadic, or has more than `precision + 1`
  /// significant bits, so it is never a rounding breakpoint of the context.
  NotBreakpoint
  /// Neither was shown; the loop must not assume the result is inexact.
  Undecided
}

///|
/// Exact `pow` results the Ziv loop cannot certify. For a positive finite base
/// `c * 2^e` (c odd) and a non-integer exponent `m / 2^k` (m odd), `x^y` is
/// dyadic exactly when `2^k` divides `e` and `c` is a perfect `2^k`-th power `r`,
/// and then it is `r^m * 2^(m * e / 2^k)` (only for `r = 1` when `m < 0`). Every
/// other result is irrational or not dyadic, and so is never a rounding
/// breakpoint. A dyadic result whose odd part is too large to compute has more
/// than `precision + 1` significant bits and is not a breakpoint either.
fn binary_pow_exactness(
  base : Binary,
  exponent : Binary,
  context : BinaryContext,
) -> BinaryPowExactness {
  guard base.classify() == FpClass::Finite &&
    !base.is_zero() &&
    !base.is_sign_minus() &&
    exponent.classify() == FpClass::Finite &&
    !exponent.is_zero() else {
    return Undecided
  }
  let unit_base = base.coefficient_().compare(Coeff::one()) == 0
  let shift = -exponent.exponent2()
  if shift <= 0 {
    // An integer exponent outside the `pown` range has |y| >= 2^31. For c > 1,
    // c^y has more than 2^31 > precision + 1 bits, and c^-y is not dyadic.
    return if unit_base { Undecided } else { NotBreakpoint }
  }
  if shift >= 31 {
    // 2^k with k >= 31 divides e only for e = 0 or e = -2^31, and an odd c > 1
    // has fewer than 2^31 bits, below the 3^(2^k) of a perfect 2^k-th power.
    let exponent2 = base.exponent2()
    return if unit_base && (exponent2 == 0 || exponent2.ctz() >= shift) {
      Undecided
    } else {
      NotBreakpoint
    }
  }
  let degree = 1 << shift
  guard base.exponent2() % degree == 0 else { return NotBreakpoint }
  let root = match
    binary_exact_nth_root_coefficient(base.coefficient_(), degree) {
    Some(root) => root
    None => return NotBreakpoint
  }
  let unit_root = root.compare(Coeff::one()) == 0
  guard unit_root || !exponent.is_sign_minus() else { return NotBreakpoint }
  let numerator = match exponent.coefficient_().to_uint64() {
    Some(value) if value < 1UL << 31 => value.reinterpret_as_int64()
    // r^m with r >= 3 and m >= 2^31 has more than precision + 1 bits.
    _ => return if unit_root { Undecided } else { NotBreakpoint }
  }
  // r^m has at least m * (bits(r) - 1) + 1 >= m * bits(r) / 2 bits.
  guard unit_root ||
    numerator * root.bit_length().to_int64() <=
    2L * context.precision.to_int64() + 64L else {
    return NotBreakpoint
  }
  let power = if unit_root {
    Coeff::one()
  } else {
    root.pow_nat(numerator.to_int().reinterpret_as_uint())
  }
  let scale = (base.exponent2() / degree).to_int64() *
    (if exponent.is_sign_minus() { -numerator } else { numerator })
  guard scale >= -2147483648L && scale <= 2147483647L else { return Undecided }
  // Rounded as a dyadic: a Binary::make of power * 2^scale would flush it to
  // zero when it lies below 2^e_min, before the context rounds it.
  Exact(binary_round_dyadic(false, power, scale.to_int(), context))
}

///|
pub fn Binary::try_pow_ctx(
  self : Binary,
  exponent : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  // IEEE 754-2019 9.2.1: pow(x, +-0) is 1 "if x is not a signaling NaN", and
  // pow(+1, y) is 1 for any y, which does not cover a signaling NaN: a
  // signaling NaN operand is an invalid operation (7.2 a) before the shortcuts.
  if self.is_signaling_nan() || exponent.is_signaling_nan() {
    match binary_nan_pair(self, exponent, context.precision) {
      Some(result) => return Ok(result)
      None => ()
    }
  }
  if exponent.classify() == FpClass::Finite && exponent.is_zero() {
    return Ok(
      (Binary::one_raw(precision=context.precision), BinaryFlags::new()),
    )
  }
  if self.classify() == FpClass::Finite &&
    self.compare(Binary::one_raw(precision=self.precision())) == 0 {
    return Ok(
      (Binary::one_raw(precision=context.precision), BinaryFlags::new()),
    )
  }
  match binary_exact_bounded_int(exponent) {
    Some(integer) => return Ok(self.pown_ctx(integer, context))
    None => ()
  }
  match binary_nan_pair(self, exponent, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  // Coefficients are odd, so a finite nonzero exponent is an integer exactly
  // when exponent2 >= 0 and an odd integer exactly when exponent2 == 0.
  let exponent_finite = exponent.classify() == FpClass::Finite
  let exponent_integer = exponent_finite && exponent.exponent2() >= 0
  let exponent_odd = exponent_finite && exponent.exponent2() == 0
  if exponent.classify() == FpClass::Infinity {
    // IEEE 754-2019 §9.2.1: pow(-1, ±inf) is 1, and otherwise the result is
    // +0 or +inf by |x| against 1, without an exception (also for x = ±0).
    let comparison = self
      .abs()
      .compare(Binary::one_raw(precision=self.precision()))
    if comparison == 0 {
      return Ok(
        (Binary::one_raw(precision=context.precision), BinaryFlags::new()),
      )
    }
    let grows = (comparison > 0) == (exponent.signum() == Sign::Positive)
    return Ok(
      (
        if grows {
          Binary::inf_raw(Sign::Positive, precision=context.precision)
        } else {
          Binary::zero_raw(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  // The result of a zero or infinite base is negative only for a negative base
  // and an odd integer exponent.
  let negative_result = self.is_sign_minus() && exponent_odd
  if self.classify() == FpClass::Infinity {
    return Ok(
      (
        if exponent.is_sign_minus() {
          if negative_result {
            Binary::negative_zero_raw(precision=context.precision)
          } else {
            Binary::zero_raw(precision=context.precision)
          }
        } else {
          Binary::inf_raw(
            if negative_result {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          )
        },
        BinaryFlags::new(),
      ),
    )
  }
  if self.is_zero() {
    if exponent.is_sign_minus() {
      return Ok(
        (
          Binary::inf_raw(
            if negative_result {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          binary_division_by_zero_flags(),
        ),
      )
    }
    return Ok(
      (
        if negative_result {
          Binary::negative_zero_raw(precision=context.precision)
        } else {
          Binary::zero_raw(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  if self.is_sign_minus() {
    guard exponent_integer else { return Ok(binary_invalid_value(context)) }
    // An integer exponent beyond the `pown` range: |x|^y, negated for an odd
    // y, which also mirrors the directed rounding modes.
    if !exponent_odd {
      return self.abs().try_pow_ctx(exponent, context)
    }
    let mirrored = {
      ..context,
      rounding: match context.rounding {
        RoundTowardPositive => RoundTowardNegative
        RoundTowardNegative => RoundTowardPositive
        mode => mode
      },
    }
    return self
      .abs()
      .try_pow_ctx(exponent, mirrored)
      .map(fn(result) { (result.0.neg(), result.1) })
  }
  match binary_exact_unit_fraction_degree(exponent) {
    Some(degree) => return self.try_rootn_ctx(degree, context)
    None => ()
  }
  // log2(result) = exponent * log2(base). The Ziv loop below cannot certify a
  // result whose own enclosure overflows, so certain overflow and underflow
  // are decided first from directed log2 bounds of the base.
  let range_down = binary_working_context(
    binary_range_check_precision,
    rounding=RoundTowardNegative,
  )
  let range_up = binary_working_context(
    binary_range_check_precision,
    rounding=RoundTowardPositive,
  )
  if binary_pow_may_leave_range(self, exponent, context) &&
    self.try_log2_ctx(range_down) is Ok((log_low, _)) &&
    self.try_log2_ctx(range_up) is Ok((log_high, _)) &&
    !log_low.is_zero() &&
    !log_high.is_zero() &&
    log_low.is_sign_minus() == log_high.is_sign_minus() {
    let (value, scale) = if log_low.is_sign_minus() {
      (exponent.neg(), (log_high.neg(), log_low.neg()))
    } else {
      (exponent, (log_low, log_high))
    }
    let scale_top = binary_exact_top(
      scale.1.coefficient_(),
      scale.1.exponent2_(),
    )
    if binary_log2_linear_out_of_range(
        value,
        fn() { Some(scale) },
        Int32::max(0, scale_top + 1),
        0,
        true,
        false,
        context,
      )
      is Some(result) {
      return Ok(result)
    }
  }
  // A result that is not a rounding breakpoint lets the loop move an exact
  // enclosure end inside the enclosure: x^y with a tiny y lies within
  // |y ln x| of 1, and the end at 1 would otherwise never round like the
  // other one (#102 for the other elementary functions).
  let inexact_result = match binary_pow_exactness(self, exponent, context) {
    Exact(result) => return Ok(result)
    NotBreakpoint => true
    Undecided => false
  }
  let mut work = Int32::max(
    context.precision + 64,
    Int32::max(self.precision(), exponent.precision()) + 16,
  )
  let mut attempt = 0
  while @internal.certified_refinement_continues(
          context.refinement_limit,
          attempt,
          work,
          context.precision,
        ) {
    match binary_ln_bounds(self, work) {
      Some(logarithm) => {
        let downward = binary_working_context(
          work,
          rounding=RoundTowardNegative,
        )
        let upward = binary_working_context(work, rounding=RoundTowardPositive)
        let exponent_lower = exponent.with_precision_raw(
          work,
          BinaryRoundingMode::RoundTowardNegative,
        )
        let exponent_upper = exponent.with_precision_raw(
          work,
          BinaryRoundingMode::RoundTowardPositive,
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
        match
          binary_bounds_at_ends(lower, upper, fn(point) {
            binary_exp_bounds(point, work)
          }) {
          Some(exp_bounds) => {
            let (result, unique, flags) = if exp_bounds.1.classify() ==
              FpClass::Infinity &&
              exp_bounds.0.classify() == FpClass::Finite {
              // x^y = exp(y ln x) overflowed the implementation range: the
              // enclosure of y ln x against the threshold decides, as for exp.
              binary_certified_edge_rounding(
                exp_bounds.0,
                exp_bounds.1,
                context,
                work,
                false,
                fn() { binary_exp_interval_overflow_side(lower, upper, work) },
              )
            } else if inexact_result {
              binary_certified_inexact_target_rounding(
                exp_bounds.0,
                exp_bounds.1,
                context,
              )
            } else {
              binary_certified_target_rounding(
                exp_bounds.0,
                exp_bounds.1,
                context,
              )
            }
            if unique {
              return Ok((result, flags))
            }
          }
          None =>
            return Err(
              binary_range_failure_state("pow", context, work, attempt),
            )
        }
      }
      None =>
        return Err(binary_range_failure_state("pow", context, work, attempt))
    }
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("pow", context, work, attempt))
}

///|
pub fn Binary::pow_ctx(
  self : Binary,
  exponent : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_pow_ctx(exponent, context), context)
}

///|
pub fn Binary::pow(self : Binary, exponent : Binary) -> Binary {
  self.pow_ctx(
    exponent,
    binary_working_context(Int32::max(self.precision(), exponent.precision())),
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
/// The enclosure of `sinh |x|` or `cosh |x|` for an argument whose `e^|x|` overflows
/// the implementation range: `sinh |x| = e^(|x| - ln 2) (1 - e^(-2 |x|))` and
/// `cosh |x| = e^(|x| - ln 2) (1 + e^(-2 |x|))` with `e^(-2 |x|)` below the
/// working precision (the argument is above 2^29, so below `2^-(2^30)`), taken as
/// one outward unit `2^-(work - 1)`; `ln 2` and the difference are formed 40 bits
/// wider than the working precision (the argument has up to 30 integer bits).
fn binary_hyperbolic_edge_bounds(
  magnitude : Binary,
  operation : BinaryHyperbolicOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let wide = work_precision + 40
  guard binary_ln2_bounds(wide) is Some((ln2_low, ln2_high)) else {
    return None
  }
  let down_wide = binary_working_context(wide, rounding=RoundTowardNegative)
  let up_wide = binary_working_context(wide, rounding=RoundTowardPositive)
  let exponent_low = magnitude.sub_ctx(ln2_high, down_wide).0
  let exponent_high = magnitude.sub_ctx(ln2_low, up_wide).0
  guard binary_exp_bounds(exponent_low, work_precision) is Some(low_bounds) &&
    binary_exp_bounds(exponent_high, work_precision) is Some(high_bounds) else {
    return None
  }
  let down = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let up = binary_working_context(work_precision, rounding=RoundTowardPositive)
  let unit = Binary::make_coeff(
    Coeff::one(),
    -(work_precision - 1),
    work_precision,
  )
  let one = Binary::one_raw(precision=work_precision)
  let lower = match operation {
    BinaryHyperbolicOperation::Sinh =>
      low_bounds.0.mul_ctx(one.sub_ctx(unit, down).0, down).0
    _ => low_bounds.0
  }
  let upper = match operation {
    BinaryHyperbolicOperation::Cosh =>
      high_bounds.1.mul_ctx(one.add_ctx(unit, up).0, up).0
    _ => high_bounds.1
  }
  Some((lower, upper))
}

///|
fn binary_hyperbolic_bounds(
  value : Binary,
  operation : BinaryHyperbolicOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  match binary_exp_bounds(value, work_precision) {
    Some(positive_exp) => {
      // exp(-x) = 1 / exp(x): [1 / U, 1 / L] when 0 < L (the enclosure of exp
      // of a finite argument is positive); otherwise the kernel on -x.
      let negative_exp = if positive_exp.0.compare(Binary::zero_raw()) > 0 {
        let one = Binary::one_raw(precision=work_precision)
        Some(
          (
            one.div_ctx(positive_exp.1, downward).0,
            one.div_ctx(positive_exp.0, upward).0,
          ),
        )
      } else {
        binary_exp_bounds(value.neg(), work_precision)
      }
      guard negative_exp is Some(negative_exp) else { return None }
      let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
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
      // `e^|x|` overflowed the implementation range although the result may not
      // (sinh and cosh are about `e^|x| / 2`): the enclosure then cannot reach the
      // result next to `2^(e_max + 1)`, so it comes from `exp(|x| - ln 2)`.
      if !(operation is BinaryHyperbolicOperation::Tanh) &&
        (
          sinh.0.classify() == FpClass::Infinity ||
          sinh.1.classify() == FpClass::Infinity ||
          cosh.1.classify() == FpClass::Infinity
        ) {
        guard binary_hyperbolic_edge_bounds(
            value.abs(),
            operation,
            work_precision,
          )
          is Some(edge) else {
          return None
        }
        return if operation is BinaryHyperbolicOperation::Sinh &&
          value.is_sign_minus() {
          Some((edge.1.neg(), edge.0.neg()))
        } else {
          Some(edge)
        }
      }
      match operation {
        BinaryHyperbolicOperation::Sinh => Some(sinh)
        BinaryHyperbolicOperation::Cosh => Some(cosh)
        BinaryHyperbolicOperation::Tanh => {
          // tanh = sinh / cosh with cosh >= 1 > 0 on the enclosure (cosh.0 is a
          // lower bound of cosh >= 1, positive at any working precision), so
          // for s in [s0, s1], c in [c0, c1] with 0 < c0 <= c1 the quotient s / c
          // is increasing in s and, for s >= 0, decreasing in c (the reverse
          // for s < 0): the extremes sit at
          //   lower = s0 >= 0 ? s0 / c1 : s0 / c0,
          //   upper = s1 >= 0 ? s1 / c0 : s1 / c1.
          let zero = Binary::zero_raw()
          let lower = if sinh.0.compare(zero) >= 0 {
            sinh.0.div_ctx(cosh.1, downward).0
          } else {
            sinh.0.div_ctx(cosh.0, downward).0
          }
          let upper = if sinh.1.compare(zero) >= 0 {
            sinh.1.div_ctx(cosh.0, upward).0
          } else {
            sinh.1.div_ctx(cosh.1, upward).0
          }
          Some((lower, upper))
        }
      }
    }
    None => None
  }
}

///|
fn Binary::try_hyperbolic_ctx(
  self : Binary,
  operation : BinaryHyperbolicOperation,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
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
              Binary::inf_raw(self.signum(), precision=context.precision)
            BinaryHyperbolicOperation::Cosh =>
              Binary::inf_raw(Sign::Positive, precision=context.precision)
            BinaryHyperbolicOperation::Tanh =>
              if self.is_sign_minus() {
                Binary::one_raw(precision=context.precision).neg()
              } else {
                Binary::one_raw(precision=context.precision)
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
              Binary::one_raw(precision=context.precision)
            _ =>
              if self.is_negative_zero() {
                Binary::negative_zero_raw(precision=context.precision)
              } else {
                Binary::zero_raw(precision=context.precision)
              }
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      // |sinh x| and cosh x are at least exp(|x|) / 4 once they can overflow.
      if !(operation is BinaryHyperbolicOperation::Tanh) &&
        binary_log2_linear_out_of_range(
          self.abs(),
          binary_log2_e_bounds,
          2,
          -2,
          false,
          operation is BinaryHyperbolicOperation::Sinh && self.is_sign_minus(),
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      // |x| <= 1/2: 0 < sinh x - x <= |x|^3 (sign of x), 0 < x - tanh x <= |x|^3
      // (sign of x) and 0 < cosh x - 1 <= x^2.
      if operation is BinaryHyperbolicOperation::Tanh &&
        binary_tanh_saturation(self, context) is Some(result) {
        return Ok(result)
      }
      let tiny = match operation {
        BinaryHyperbolicOperation::Sinh =>
          binary_tiny_argument_result(
            self,
            !self.is_sign_minus(),
            3L * binary_top_bound(self),
            context,
          )
        BinaryHyperbolicOperation::Tanh =>
          binary_tiny_argument_result(
            self,
            self.is_sign_minus(),
            3L * binary_top_bound(self),
            context,
          )
        BinaryHyperbolicOperation::Cosh =>
          binary_tiny_argument_result(
            Binary::one_raw(precision=context.precision),
            true,
            2L * binary_top_bound(self),
            context,
          )
      }
      if tiny is Some(result) {
        return Ok(result)
      }
      let mut work = Int32::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_hyperbolic_bounds(self, operation, work) {
          Some(bounds) => {
            let (result, unique, flags) = if operation
              is BinaryHyperbolicOperation::Tanh {
              binary_certified_inexact_target_rounding(
                bounds.0,
                bounds.1,
                context,
              )
            } else {
              binary_certified_edge_rounding(
                bounds.0,
                bounds.1,
                context,
                work,
                operation is BinaryHyperbolicOperation::Sinh &&
                self.is_sign_minus(),
                fn() {
                  binary_exp_overflow_side(
                    self.abs(),
                    work,
                    count=binary_value_e_max + 2,
                    inexact_above=operation is BinaryHyperbolicOperation::Sinh,
                    inexact_below=operation is BinaryHyperbolicOperation::Cosh,
                  )
                },
              )
            }
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
        work += Int32::max(32, work / 2)
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
pub fn Binary::try_sinh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Sinh, context)
}

///|
pub fn Binary::sinh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_sinh_ctx(context), context)
}

///|
pub fn Binary::sinh(self : Binary) -> Binary {
  self.sinh_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_cosh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Cosh, context)
}

///|
pub fn Binary::cosh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_cosh_ctx(context), context)
}

///|
pub fn Binary::cosh(self : Binary) -> Binary {
  self.cosh_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_tanh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_hyperbolic_ctx(BinaryHyperbolicOperation::Tanh, context)
}

///|
pub fn Binary::tanh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_tanh_ctx(context), context)
}

///|
pub fn Binary::tanh(self : Binary) -> Binary {
  self.tanh_ctx(binary_working_context(self.precision())).0
}

///|
#derive(Eq)
priv enum BinaryInverseHyperbolicOperation {
  Asinh
  Acosh
  Atanh
}

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
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let lower_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  match
    (
      lower_value.try_hypot_ctx(one, downward),
      upper_value.try_hypot_ctx(one, upward),
    ) {
    (Ok(lower_hypot), Ok(upper_hypot)) => {
      let lower_argument = lower_value.add_ctx(lower_hypot.0, downward).0
      let upper_argument = upper_value.add_ctx(upper_hypot.0, upward).0
      binary_bounds_at_ends(lower_argument, upper_argument, fn(point) {
        binary_ln_bounds(point, work_precision)
      })
    }
    _ => None
  }
}

///|
fn binary_acosh_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let lower_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
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
  binary_bounds_at_ends(lower_argument, upper_argument, fn(point) {
    binary_ln_bounds(point, work_precision)
  })
}

///|
fn binary_atanh_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
  let lower_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let lower_numerator = one.add_ctx(lower_value, downward).0
  let upper_numerator = one.add_ctx(upper_value, upward).0
  let lower_denominator = one.sub_ctx(upper_value, downward).0
  let upper_denominator = one.sub_ctx(lower_value, upward).0
  let lower_ratio = lower_numerator.div_ctx(upper_denominator, downward).0
  let upper_ratio = upper_numerator.div_ctx(lower_denominator, upward).0
  match
    binary_bounds_at_ends(lower_ratio, upper_ratio, fn(point) {
      binary_ln_bounds(point, work_precision)
    }) {
    Some(logs) =>
      Some((logs.0.mul_ctx(half, downward).0, logs.1.mul_ctx(half, upward).0))
    _ => None
  }
}

///|
fn Binary::try_inverse_hyperbolic_ctx(
  self : Binary,
  operation : BinaryInverseHyperbolicOperation,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
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
              Binary::inf_raw(self.signum(), precision=context.precision),
              BinaryFlags::new(),
            ),
          )
        BinaryInverseHyperbolicOperation::Acosh if !self.is_sign_minus() =>
          Ok(
            (
              Binary::inf_raw(Sign::Positive, precision=context.precision),
              BinaryFlags::new(),
            ),
          )
        _ => Ok(binary_invalid_value(context))
      }
    FpClass::Finite if self.is_zero() =>
      match operation {
        BinaryInverseHyperbolicOperation::Asinh
        | BinaryInverseHyperbolicOperation::Atanh =>
          Ok(
            (
              if self.is_negative_zero() {
                Binary::negative_zero_raw(precision=context.precision)
              } else {
                Binary::zero_raw(precision=context.precision)
              },
              BinaryFlags::new(),
            ),
          )
        BinaryInverseHyperbolicOperation::Acosh =>
          Ok(binary_invalid_value(context))
      }
    FpClass::Finite => {
      let one = Binary::one_raw(precision=self.precision())
      match operation {
        BinaryInverseHyperbolicOperation::Acosh if self.compare(one) < 0 =>
          return Ok(binary_invalid_value(context))
        BinaryInverseHyperbolicOperation::Atanh if self.abs().compare(one) > 0 =>
          return Ok(binary_invalid_value(context))
        BinaryInverseHyperbolicOperation::Atanh if self.abs().compare(one) == 0 =>
          return Ok(
            (
              Binary::inf_raw(self.signum(), precision=context.precision),
              binary_division_by_zero_flags(),
            ),
          )
        _ => ()
      }
      if operation == BinaryInverseHyperbolicOperation::Acosh &&
        self.compare(one) == 0 {
        return Ok(
          (Binary::zero_raw(precision=context.precision), BinaryFlags::new()),
        )
      }
      // |x| <= 1/2: 0 < x - asinh x <= |x|^3 and 0 < atanh x - x <= |x|^3 (sign
      // of x).
      if operation != BinaryInverseHyperbolicOperation::Acosh &&
        binary_tiny_argument_result(
          self,
          (operation == BinaryInverseHyperbolicOperation::Atanh) !=
          self.is_sign_minus(),
          3L * binary_top_bound(self),
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      let mut work = Int32::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        let bounds = match operation {
          BinaryInverseHyperbolicOperation::Asinh =>
            match binary_asinh_positive_bounds(self.abs(), work) {
              Some(positive) =>
                Some(
                  if self.is_sign_minus() {
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
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
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
pub fn Binary::try_asinh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Asinh,
    context,
  )
}

///|
pub fn Binary::asinh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_asinh_ctx(context), context)
}

///|
pub fn Binary::asinh(self : Binary) -> Binary {
  self.asinh_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_acosh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Acosh,
    context,
  )
}

///|
pub fn Binary::acosh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_acosh_ctx(context), context)
}

///|
pub fn Binary::acosh(self : Binary) -> Binary {
  self.acosh_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_atanh_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_inverse_hyperbolic_ctx(
    BinaryInverseHyperbolicOperation::Atanh,
    context,
  )
}

///|
pub fn Binary::atanh_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_atanh_ctx(context), context)
}

///|
pub fn Binary::atanh(self : Binary) -> Binary {
  self.atanh_ctx(binary_working_context(self.precision())).0
}

///|
/// Series enclosure of `atan` on a nonnegative pair, `l <= atan(x) <= u` for
/// every `x` in `[lo, hi]`, with `0 <= lo <= hi <= 1/2` after rounding to
/// `work_precision`: `atan x = x - R(x)` with `R(x) = x^3/3 - x^5/5 + x^7/7 - ...`
/// increasing in `x`, so `l = lo - Rup` and `u = hi - Rlow` for bounds
/// `Rlow <= R(lo)` and `R(hi) <= Rup`. `R` is computed in fixed point (integers
/// of `F` fractional bits, no `Binary` operation per term), see
/// `binary_atan_fixed_remainder`; for an argument below `2^-(w/2 + 7)` the
/// remainder is bounded by its first term. `None` when the fixed-point series
/// does not stop (never for these arguments) or the arguments are out of range.
fn binary_atan_small_positive_pair_bounds(
  lo : Binary,
  hi : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower_value = if lo.is_zero() {
    Binary::zero_raw(precision=work_precision)
  } else {
    lo.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
  }
  let upper_value = hi.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
  guard (lower_value.is_zero() || lower_value.signum() == Sign::Positive) &&
    upper_value.compare(half) <= 0 else {
    return None
  }
  if upper_value.is_zero() {
    return Some((lower_value, upper_value))
  }
  let q = -binary_exact_top(
    upper_value.coefficient_(),
    upper_value.exponent2_(),
  )
  if q.to_int64() >= (work_precision / 2 + 8).to_int64() {
    // R(x) <= x^3/3 (alternating series with decreasing terms) and, for
    // x < 2^-(w/2 + 7), R(x) >= 0: the bounds are lo - hi^3/3 and hi.
    let cube = upper_value.mul_ctx(upper_value, upward).0.mul_ctx(
        upper_value, upward,
      ).0
    let third = Binary::from_int_raw(3, precision=work_precision)
    let remainder_up = cube.div_ctx(third, upward).0
    return Some((lower_value.sub_ctx(remainder_up, downward).0, upper_value))
  }
  let fraction = work_precision + q + 20 + bit_length_int(work_precision)
  match binary_atan_fixed_remainder(lower_value, upper_value, fraction) {
    None => None
    Some((remainder_low, remainder_up)) => {
      let lower = if remainder_up.is_zero() {
        lower_value
      } else {
        lower_value.sub_ctx(
          Binary::make_coeff(
            remainder_up,
            -fraction,
            Int32::max(1, remainder_up.bit_length()),
          ),
          downward,
        ).0
      }
      let upper = if remainder_low.is_zero() {
        upper_value
      } else {
        upper_value.sub_ctx(
          Binary::make_coeff(
            remainder_low,
            -fraction,
            Int32::max(1, remainder_low.bit_length()),
          ),
          upward,
        ).0
      }
      Some((lower, upper))
    }
  }
}

///|
/// `ceil(value * 2^shift)` of an integer, for a shift of either sign.
fn fixed_ceil_shift(value : Coeff, shift : Int32) -> Coeff {
  if shift >= 0 {
    return value.shift_left(shift)
  }
  let quotient = value.shift_right(-shift)
  if quotient.shift_left(-shift).compare(value) == 0 {
    quotient
  } else {
    quotient.add(Coeff::one())
  }
}

///|
/// Bounds `(low, up)`, in units of `2^-fraction`, with `low <= R(lo)` and
/// `R(hi) <= up` for `R(x) = x^3/3 - x^5/5 + x^7/7 - ...`, `0 <= lo <= hi <= 1/2`.
///
/// Two integer chains: `P_low(k) <= lo^(2k+1) 2^F` by floors (`P(k) =
/// floor(P(k-1) S / 2^F)` with `S = floor(lo^2 2^F)` and `P(0) = floor(lo 2^F)`;
/// a floor never exceeds the exact product of lower bounds), and `P_up(k) >=
/// hi^(2k+1) 2^F` by ceilings. Their terms `T_low(k) = floor(P_low(k)/(2k+1))`
/// and `T_up(k) = ceil(P_up(k)/(2k+1))` bound `t_k(lo)` from below and `t_k(hi)`
/// from above (`t_k` is increasing in `x`). For the alternating series with
/// decreasing terms the partial sum after an odd number of terms is at least
/// `R` and after an even number at most `R`, so with
/// `A = sum_{odd} T_up`, `B = sum_{even} T_low`, `C = sum_{odd} T_low` and
/// `D = sum_{even} T_up`: `R(hi) <= A - B` (odd partial sum, upper terms added,
/// lower terms subtracted) and `R(lo) >= C' - D` (even partial sum, with `C'`
/// the odd terms before the last one). The series stops at an odd `k` whose
/// `T_up` is below 2 units. Each floor or ceiling loses at most one unit; with
/// `a^2 <= 1/4` the chain errors stay below 2 units, so each term is within 3
/// units and the whole enclosure within `1.5 F` units, covered by the 20 and
/// `bit_length(w)` guard bits of `fraction`.
fn binary_atan_fixed_remainder(
  lo : Binary,
  hi : Binary,
  fraction : Int32,
) -> (Coeff, Coeff)? {
  let (low_scaled, low_square) = if lo.is_zero() {
    (Coeff::zero(), Coeff::zero())
  } else {
    (
      fixed_scaled_floor(lo, fraction),
      fixed_shift(
        lo.coefficient_().mul(lo.coefficient_()),
        2 * lo.exponent2_() + fraction,
      ),
    )
  }
  let up_scaled = match fixed_scaled_exact(hi, fraction) {
    Some(exact) => exact
    None => fixed_scaled_floor(hi, fraction).add(Coeff::one())
  }
  let up_square = fixed_ceil_shift(
    hi.coefficient_().mul(hi.coefficient_()),
    2 * hi.exponent2_() + fraction,
  )
  let mut power_low = low_scaled
  let mut power_up = up_scaled
  let mut odd_up = Coeff::zero()
  let mut odd_low = Coeff::zero()
  let mut even_low = Coeff::zero()
  let mut even_up = Coeff::zero()
  let two = Coeff::from_uint64(2UL)
  let mut index = 1
  while index < 20000 {
    power_low = power_low.mul(low_square).shift_right(fraction)
    power_up = fixed_ceil_shift(power_up.mul(up_square), -fraction)
    let divisor = Coeff::from_uint64((2 * index + 1).to_uint64())
    let term_low = bin_coeff_short_div_rem(power_low, divisor).0
    let (quotient, remainder) = bin_coeff_short_div_rem(power_up, divisor)
    let term_up = if remainder.is_zero() {
      quotient
    } else {
      quotient.add(Coeff::one())
    }
    if index % 2 == 1 {
      if term_up.compare(two) < 0 {
        // Stop: R(hi) <= A - B, R(lo) >= (C before this term) - D.
        let up = odd_up.add(term_up).sub_checked(even_low)
        let low = odd_low.sub_checked(even_up)
        match (up, low) {
          (Ok(up_value), Ok(low_value)) => return Some((low_value, up_value))
          (Ok(up_value), Err(_)) => return Some((Coeff::zero(), up_value))
          _ => return None
        }
      }
      odd_up = odd_up.add(term_up)
      odd_low = odd_low.add(term_low)
    } else {
      even_low = even_low.add(term_low)
      even_up = even_up.add(term_up)
    }
    index += 1
  }
  None
}

///|
/// A bound of the reduction `r(x) = x / (1 + sqrt(1 + x^2))` for finite
/// `x > 1/2` at `work_precision`: a lower bound when `upper` is false, an upper
/// bound when it is true (the caller passes `x` rounded in the matching
/// direction; `r` is increasing).
///
/// Moderate `x`: `x` divided by a directed `1 + sqrt(1 + x^2)` (directed
/// squares, sums and square roots, each monotone on nonnegative numbers).
/// When the leading bit of `x` is at least `2 w + 2` the square is not formed:
/// it could leave the implementation exponent range (it does for
/// `x >= 2^(2^29)`, and an enclosing `x + 2` overflows near the top of the
/// range). Dividing numerator and denominator by `x`, with `y = 1/x <= 2^-(2w+2)`,
/// `r(x) = 1 / (y + sqrt(1 + y^2))`, and `1 <= sqrt(1 + y^2) <= 1 + y^2/2
/// <= 1 + y^2`, so `1 + y <= y + sqrt(1 + y^2) <= 1 + y + y^2`, hence
/// `1 / (1 + y + y^2) <= r(x) <= 1 / (1 + y)`. With `y` bounded by directed
/// reciprocals (`y_down <= y <= y_up`) the lower bound is `1 / (1 + y_up + y_up^2)`
/// rounded down and the upper bound `1 / (1 + y_down)` rounded up; their
/// relative gap is below `2 y`, far under the working precision, and `1/x`
/// cannot overflow.
fn binary_atan_reduction_ratio(
  x : Binary,
  upper : Bool,
  work_precision : Int32,
) -> Binary {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let top = x.exact_top().to_int64()
  if top >= 2L * work_precision.to_int64() + 2L {
    return if upper {
      let y_down = one.div_ctx(x, downward).0
      one.div_ctx(one.add_ctx(y_down, downward).0, upward).0
    } else {
      let y_up = one.div_ctx(x, upward).0
      let denominator = one.add_ctx(
          y_up.add_ctx(y_up.mul_ctx(y_up, upward).0, upward).0,
          upward,
        ).0
      one.div_ctx(denominator, downward).0
    }
  }
  if upper {
    let denominator = one.add_ctx(
        one.add_ctx(x.mul_ctx(x, downward).0, downward).0.sqrt_ctx(downward).0,
        downward,
      ).0
    x.div_ctx(denominator, upward).0
  } else {
    let denominator = one.add_ctx(
        one.add_ctx(x.mul_ctx(x, upward).0, upward).0.sqrt_ctx(upward).0,
        upward,
      ).0
    x.div_ctx(denominator, downward).0
  }
}

///|
/// Enclosure of `atan` over the nonnegative pair `[lo, hi]` by one evaluation
/// chain. For `x > 1/2` it uses `atan x = 2 atan(r(x))` with
/// `r(x) = x / (1 + sqrt(1 + x^2))`. `r` is increasing on `x >= 0` (the
/// numerator grows and the denominator is positive and grows slower in
/// relative terms: `r(x) = tan(atan(x) / 2)`), and so is `atan`. Hence
/// `atan(x) >= 2 atan(r(lo))` and `atan(x) <= 2 atan(r(hi))` for every `x` in
/// `[lo, hi]`, and `r(lo)` needs a lower bound of `r` at `lo` (numerator
/// rounded down, denominator bound rounded up) and `r(hi)` an upper bound
/// (numerator rounded up, denominator bound rounded down). The reduced pair
/// is again nonnegative and ordered, so the recursion is a single chain
/// (at most two levels for any finite argument: `r(x) <= 1`, `r(1) < 1/2`).
fn binary_atan_positive_pair_bounds(
  lo : Binary,
  hi : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
  if hi.compare(half) <= 0 {
    return binary_atan_small_positive_pair_bounds(lo, hi, work_precision)
  }
  // An infinite end comes from a quotient that overflowed (`atan2` with
  // exponents far apart): atan(+inf) = pi/2, so that end is bounded by pi/2
  // rounded in the matching direction; a finite lower end is evaluated alone.
  if hi.classify() == FpClass::Infinity {
    guard binary_pi_bounds(work_precision) is Some(pi) else { return None }
    let half_pi_upper = pi.1.mul_ctx(
        half,
        binary_working_context(work_precision, rounding=RoundTowardPositive),
      ).0
    let half_pi_lower = pi.0.mul_ctx(
        half,
        binary_working_context(work_precision, rounding=RoundTowardNegative),
      ).0
    if lo.classify() == FpClass::Infinity {
      return Some((half_pi_lower, half_pi_upper))
    }
    guard binary_atan_positive_pair_bounds(lo, lo, work_precision)
      is Some(lower_pair) else {
      return None
    }
    return Some((lower_pair.0, half_pi_upper))
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let lower_value = lo.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = hi.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let ratio_lower = binary_atan_reduction_ratio(
    lower_value, false, work_precision,
  )
  let ratio_upper = binary_atan_reduction_ratio(
    upper_value, true, work_precision,
  )
  match
    binary_atan_positive_pair_bounds(ratio_lower, ratio_upper, work_precision) {
    Some(reduced) => {
      let two = Binary::from_int_raw(2, precision=work_precision)
      Some(
        (reduced.0.mul_ctx(two, downward).0, reduced.1.mul_ctx(two, upward).0),
      )
    }
    None => None
  }
}

///|
/// Enclosure of `atan` over `[lo, hi]` (`lo <= hi`, finite) by one chain.
/// `atan` is odd and increasing: a negative pair maps to `[-hi, -lo]`; a pair
/// that contains zero is widened to `[-m, m]` with `m = max(-lo, hi)`, which
/// contains it, and `atan(-m) = -atan(m)`.
fn binary_atan_pair_bounds(
  lo : Binary,
  hi : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  if hi.is_zero() && lo.is_zero() {
    let zero = Binary::zero_raw(precision=work_precision)
    return Some((zero, zero))
  }
  if lo.is_sign_minus() && !lo.is_zero() {
    if hi.is_sign_minus() || hi.is_zero() {
      match
        binary_atan_positive_pair_bounds(hi.neg(), lo.neg(), work_precision) {
        Some(positive) => Some((positive.1.neg(), positive.0.neg()))
        None => None
      }
    } else {
      let magnitude = if lo.neg().compare(hi) > 0 { lo.neg() } else { hi }
      match
        binary_atan_positive_pair_bounds(
          Binary::zero_raw(precision=work_precision),
          magnitude,
          work_precision,
        ) {
        Some(positive) => Some((positive.1.neg(), positive.1))
        None => None
      }
    }
  } else {
    binary_atan_positive_pair_bounds(lo, hi, work_precision)
  }
}

///|
fn binary_atan_finite_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  if value.is_zero() {
    let zero = value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTiesToEven,
    )
    return Some((zero, zero))
  }
  binary_atan_pair_bounds(
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    work_precision,
  )
}

///|
fn binary_pi_series_compute(work_precision : Int32) -> (Binary, Binary)? {
  match
    binary_atan_finite_bounds(
      Binary::one_raw(precision=work_precision),
      work_precision,
    ) {
    Some(quarter_pi) => {
      let downward = binary_working_context(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = binary_working_context(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let four = Binary::from_int_raw(4, precision=work_precision)
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
pub fn Binary::try_atan_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_pi_bounds(work) {
          Some(pi) => {
            let downward = binary_working_context(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = binary_working_context(
              work,
              rounding=RoundTowardPositive,
            )
            let half = Binary::make_coeff(Coeff::one(), -1, work)
            let bounds = if self.is_sign_minus() {
              (
                pi.1.mul_ctx(half, upward).0.neg(),
                pi.0.mul_ctx(half, downward).0.neg(),
              )
            } else {
              (pi.0.mul_ctx(half, downward).0, pi.1.mul_ctx(half, upward).0)
            }
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("atan", context, work, attempt))
    }
    FpClass::Finite if self.is_zero() => Ok(self.apply_ctx(context))
    FpClass::Finite => {
      let mut work = Int32::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_atan_finite_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("atan", context, work, attempt))
    }
  }
}

///|
pub fn Binary::atan_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_atan_ctx(context), context)
}

///|
pub fn Binary::atan(self : Binary) -> Binary {
  self.atan_ctx(binary_working_context(self.precision())).0
}

///|
fn binary_asin_bounds(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = Binary::one_raw(precision=work_precision)
  let lower_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let upper_value = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let lower_square = if lower_value.compare(Binary::zero_raw()) <= 0 &&
    upper_value.compare(Binary::zero_raw()) >= 0 {
    Binary::zero_raw(precision=work_precision)
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
  // f(x) = x / sqrt(1 - x^2) is increasing on (-1, 1) (numerator increasing,
  // and for x >= 0 the denominator shrinks as x grows). For x in [lo, hi],
  // sqrt(1 - x^2) lies in [lower_root, upper_root], so
  //   lo <  0: f(x) >= f(lo) >= lo / lower_root (negative over a smaller
  //            positive number is more negative),
  //   lo >= 0: f(x) >= f(lo) >= lo / upper_root,
  //   hi >= 0: f(x) <= f(hi) <= hi / lower_root,
  //   hi <  0: f(x) <= f(hi) <= hi / upper_root.
  // Both roots are positive for |x| < 1 at this working precision.
  guard lower_root.compare(Binary::zero_raw()) > 0 else { return None }
  let ratio_lower = lower_value.div_ctx(
      if lower_value.compare(Binary::zero_raw()) < 0 {
        lower_root
      } else {
        upper_root
      },
      downward,
    ).0
  let ratio_upper = upper_value.div_ctx(
      if upper_value.compare(Binary::zero_raw()) >= 0 {
        lower_root
      } else {
        upper_root
      },
      upward,
    ).0
  match binary_atan_pair_bounds(ratio_lower, ratio_upper, work_precision) {
    Some(bounds) => Some(bounds)
    None => None
  }
}

///|
pub fn Binary::try_asin_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => Ok(binary_invalid_value(context))
    FpClass::Finite => {
      let one = Binary::one_raw(precision=self.precision())
      if self.abs().compare(one) > 0 {
        return Ok(binary_invalid_value(context))
      }
      if self.is_zero() {
        return Ok(self.apply_ctx(context))
      }
      if self.abs().compare(one) == 0 {
        let mut work = context.precision + 64
        let mut attempt = 0
        while @internal.certified_refinement_continues(
                context.refinement_limit,
                attempt,
                work,
                context.precision,
              ) {
          match binary_pi_bounds(work) {
            Some(pi) => {
              let downward = binary_working_context(
                work,
                rounding=RoundTowardNegative,
              )
              let upward = binary_working_context(
                work,
                rounding=RoundTowardPositive,
              )
              let half = Binary::make_coeff(Coeff::one(), -1, work)
              let bounds = if self.is_sign_minus() {
                (
                  pi.1.mul_ctx(half, upward).0.neg(),
                  pi.0.mul_ctx(half, downward).0.neg(),
                )
              } else {
                (pi.0.mul_ctx(half, downward).0, pi.1.mul_ctx(half, upward).0)
              }
              let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
          work += Int32::max(32, work / 2)
          attempt += 1
        }
        return Err(
          binary_refinement_failure_state("asin", context, work, attempt),
        )
      }
      // |x| <= 1/2: 0 < asin x - x <= |x|^3 (sign of x).
      if binary_tiny_argument_result(
          self,
          !self.is_sign_minus(),
          3L * binary_top_bound(self),
          context,
        )
        is Some(result) {
        return Ok(result)
      }
      let mut work = Int32::max(context.precision + 64, self.precision() + 16)
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_asin_bounds(self, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      Err(binary_refinement_failure_state("asin", context, work, attempt))
    }
  }
}

///|
pub fn Binary::asin_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_asin_ctx(context), context)
}

///|
pub fn Binary::asin(self : Binary) -> Binary {
  self.asin_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_acos_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  // Without this guard a NaN, an infinity or a finite |x| > 1 reaches the
  // certified asin bounds below and recurses until the stack overflows.
  match self.class() {
    FpClass::NaN =>
      return Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => return Ok(binary_invalid_value(context))
    FpClass::Finite =>
      if self.abs().compare(Binary::one_raw(precision=self.precision())) > 0 {
        return Ok(binary_invalid_value(context))
      }
  }
  if self.classify() == FpClass::Finite {
    let one = Binary::one_raw(precision=self.precision())
    if self.abs().compare(one) == 0 {
      if self.compare(one) == 0 {
        return Ok(
          (Binary::zero_raw(precision=context.precision), BinaryFlags::new()),
        )
      }
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_pi_bounds(work) {
          Some(pi) => {
            let downward = binary_working_context(
              work,
              rounding=RoundTowardNegative,
            )
            let upward = binary_working_context(
              work,
              rounding=RoundTowardPositive,
            )
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
              pi.0.apply_ctx(downward).0,
              pi.1.apply_ctx(upward).0,
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      return Err(
        binary_refinement_failure_state("acos", context, work, attempt),
      )
    }
  }
  let mut work = Int32::max(context.precision + 64, self.precision() + 16)
  let mut attempt = 0
  while @internal.certified_refinement_continues(
          context.refinement_limit,
          attempt,
          work,
          context.precision,
        ) {
    match (binary_asin_bounds(self, work), binary_pi_bounds(work)) {
      (Some(asin_bounds), Some(pi)) => {
        let downward = binary_working_context(
          work,
          rounding=RoundTowardNegative,
        )
        let upward = binary_working_context(work, rounding=RoundTowardPositive)
        let half = Binary::make_coeff(Coeff::one(), -1, work)
        let lower = pi.0.mul_ctx(half, downward).0.sub_ctx(
            asin_bounds.1,
            downward,
          ).0
        let upper = pi.1.mul_ctx(half, upward).0.sub_ctx(asin_bounds.0, upward).0
        let (result, unique, flags) = binary_certified_inexact_target_rounding(
          lower, upper, context,
        )
        if unique {
          return Ok((result, flags))
        }
      }
      _ =>
        return Err(binary_range_failure_state("acos", context, work, attempt))
    }
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("acos", context, work, attempt))
}

///|
pub fn Binary::acos_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_acos_ctx(context), context)
}

///|
pub fn Binary::acos(self : Binary) -> Binary {
  self.acos_ctx(binary_working_context(self.precision())).0
}

///|
fn binary_pi_fraction_bounds(
  numerator : Int32,
  denominator_shift : Int32,
  negative : Bool,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match binary_pi_bounds(work_precision) {
    Some(pi) => {
      let downward = binary_working_context(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = binary_working_context(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let factor = Binary::make_coeff(
        Coeff::from_uint64(numerator.reinterpret_as_uint().to_uint64()),
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
  ordinate : Binary,
  abscissa : Binary,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let ordinate_lower = ordinate.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let ordinate_upper = ordinate.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let abscissa_lower = abscissa.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let abscissa_upper = abscissa.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  // y / x over [y_lo, y_hi] x [x_lo, x_hi] with x of one strict sign
  // (zero abscissas are handled before this function). For x > 0 the ratio
  // is increasing in y and, for y >= 0, decreasing in x (the reverse for
  // y < 0); for x < 0 it is decreasing in y and the x-dependence flips.
  // Choosing the extreme corner per sign case gives the exact range:
  //   x > 0: lower = y_lo >= 0 ? y_lo / x_hi : y_lo / x_lo
  //          upper = y_hi >= 0 ? y_hi / x_lo : y_hi / x_hi
  //   x < 0: lower = y_hi >= 0 ? y_hi / x_hi : y_hi / x_lo
  //          upper = y_lo >= 0 ? y_lo / x_lo : y_lo / x_hi
  let zero = Binary::zero_raw()
  let (ratio_lower, ratio_upper) = if abscissa.signum() == Sign::Positive {
    (
      if ordinate_lower.compare(zero) >= 0 {
        ordinate_lower.div_ctx(abscissa_upper, downward).0
      } else {
        ordinate_lower.div_ctx(abscissa_lower, downward).0
      },
      if ordinate_upper.compare(zero) >= 0 {
        ordinate_upper.div_ctx(abscissa_lower, upward).0
      } else {
        ordinate_upper.div_ctx(abscissa_upper, upward).0
      },
    )
  } else {
    (
      if ordinate_upper.compare(zero) >= 0 {
        ordinate_upper.div_ctx(abscissa_upper, downward).0
      } else {
        ordinate_upper.div_ctx(abscissa_lower, downward).0
      },
      if ordinate_lower.compare(zero) >= 0 {
        ordinate_lower.div_ctx(abscissa_lower, upward).0
      } else {
        ordinate_lower.div_ctx(abscissa_upper, upward).0
      },
    )
  }
  match binary_atan_pair_bounds(ratio_lower, ratio_upper, work_precision) {
    Some(angle) =>
      if abscissa.signum() == Sign::Positive {
        Some(angle)
      } else {
        match binary_pi_bounds(work_precision) {
          Some(pi) =>
            if ordinate.signum() == Sign::Negative {
              Some(
                (
                  angle.0.sub_ctx(pi.1, downward).0,
                  angle.1.sub_ctx(pi.0, upward).0,
                ),
              )
            } else {
              Some(
                (
                  angle.0.add_ctx(pi.0, downward).0,
                  angle.1.add_ctx(pi.1, upward).0,
                ),
              )
            }
          None => None
        }
      }
    None => None
  }
}

///|
pub fn Binary::try_atan2_ctx(
  self : Binary,
  abscissa : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_pair(self, abscissa, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  let self_infinite = self.classify() == FpClass::Infinity
  let abscissa_infinite = abscissa.classify() == FpClass::Infinity
  // A zero ordinate keeps its sign: atan2(±0, x) is ±0 when x is +0 or
  // positive and ±π when x is -0 or negative (IEEE 754-2019 §9.2.1).
  let fraction = if self_infinite && abscissa_infinite {
    Some(
      (if abscissa.is_sign_minus() { 3 } else { 1 }, 2, self.is_sign_minus()),
    )
  } else if self.is_zero() {
    if abscissa.is_sign_minus() {
      Some((1, 0, self.is_sign_minus()))
    } else {
      None
    }
  } else if self_infinite || abscissa.is_zero() {
    Some((1, 1, self.is_sign_minus()))
  } else if abscissa_infinite && abscissa.is_sign_minus() {
    Some((1, 0, self.is_sign_minus()))
  } else {
    None
  }
  match fraction {
    Some((numerator, shift, negative)) => {
      let mut work = context.precision + 64
      let mut attempt = 0
      while @internal.certified_refinement_continues(
              context.refinement_limit,
              attempt,
              work,
              context.precision,
            ) {
        match binary_pi_fraction_bounds(numerator, shift, negative, work) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      return Err(
        binary_refinement_failure_state("atan2", context, work, attempt),
      )
    }
    None => ()
  }
  if abscissa_infinite && !abscissa.is_sign_minus() {
    return Ok(
      (
        if self.is_sign_minus() {
          Binary::negative_zero_raw(precision=context.precision)
        } else {
          Binary::zero_raw(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  if self.is_zero() {
    return Ok(
      (
        if self.is_negative_zero() {
          Binary::negative_zero_raw(precision=context.precision)
        } else {
          Binary::zero_raw(precision=context.precision)
        },
        BinaryFlags::new(),
      ),
    )
  }
  // x > 0 and a quotient far below the exponent range. With D = top(y) -
  // top(x), 2^(D - 1) < |y/x| < 2^(D + 1), and atan(t) = t (1 - e) with
  // 0 < e < t^2 / 3, so 0 < |atan2(y, x)| < |y/x| < 2^(D + 1). The directed
  // quotient of the enclosure would flush to zero there and the Ziv loop would
  // never separate the result from 0. When 2^(D + 1) is at most a quarter of the
  // smallest subnormal 2^(e_min - p + 1) of the context, the result lies
  // strictly between 0 and a quarter of it, which rounds exactly as the
  // quotient `y / x` does: zero or the smallest subnormal, inexact and
  // underflow (the sign is that of y).
  if !abscissa.is_sign_minus() {
    let distance = binary_pi_top(self) - binary_pi_top(abscissa)
    if distance <=
      context.range_e_min().to_int64() - context.precision.to_int64() - 2L {
      return Ok(binary_tiny_nonzero_result(self.is_sign_minus(), context))
    }
  }
  let mut work = Int32::max(
    context.precision + 64,
    Int32::max(self.precision(), abscissa.precision()) + 16,
  )
  let mut attempt = 0
  while @internal.certified_refinement_continues(
          context.refinement_limit,
          attempt,
          work,
          context.precision,
        ) {
    match binary_atan2_finite_bounds(self, abscissa, work) {
      Some(bounds) => {
        let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  Err(binary_refinement_failure_state("atan2", context, work, attempt))
}

///|
pub fn Binary::atan2_ctx(
  self : Binary,
  abscissa : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_atan2_ctx(abscissa, context), context)
}

///|
pub fn Binary::atan2(self : Binary, abscissa : Binary) -> Binary {
  self.atan2_ctx(
    abscissa,
    binary_working_context(Int32::max(self.precision(), abscissa.precision())),
  ).0
}

///|
#derive(Eq)
priv enum BinaryTrigonometricOperation {
  Sin
  Cos
  Tan
}

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
  value : Binary,
  cosine : Bool,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match binary_sin_cos_fixed_series(value, cosine, work_precision) {
    Some(bounds) => return Some(bounds)
    None => ()
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let negative = value.is_sign_minus()
  let argument = if negative { value.neg() } else { value }
  let argument_lower = argument.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let argument_upper = argument.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let square_lower = argument_lower.mul_ctx(argument_lower, downward).0
  let square_upper = argument_upper.mul_ctx(argument_upper, upward).0
  let mut term_lower = if cosine {
    Binary::one_raw(precision=work_precision)
  } else {
    argument_lower
  }
  let mut term_upper = if cosine {
    Binary::one_raw(precision=work_precision)
  } else {
    argument_upper
  }
  let mut sum_lower = term_lower
  let mut sum_upper = term_upper
  let mut bracket_lower = term_lower
  let mut bracket_upper = term_upper
  let threshold = Binary::make_coeff(
    Coeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  while index < 20000 {
    if cosine {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          Binary::from_int_raw(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          Binary::from_int_raw(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          upward,
        ).0
    } else {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          Binary::from_int_raw(
            2 * index * (2 * index + 1),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          Binary::from_int_raw(
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
fn binary_floor_integer(value : Binary) -> Binary? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() || value.exponent2() >= 0 {
    return Some(value)
  }
  let shift = -value.exponent2()
  let magnitude = value.coefficient_()
  let quotient = if shift >= magnitude.bit_length() {
    Coeff::zero()
  } else {
    magnitude.shift_right(shift)
  }
  let has_remainder = if shift >= magnitude.bit_length() {
    !magnitude.is_zero()
  } else {
    quotient.shift_left(shift).compare(magnitude) != 0
  }
  let floor_magnitude = if value.is_sign_minus() && has_remainder {
    quotient.add(Coeff::one())
  } else {
    quotient
  }
  let integer = Binary::make_coeff(
    floor_magnitude,
    0,
    Int32::max(1, floor_magnitude.bit_length()),
  )
  Some(if value.is_sign_minus() { integer.neg() } else { integer })
}

///|
fn binary_integer_mod4(value : Binary) -> Int32? {
  guard value.classify() == FpClass::Finite &&
    (value.is_zero() || value.exponent2() >= 0) else {
    return None
  }
  let magnitude_residue = if value.is_zero() || value.exponent2() >= 2 {
    0
  } else if value.exponent2() == 1 {
    if value.coefficient_().test_bit(0) {
      2
    } else {
      0
    }
  } else {
    (if value.coefficient_().test_bit(0) { 1 } else { 0 }) +
    (if value.coefficient_().test_bit(1) { 2 } else { 0 })
  }
  Some(
    if value.is_sign_minus() && magnitude_residue != 0 {
      4 - magnitude_residue
    } else {
      magnitude_residue
    },
  )
}

///|
/// `x / 2` at the working precision, the value of `x.mul_ctx(1/2, context)`: when
/// `x` is a finite nonzero value of exactly `work_precision` bits (the bounds of
/// `pi` and of its halves are) the product by a power of two changes only the
/// exponent, rounds nothing and cannot overflow (the unbounded working context has
/// no exponent range and the exponent of `pi / 2^k` is about `-work_precision`),
/// so the exponent is changed in place; any other value, and any value whose exponent is within 2^30 of the
/// bottom of the implementation range, takes the product.
fn binary_halve_bound(
  x : Binary,
  work_precision : Int32,
  context : BinaryContext,
) -> Binary {
  if x.classify() == FpClass::Finite &&
    !x.is_zero() &&
    x.precision() == work_precision &&
    x.exponent2() > -1073741824 {
    binary_halve_exact(x)
  } else {
    x.mul_ctx(Binary::make_coeff(Coeff::one(), -1, work_precision), context).0
  }
}

///|
/// Largest working precision of the argument reduction of `sin`, `cos` and
/// `tan` (bits): an argument of binary exponent `k` needs about `k` more bits
/// than the result for the reduction modulo pi/2.
let binary_trig_work_limit : Int32 = 8_000_000

///|
fn binary_trigonometric_reduction(
  value : Binary,
  half_pi : (Binary, Binary),
  work_precision : Int32,
) -> ((Binary, Binary), Int32)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let input_bounds = (
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  // Both ends strictly inside (-pi/4, pi/4) (the lower bound of pi/4 is half the
  // lower bound of pi/2, exact): x / (pi/2) lies in (-1/2, 1/2) at both ends,
  // so the nearest integer is 0 for both, the product 0 * (pi/2) is 0 and the
  // reduced argument is the input itself. Same result as the general path.
  let quarter_lower = binary_halve_bound(half_pi.0, work_precision, downward)
  if input_bounds.0.compare(quarter_lower.neg()) > 0 &&
    input_bounds.1.compare(quarter_lower) < 0 {
    return Some((input_bounds, 0))
  }
  let quotient = binary_quotient_bounds(input_bounds, half_pi, downward, upward)
  guard quotient is Some((quotient_lower, quotient_upper)) else { return None }
  let half = Binary::make_coeff(Coeff::one(), -1, work_precision)
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
  value : Binary,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  if work_precision >= binary_trig_burst_min_precision {
    let burst = match operation {
      BinaryTrigonometricOperation::Sin =>
        binary_trig_bounds_burst(value, false, work_precision)
      BinaryTrigonometricOperation::Cos =>
        binary_trig_bounds_burst(value, true, work_precision)
      BinaryTrigonometricOperation::Tan => None
    }
    match burst {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  binary_trigonometric_bounds_series(value, operation, work_precision)
}

///|
/// The enclosure of `sin`, `cos` or `tan` by the reduction with an enclosure of
/// `pi / 2` and the series: the path below the bit-burst threshold and the
/// reference of its tests.
fn binary_trigonometric_bounds_series(
  value : Binary,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let pi = binary_pi_bounds(work_precision).unwrap()
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let half_pi = (
    binary_halve_bound(pi.0, work_precision, downward),
    binary_halve_bound(pi.1, work_precision, upward),
  )
  let quarter_pi = (
    binary_halve_bound(half_pi.0, work_precision, downward),
    binary_halve_bound(half_pi.1, work_precision, upward),
  )
  let reduction = binary_trigonometric_reduction(value, half_pi, work_precision)
  guard reduction is Some(((lower, upper), quadrant)) else { return None }
  guard lower.compare(quarter_pi.0.neg()) >= 0 &&
    upper.compare(quarter_pi.1) <= 0 else {
    return None
  }
  // The reduction needed `work_precision` bits for the cancellation of a huge
  // argument (its top bound is `top`); the reduced argument lies in
  // (-pi/4, pi/4) and the series needs only the precision of the result:
  // `work_precision - top`. The enclosure is rounded outward to it first.
  let top = binary_top_bound(value)
  let series_precision = if top > 256L {
    Int32::max(64, work_precision - top.to_int())
  } else {
    work_precision
  }
  if series_precision >= work_precision {
    return binary_reduced_trigonometric_bounds(
      lower, upper, quadrant, operation, work_precision,
    )
  }
  binary_reduced_trigonometric_bounds(
    lower.with_precision_raw(
      series_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    upper.with_precision_raw(
      series_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    quadrant,
    operation,
    series_precision,
  )
}

///|
/// `a - b` for `a >= b` rounded upward (a nonnegative upper bound of the distance).
fn upward_distance(a : Binary, b : Binary, upward : BinaryContext) -> Binary {
  a.sub_ctx(b, upward).0
}

///|
/// Number of calls of `binary_reduced_trigonometric_bounds`: one per refinement
/// round of the trigonometric functions. Read by the tests that bound the rounds.
let binary_reduced_trigonometric_calls : Ref[Int32] = Ref(0)

///|
fn binary_reduced_trigonometric_bounds(
  lower : Binary,
  upper : Binary,
  quadrant : Int32,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  binary_reduced_trigonometric_calls.val += 1
  let one = Binary::one_raw(precision=work_precision)
  guard lower.compare(upper) <= 0 &&
    lower.compare(one.neg()) >= 0 &&
    upper.compare(one) <= 0 else {
    return None
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  // The quadrant maps sine and cosine of the reduced argument onto the result
  // (see `mapped`): sine and cosine results of the even quadrants come from
  // the sine and cosine series, those of the odd quadrants from the other one.
  // A series that the requested operation does not read is not evaluated;
  // `zero` stands in for it and is never read.
  let zero = Binary::zero_raw(precision=work_precision)
  let sine_first = match quadrant % 4 {
    0 | 2 => true
    _ => false
  }
  let need_sin = match operation {
    BinaryTrigonometricOperation::Sin => sine_first
    BinaryTrigonometricOperation::Cos => !sine_first
    BinaryTrigonometricOperation::Tan => true
  }
  let need_cos = match operation {
    BinaryTrigonometricOperation::Sin => !sine_first
    BinaryTrigonometricOperation::Cos => sine_first
    BinaryTrigonometricOperation::Tan => true
  }
  // The reduced interval `[lower, upper]` has two distinct ends whenever the
  // quadrant is not 0 (the reduction encloses `x - n pi / 2` from both ends of
  // `pi`). Sine and cosine are 1-Lipschitz (`|sin'| = |cos| <= 1`, `|cos'| =
  // |sin| <= 1`), so for ANY value `m` and `h` an upper bound of both
  // `upper - m` and `m - lower` (here `m` the midpoint rounded to nearest and
  // `h` the larger of the two differences, each rounded upward; soundness does
  // not need `m` to lie in the interval, `h` covers both distances whatever `m`
  // is), every `x` of the interval has `|f(x) - f(m)| <= h`, so `f(x)` lies in
  // `[f(m)_low - h, f(m)_high + h]` (the two sums rounded outward): one series
  // evaluation instead of one at each end. For `tan` the widened enclosures
  // feed the unchanged quotient: the reduced argument is within `pi / 4`, so the
  // cosine is at least `cos(pi / 4) = 0.7071` and `h` is a few units of the work
  // precision, hence the widened cosine enclosure excludes 0 wherever the
  // two-ended one did.
  let point = lower.compare(upper) == 0
  let middle = if point {
    lower
  } else {
    let nearest = binary_working_context(work_precision)
    binary_halve_bound(lower.add_ctx(upper, nearest).0, work_precision, nearest)
  }
  let radius = if point {
    zero
  } else {
    let up = upward_distance(upper, middle, upward)
    let down = upward_distance(middle, lower, upward)
    if up.compare(down) >= 0 {
      up
    } else {
      down
    }
  }
  // The widening must not cross a bound that the true value sits on, or within
  // the directed-rounding unit of at every work precision: a widened end across
  // such a bound can never be certified, while one across a bound the true value
  // is strictly inside of is harmless, refinement shrinks `h`. The mechanism: the
  // target rounding (`binary_certified_inexact_target_rounding`) knows the result
  // of these functions at a nonzero reduced argument is inexact, so it treats the
  // true value as never equal to an end and moves an end that may be a rounding
  // breakpoint of the target format (a value of at most `precision + 1` bits, 1
  // among them) strictly inside (`binary_inexact_inner_endpoint`). The cosine of
  // a tiny argument is `1 - x^2/2`, closer to 1 than any work precision resolves:
  // the capped enclosure `[1 - d, 1]` becomes `[1 - d, 1 - tiny]` and rounds to
  // one value in every direction, while `[1 - d, 1 + h]` keeps an end that is not
  // a breakpoint (it has about the work precision in bits) and rounds to 1 on one
  // side and to the number below on the other for ever. (An end at exactly 0 is
  // not moved; for a sine of one sign the clamp below can only produce it where
  // the true value, at least `l` or at most `u`, is strictly inside and
  // refinement converges.) The range bounds of both functions are `-1` and `1`;
  // the sine of an interval with ends of one sign has that sign (`sin x` has the
  // sign of `x` for `|x| <= 1`), so its enclosure stops at 0. A point interval is
  // not widened.
  let one = Binary::one_raw(precision=work_precision)
  let clamp_range = fn(bounds : (Binary, Binary)) -> (Binary, Binary) {
    (
      if bounds.0.compare(one.neg()) < 0 {
        one.neg()
      } else {
        bounds.0
      },
      if bounds.1.compare(one) > 0 {
        one
      } else {
        bounds.1
      },
    )
  }
  let sin_bounds = if need_sin {
    let series = binary_sin_cos_series(middle, false, work_precision).unwrap()
    if point {
      series
    } else {
      let widened = clamp_range(
        (
          series.0.sub_ctx(radius, downward).0,
          series.1.add_ctx(radius, upward).0,
        ),
      )
      if lower.compare(zero) > 0 && widened.0.compare(zero) < 0 {
        (zero, widened.1)
      } else if upper.compare(zero) < 0 && widened.1.compare(zero) > 0 {
        (widened.0, zero)
      } else {
        widened
      }
    }
  } else {
    (zero, zero)
  }
  let cos_bounds = if !need_cos {
    (zero, zero)
  } else {
    let series = binary_sin_cos_series(middle, true, work_precision).unwrap()
    let widened = if point {
      series
    } else {
      clamp_range(
        (
          series.0.sub_ctx(radius, downward).0,
          series.1.add_ctx(radius, upward).0,
        ),
      )
    }
    // An interval that contains 0 reaches 1.
    if lower.compare(zero) <= 0 && upper.compare(zero) >= 0 {
      (widened.0, one)
    } else {
      widened
    }
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
      guard !(mapped.1.0.compare(Binary::zero_raw()) <= 0 &&
        mapped.1.1.compare(Binary::zero_raw()) >= 0) else {
        return None
      }
      // The cosine enclosure has a definite sign here. For a negative cosine
      // n / d = (-n) / (-d) with -d positive.
      if mapped.1.0.compare(Binary::zero_raw()) > 0 {
        return binary_quotient_bounds(mapped.0, mapped.1, downward, upward)
      }
      // A zero end of the numerator: its sign depends on the candidate order of
      // the four-candidate form, so keep that form (rare: only for an exact
      // zero argument).
      if mapped.0.0.is_zero() || mapped.0.1.is_zero() {
        return Some(
          binary_quotient_bounds_general(mapped.0, mapped.1, downward, upward),
        )
      }
      return binary_quotient_bounds(
        (mapped.0.1.neg(), mapped.0.0.neg()),
        (mapped.1.1.neg(), mapped.1.0.neg()),
        downward,
        upward,
      )
    }
  }
}

///|
fn Binary::try_trigonometric_ctx(
  self : Binary,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => Ok(binary_invalid_value(context))
    FpClass::Finite if self.is_zero() =>
      Ok(
        (
          if operation == BinaryTrigonometricOperation::Cos {
            Binary::one_raw(precision=context.precision)
          } else {
            self.apply_ctx(context).0
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite => {
      let adjusted_exponent = self.exponent2().to_int64() +
        self.coefficient_bits().to_int64()
      let required = context.precision.to_int64() +
        Int64::max(0L, adjusted_exponent) +
        96L
      guard required <= binary_trig_work_limit.to_int64() else {
        return Err(
          binary_certification_failure(
            operation.name(),
            @def.CertificationStage::RangeReduction,
            @def.CertificationFailureReason::ResourceLimit,
            context.precision,
            binary_trig_work_limit,
            0,
          ),
        )
      }
      // |x| <= 1/2: 0 < x - sin x <= |x|^3 and 0 < tan x - x <= |x|^3 (sign of
      // x), and 0 < 1 - cos x <= x^2.
      let tiny = match operation {
        BinaryTrigonometricOperation::Sin =>
          binary_tiny_argument_result(
            self,
            self.is_sign_minus(),
            3L * binary_top_bound(self),
            context,
          )
        BinaryTrigonometricOperation::Tan =>
          binary_tiny_argument_result(
            self,
            !self.is_sign_minus(),
            3L * binary_top_bound(self),
            context,
          )
        BinaryTrigonometricOperation::Cos =>
          binary_tiny_argument_result(
            Binary::one_raw(precision=context.precision),
            false,
            2L * binary_top_bound(self),
            context,
          )
      }
      if tiny is Some(result) {
        return Ok(result)
      }
      let mut budget = CertifiedRefinementBudget::new(
        Int32::max(required.to_int(), self.precision() + 16),
        limit=context.refinement_limit,
      )
      let mut certified_range = false
      while budget.available() && budget.precision() <= binary_trig_work_limit {
        match binary_trigonometric_bounds(self, operation, budget.precision()) {
          Some(bounds) => {
            certified_range = true
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
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
pub fn Binary::try_sin_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Sin, context)
}

///|
pub fn Binary::sin_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_sin_ctx(context), context)
}

///|
pub fn Binary::sin(self : Binary) -> Binary {
  self.sin_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_cos_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Cos, context)
}

///|
pub fn Binary::cos_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_cos_ctx(context), context)
}

///|
pub fn Binary::cos(self : Binary) -> Binary {
  self.cos_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_tan_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_trigonometric_ctx(BinaryTrigonometricOperation::Tan, context)
}

///|
pub fn Binary::tan_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_tan_ctx(context), context)
}

///|
pub fn Binary::tan(self : Binary) -> Binary {
  self.tan_ctx(binary_working_context(self.precision())).0
}
