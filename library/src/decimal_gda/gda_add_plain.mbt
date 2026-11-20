///|
// The plain case of `add` and `subtract`, without the allocations of the
// general route (`add_ctx`, `add_finite_values_ctx`, `normalize_decimal_parts_ctx_repr`,
// `complete_decimal_gda`).
//
// It covers an extended context without clamping and two finite nonzero
// operands whose smaller adjusted exponent is not below the rounding position
// of the larger (so no operand is absorbed), whose nonzero exact sum has an
// adjusted exponent in `[e_min, e_max - 1]` (so the result can neither
// overflow, nor be subnormal, nor change exponent for the exponent range).
// Everything else returns `None` and takes the general route, which stays the
// definition of the behavior: for these operands that route forms the exact
// aligned sum (`decimal_exact_aligned_sum_result`), rounds it once to the
// precision (a trimmed run of zero digits and a rounded remainder give the
// same value, exponent and `rounded` and `inexact` flags), and divides by ten
// exactly when the rounding carried into a digit beyond the precision.

///|
let gda_flags_rounded_only : GdaFlags = {
  conversion_syntax: false,
  division_by_zero: false,
  division_impossible: false,
  division_undefined: false,
  invalid_context: false,
  invalid_operation: false,
  overflow: false,
  underflow: false,
  subnormal: false,
  inexact: false,
  rounded: true,
  clamped: false,
  lost_digits: false,
}

///|
let gda_flags_rounded_inexact : GdaFlags = {
  conversion_syntax: false,
  division_by_zero: false,
  division_impossible: false,
  division_undefined: false,
  invalid_context: false,
  invalid_operation: false,
  overflow: false,
  underflow: false,
  subnormal: false,
  inexact: true,
  rounded: true,
  clamped: false,
  lost_digits: false,
}

///|
fn gda_add_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
  subtract_rhs : Bool,
) -> GdaOutcome[Decimal]? {
  guard ctx.extended_ &&
    ctx.precision_ >= 1 &&
    !ctx.clamp_ &&
    lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite else {
    return None
  }
  let lhs_coefficient = lhs.coefficient
  let rhs_coefficient = rhs.coefficient
  guard !lhs_coefficient.is_zero() && !rhs_coefficient.is_zero() else {
    return None
  }
  let precision = ctx.precision_
  let lhs_digits = lhs_coefficient.digits10()
  let rhs_digits = rhs_coefficient.digits10()
  let lhs_adjusted = lhs.exponent10.to_int64() + lhs_digits.to_int64() - 1L
  let rhs_adjusted = rhs.exponent10.to_int64() + rhs_digits.to_int64() - 1L
  let high_adjusted = if lhs_adjusted >= rhs_adjusted {
    lhs_adjusted
  } else {
    rhs_adjusted
  }
  let low_adjusted = if lhs_adjusted >= rhs_adjusted {
    rhs_adjusted
  } else {
    lhs_adjusted
  }
  guard low_adjusted >= high_adjusted - precision.to_int64() + 1L else {
    return None
  }
  guard !exact_aligned_gap_too_large(lhs, rhs) else { return None }
  let rhs_negative = rhs.negative != subtract_rhs
  // the operand with the smaller exponent is `low`
  let lhs_is_low = lhs.exponent10 <= rhs.exponent10
  let low_coefficient = if lhs_is_low {
    lhs_coefficient
  } else {
    rhs_coefficient
  }
  let high_coefficient = if lhs_is_low {
    rhs_coefficient
  } else {
    lhs_coefficient
  }
  let low_negative = if lhs_is_low { lhs.negative } else { rhs_negative }
  let high_negative = if lhs_is_low { rhs_negative } else { lhs.negative }
  let target = if lhs_is_low { lhs.exponent10 } else { rhs.exponent10 }
  let padding = if lhs_is_low {
    rhs.exponent10 - lhs.exponent10
  } else {
    lhs.exponent10 - rhs.exponent10
  }
  let low_units = match low_coefficient {
    DecCoeff::Small(_) => dec_coeff_copy_limbs(low_coefficient)
    DecCoeff::Limbs(units, _) => units
  }
  let high_units = match high_coefficient {
    DecCoeff::Small(_) => dec_coeff_copy_limbs(high_coefficient)
    DecCoeff::Limbs(units, _) => units
  }
  let low_unit_len = dec_coeff_unit_len(low_coefficient)
  let high_unit_len = dec_coeff_unit_len(high_coefficient)
  // decAddOp: whole-unit shift and a power-of-ten multiplier of the addend
  let bshift = (padding + dec_coeff_dpun) / dec_coeff_dpun - 1
  let mult = decimal_small_pow10(padding - bshift * dec_coeff_dpun)
  let acc = Array::make(
    Int32::max(low_unit_len, high_unit_len + bshift) + 2,
    0U,
  )
  let same_sign = low_negative == high_negative
  let signed_len = dec_coeff_unit_add_sub(
    low_units,
    low_unit_len,
    high_units,
    high_unit_len,
    bshift,
    acc,
    if same_sign {
      mult
    } else {
      -mult
    },
  )
  let negative = if same_sign {
    low_negative
  } else if signed_len < 0 {
    high_negative
  } else {
    low_negative
  }
  let sum_len = if signed_len < 0 { -signed_len } else { signed_len }
  let exact_digits = dec_coeff_accumulator_digits(acc, sum_len)
  let discard = if exact_digits > precision {
    exact_digits - precision
  } else {
    0
  }
  // read before the rounding overwrites the array
  let inexact = discard > 0 &&
    dec_coeff_accumulator_discards_nonzero(acc, discard)
  let magnitude = dec_coeff_round_accumulator(
    acc,
    sum_len,
    discard,
    negative,
    ctx.decimal_.decimal_rounding.kernel(),
  )
  if magnitude.is_zero() {
    return None
  }
  let exact_adjusted = target.to_int64() + exact_digits.to_int64() - 1L
  guard exact_adjusted >= ctx.e_min_.to_int64() &&
    exact_adjusted < ctx.e_max_.to_int64() else {
    return None
  }
  let mut exponent = target + discard
  let mut magnitude = magnitude
  if magnitude.digits10() > precision {
    // the rounding carried into 10^precision
    exponent += 1
    magnitude = match exact_divide_by_power_of_ten_repr(magnitude, 1) {
      Some(value) => value
      None => abort("gda_add_plain expected an exact divide by 10")
    }
  }
  let value = finite_with_exponent_repr(
    negative, magnitude, exponent, precision,
  )
  if discard == 0 {
    return Some(Completed(value, ctx, GdaFlags::new()))
  }
  Some(
    complete_gda_raised(
      value,
      ctx,
      if inexact {
        gda_flags_rounded_inexact
      } else {
        gda_flags_rounded_only
      },
    ),
  )
}
