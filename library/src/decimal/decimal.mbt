///|
// Shared internal decimal helpers.

fn max_precision(a : Decimal, b : Decimal) -> Int32 {
  Int32::max(a.precision_, b.precision_)
}

///|
fn coeff_from_bigint(magnitude : BigInt) -> DecCoeff {
  dec_coeff_from_bigint_repr(abs_bigint(magnitude))
}

///|
fn coeff_bigint(coeff : DecCoeff) -> BigInt {
  dec_coeff_to_bigint_repr(coeff)
}

///|
fn coeff_digits(coeff : DecCoeff) -> Int32 {
  coeff.digits10()
}

///|
fn finite_precision_for_coeff(coeff : DecCoeff, ctx : DecimalContext) -> Int32 {
  if ctx.precision == 0 {
    Int32::max(1, coeff_digits(coeff))
  } else {
    Int32::max(1, ctx.precision)
  }
}

///|
fn coeff_trailing_decimal_zeros(coeff : DecCoeff) -> Int32 {
  let (_, _, dropped) = trim_trailing_decimal_zeros_repr(coeff, 0)
  dropped
}

///|
/// The precision label of a value names a format a context could have (S5): a
/// precision outside `1..=decimal_precision_max` aborts, naming the function.
fn decimal_check_precision(name : String, precision : Int32) -> Int32 {
  if precision < 1 || precision > decimal_precision_max {
    abort(
      "Decimal::\{name}: precision \{precision} must be within 1..=\{decimal_precision_max}",
    )
  }
  precision
}

///|
/// The payload of a NaN is the trailing significand field of the format
/// (IEEE 754-2019 3.5.2, 6.2.3): a non-negative integer of at most
/// `precision - 1` digits (S6). It is checked where a NaN is made; it is
/// truncated only by a conversion to a narrower format.
fn decimal_check_payload(
  name : String,
  payload : BigInt,
  precision : Int32,
) -> Unit {
  let coefficient = coeff_from_bigint(payload)
  if payload < bigint_zero() ||
    (!coefficient.is_zero() && coeff_digits(coefficient) > precision - 1) {
    abort(
      "Decimal::\{name}: payload must be a non-negative integer of at most precision - 1 digits",
    )
  }
}

///|
fn make_special(
  class : FpClass,
  negative : Bool,
  payload : BigInt,
  precision : Int32,
  signaling_nan : Bool,
) -> Decimal {
  make_special_repr(
    class,
    negative,
    coeff_from_bigint(payload),
    precision,
    signaling_nan,
  )
}

///|
fn make_special_repr(
  class : FpClass,
  negative : Bool,
  payload : DecCoeff,
  precision : Int32,
  signaling_nan : Bool,
) -> Decimal {
  {
    class,
    negative,
    coefficient: payload,
    exponent10: 0,
    precision_: precision,
    signaling_nan,
  }
}

///|
fn exact_finite_sqrt(value : Decimal, precision : Int32) -> Decimal? {
  guard value.class == FpClass::Finite else { return None }
  if value.coefficient.is_zero() {
    let preferred_exponent = value.exponent10 >> 1
    return Some(
      finite_with_exponent_repr(
        value.negative,
        dec_coeff_zero(),
        preferred_exponent,
        precision,
      ),
    )
  }
  guard !value.negative else { return None }
  let (normalized_coeff0, normalized_exp) = remove_factor10_repr(
    value.coefficient,
    value.exponent10,
  )
  let (radicand, exponent10) = if (normalized_exp & 1) == 0 {
    (normalized_coeff0, normalized_exp)
  } else {
    (dec_coeff_multiply_by_unit_repr(normalized_coeff0, 10), normalized_exp - 1)
  }
  // The floor root and its remainder radicand - root^2 come from one Newton
  // iteration: the radicand is a square exactly when the remainder is zero, so
  // the root is not squared again.
  let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(radicand)
  if remainder.is_zero() {
    let exact = finite_with_exponent_repr(
      false,
      root,
      exponent10 / 2,
      precision,
    )
    let preferred_exponent = value.exponent10 >> 1
    let extra_zeros = exact.exponent10 - preferred_exponent
    let available_zeros = Int32::max(
      0,
      precision - exact.coefficient.digits10(),
    )
    let zeros_to_add = Int32::min(extra_zeros, available_zeros)
    if zeros_to_add > 0 {
      Some(
        finite_with_exponent_repr(
          false,
          dec_coeff_shift_power10_repr(exact.coefficient, zeros_to_add),
          exact.exponent10 - zeros_to_add,
          precision,
        ),
      )
    } else {
      Some(exact)
    }
  } else {
    None
  }
}

///|
fn exact_result_rounding_flags(
  value : Decimal,
  preferred_exponent : Int32,
  ctx : DecimalContext,
) -> (Bool, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    return (false, DecimalFlags::new())
  }
  guard ctx.precision > 0 && !value.coefficient.is_zero() else {
    return (false, DecimalFlags::new())
  }
  let shift = Int32::max(0, value.exponent10 - preferred_exponent)
  let effective_digits = value.coefficient.digits10() + shift
  let extra_digits = effective_digits - ctx.precision
  guard extra_digits > 0 else { return (false, DecimalFlags::new()) }
  let trailing_zeros = coeff_trailing_decimal_zeros(value.coefficient)
  let effective_trailing_zeros = trailing_zeros + shift
  (
    true,
    { ..DecimalFlags::new(), inexact: effective_trailing_zeros < extra_digits, },
  )
}

///|
/// Whether an exact result lies below the normal range, so that its single
/// rounding is to Etiny. A result whose exponent is below Etiny but whose
/// coefficient is longer than `precision` can still be normal; it must be
/// rounded once to `precision` digits, not to Etiny (which would leave more
/// than `precision` digits or round it twice).
fn exact_result_is_subnormal(
  value : Decimal,
  precision : Int32,
  ctx : DecimalContext,
) -> Bool {
  ctx.precision > 0 &&
  !value.coefficient.is_zero() &&
  value.exponent10 + Int32::max(0, value.coefficient.digits10() - precision) <
  etiny(ctx)
}

///|
fn exact_decimal_reciprocal(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let (without_twos, twos) = dec_coeff_count_factor_unit_repr(
    value.coefficient,
    2,
  )
  let (without_fives, fives) = dec_coeff_count_factor_unit_repr(without_twos, 5)
  guard dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 else {
    return None
  }
  let scale = Int32::max(twos, fives)
  let magnitude = dec_coeff_multiply_repr(
    dec_coeff_pow_unit_repr(2, scale - twos),
    dec_coeff_pow_unit_repr(5, scale - fives),
  )
  Some(
    normalize_decimal_parts_ctx_repr(
      value.negative,
      magnitude,
      -scale - value.exponent10,
      ctx,
    ),
  )
}

///|
fn exact_decimal_division_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  // The gcd route below returns `None` exactly when the quotient has no finite
  // decimal expansion; decide that first, without the gcd (the kernel function
  // states and proves the criterion).
  guard has_finite_decimal_expansion_repr(
    dividend.coefficient,
    divisor.coefficient,
  ) else {
    return None
  }
  let gcd = dec_coeff_gcd_repr(dividend.coefficient, divisor.coefficient)
  let (reduced_denominator, denominator_remainder) = dec_coeff_div_rem_repr(
    divisor.coefficient,
    gcd,
  )
  guard denominator_remainder.is_zero() else {
    abort(
      "exact_decimal_division_result expected an exact denominator gcd division",
    )
  }
  let (without_twos, twos) = dec_coeff_count_factor_unit_repr(
    reduced_denominator, 2,
  )
  let (without_fives, fives) = dec_coeff_count_factor_unit_repr(without_twos, 5)
  guard dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 else {
    return None
  }
  let (reduced_numerator, numerator_remainder) = dec_coeff_div_rem_repr(
    dividend.coefficient,
    gcd,
  )
  guard numerator_remainder.is_zero() else {
    abort(
      "exact_decimal_division_result expected an exact numerator gcd division",
    )
  }
  let scale = Int32::max(twos, fives)
  let magnitude = dec_coeff_multiply_repr(
    reduced_numerator,
    dec_coeff_pow_unit_repr(2, scale - twos),
  )
  let magnitude = dec_coeff_multiply_repr(
    magnitude,
    dec_coeff_pow_unit_repr(5, scale - fives),
  )
  Some(
    normalize_decimal_parts_ctx_repr(
      dividend.negative != divisor.negative,
      magnitude,
      dividend.exponent10 - divisor.exponent10 - scale,
      ctx,
    ),
  )
}

///|
fn decimal_division_adjusted_coefficient(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Int32 {
  let exponent = numerator.digits10() - denominator.digits10()
  let comparison = if exponent >= 0 {
    dec_coeff_compare_scaled_repr(numerator, denominator, exponent)
  } else {
    -dec_coeff_compare_scaled_repr(denominator, numerator, -exponent)
  }
  if comparison >= 0 {
    exponent
  } else {
    exponent - 1
  }
}

///|
fn bounded_inexact_decimal_division_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 else { return None }
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  let adjusted_coefficient = decimal_division_adjusted_coefficient(
    dividend.coefficient,
    divisor.coefficient,
  )
  let adjusted = dividend.exponent10 - divisor.exponent10 + adjusted_coefficient
  // Keep the existing path for subnormal results: it carries enough extra
  // quotient digits for the configured before/after tininess policy.
  guard adjusted >= ctx.e_min else { return None }
  let precision = finite_precision_for(bigint_one(), ctx)
  let scale = precision - 1 - adjusted_coefficient
  let (numerator, denominator, result_exponent) = if scale >= 0 {
    (
      dec_coeff_shift_power10_repr(dividend.coefficient, scale),
      divisor.coefficient,
      dividend.exponent10 - divisor.exponent10 - scale,
    )
  } else {
    (
      dividend.coefficient,
      dec_coeff_shift_power10_repr(divisor.coefficient, -scale),
      dividend.exponent10 - divisor.exponent10 - scale,
    )
  }
  let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, denominator)
  let quotient = if should_increment_decimal_repr(
      quotient,
      remainder,
      denominator,
      dividend.negative != divisor.negative,
      ctx.decimal_rounding,
    ) {
    dec_coeff_magnitude_add_unit(quotient, 1)
  } else {
    quotient
  }
  let (value, normalize_flags) = normalize_decimal_parts_ctx_repr(
    dividend.negative != divisor.negative,
    quotient,
    result_exponent,
    ctx,
  )
  let value = expand_inexact_division_cohort(value, ctx, pad_precision=true)
  let flags = with_underflow_for_inexact_subnormal(
    value,
    { ..normalize_flags, inexact: true, },
    ctx,
  )
  Some((value, flags))
}

///|
fn exact_division_by_power_of_ten_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  let power = match decimal_power_of_ten_exponent(divisor) {
    Some(value) => value
    None => return None
  }
  let precision = finite_precision_for(bigint_one(), ctx)
  let negative = dividend.negative != divisor.negative
  let lower_adjusted = adjusted_exponent64(dividend) -
    adjusted_exponent64(divisor)
  if lower_adjusted > ctx.e_max.to_int64() {
    return Some(decimal_overflow_result(negative, ctx))
  }
  let preferred_exponent = dividend.exponent10 - divisor.exponent10
  let exact_unrounded = normalize_decimal_parts_gda_repr(
    negative,
    dividend.coefficient,
    dividend.exponent10 - power,
    dividend.coefficient.digits10(),
    ctx.decimal_rounding,
  )
  let (exact_discards, exact_rounding) = exact_result_rounding_flags(
    exact_unrounded, preferred_exponent, ctx,
  )
  let rounded_value = normalize_decimal_parts_gda_repr(
    negative,
    dividend.coefficient,
    dividend.exponent10 - power,
    precision,
    ctx.decimal_rounding,
  )
  if exact_discards {
    let prefinal = if exact_result_is_subnormal(exact_unrounded, precision, ctx) {
      exact_unrounded
    } else if !exact_rounding.inexact {
      expand_rounded_exact_cohort_toward_preferred_exponent(
        rounded_value, preferred_exponent, ctx,
      )
    } else {
      expand_inexact_division_cohort(rounded_value, ctx, pad_precision=true)
    }
    let (value, flags) = finalize_finite_ctx(prefinal, exact_rounding, ctx)
    Some((value, with_underflow_for_inexact_subnormal(value, flags, ctx)))
  } else {
    let exact_value = expand_exact_cohort_toward_preferred_exponent(
      rounded_value, preferred_exponent, ctx,
    )
    Some(finalize_finite_ctx(exact_value, DecimalFlags::new(), ctx))
  }
}

///|
fn has_finite_decimal_unit_magnitude(value : Decimal) -> Bool {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return false
  }
  let (reduced, _, dropped) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    0,
  )
  dec_coeff_compare_repr(reduced, dec_coeff_from_int(1)) == 0 &&
  value.exponent10 + dropped == 0
}

///|
fn is_finite_decimal_one(value : Decimal) -> Bool {
  !value.negative && has_finite_decimal_unit_magnitude(value)
}

///|
fn is_finite_decimal_negative_one(value : Decimal) -> Bool {
  value.negative && has_finite_decimal_unit_magnitude(value)
}

///|
fn decimal_exact_aligned_sum_result(
  lhs : Decimal,
  rhs : Decimal,
  target : Int32,
) -> (Bool, DecCoeff) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_exact_aligned_sum_result expects finite operands")
  }
  ignore(target)
  let (low, high) = if lhs.exponent10 <= rhs.exponent10 {
    (lhs, rhs)
  } else {
    (rhs, lhs)
  }
  let low_units = dec_coeff_copy_limbs(low.coefficient)
  let low_unit_len = dec_coeff_unit_len(low.coefficient)

  let high_units = dec_coeff_copy_limbs(high.coefficient)
  let high_unit_len = dec_coeff_unit_len(high.coefficient)
  let padding = high.exponent10 - low.exponent10
  // GDA decAddOp splits decimal padding into a whole-unit shift and a
  // power-of-ten multiplier, then calls decUnitAddSub directly
  // (libdecnumber/decNumber.c lines 3978-4018 and 4055-4059).
  let bshift = (padding + dec_coeff_dpun) / dec_coeff_dpun - 1
  let mult = decimal_small_pow10(padding - bshift * dec_coeff_dpun)

  let acc : Array[UInt32] = []
  let mut pad = 0
  while pad < Int32::max(low_unit_len, high_unit_len + bshift) + 2 {
    acc.push(0U)
    pad += 1
  }

  let len = if low.negative == high.negative {
    dec_coeff_unit_add_sub(
      low_units, low_unit_len, high_units, high_unit_len, bshift, acc, mult,
    )
  } else {
    let calc = dec_coeff_unit_add_sub(
      low_units,
      low_unit_len,
      high_units,
      high_unit_len,
      bshift,
      acc,
      -mult,
    )
    if calc < 0 {
      -calc
    } else {
      calc
    }
  }

  let compact : Array[UInt32] = []
  let mut index = 0
  while index < len {
    compact.push(acc[index])
    index += 1
  }
  let magnitude = dec_coeff_from_unit_accumulator(compact, len)
  let negative = if magnitude.is_zero() {
    false
  } else if low.negative == high.negative {
    low.negative
  } else {
    (
      compare_finite_magnitude_repr(
        low.coefficient,
        low.exponent10,
        high.coefficient,
        high.exponent10,
      ) >
      0 &&
      low.negative
    ) ||
    (
      compare_finite_magnitude_repr(
        high.coefficient,
        high.exponent10,
        low.coefficient,
        low.exponent10,
      ) >
      0 &&
      high.negative
    )
  }
  (negative, magnitude)
}

///|
/// Whether the exact aligned sum of two finite operands would need more than
/// 2,000,000,000 padding digits: the exponent gap is taken in `Int64`, and the
/// callers return a NaN instead of letting the `Int32` padding overflow (#446).
fn exact_aligned_gap_too_large(lhs : Decimal, rhs : Decimal) -> Bool {
  let gap = lhs.exponent10.to_int64() - rhs.exponent10.to_int64()
  gap > 2000000000L || gap < -2000000000L
}

///|
// Rounds the exact context-free result (-1)^negative * magnitude * 10^exponent10
// once, with `mode` (half-even by default), to `precision` digits when `round_to_precision` is set and
// to the exponent range of a context-free value: the stored exponent must not
// be below the minimum of `Int` and the adjusted exponent must not exceed its
// maximum. This is IEEE 754-2019 §7.4 and §7.5 for that exponent range: a
// result too large is a signed infinity, and a result too small is rounded to
// the smallest exponent, possibly to a signed zero (gradual underflow), rather
// than being replaced by zero or wrapping around. With `reduce` the result is
// the reduced member of its cohort (a zero then has exponent 0).
fn context_free_round_wide(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int64,
  precision : Int32,
  round_to_precision~ : Bool,
  reduce~ : Bool,
  mode~ : DecimalRound = DecimalRound::HalfEven,
) -> Decimal {
  let precision = Int32::max(1, precision)
  let min_exponent = decimal_value_e_tiny.to_int64()
  let max_exponent = decimal_value_e_max.to_int64()
  if magnitude.is_zero() {
    // A zero keeps its value when its exponent is clamped to the stored range.
    return finite_with_exponent_repr(
      negative,
      magnitude,
      if reduce {
        0
      } else {
        scaleb_int64_to_int(exponent10)
      },
      precision,
    )
  }
  let digits = magnitude.digits10()
  let mut target = exponent10
  if round_to_precision && digits > precision {
    target = exponent10 + (digits - precision).to_int64()
  }
  if target < min_exponent {
    target = min_exponent
  }
  let shift = target - exponent10
  let mut rounded = if shift == 0L {
    magnitude
  } else if shift > digits.to_int64() {
    // Below a tenth of a unit of the target exponent: only the directed
    // modes away from zero can give a unit.
    huge_shift_rounded_unit_repr(magnitude, negative, mode)
  } else {
    round_positive_decimal_div_pow10_repr(
      magnitude,
      shift.to_int(),
      negative,
      mode,
    ).0
  }
  if round_to_precision && rounded.digits10() > precision {
    // The rounding carried into 10^precision: drop only the carry digit, so
    // the result keeps `precision` digits (10^(precision-1) at the next
    // exponent) and stays in the cohort the rounding selected.
    rounded = dec_coeff_power10_repr(precision - 1)
    target = target + 1L
  }
  if rounded.is_zero() {
    return finite_with_exponent_repr(
      negative,
      rounded,
      if reduce {
        0
      } else {
        target.to_int()
      },
      precision,
    )
  }
  if target + (rounded.digits10() - 1).to_int64() > max_exponent {
    return if overflow_to_infinity(negative, mode) {
      Decimal::inf(negative~, precision~)
    } else {
      // The largest finite value with the result's number of digits.
      let digits = if round_to_precision { precision } else { digits }
      finite_with_exponent_repr(
        negative,
        dec_coeff_magnitude_sub_unit(dec_coeff_power10_repr(digits), 1),
        decimal_value_e_max - digits + 1,
        precision,
      )
    }
  }
  if reduce {
    let (reduced, reduced_exponent) = remove_factor10_repr(
      rounded,
      target.to_int(),
    )
    finite_with_exponent_repr(negative, reduced, reduced_exponent, precision)
  } else {
    finite_with_exponent_repr(negative, rounded, target.to_int(), precision)
  }
}

///|
/// The text of the refusal of a value outside the stored range: it names the
/// offending exponent and both limits.
fn decimal_value_range_message(
  exponent10 : Int64,
  adjusted : Int64,
  rounded : (Int64, Int64)?,
) -> String {
  let base = "the value with exponent \{exponent10} (adjusted exponent \{adjusted}) is outside the range of a Decimal (smallest exponent \{decimal_value_e_tiny}, largest adjusted exponent \{decimal_value_e_max})"
  match rounded {
    Some((rounded_exponent, rounded_adjusted)) =>
      base +
      "; after the rounding to the precision its exponent is \{rounded_exponent} (adjusted exponent \{rounded_adjusted})"
    None => base
  }
}

///|
/// The exact value `(-1)^negative * magnitude * 10^exponent10` as a stored
/// value, or the reason why it is none: rounded once to `precision` digits when
/// it is longer (a carry into `10^precision` leaves `10^(precision-1)` at the
/// next exponent) and then checked against the stored range, so the check
/// sees the exponent after the rounding. Nothing is replaced silently: a
/// value below `decimal_value_e_tiny` or above `decimal_value_e_max` is an
/// `Err`. A zero is treated like every finite value (its adjusted exponent is
/// its exponent) and keeps the exponent given.
fn decimal_round_checked(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int64,
  precision : Int32,
  mode : DecimalRound,
) -> Result[Decimal, String] {
  let min_exponent = decimal_value_e_tiny.to_int64()
  let max_exponent = decimal_value_e_max.to_int64()
  if magnitude.is_zero() {
    return if exponent10 < min_exponent || exponent10 > max_exponent {
      Err(decimal_value_range_message(exponent10, exponent10, None))
    } else {
      Ok(
        finite_with_exponent_repr(
          negative,
          magnitude,
          exponent10.to_int(),
          precision,
        ),
      )
    }
  }
  let digits = magnitude.digits10()
  let given_adjusted = exponent10 + (digits - 1).to_int64()
  let mut target = exponent10
  let mut rounded = magnitude
  if digits > precision {
    let shift = (digits - precision).to_int64()
    target = exponent10 + shift
    rounded = round_positive_decimal_div_pow10_repr(
        magnitude,
        shift.to_int(),
        negative,
        mode,
      ).0
    if rounded.digits10() > precision {
      rounded = dec_coeff_power10_repr(precision - 1)
      target = target + 1L
    }
  }
  if target < min_exponent ||
    target + (rounded.digits10() - 1).to_int64() > max_exponent {
    let rounded_adjusted = target + (rounded.digits10() - 1).to_int64()
    return Err(
      decimal_value_range_message(
        exponent10,
        given_adjusted,
        if target == exponent10 {
          None
        } else {
          Some((target, rounded_adjusted))
        },
      ),
    )
  }
  Ok(finite_with_exponent_repr(negative, rounded, target.to_int(), precision))
}

///|
fn compare_magnitude_to_half_ulp(
  value : Decimal,
  ulp_exponent : Int32,
) -> Int32 {
  let adjusted = adjusted_exponent(value)
  if adjusted < ulp_exponent - 1 {
    return -1
  }
  if adjusted > ulp_exponent - 1 {
    return 1
  }
  let digits = value.coefficient.digits10()
  dec_coeff_compare_repr(
    value.coefficient,
    dec_coeff_multiply_by_unit_repr(dec_coeff_power10_repr(digits - 1), 5),
  )
}

///|
fn exact_units_at_quantum_repr(value : Decimal, quantum : Int32) -> DecCoeff {
  let shift = value.exponent10 - quantum
  guard shift >= 0 else {
    abort("exact_units_at_quantum_repr requires an exact non-negative shift")
  }
  dec_coeff_shift_power10_repr(value.coefficient, shift)
}

///|
fn exact_base_small_addend_step(
  base_is_odd : Bool,
  base_ends_zero_or_five : Bool,
  base_negative : Bool,
  low_negative : Bool,
  cmp_half : Int32,
  mode : DecimalRound,
) -> Int32 {
  dec_coeff_addend_rounding_step(
    base_is_odd,
    base_ends_zero_or_five,
    base_negative,
    low_negative,
    cmp_half,
    mode.kernel(),
  )
}

///|
fn exact_base_small_addend_result(
  base : Decimal,
  ulp_exponent : Int32,
  low : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let cmp_half = compare_magnitude_to_half_ulp(low, ulp_exponent)
  let base_units_repr = exact_units_at_quantum_repr(base, ulp_exponent)
  // GDA decAddOp carries a residue into decFinish/decApplyRound; a nearest
  // result below half makes no coefficient step, while a half-even tie reads
  // the retained coefficient LSD. Both decisions are unit-native here.
  let step = exact_base_small_addend_step(
    dec_coeff_is_odd(base_units_repr),
    dec_coeff_limb_at(base_units_repr, 0).reinterpret_as_int() % 10 == 0 ||
    dec_coeff_limb_at(base_units_repr, 0).reinterpret_as_int() % 10 == 5,
    base.negative,
    low.negative,
    cmp_half,
    ctx.decimal_rounding,
  )
  let (negative, magnitude) = if step == 0 {
    (base.negative, base_units_repr)
  } else {
    dec_coeff_signed_step_unit_repr(base.negative, base_units_repr, step > 0)
  }
  let (value, adjust_flags) = normalize_decimal_parts_ctx_repr(
    negative, magnitude, ulp_exponent, ctx,
  )
  let mut flags = adjust_flags.combine({ ..DecimalFlags::new(), inexact: true, })
  if low.negative != base.negative &&
    adjusted_exponent(base) == ctx.e_min &&
    is_power_of_ten_coeff(base_units_repr) {
    flags = { ..flags, underflow: true, }
  }
  (value, flags)
}

///|
fn nan_operand_flags(a : Decimal, b : Decimal) -> DecimalFlags {
  if a.is_signaling_nan() || b.is_signaling_nan() {
    { ..DecimalFlags::new(), invalid_operation: true, }
  } else {
    DecimalFlags::new()
  }
}

///|
fn invalid_flags() -> DecimalFlags {
  { ..DecimalFlags::new(), invalid_operation: true, }
}

///|
/// The flags of a result the library could not compute (S4): a NaN with
/// `not_computed`, and not `invalid_operation`, which reports a case for which
/// IEEE 754-2019 defines an invalid result.
fn not_computed_flags() -> DecimalFlags {
  { ..DecimalFlags::new(), not_computed: true, }
}

///|
fn not_computed_result(ctx : DecimalContext) -> (Decimal, DecimalFlags) {
  (
    Decimal::nan(precision=finite_precision_for(bigint_zero(), ctx)),
    not_computed_flags(),
  )
}

///|
/// The error of a `try_` form for an operation the library cannot carry out
/// within a limit of the implementation (a context or an operand beyond what the
/// kernels support); the same `not_computed` condition as `not_computed_result`.
fn decimal_context_limit(
  operation : String,
  ctx : DecimalContext,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation,
      @def.CertificationStage::RangeReduction,
      @def.CertificationFailureReason::ResourceLimit,
      ctx.precision,
      0,
      0,
    ),
  )
}

///|
/// A certification failure of a function that another one delegates to, named
/// after the public operation the caller called (`powr` and `pown` run `pow`).
fn decimal_failure_of(
  operation : String,
  result : Result[(Decimal, DecimalFlags), @def.ArithmeticError],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match result {
    Err(error) =>
      match error.certification_failure_detail() {
        Some(detail) =>
          Err(
            @def.ArithmeticError::certification_failure(
              @def.CertificationFailureDetail::new(
                operation,
                detail.stage(),
                detail.reason(),
                detail.target_precision(),
                detail.work_precision(),
                detail.refinements(),
              ),
            ),
          )
        None => Err(error)
      }
    Ok(value) => Ok(value)
  }
}

///|
fn math_context_is_restricted(ctx : DecimalContext) -> Bool {
  ctx.precision > 999_999 || ctx.e_max > 999_999 || ctx.e_min < -999_999
}

///|
fn gda_context_is_restricted(ctx : DecimalContext) -> Bool {
  ctx.precision > decimal_precision_max ||
  ctx.e_max > decimal_implementation_e_max ||
  ctx.e_min < decimal_implementation_e_min
}

///|
fn div_zero_flags(division_undefined : Bool) -> DecimalFlags {
  if division_undefined {
    { ..DecimalFlags::new(), invalid_operation: true, }
  } else {
    { ..DecimalFlags::new(), division_by_zero: true, }
  }
}

///|
fn decimal_order_sign(x : Decimal) -> Int32 {
  if x.negative {
    -1
  } else {
    1
  }
}

///|
fn compare_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn abs_int(value : Int32) -> Int32 {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn divide_integer_zero_quotient_flags() -> DecimalFlags {
  DecimalFlags::new()
}

///|
fn decimal_nearest_remainder_parts(
  dividend : Decimal,
  divisor : Decimal,
) -> (Bool, DecCoeff, Int32) {
  // The exponent difference of operands near the `Int` limits exceeds `Int`:
  // form it in Int64 and reduce the power of ten modulo 2 * divisor in chunks.
  let scale64 = dividend.exponent10.to_int64() - divisor.exponent10.to_int64()
  let scale = if scale64 < 0L { scale64.to_int() } else { 0 }
  let (quotient_odd, remainder, denominator, target) = if scale64 >= 0L {
    let denominator = divisor.coefficient
    let doubled_denominator = dec_coeff_multiply_by_unit_repr(denominator, 2)
    let residue = dec_coeff_shift_power10_mod_wide_repr(
      dividend.coefficient,
      scale64,
      doubled_denominator,
    )
    if dec_coeff_compare_repr(residue, denominator) >= 0 {
      (
        true,
        dec_coeff_magnitude_sub_repr(residue, denominator),
        denominator,
        divisor.exponent10,
      )
    } else {
      (false, residue, denominator, divisor.exponent10)
    }
  } else {
    let denominator = dec_coeff_shift_power10_repr(divisor.coefficient, -scale)
    let (quotient, remainder) = dec_coeff_div_rem_repr(
      dividend.coefficient,
      denominator,
    )
    (dec_coeff_is_odd(quotient), remainder, denominator, dividend.exponent10)
  }
  let twice_remainder = dec_coeff_multiply_by_unit_repr(remainder, 2)
  let half_compare = dec_coeff_compare_repr(twice_remainder, denominator)
  let increment = half_compare > 0 || (half_compare == 0 && quotient_odd)
  let magnitude = if increment {
    dec_coeff_magnitude_sub_repr(denominator, remainder)
  } else {
    remainder
  }
  let negative = !magnitude.is_zero() && dividend.negative != increment
  (negative, magnitude, target)
}

///|
fn compare_twice_dividend_to_divisor(
  dividend : Decimal,
  divisor : Decimal,
) -> Int32 {
  guard dividend.class == FpClass::Finite && divisor.class == FpClass::Finite else {
    return 0
  }
  compare_finite_magnitude_repr(
    dec_coeff_multiply_by_unit_repr(dividend.coefficient, 2),
    dividend.exponent10,
    divisor.coefficient,
    divisor.exponent10,
  )
}

///|
fn finite_nearest_integer_quotient_is_zero(
  dividend : Decimal,
  divisor : Decimal,
) -> Bool {
  guard dividend.class == FpClass::Finite && divisor.class == FpClass::Finite else {
    return false
  }
  guard !dividend.coefficient.is_zero() && !divisor.coefficient.is_zero() else {
    return false
  }
  compare_twice_dividend_to_divisor(dividend, divisor) <= 0
}

///|
fn zero_quotient_remainder_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if dividend.coefficient.is_zero() {
    let target = Int32::min(dividend.exponent10, divisor.exponent10)
    let zero = finite_with_exponent(
      dividend.negative,
      bigint_zero(),
      target,
      finite_precision_for(bigint_zero(), ctx),
    )
    return finalize_finite_ctx(zero, DecimalFlags::new(), ctx)
  }
  if ctx.precision > 0 {
    // The remainder is the dividend itself, with the smaller exponent as its
    // ideal exponent. Moving it towards that exponent by at most p + 1 -
    // digits places and normalizing once rounds and clamps the delivered
    // result only, not the dividend at its own exponent.
    let preferred = Int32::min(dividend.exponent10, divisor.exponent10)
    let room = Int32::max(
      0,
      ctx.precision + 1 - dividend.coefficient.digits10(),
    )
    let shift = Int64::min(
      dividend.exponent10.to_int64() - preferred.to_int64(),
      room.to_int64(),
    ).to_int()
    return normalize_decimal_parts_ctx_repr(
      dividend.negative,
      dec_coeff_shift_power10_repr(dividend.coefficient, shift),
      dividend.exponent10 - shift,
      ctx,
    )
  }
  let (base, base_flags) = apply_finite_ctx(dividend, ctx)
  guard base_flags.has_error() == false &&
    base.class == FpClass::Finite &&
    !base.coefficient.is_zero() else {
    return (base, base_flags)
  }
  let preferred_exponent = Int32::min(dividend.exponent10, divisor.exponent10)
  if preferred_exponent < base.exponent10 {
    let digits = base.coefficient.digits10()
    let wanted_shift = base.exponent10 - preferred_exponent
    let actual_shift = if ctx.precision == 0 {
      wanted_shift
    } else {
      Int32::min(wanted_shift, Int32::max(0, ctx.precision - digits))
    }
    if actual_shift > 0 {
      let shifted = finite_with_exponent_repr(
        base.negative,
        dec_coeff_shift_power10_repr(base.coefficient, actual_shift),
        base.exponent10 - actual_shift,
        base.precision_,
      )
      return finalize_finite_ctx(shifted, base_flags, ctx)
    }
  }
  (base, base_flags)
}
