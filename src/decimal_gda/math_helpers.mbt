///|
// Power, logarithm, and exponential helper routines.

///|
fn decimal_exact_integer_coeff(rhs : Decimal) -> (Bool, GdaCoeff)? {
  guard rhs.class == FpClass::Finite else { return None }
  let magnitude = if rhs.exponent10 >= 0 {
    gda_coeff_shift_power10_repr(rhs.coefficient, rhs.exponent10)
  } else {
    match exact_divide_by_power_of_ten_repr(rhs.coefficient, -rhs.exponent10) {
      Some(value) => value
      None => return None
    }
  }
  Some((rhs.negative && !magnitude.is_zero(), magnitude))
}

///|
fn gda_coeff_to_bounded_int(coeff : GdaCoeff, limit : Int) -> Int? {
  guard limit >= 0 else { return None }
  let unit_count = gda_coeff_d2u(coeff.digits10())
  let mut value = 0
  for i = unit_count - 1; i >= 0; i = i - 1 {
    let unit = gda_coeff_limb_at(coeff, i).reinterpret_as_int()
    let remaining = limit - unit
    guard remaining >= 0 && value <= remaining / gda_coeff_base else {
      return None
    }
    value = value * gda_coeff_base + unit
  }
  Some(value)
}

///|
fn gda_bounded_int_digits(value : Int) -> Int {
  guard value >= 0 else {
    abort("gda_bounded_int_digits expects a non-negative value")
  }
  let mut remaining = value
  let mut digits = 1
  while remaining >= 10 {
    remaining /= 10
    digits += 1
  }
  digits
}

///|
fn gda_power10_bounded_int(exponent : Int, limit : Int) -> Int? {
  guard exponent >= 0 && limit >= 0 else { return None }
  guard exponent < gda_bounded_int_digits(limit) else { return None }
  let mut factor = 1
  for _ in 0..<exponent {
    factor *= 10
  }
  Some(factor)
}

///|
fn decimal_exact_integer_count_bounded(rhs : Decimal, limit : Int) -> Int? {
  guard rhs.class == FpClass::Finite && limit >= 0 else { return None }
  if rhs.coefficient.is_zero() {
    return Some(0)
  }
  let magnitude = if rhs.exponent10 >= 0 {
    let factor = match gda_power10_bounded_int(rhs.exponent10, limit) {
      Some(value) => value
      None => return None
    }
    let coefficient_limit = limit / factor
    match gda_coeff_to_bounded_int(rhs.coefficient, coefficient_limit) {
      Some(value) => value * factor
      None => return None
    }
  } else {
    let exact = match
      exact_divide_by_power_of_ten_repr(rhs.coefficient, -rhs.exponent10) {
      Some(value) => value
      None => return None
    }
    match gda_coeff_to_bounded_int(exact, limit) {
      Some(value) => value
      None => return None
    }
  }
  Some(if rhs.negative { -magnitude } else { magnitude })
}

///|
fn decimal_power_integer_count(rhs : Decimal, limit : Int) -> Int? {
  decimal_exact_integer_count_bounded(rhs, limit)
}

///|
fn decimal_power_gda_integer_count(rhs : Decimal) -> Int? {
  let limit = if rhs.negative { 1_999_999_997 } else { 999_999_999 }
  decimal_exact_integer_count_bounded(rhs, limit)
}

///|
fn decimal_power_integer_is_odd(rhs : Decimal) -> Bool? {
  guard rhs.class == FpClass::Finite else { return None }
  if rhs.coefficient.is_zero() {
    return Some(false)
  }
  if rhs.exponent10 > 0 {
    return Some(false)
  }
  match decimal_exact_integer_coeff(rhs) {
    Some((_, magnitude)) => Some(gda_coeff_is_odd(magnitude))
    None => None
  }
}

///|
fn decimal_power_operand_out_of_range(value : Decimal) -> Bool {
  value.class == FpClass::Finite && adjusted_exponent(value) > 999_999
}

///|
fn decimal_power_math_operand_out_of_range(
  value : Decimal,
  ctx : DecimalContext,
) -> Bool {
  value.class == FpClass::Finite &&
  (adjusted_exponent(value) > 999_999 || value.exponent10 < 2 * ctx.e_min - 2)
}

///|
fn decimal_math_operand_out_of_range(value : Decimal) -> Bool {
  value.class == FpClass::Finite &&
  !value.coefficient.is_zero() &&
  (
    value.coefficient.digits10() > 999_999 ||
    value.exponent10 + value.coefficient.digits10() > 1_000_000 ||
    value.exponent10 + value.coefficient.digits10() < -1_999_996
  )
}

///|
fn decimal_power_finite_noninteger_operand_range_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite && exponent.class == FpClass::Finite else {
    return None
  }
  match decimal_power_gda_integer_count(exponent) {
    Some(_) => None
    None =>
      if decimal_math_operand_out_of_range(base) ||
        decimal_math_operand_out_of_range(exponent) {
        let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
        Some((Decimal::nan(precision~), invalid_flags()))
      } else {
        None
      }
  }
}

///|
fn decimal_power_one_limit_result(
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let zeros = Int::max(0, precision - 1)
  (
    finite_with_exponent_repr(
      false,
      gda_coeff_power10_repr(zeros),
      -zeros,
      precision,
    ),
    { ..DecimalFlags::new(), inexact: true, rounded: true },
  )
}

///|
fn decimal_power_one_finite_exponent_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard is_finite_decimal_one(base) && exponent.class == FpClass::Finite else {
    return None
  }
  match decimal_power_integer_is_odd(exponent) {
    Some(_) => None
    None => {
      let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
      if adjusted_exponent(exponent) > 999_999 ||
        exponent.exponent10 + exponent.coefficient.digits10() < -1_999_996 {
        Some((Decimal::nan(precision~), invalid_flags()))
      } else if adjusted_exponent(exponent) >= ctx.e_max {
        Some(decimal_apply_finite_ctx(Decimal::one(precision~), ctx))
      } else {
        Some(decimal_power_one_limit_result(ctx))
      }
    }
  }
}

///|
fn decimal_power_positive_noninteger_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite && exponent.class == FpClass::Finite else {
    return None
  }
  guard !base.negative && !base.coefficient.is_zero() else { return None }
  match decimal_power_gda_integer_count(exponent) {
    Some(_) => None
    None =>
      match decimal_power_adjacent_one_directed_result(base, exponent, ctx) {
        Some(result) => Some(result)
        None =>
          Some(
            decimal_power_positive_noninteger_work_result(base, exponent, ctx),
          )
      }
  }
}

///|
fn decimal_power_adjacent_one_directed_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard exponent.class == FpClass::Finite &&
    !exponent.negative &&
    !exponent.coefficient.is_zero() else {
    return None
  }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let one = Decimal::one(precision~)
  guard exponent.compare(one) < 0 else { return None }
  let flags = { ..DecimalFlags::new(), rounded: true, inexact: true }
  if base.compare(one) > 0 {
    guard ctx.decimal_rounding == DecimalRoundingMode::Ceiling ||
      ctx.decimal_rounding == DecimalRoundingMode::Floor else {
      return None
    }
    let next = decimal_next(one, ctx, true).0
    guard base.compare_total(next) == 0 else { return None }
    if ctx.decimal_rounding == DecimalRoundingMode::Ceiling {
      Some((base, flags))
    } else {
      Some(decimal_power_one_limit_result(ctx))
    }
  } else if base.compare(one) < 0 {
    guard ctx.decimal_rounding == DecimalRoundingMode::Ceiling ||
      ctx.decimal_rounding == DecimalRoundingMode::Floor else {
      return None
    }
    let previous = decimal_next(one, ctx, false).0
    guard base.compare_total(previous) == 0 else { return None }
    if ctx.decimal_rounding == DecimalRoundingMode::Floor {
      Some((base, flags))
    } else {
      Some(decimal_power_one_limit_result(ctx))
    }
  } else {
    None
  }
}

///|
fn decimal_power_positive_noninteger_work_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match decimal_certified_power_result(base, exponent, ctx) {
    Ok(result) => decimal_power_noninteger_gda_result(result, ctx)
    Err(_) => abort("certified decimal power evaluation failed")
  }
}

///|
fn decimal_power_noninteger_gda_result(
  result : (Decimal, DecimalFlags),
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let value = if result.0.class == FpClass::Finite {
    expand_inexact_division_cohort(result.0, ctx, pad_precision=true)
  } else {
    result.0
  }
  (
    value,
    {
      ..result.1,
      rounded: true,
      inexact: true,
      underflow: result.1.underflow || result.1.subnormal,
    },
  )
}

///|
fn decimal_power_finite_noninteger_domain_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite && exponent.class == FpClass::Finite else {
    return None
  }
  match decimal_power_integer_is_odd(exponent) {
    Some(_) => return None
    None => ()
  }
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  if base.coefficient.is_zero() {
    if exponent.negative && !exponent.coefficient.is_zero() {
      return Some(
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new()),
      )
    }
    return Some(
      (
        finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
        DecimalFlags::new(),
      ),
    )
  }
  if base.negative {
    return Some((Decimal::nan(precision~), invalid_flags()))
  }
  None
}

///|
fn decimal_math_result_ctx(ctx : DecimalContext) -> DecimalContext {
  { ..ctx, decimal_rounding: DecimalRoundingMode::HalfEven }
}

///|
fn normalize_decimal_parts_math_ctx_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  exponent10 : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  normalize_decimal_parts_ctx_repr(
    negative,
    magnitude,
    exponent10,
    decimal_math_result_ctx(ctx),
  )
}

///|
fn decimal_normalize_finite_work(
  value : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("decimal_normalize_finite_work expects a finite operand")
  }
  normalize_decimal_parts_math_ctx_repr(
    value.negative,
    value.coefficient,
    value.exponent10,
    work_ctx,
  )
}

///|
fn decimal_apply_finite_ctx(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("decimal_apply_finite_ctx expects a finite operand")
  }
  normalize_decimal_parts_ctx_repr(
    value.negative,
    value.coefficient,
    value.exponent10,
    ctx,
  )
}

///|
fn decimal_power_integer_work_ctx(
  count : Int,
  ctx : DecimalContext,
) -> DecimalContext {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let extra_digits = gda_coeff_from_int_magnitude(count).digits10() +
    (if ctx.extended { 2 } else { 1 })
  {
    ..ctx,
    precision: precision + extra_digits,
    decimal_rounding: DecimalRoundingMode::HalfEven,
  }
}

///|
fn decimal_power_large_integer_exponent_bound_result(
  base : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite && !base.coefficient.is_zero() else {
    return None
  }
  guard count > 0 else { return None }
  let negative = base.negative && (count & 1) == 1
  let digits = base.coefficient.digits10()
  let lower_base = base.exponent10 + digits - 1
  let lower_product = signed_gda_coeff(
    (count < 0) != (lower_base < 0),
    gda_coeff_multiply_repr(
      gda_coeff_from_int_magnitude(count),
      gda_coeff_from_int_magnitude(lower_base),
    ),
  )
  if gda_coeff_signed_compare_int_repr(
      lower_product.negative,
      lower_product.magnitude,
      ctx.e_max,
    ) >
    0 {
    return Some(decimal_overflow_result(negative, ctx))
  }
  // For positive integer powers the exact adjusted exponent lies in
  // [n*(e+d-1), n*(e+d)-1]. Only the upper end is safe for a zero shortcut.
  let upper_base = base.exponent10 + digits
  let upper_product = signed_gda_coeff(
    (count < 0) != (upper_base < 0),
    gda_coeff_multiply_repr(
      gda_coeff_from_int_magnitude(count),
      gda_coeff_from_int_magnitude(upper_base),
    ),
  ).sub(signed_gda_coeff(false, gda_coeff_from_int(1)))
  if gda_coeff_signed_compare_int_repr(
      upper_product.negative,
      upper_product.magnitude,
      etiny(ctx),
    ) <
    0 {
    let (value, flags) = decimal_power_underflow_zero_result(negative, ctx)
    return Some(({ ..value, negative, }, flags))
  }
  None
}

///|
fn decimal_power_integer_exact_result(
  base : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Finite && !base.coefficient.is_zero() else {
    return None
  }
  guard count != 0 else { return None }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let n = abs_int(count)
  let negative = base.negative && (n & 1) == 1
  let magnitude = if ctx.precision == 0 {
    gda_coeff_exact_power_repr(base.coefficient, n)
  } else {
    match gda_coeff_exact_power_if_fits_repr(base.coefficient, n, precision) {
      Some(value) => value
      None => return None
    }
  }
  // GDA's integer-power path keeps both the repeated-multiply accumulator
  // and the optional 1/x result as decNumber Unit coefficients
  // (decNumber.c lines 2167-2215); retain the same representation here.
  let exact = finite_with_exponent_repr(
    negative,
    magnitude,
    base.exponent10 * n,
    precision,
  )
  if count > 0 {
    Some(
      normalize_decimal_parts_ctx_repr(
        negative,
        magnitude,
        base.exponent10 * n,
        ctx,
      ),
    )
  } else {
    match exact_decimal_reciprocal(exact, ctx) {
      Some(result) => Some(result)
      None =>
        if ctx.precision == 0 {
          Some(decimal_div_finite_work(Decimal::one(precision~), exact, ctx))
        } else {
          None
        }
    }
  }
}

///|
fn decimal_power_integer_bounded_result(
  base : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let work_ctx = decimal_power_integer_work_ctx(count, ctx)
  let one = Decimal::one(
    precision=finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx),
  )
  let (factor0, initial_flags) = if count < 0 && ctx.extended {
    decimal_div_finite_work(one, base, work_ctx)
  } else {
    (base, DecimalFlags::new())
  }
  guard factor0.class == FpClass::Finite else {
    return (factor0, initial_flags)
  }
  let mut flags = initial_flags
  let mut acc = one
  let magnitude = abs_int(count)
  let mut bit_mask = 1
  while bit_mask <= magnitude / 2 {
    bit_mask = bit_mask << 1
  }
  let mut seen_bit = false
  while bit_mask > 0 {
    if (magnitude & bit_mask) != 0 {
      seen_bit = true
      let (next_acc, mul_flags) = decimal_mul_finite_work_power_fast(
        acc, factor0, work_ctx,
      )
      flags = flags.combine(mul_flags)
      acc = next_acc
      if decimal_power_terminal_work_result(acc, flags) {
        return decimal_power_terminal_result(base, count, flags, ctx)
      }
    }
    bit_mask = bit_mask >> 1
    if bit_mask > 0 && seen_bit {
      let (next_acc, square_flags) = decimal_mul_finite_work_power_fast(
        acc, acc, work_ctx,
      )
      flags = flags.combine(square_flags)
      acc = next_acc
      if decimal_power_terminal_work_result(acc, flags) {
        return decimal_power_terminal_result(base, count, flags, ctx)
      }
    }
  }
  let (powered, power_flags) = if count < 0 && !ctx.extended {
    let (reciprocal, reciprocal_flags) = decimal_div_finite_work(
      one, acc, work_ctx,
    )
    (reciprocal, flags.combine(reciprocal_flags))
  } else {
    (acc, flags)
  }
  let (result, finalize_flags) = decimal_apply_finite_ctx(powered, ctx)
  (result, power_flags.combine(finalize_flags))
}

///|
fn decimal_power_terminal_result(
  base : Decimal,
  count : Int,
  flags : DecimalFlags,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let negative = base.negative && (abs_int(count) & 1) == 1
  if ctx.extended {
    if flags.overflow {
      decimal_overflow_result(negative, ctx)
    } else {
      decimal_power_underflow_zero_result(negative, ctx)
    }
  } else if count < 0 {
    if flags.overflow {
      decimal_power_underflow_zero_result(negative, ctx)
    } else {
      decimal_overflow_result(negative, ctx)
    }
  } else if flags.overflow {
    decimal_overflow_result(negative, ctx)
  } else {
    decimal_power_underflow_zero_result(negative, ctx)
  }
}

///|
fn decimal_power_integer_finite_result(
  base : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let required_precision = finite_precision_for_coeff(
      gda_coeff_from_int(1),
      ctx,
    ) +
    gda_coeff_from_int_magnitude(count).digits10() +
    (if ctx.extended { 2 } else { 1 })
  if required_precision > 999_999_999 {
    let negative = base.negative && (abs_int(count) & 1) == 1
    return (
      Decimal::inf(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=finite_precision_for_coeff(gda_coeff_from_int(1), ctx),
      ),
      { ..DecimalFlags::new(), overflow: true },
    )
  }
  match decimal_power_large_integer_exponent_bound_result(base, count, ctx) {
    Some(result) => return result
    None => ()
  }
  let result = match decimal_power_integer_exact_result(base, count, ctx) {
    Some(result) => result
    None => decimal_power_integer_bounded_result(base, count, ctx)
  }
  decimal_power_finalize_result(result, ctx)
}

///|
fn decimal_power_finalize_result(
  result : (Decimal, DecimalFlags),
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let value = result.0
  if ctx.extended || value.class != FpClass::Finite {
    return result
  }
  finish_context_result(value, result.1, ctx, true)
}

///|
fn decimal_exp_underflow_zero_result(
  ctx : DecimalContext,
  clamped : Bool,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  let result = (
    finite_with_exponent_repr(false, gda_coeff_zero(), etiny(ctx), precision),
    {
      ..DecimalFlags::new(),
      underflow: true,
      inexact: true,
      rounded: true,
      clamped: clamped || ctx.extended,
      subnormal: true,
    },
  )
  if ctx.extended || clamped {
    result
  } else {
    (
      finish_subset_finite_result(result.0, ctx, false),
      { ..result.1, clamped: false },
    )
  }
}

///|
fn decimal_math_target_precision(ctx : DecimalContext) -> Int {
  if ctx.precision == 0 {
    34
  } else {
    Int::max(1, ctx.precision)
  }
}

///|
fn decimal_math_work_ctx(precision : Int) -> DecimalContext {
  DecimalContext::new(
    precision=Int::max(precision, 1),
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
}

///|
fn decimal_math_small_threshold(work_precision : Int) -> Decimal {
  finite_with_exponent_repr(
    false,
    gda_coeff_from_int(1),
    -(work_precision + 2),
    1,
  )
}

///|
fn decimal_math_abs(value : Decimal) -> Decimal {
  if value.class == FpClass::Finite {
    { ..value, negative: false }
  } else {
    value
  }
}

///|
fn decimal_math_term_is_small(value : Decimal, threshold : Decimal) -> Bool {
  guard value.class == FpClass::Finite else { return false }
  decimal_math_abs(value).compare(threshold) <= 0
}

///|
fn decimal_mul_finite_by_small_int_work(
  value : Decimal,
  factor : Int,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("decimal_mul_finite_by_small_int_work expects a finite operand")
  }
  guard factor >= 0 else {
    abort("decimal_mul_finite_by_small_int_work expects a non-negative factor")
  }
  normalize_decimal_parts_math_ctx_repr(
    value.negative,
    gda_coeff_multiply_repr(
      value.coefficient,
      gda_coeff_from_nonnegative_int(factor),
    ),
    value.exponent10,
    work_ctx,
  )
}

///|
fn decimal_div_finite_by_small_int_work(
  value : Decimal,
  divisor : Int,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("decimal_div_finite_by_small_int_work expects a finite operand")
  }
  guard divisor > 0 else {
    abort("decimal_div_finite_by_small_int_work expects a positive divisor")
  }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx)
  let denominator = gda_coeff_from_nonnegative_int(divisor)
  let extra = precision + denominator.digits10() + 2
  let numerator = gda_coeff_shift_power10_repr(value.coefficient, extra)
  let exact = has_finite_decimal_expansion_repr(value.coefficient, denominator)
  let q = round_positive_decimal_div_repr(
    numerator,
    denominator,
    value.negative,
    work_ctx.decimal_rounding,
  )
  let (result, flags) = if exact {
    let exact_unrounded = normalize_decimal_parts_gda_repr(
      value.negative,
      q,
      value.exponent10 - extra,
      q.digits10(),
      work_ctx.decimal_rounding,
    )
    let exact_rounding = exact_result_rounding_flags(
      exact_unrounded,
      value.exponent10,
      work_ctx,
    )
    let rounded_value = normalize_decimal_parts_gda_repr(
      value.negative,
      q,
      value.exponent10 - extra,
      precision,
      work_ctx.decimal_rounding,
    )
    if exact_rounding.rounded {
      let prefinal = if exact_unrounded.exponent10 < etiny(work_ctx) {
        exact_unrounded
      } else if !exact_rounding.inexact {
        expand_rounded_exact_cohort_toward_preferred_exponent(
          rounded_value,
          value.exponent10,
          work_ctx,
        )
      } else {
        expand_inexact_division_cohort(
          rounded_value,
          work_ctx,
          pad_precision=true,
        )
      }
      let (result, flags) = finalize_finite_ctx(
        prefinal, exact_rounding, work_ctx,
      )
      (result, with_underflow_for_inexact_subnormal(result, flags, work_ctx))
    } else {
      let exact_value = expand_exact_cohort_toward_preferred_exponent(
        rounded_value,
        value.exponent10,
        work_ctx,
      )
      let exact_value = if work_ctx.clamp {
        exact_value
      } else {
        expand_finite_cohort_toward_target_exponent(exact_value, 0, work_ctx)
      }
      finalize_finite_ctx(exact_value, DecimalFlags::new(), work_ctx)
    }
  } else {
    finalize_finite_ctx(
      normalize_decimal_parts_gda_repr(
        value.negative,
        q,
        value.exponent10 - extra,
        precision,
        work_ctx.decimal_rounding,
      ),
      DecimalFlags::new(),
      work_ctx,
    )
  }
  if exact {
    (result, flags)
  } else {
    let result = expand_inexact_division_cohort(result, work_ctx)
    (
      result,
      with_underflow_for_inexact_subnormal(
        result,
        { ..flags, rounded: true, inexact: true },
        work_ctx,
      ),
    )
  }
}

///|
fn decimal_div_finite_work(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_div_finite_work expects finite operands")
  }
  guard !rhs.coefficient.is_zero() else {
    abort("decimal_div_finite_work expects a non-zero divisor")
  }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx)
  if lhs.coefficient.is_zero() {
    return finalize_finite_ctx(
      finite_with_exponent_repr(
        lhs.negative != rhs.negative,
        gda_coeff_zero(),
        lhs.exponent10 - rhs.exponent10,
        precision,
      ),
      DecimalFlags::new(),
      work_ctx,
    )
  }
  match exact_division_by_power_of_ten_result(lhs, rhs, work_ctx) {
    Some(result) => return result
    None => ()
  }
  let denominator = rhs.coefficient
  let extra = precision + denominator.digits10() + 2
  let numerator = gda_coeff_shift_power10_repr(lhs.coefficient, extra)
  let exact = has_finite_decimal_expansion_repr(
    lhs.coefficient,
    rhs.coefficient,
  )
  let q = round_positive_decimal_div_repr(
    numerator,
    denominator,
    lhs.negative != rhs.negative,
    work_ctx.decimal_rounding,
  )
  let (value, round_flags) = if exact {
    let exact_unrounded = normalize_decimal_parts_gda_repr(
      lhs.negative != rhs.negative,
      q,
      lhs.exponent10 - rhs.exponent10 - extra,
      q.digits10(),
      work_ctx.decimal_rounding,
    )
    let exact_rounding = exact_result_rounding_flags(
      exact_unrounded,
      lhs.exponent10 - rhs.exponent10,
      work_ctx,
    )
    let rounded_value = normalize_decimal_parts_gda_repr(
      lhs.negative != rhs.negative,
      q,
      lhs.exponent10 - rhs.exponent10 - extra,
      precision,
      work_ctx.decimal_rounding,
    )
    if exact_rounding.rounded {
      let prefinal = if exact_unrounded.exponent10 < etiny(work_ctx) {
        exact_unrounded
      } else if !exact_rounding.inexact {
        expand_rounded_exact_cohort_toward_preferred_exponent(
          rounded_value,
          lhs.exponent10 - rhs.exponent10,
          work_ctx,
        )
      } else {
        expand_inexact_division_cohort(
          rounded_value,
          work_ctx,
          pad_precision=true,
        )
      }
      let (value, flags) = finalize_finite_ctx(
        prefinal, exact_rounding, work_ctx,
      )
      (value, with_underflow_for_inexact_subnormal(value, flags, work_ctx))
    } else {
      let exact_value = expand_exact_cohort_toward_preferred_exponent(
        rounded_value,
        lhs.exponent10 - rhs.exponent10,
        work_ctx,
      )
      let exact_value = if work_ctx.clamp {
        exact_value
      } else {
        expand_finite_cohort_toward_target_exponent(exact_value, 0, work_ctx)
      }
      finalize_finite_ctx(exact_value, DecimalFlags::new(), work_ctx)
    }
  } else {
    finalize_finite_ctx(
      normalize_decimal_parts_gda_repr(
        lhs.negative != rhs.negative,
        q,
        lhs.exponent10 - rhs.exponent10 - extra,
        precision,
        work_ctx.decimal_rounding,
      ),
      DecimalFlags::new(),
      work_ctx,
    )
  }
  if exact {
    (value, round_flags)
  } else {
    let value = expand_inexact_division_cohort(value, work_ctx)
    (
      value,
      with_underflow_for_inexact_subnormal(
        value,
        { ..round_flags, rounded: true, inexact: true },
        work_ctx,
      ),
    )
  }
}

///|
fn decimal_mul_finite_work(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_mul_finite_work expects finite operands")
  }
  normalize_decimal_parts_math_ctx_repr(
    lhs.negative != rhs.negative,
    gda_coeff_multiply_repr(lhs.coefficient, rhs.coefficient),
    lhs.exponent10 + rhs.exponent10,
    work_ctx,
  )
}

///|
fn decimal_mul_finite_work_power_fast(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_mul_finite_work_power_fast expects finite operands")
  }
  if lhs.coefficient.is_zero() || rhs.coefficient.is_zero() {
    return normalize_decimal_parts_math_ctx_repr(
      lhs.negative != rhs.negative,
      gda_coeff_zero(),
      lhs.exponent10 + rhs.exponent10,
      work_ctx,
    )
  }
  let negative = lhs.negative != rhs.negative
  let lower_adjusted = adjusted_exponent(lhs).to_int64() +
    adjusted_exponent(rhs).to_int64()
  if lower_adjusted > work_ctx.e_max.to_int64() {
    return decimal_overflow_result(negative, work_ctx)
  }
  let upper_adjusted = lower_adjusted + 1L
  if upper_adjusted < etiny(work_ctx).to_int64() {
    return decimal_underflow_zero_result(negative, work_ctx)
  }
  decimal_mul_finite_work(lhs, rhs, work_ctx)
}

///|
fn decimal_power_terminal_work_result(
  value : Decimal,
  flags : DecimalFlags,
) -> Bool {
  value.class != FpClass::Finite ||
  flags.overflow ||
  (
    flags.underflow &&
    value.class == FpClass::Finite &&
    value.coefficient.is_zero()
  )
}

///|
fn decimal_sub_finite_work(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_sub_finite_work expects finite operands")
  }
  decimal_add_finite_work(lhs, { ..rhs, negative: !rhs.negative }, work_ctx)
}

///|
fn decimal_add_finite_work(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_add_finite_work expects finite operands")
  }
  let target = Int::min(lhs.exponent10, rhs.exponent10)
  let (negative, exact) = decimal_exact_aligned_sum_result(lhs, rhs, target)
  normalize_decimal_parts_math_ctx_repr(negative, exact, target, work_ctx)
}

///|
fn decimal_round_scaled_coeff(
  value : SignedGdaCoeff,
  shift : Int,
) -> SignedGdaCoeff {
  value.round_power10_half_even(shift)
}

///|
fn decimal_ln_atanh_scaled_coeff(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
  scale : Int,
) -> SignedGdaCoeff {
  guard !numerator.is_zero() && !denominator.is_zero() else {
    abort("decimal_ln_atanh_scaled_coeff expects positive rational input")
  }
  let comparison = gda_coeff_compare_repr(numerator, denominator)
  if comparison == 0 {
    return signed_gda_coeff_zero()
  }
  let extra_digits = 8
  let work_scale = scale + extra_digits
  let negative = comparison < 0
  let delta = if negative {
    gda_coeff_magnitude_sub_repr(denominator, numerator)
  } else {
    gda_coeff_magnitude_sub_repr(numerator, denominator)
  }
  let sum = gda_coeff_magnitude_add_repr(numerator, denominator)
  let scale_factor = gda_coeff_power10_repr(work_scale)
  let delta2 = gda_coeff_square_repr(delta)
  let sum2 = gda_coeff_square_repr(sum)
  let mut power_num = delta
  let mut power_den = sum
  let mut divisor_index = 1
  let mut total = gda_coeff_zero()
  let stop_threshold = gda_coeff_power10_repr(extra_digits)
  let mut active = true
  while active {
    let divisor = gda_coeff_multiply_repr(
      power_den,
      gda_coeff_from_nonnegative_int(divisor_index),
    )
    let scaled_power = gda_coeff_multiply_repr(scale_factor, power_num)
    let term_numerator = gda_coeff_multiply_by_unit_repr(scaled_power, 2)
    let term = gda_coeff_div_rem_repr(term_numerator, divisor).0
    total = gda_coeff_magnitude_add_repr(total, term)
    if gda_coeff_compare_repr(term, stop_threshold) <= 0 {
      active = false
    } else {
      power_num = gda_coeff_multiply_repr(power_num, delta2)
      power_den = gda_coeff_multiply_repr(power_den, sum2)
      divisor_index += 2
    }
  }
  decimal_round_scaled_coeff(signed_gda_coeff(negative, total), extra_digits)
}

///|
fn decimal_transcendental_ln_constants(
  work_scale : Int,
) -> (GdaCoeff, GdaCoeff, GdaCoeff) {
  let cache = decimal_math_constant_cache.val
  if cache.scale >= work_scale && cache.scale > 0 {
    let shift = cache.scale - work_scale
    return (
      decimal_round_scaled_coeff(signed_gda_coeff(false, cache.ln2), shift).magnitude,
      decimal_round_scaled_coeff(signed_gda_coeff(false, cache.ln5), shift).magnitude,
      decimal_round_scaled_coeff(signed_gda_coeff(false, cache.ln10), shift).magnitude,
    )
  }
  let ln2 = decimal_ln_atanh_scaled_coeff(
      gda_coeff_from_int(2),
      gda_coeff_from_int(1),
      work_scale,
    ).magnitude
  let ln_five_quarters = decimal_ln_atanh_scaled_coeff(
      gda_coeff_from_int(5),
      gda_coeff_from_int(4),
      work_scale,
    ).magnitude
  let ln10 = gda_coeff_magnitude_add_repr(
    gda_coeff_multiply_by_unit_repr(ln2, 3),
    ln_five_quarters,
  )
  let ln5 = gda_coeff_magnitude_sub_repr(ln10, ln2)
  decimal_math_constant_cache.val = { scale: work_scale, ln2, ln5, ln10 }
  (ln2, ln5, ln10)
}

///|
fn decimal_math_scaled_constant(
  magnitude : GdaCoeff,
  scale : Int,
  work_ctx : DecimalContext,
) -> Decimal {
  normalize_decimal_parts_math_ctx_repr(false, magnitude, -scale, work_ctx).0
}

///|
fn decimal_ln_near_one_series(
  mantissa : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx)
  let one = Decimal::one(precision~)
  let threshold = decimal_math_small_threshold(work_ctx.precision)
  let (delta, delta_flags) = decimal_sub_finite_work(mantissa, one, work_ctx)
  guard delta.class == FpClass::Finite else { return (delta, delta_flags) }
  let (sum_base, sum_flags) = decimal_add_finite_work(mantissa, one, work_ctx)
  guard sum_base.class == FpClass::Finite else {
    return (sum_base, delta_flags.combine(sum_flags))
  }
  let (t, t_flags) = decimal_div_finite_work(delta, sum_base, work_ctx)
  guard t.class == FpClass::Finite else {
    return (t, delta_flags.combine(sum_flags).combine(t_flags))
  }
  let (t2, t2_flags) = decimal_mul_finite_work(t, t, work_ctx)
  guard t2.class == FpClass::Finite else {
    return (
      t2,
      delta_flags.combine(sum_flags).combine(t_flags).combine(t2_flags),
    )
  }
  let mut flags = delta_flags
    .combine(sum_flags)
    .combine(t_flags)
    .combine(t2_flags)
  let mut sum = t
  let mut term = t
  let mut divisor = 3
  let mut steps = 0
  let max_steps = Int::max(32, work_ctx.precision / 2 + 32)
  while steps < max_steps {
    let (next_term0, mul_flags) = decimal_mul_finite_work(term, t2, work_ctx)
    flags = flags.combine(mul_flags)
    term = next_term0
    if term.class != FpClass::Finite {
      return (term, flags)
    }
    let (next_piece, div_flags) = decimal_div_finite_by_small_int_work(
      term, divisor, work_ctx,
    )
    flags = flags.combine(div_flags)
    if next_piece.class != FpClass::Finite {
      return (next_piece, flags)
    }
    let (next_sum, add_flags) = decimal_add_finite_work(
      sum, next_piece, work_ctx,
    )
    flags = flags.combine(add_flags)
    sum = next_sum
    if sum.class != FpClass::Finite {
      return (sum, flags)
    }
    if decimal_math_term_is_small(next_piece, threshold) {
      break
    }
    divisor += 2
    steps += 1
  }
  let (result, scale_flags) = decimal_mul_finite_by_small_int_work(
    sum, 2, work_ctx,
  )
  (result, flags.combine(scale_flags))
}

///|
fn _decimal_ln_positive_finite_work_result_with_ln10(
  value : Decimal,
  work_ctx : DecimalContext,
  ln10_scaled : GdaCoeff,
) -> (Decimal, DecimalFlags) {
  match
    decimal_ln_lookaside_work_result_with_ln10(value, work_ctx, ln10_scaled) {
    Some(result) => return result
    None => ()
  }
  let work_precision = work_ctx.precision
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx)
  let adjusted = adjusted_exponent(value)
  let one = Decimal::one(precision~)
  let near_threshold = finite_with_exponent_repr(
    false,
    gda_coeff_from_int(1),
    -1,
    1,
  )
  let mut flags = DecimalFlags::new()
  let mut mantissa = finite_with_exponent_repr(
    false,
    value.coefficient,
    value.exponent10 - adjusted,
    finite_precision_for_coeff(value.coefficient, decimal_exact_work_context()),
  )
  let (mantissa0, mantissa_flags) = decimal_normalize_finite_work(
    mantissa, work_ctx,
  )
  mantissa = mantissa0
  flags = flags.combine(mantissa_flags)
  let mut sqrt_reductions = 0
  while sqrt_reductions < 12 {
    let (delta, delta_flags) = decimal_sub_finite_work(mantissa, one, work_ctx)
    flags = flags.combine(delta_flags)
    if delta.class != FpClass::Finite ||
      decimal_math_term_is_small(delta, near_threshold) {
      break
    }
    let (next_mantissa, sqrt_flags) = mantissa.sqrt_ctx(work_ctx)
    flags = flags.combine(sqrt_flags)
    mantissa = next_mantissa
    if mantissa.class != FpClass::Finite {
      return (mantissa, flags)
    }
    sqrt_reductions += 1
  }
  let (series, series_flags) = decimal_ln_near_one_series(mantissa, work_ctx)
  flags = flags.combine(series_flags)
  guard series.class == FpClass::Finite else { return (series, flags) }
  let (scaled_series, scaled_flags) = if sqrt_reductions == 0 {
    (series, DecimalFlags::new())
  } else {
    decimal_mul_finite_by_small_int_work(series, 1 << sqrt_reductions, work_ctx)
  }
  flags = flags.combine(scaled_flags)
  guard scaled_series.class == FpClass::Finite else {
    return (scaled_series, flags)
  }
  if adjusted == 0 {
    return (scaled_series, flags)
  }
  let scaled_exponent = signed_gda_coeff_from_int_product(adjusted, ln10_scaled)
  let exponent_term = {
    ..decimal_math_scaled_constant(
      scaled_exponent.magnitude,
      work_precision + 12,
      work_ctx,
    ),
    negative: scaled_exponent.negative,
  }
  let (result, add_flags) = decimal_add_finite_work(
    scaled_series, exponent_term, work_ctx,
  )
  (result, flags.combine(add_flags))
}

///|
fn decimal_ln_lookaside_work_result_with_ln10(
  value : Decimal,
  work_ctx : DecimalContext,
  ln10_scaled : GdaCoeff,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite &&
    !value.negative &&
    !value.coefficient.is_zero() else {
    return None
  }
  let (reduced0, _, power10s) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    0,
  )
  let decade = value.exponent10 + power10s
  let constant_scale = work_ctx.precision + 12
  let mut total_scaled = signed_gda_coeff_from_int_product(decade, ln10_scaled)
  if gda_coeff_matches_unit_repr(reduced0, 1) {
    guard decade != 0 else { return None }
  } else if gda_coeff_matches_unit_repr(reduced0, 2) {
    total_scaled = total_scaled.add(
      signed_gda_coeff(
        false,
        decimal_transcendental_ln_constants(constant_scale).0,
      ),
    )
  } else if gda_coeff_matches_unit_repr(reduced0, 5) {
    total_scaled = total_scaled.add(
      signed_gda_coeff(
        false,
        decimal_transcendental_ln_constants(constant_scale).1,
      ),
    )
  } else {
    return None
  }
  let result = decimal_math_scaled_constant(
    total_scaled.magnitude,
    constant_scale,
    work_ctx,
  )
  Some(
    (
      if total_scaled.negative {
        { ..result, negative: true }
      } else {
        result
      },
      { ..DecimalFlags::new(), rounded: true, inexact: true },
    ),
  )
}

///|
fn decimal_finite_to_scaled_repr(
  value : Decimal,
  scale : Int,
) -> (Bool, GdaCoeff) {
  let shift = value.exponent10 + scale
  let magnitude = if shift >= 0 {
    gda_coeff_shift_power10_repr(value.coefficient, shift)
  } else {
    gda_coeff_div_rem_repr(value.coefficient, gda_coeff_power10_repr(-shift)).0
  }
  (value.negative && !magnitude.is_zero(), magnitude)
}

///|
fn decimal_floor_div_scaled_repr(
  negative : Bool,
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> Int {
  guard !denominator.is_zero() else {
    abort("decimal_floor_div_scaled_repr expects a positive denominator")
  }
  let (quotient0, remainder) = gda_coeff_div_rem_repr(numerator, denominator)
  let quotient = if negative && !remainder.is_zero() {
    gda_coeff_magnitude_add_unit(quotient0, 1)
  } else {
    quotient0
  }
  let magnitude = match gda_coeff_to_bounded_int(quotient, 999_999_999) {
    Some(value) => value
    None =>
      abort("decimal_floor_div_scaled_repr quotient exceeds GDA math bounds")
  }
  if negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn decimal_exp_series_result(
  reduced : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), work_ctx)
  let one = Decimal::one(precision~)
  let threshold = decimal_math_small_threshold(work_ctx.precision)
  let mut flags = DecimalFlags::new()
  let mut sum = one
  let mut term = one
  let mut index = 1
  let mut steps = 0
  let max_steps = Int::max(48, work_ctx.precision + 32)
  while steps < max_steps {
    let (next_term0, mul_flags) = decimal_mul_finite_work(
      term, reduced, work_ctx,
    )
    flags = flags.combine(mul_flags)
    term = next_term0
    if term.class != FpClass::Finite {
      return (term, flags)
    }
    let (next_term, div_flags) = decimal_div_finite_by_small_int_work(
      term, index, work_ctx,
    )
    flags = flags.combine(div_flags)
    term = next_term
    if term.class != FpClass::Finite {
      return (term, flags)
    }
    let (next_sum, add_flags) = decimal_add_finite_work(sum, term, work_ctx)
    flags = flags.combine(add_flags)
    sum = next_sum
    if sum.class != FpClass::Finite {
      return (sum, flags)
    }
    if decimal_math_term_is_small(term, threshold) {
      break
    }
    index += 1
    steps += 1
  }
  (sum, flags)
}

///|
fn _decimal_exp_finite_work_result_with_ln10(
  value : Decimal,
  work_ctx : DecimalContext,
  ln10_scaled : GdaCoeff,
) -> (Decimal, DecimalFlags) {
  match decimal_exp_extreme_half_even_result(value, work_ctx) {
    Some(result) => return result
    None => ()
  }
  let work_precision = work_ctx.precision
  let halving_threshold = finite_with_exponent_repr(
    false,
    gda_coeff_from_int(125),
    -3,
    3,
  )
  let constant_scale = work_precision + 12
  let (scaled_negative, scaled_input) = decimal_finite_to_scaled_repr(
    value, constant_scale,
  )
  let ln10_coefficient = ln10_scaled
  let exponent10 = decimal_floor_div_scaled_repr(
    scaled_negative, scaled_input, ln10_coefficient,
  )
  let exponent_product = gda_coeff_multiply_repr(
    gda_coeff_from_nonnegative_int(abs_int(exponent10)),
    ln10_coefficient,
  )
  let (reduced_negative, reduced_magnitude) = gda_coeff_signed_add_repr(
    scaled_negative,
    scaled_input,
    exponent10 >= 0,
    exponent_product,
  )
  let mut flags = DecimalFlags::new()
  let mut reduced = normalize_decimal_parts_math_ctx_repr(
      reduced_negative,
      reduced_magnitude,
      -constant_scale,
      work_ctx,
    ).0
  let mut halvings = 0
  while reduced.class == FpClass::Finite &&
        decimal_math_abs(reduced).compare(halving_threshold) > 0 &&
        halvings < 24 {
    let (next_reduced, div_flags) = decimal_div_finite_by_small_int_work(
      reduced, 2, work_ctx,
    )
    flags = flags.combine(div_flags)
    reduced = next_reduced
    halvings += 1
  }
  guard reduced.class == FpClass::Finite else { return (reduced, flags) }
  let (series, series_flags) = decimal_exp_series_result(reduced, work_ctx)
  flags = flags.combine(series_flags)
  let mut result = series
  guard result.class == FpClass::Finite else { return (result, flags) }
  let mut remaining = halvings
  while remaining > 0 {
    let (next_result, square_flags) = decimal_mul_finite_work(
      result, result, work_ctx,
    )
    flags = flags.combine(square_flags)
    result = next_result
    if result.class != FpClass::Finite {
      return (result, flags)
    }
    remaining -= 1
  }
  if exponent10 != 0 {
    result = { ..result, exponent10: result.exponent10 + exponent10 }
    let (normalized, normalize_flags) = decimal_normalize_finite_work(
      result, work_ctx,
    )
    result = normalized
    flags = flags.combine(normalize_flags)
  }
  (result, flags)
}

///|
fn decimal_exp_boundary_entry(
  ctx : DecimalContext,
) -> DecimalExpBoundaryCacheEntry {
  for entry in decimal_exp_boundary_cache {
    if entry.precision == ctx.precision &&
      entry.e_min == ctx.e_min &&
      entry.e_max == ctx.e_max &&
      entry.clamp == ctx.clamp {
      return entry
    }
  }
  let boundary_precision = Int::max(decimal_math_target_precision(ctx) + 12, 64)
  let boundary_ctx = decimal_math_work_ctx(boundary_precision)
  let boundary_scale = boundary_precision + 12
  let (_, ln5_scaled, ln10_scaled) = decimal_transcendental_ln_constants(
    boundary_scale,
  )
  let lower_scaled = signed_gda_coeff(false, ln5_scaled).add(
    signed_gda_coeff_from_int_product(etiny(ctx) - 1, ln10_scaled),
  )
  let upper_scaled = signed_gda_coeff_from_int_product(
    ctx.e_max + 1,
    ln10_scaled,
  )
  let entry = {
    precision: ctx.precision,
    e_min: ctx.e_min,
    e_max: ctx.e_max,
    clamp: ctx.clamp,
    lower: normalize_decimal_parts_math_ctx_repr(
      lower_scaled.negative,
      lower_scaled.magnitude,
      -boundary_scale,
      boundary_ctx,
    ).0,
    upper: normalize_decimal_parts_math_ctx_repr(
      upper_scaled.negative,
      upper_scaled.magnitude,
      -boundary_scale,
      boundary_ctx,
    ).0,
  }
  if decimal_exp_boundary_cache.length() < decimal_exp_boundary_cache_capacity {
    decimal_exp_boundary_cache.push(entry)
  } else {
    let next = decimal_exp_boundary_cache_next.val
    decimal_exp_boundary_cache[next] = entry
    decimal_exp_boundary_cache_next.val = (next + 1) %
      decimal_exp_boundary_cache_capacity
  }
  entry
}

///|
fn decimal_exp_extreme_half_even_result(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let boundary = decimal_exp_boundary_entry(ctx)
  if value.negative {
    if value.compare(boundary.lower) <= 0 {
      let clamped = match decimal_power_gda_integer_count(value) {
        Some(count) => count <= -1000
        None => false
      }
      Some(decimal_exp_underflow_zero_result(ctx, clamped))
    } else {
      None
    }
  } else if value.compare(boundary.upper) >= 0 {
    Some(decimal_overflow_result(false, ctx))
  } else {
    None
  }
}

///|
fn decimal_power_compare_abs_one(value : Decimal, precision : Int) -> Int {
  compare_finite(
    { ..value, negative: false },
    finite_with_exponent_repr(false, gda_coeff_from_int(1), 0, precision),
  )
}

///|
fn decimal_power_infinite_exponent_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard exponent.class == FpClass::Infinity else { return None }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  match base.class {
    FpClass::NaN => None
    FpClass::Infinity =>
      if base.negative {
        Some((Decimal::nan(precision~), invalid_flags()))
      } else if exponent.negative {
        Some(
          (
            finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
            DecimalFlags::new(),
          ),
        )
      } else {
        Some((Decimal::inf(Sign::Positive, precision~), DecimalFlags::new()))
      }
    FpClass::Finite =>
      if base.coefficient.is_zero() {
        if exponent.negative {
          Some((Decimal::inf(Sign::Positive, precision~), DecimalFlags::new()))
        } else {
          Some(
            (
              finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
              DecimalFlags::new(),
            ),
          )
        }
      } else if base.negative {
        Some((Decimal::nan(precision~), invalid_flags()))
      } else {
        let cmp = decimal_power_compare_abs_one(base, precision)
        if cmp == 0 {
          Some(decimal_power_one_limit_result(ctx))
        } else if (cmp < 0 && !exponent.negative) ||
          (cmp > 0 && exponent.negative) {
          Some(
            (
              finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
              DecimalFlags::new(),
            ),
          )
        } else {
          Some((Decimal::inf(Sign::Positive, precision~), DecimalFlags::new()))
        }
      }
  }
}

///|
fn decimal_power_infinite_base_noninteger_result(
  base : Decimal,
  exponent : Decimal,
  precision : Int,
) -> (Decimal, DecimalFlags)? {
  guard base.class == FpClass::Infinity else { return None }
  guard exponent.class == FpClass::Finite else { return None }
  match decimal_power_integer_is_odd(exponent) {
    Some(_) => None
    None =>
      if base.negative {
        Some((Decimal::nan(precision~), invalid_flags()))
      } else if exponent.negative {
        Some(
          (
            finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
            DecimalFlags::new(),
          ),
        )
      } else {
        Some((Decimal::inf(Sign::Positive, precision~), DecimalFlags::new()))
      }
  }
}

///|
fn decimal_power_simple_ten_exponent(base : Decimal) -> Int? {
  guard base.class == FpClass::Finite && !base.coefficient.is_zero() else {
    return None
  }
  if gda_coeff_compare_repr(base.coefficient, gda_coeff_from_int(10)) == 0 &&
    base.exponent10 == 0 {
    Some(1)
  } else if gda_coeff_compare_repr(base.coefficient, gda_coeff_from_int(1)) == 0 &&
    base.exponent10 == -1 {
    Some(-1)
  } else {
    None
  }
}

///|
fn decimal_power_of_ten_exponent(base : Decimal) -> Int? {
  guard base.class == FpClass::Finite && !base.coefficient.is_zero() else {
    return None
  }
  let (remaining0, _, zeros) = trim_trailing_decimal_zeros_repr(
    base.coefficient,
    0,
  )
  guard gda_coeff_compare_repr(remaining0, gda_coeff_from_int(1)) == 0 else {
    return None
  }
  Some(base.exponent10 + zeros)
}

///|
fn decimal_underflow_zero_result(
  negative : Bool,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  (
    finite_with_exponent_repr(negative, gda_coeff_zero(), etiny(ctx), precision),
    {
      ..DecimalFlags::new(),
      underflow: true,
      inexact: true,
      rounded: true,
      clamped: true,
      subnormal: true,
    },
  )
}

///|
fn decimal_power_underflow_zero_result(
  negative : Bool,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (value, flags) = decimal_underflow_zero_result(negative, ctx)
  if ctx.extended {
    (value, flags)
  } else {
    (value, { ..flags, clamped: false })
  }
}

///|
fn decimal_power_of_ten_extreme_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let base_power = match decimal_power_of_ten_exponent(base) {
    Some(value) => value
    None => return None
  }
  let count = match decimal_power_gda_integer_count(exponent) {
    Some(value) => value
    None => return None
  }
  guard count != 0 && base_power != 0 else { return None }
  let result_exponent = base_power.to_int64() * count.to_int64()
  let negative = match decimal_power_integer_is_odd(exponent) {
    Some(odd) => base.negative && odd
    None => false
  }
  if result_exponent > ctx.e_max.to_int64() {
    Some(decimal_overflow_result(negative, ctx))
  } else if result_exponent < etiny(ctx).to_int64() &&
    ctx.decimal_rounding == DecimalRoundingMode::HalfEven {
    Some(decimal_power_underflow_zero_result(negative, ctx))
  } else {
    None
  }
}

///|
fn decimal_power_simple_ten_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let base_power = match decimal_power_simple_ten_exponent(base) {
    Some(value) => value
    None => return None
  }
  let count = match decimal_power_integer_count(exponent, 999_999_999) {
    Some(value) => value
    None => return None
  }
  let result_exponent = base_power * count
  guard result_exponent <= ctx.e_max && result_exponent >= etiny(ctx) else {
    return None
  }
  let negative = match decimal_power_integer_is_odd(exponent) {
    Some(odd) => base.negative && odd
    None => false
  }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  if gda_coeff_matches_unit_repr(base.coefficient, 10) && count > 0 {
    if count + 1 <= precision {
      Some(
        finalize_finite_ctx(
          finite_with_exponent_repr(
            negative,
            gda_coeff_power10_repr(count),
            0,
            precision,
          ),
          DecimalFlags::new(),
          ctx,
        ),
      )
    } else {
      Some(
        finalize_finite_ctx(
          finite_with_exponent_repr(
            negative,
            gda_coeff_power10_repr(precision - 1),
            result_exponent - precision + 1,
            precision,
          ),
          { ..DecimalFlags::new(), rounded: true },
          ctx,
        ),
      )
    }
  } else {
    let flags = if !ctx.extended &&
      gda_coeff_matches_unit_repr(base.coefficient, 10) &&
      count < 0 &&
      abs_int(count) + 1 > precision {
      { ..DecimalFlags::new(), rounded: true }
    } else {
      DecimalFlags::new()
    }
    Some(
      finalize_finite_ctx(
        finite_with_exponent_repr(
          negative,
          gda_coeff_from_int(1),
          result_exponent,
          precision,
        ),
        flags,
        ctx,
      ),
    )
  }
}

///|
fn decimal_power_exact_ten_result(
  base : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard gda_coeff_matches_unit_repr(base.coefficient, 1) else { return None }
  if decimal_power_gda_integer_count(exponent) is None &&
    decimal_power_math_operand_out_of_range(exponent, ctx) {
    return None
  }
  let base_power = match decimal_power_of_ten_exponent(base) {
    Some(value) => value
    None => return None
  }
  let (count_negative, count_magnitude) = match
    decimal_exact_integer_coeff(exponent) {
    Some(value) => value
    None => return None
  }
  let negative = match decimal_power_integer_is_odd(exponent) {
    Some(odd) => base.negative && odd
    None => false
  }
  if count_magnitude.is_zero() {
    return Some(
      decimal_apply_finite_ctx(
        Decimal::one(
          precision=finite_precision_for_coeff(gda_coeff_from_int(1), ctx),
        ),
        ctx,
      ),
    )
  }
  let result_exponent_negative = count_negative != (base_power < 0)
  let result_exponent_magnitude = gda_coeff_multiply_repr(
    count_magnitude,
    gda_coeff_from_nonnegative_int(abs_int(base_power)),
  )
  if gda_coeff_signed_compare_int_repr(
      result_exponent_negative,
      result_exponent_magnitude,
      ctx.e_max,
    ) >
    0 {
    return Some(decimal_overflow_result(negative, ctx))
  }
  if gda_coeff_signed_compare_int_repr(
      result_exponent_negative,
      result_exponent_magnitude,
      etiny(ctx),
    ) <
    0 {
    return Some(decimal_power_underflow_zero_result(negative, ctx))
  }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let exponent_limit = Int::max(abs_int(ctx.e_max), abs_int(etiny(ctx)))
  let result_exponent_magnitude = match
    gda_coeff_to_bounded_int(result_exponent_magnitude, exponent_limit) {
    Some(value) => value
    None => abort("decimal_power_exact_ten_result exceeded context bounds")
  }
  let result_exponent = if result_exponent_negative {
    -result_exponent_magnitude
  } else {
    result_exponent_magnitude
  }
  let result = if result_exponent >= 0 {
    if result_exponent + 1 <= precision {
      finite_with_exponent_repr(
        negative,
        gda_coeff_power10_repr(result_exponent),
        0,
        precision,
      )
    } else {
      finite_with_exponent_repr(
        negative,
        gda_coeff_power10_repr(precision - 1),
        result_exponent - precision + 1,
        precision,
      )
    }
  } else {
    finite_with_exponent_repr(
      negative,
      gda_coeff_from_int(1),
      result_exponent,
      precision,
    )
  }
  let flags = if result_exponent >= 0 && result_exponent + 1 > precision {
    { ..DecimalFlags::new(), rounded: true }
  } else if result_exponent < ctx.e_min {
    { ..DecimalFlags::new(), subnormal: true }
  } else {
    DecimalFlags::new()
  }
  Some((result, flags))
}

///|
fn decimal_power_positive_integer_restricted(rhs : Decimal) -> Bool {
  match decimal_exact_integer_coeff(rhs) {
    Some((negative, magnitude)) =>
      !negative && gda_coeff_to_bounded_int(magnitude, 999_999_999) is None
    None => false
  }
}
