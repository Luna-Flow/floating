///|
// The plain cases of `add_ctx`, `sub_ctx`, `mul_ctx` and `div_ctx`: finite
// nonzero operands, a context with a precision, and a result that is neither
// subnormal, nor beyond the range, nor folded down by the clamp. They compute
// the result straight from the coefficients and return `None` for everything
// else, which takes the general route unchanged; that route stays the
// definition of the behavior (the differential tests keep the general route
// as the reference).
//
// The exponent of the result. IEEE 754-2019 5.2: if the result is inexact the
// cohort member of least possible exponent is used (`p` digits); if it is
// exact the member with the preferred exponent, or the nearest one when the
// cohort has none. 5.4.1 gives the preferred exponent: `min(Q(x), Q(y))` for
// addition and subtraction, `Q(x) + Q(y)` for multiplication and
// `Q(x) - Q(y)` for division. An exact sum or product of at most `p` digits
// therefore keeps the exponent `min(Q(x), Q(y))`, resp. `Q(x) + Q(y)`; one of
// more digits (which cannot have the preferred exponent in `p` digits) has
// `p` digits and the exponent of the discarded digits, as an inexact one has.
// A quotient with an exact result is left to the general route, which applies
// the preferred exponent `Q(x) - Q(y)` to it.
//
// For such an operation the general route rounds the exact result once to the
// precision (a trimmed run of zero digits and a rounded remainder give the same
// value and exponent), raises `inexact` when a nonzero digit was discarded and
// divides by ten exactly when the rounding carried into a digit beyond the
// precision. It raises no other flag: the result is not tiny (its adjusted
// exponent before rounding is at least `e_min`) and cannot overflow (it is
// below `e_max`, so a carry stays within it).

///|
/// The flag set of an inexact plain result, built once. Invariant: like the
/// empty set (`decimal_flags_none_value`) it is never written; every update of
/// a flag set is a copy.
let decimal_flags_inexact_value : DecimalFlags = {
  inexact: true,
  underflow: false,
  overflow: false,
  division_by_zero: false,
  invalid_operation: false,
  not_computed: false,
}

///|
/// The result of a plain operation: the value rounded to `precision` digits.
/// `None` when the clamp of the context would fold the exponent down.
fn decimal_plain_finish(
  negative : Bool,
  magnitude : DecCoeff,
  exponent : Int32,
  inexact : Bool,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let precision = ctx.precision
  let mut magnitude = magnitude
  let mut exponent = exponent
  if magnitude.digits10() > precision {
    // the rounding carried into 10^precision
    exponent += 1
    magnitude = match exact_divide_by_power_of_ten_repr(magnitude, 1) {
      Some(value) => value
      None => abort("decimal_plain_finish expected an exact divide by 10")
    }
  }
  if ctx.clamp && exponent > etop(ctx, precision) {
    return None
  }
  let value = finite_with_exponent_repr(
    negative, magnitude, exponent, precision,
  )
  Some(
    (
      value,
      if inexact {
        decimal_flags_inexact_value
      } else {
        decimal_flags_none_value
      },
    ),
  )
}

///|
fn decimal_plain_adjusted_in_range(
  adjusted : Int64,
  ctx : DecimalContext,
) -> Bool {
  adjusted >= ctx.e_min.to_int64() && adjusted < ctx.e_max.to_int64()
}

///|
/// Whether `numerator / divisor` has a finite decimal expansion, for a divisor
/// of one limb: with `divisor = 2^a 5^b u` and `u` prime to 10 it does iff `u`
/// divides `numerator` (the argument of `has_finite_decimal_expansion_repr`).
/// No allocation: `u` is found by dividing out 2 and 5 in a word, and the
/// remainder by `u` is read limb by limb.
fn decimal_word_divisor_terminates(
  numerator : DecCoeff,
  divisor : Int32,
) -> Bool {
  let mut part = divisor
  while part % 2 == 0 {
    part = part / 2
  }
  while part % 5 == 0 {
    part = part / 5
  }
  part == 1 || dec_coeff_mod_unit(numerator, part) == 0
}

///|
/// `lhs + rhs`, or `lhs - rhs` when `subtract_rhs`, in the plain case: the
/// smaller adjusted exponent is not below the rounding position of the larger
/// (no operand is absorbed) and the sum is nonzero.
fn decimal_add_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
  subtract_rhs : Bool,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision >= 1 &&
    lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite else {
    return None
  }
  let lhs_coefficient = lhs.coefficient
  let rhs_coefficient = rhs.coefficient
  guard !lhs_coefficient.is_zero() && !rhs_coefficient.is_zero() else {
    return None
  }
  let precision = ctx.precision
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
    ctx.decimal_rounding.kernel(),
  )
  if magnitude.is_zero() {
    return None
  }
  let exact_adjusted = target.to_int64() + exact_digits.to_int64() - 1L
  guard decimal_plain_adjusted_in_range(exact_adjusted, ctx) else {
    return None
  }
  decimal_plain_finish(negative, magnitude, target + discard, inexact, ctx)
}

///|
fn decimal_mul_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision >= 1 &&
    lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    !lhs.coefficient.is_zero() &&
    !rhs.coefficient.is_zero() else {
    return None
  }
  let exponent64 = lhs.exponent10.to_int64() + rhs.exponent10.to_int64()
  guard exponent64 >= -2147483648L && exponent64 <= 2147483647L else {
    return None
  }
  let precision = ctx.precision
  let exact = dec_coeff_multiply_repr(lhs.coefficient, rhs.coefficient)
  let digits = exact.digits10()
  let adjusted = exponent64 + digits.to_int64() - 1L
  guard decimal_plain_adjusted_in_range(adjusted, ctx) else { return None }
  let negative = lhs.negative != rhs.negative
  if digits <= precision {
    return decimal_plain_finish(
      negative,
      exact,
      exponent64.to_int(),
      false,
      ctx,
    )
  }
  let discard = digits - precision
  let inexact = dec_coeff_discards_nonzero(exact, discard)
  let magnitude = dec_coeff_round_pow10_coeff(
    exact,
    discard,
    negative,
    ctx.decimal_rounding.kernel(),
  )
  decimal_plain_finish(
    negative,
    magnitude,
    (exponent64 + discard.to_int64()).to_int(),
    inexact,
    ctx,
  )
}

///|
/// The quotient is formed to at least `p + 2` digits by one division of
/// `a * 10^k`, `k = max(0, p + 2 + digits(b) - digits(a))`, rounded with
/// `ZeroFiveUp` (a nonzero remainder leaves the last digit off 0 and 5, so the
/// final rounding sees the right side of every midpoint), and rounded once to
/// `p` digits. A quotient with a finite decimal expansion returns `None`: its
/// exponent and flags follow the ideal-exponent rules of the general route.
fn decimal_div_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision >= 1 &&
    lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    !lhs.coefficient.is_zero() &&
    !rhs.coefficient.is_zero() else {
    return None
  }
  let difference = lhs.exponent10.to_int64() - rhs.exponent10.to_int64()
  guard difference > -1000000000L && difference < 1000000000L else {
    return None
  }
  // A quotient with a finite expansion goes to the general route, and the
  // scaled division below would be wasted on it. The cheap classes are decided
  // first: equal coefficients, and a divisor of one limb (at most 9 digits),
  // where the test is a division by a word at most and, for a divisor
  // 2^a 5^b, none at all. For a longer divisor the remainder of the scaled
  // division decides the same, and a test of its own would cost about as much
  // as that division.
  if dec_coeff_compare_repr(lhs.coefficient, rhs.coefficient) == 0 {
    return None
  }
  if rhs.coefficient is Small(divisor) &&
    divisor < 1_000_000_000UL &&
    decimal_word_divisor_terminates(lhs.coefficient, divisor.to_int()) {
    return None
  }
  let precision = ctx.precision
  let lhs_digits = lhs.coefficient.digits10()
  let rhs_digits = rhs.coefficient.digits10()
  let extra = Int32::max(0, precision + 2 + rhs_digits - lhs_digits)
  let negative = lhs.negative != rhs.negative
  // zero stands for a quotient with a finite decimal expansion
  let quotient = dec_coeff_div_scaled_inexact(
    lhs.coefficient,
    extra,
    rhs.coefficient,
  )
  if quotient.is_zero() {
    return None
  }
  let digits = quotient.digits10()
  guard digits > precision else { return None }
  let exponent64 = difference - extra.to_int64()
  let adjusted = exponent64 + digits.to_int64() - 1L
  guard decimal_plain_adjusted_in_range(adjusted, ctx) else { return None }
  let discard = digits - precision
  let magnitude = dec_coeff_round_pow10_coeff(
    quotient,
    discard,
    negative,
    ctx.decimal_rounding.kernel(),
  )
  decimal_plain_finish(
    negative,
    magnitude,
    (exponent64 + discard.to_int64()).to_int(),
    true,
    ctx,
  )
}
