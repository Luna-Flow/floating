///|
// The plain cases of `multiply` and `divide`, in the style of `gda_add_plain`:
// an extended, non-clamping context, finite nonzero operands, and a result
// whose adjusted exponent lies in `[e_min, e_max - 1]` (so it can neither
// overflow, nor be subnormal, nor change exponent for the exponent range, even
// after a carry into a digit beyond the precision). Everything else returns
// `None` and takes the general route, which stays the definition of the
// behavior.
//
// multiply: the exact product rounded once to the precision at the exponent
// `e1 + e2` (plus the digits discarded); `rounded` when digits were discarded,
// `inexact` when a nonzero one was.
//
// divide: the quotient is formed to at least `p + 2` digits by one division of
// `a * 10^k`, `k = max(0, p + 2 + digits(b) - digits(a))`, rounded with
// `ZeroFiveUp` (a nonzero remainder leaves the last digit off 0 and 5, so the
// final rounding sees the right side of every midpoint, as in the general
// route), and rounded once to `p` digits. A quotient whose decimal expansion is
// finite (the remainder test of `dec_coeff_round_div_expansion`) returns `None`:
// its exponent and flags follow the ideal-exponent rules of the general route.
// For an inexact quotient the result has exactly `p` digits at the exponent
// `e1 - e2 - k` plus the digits discarded, `rounded` and `inexact` are raised.
// The general route divides by `10^(p + digits(b) + 2)` independent of
// `digits(a)`, which doubles the quotient; the value, the exponent and the
// flags do not depend on the number of guard digits beyond `p + 2`.

///|
fn gda_plain_context_ok(ctx : GdaContext) -> Bool {
  ctx.extended_ && ctx.precision_ >= 1 && !ctx.clamp_
}

///|
fn gda_plain_finish(
  negative : Bool,
  magnitude : DecCoeff,
  exponent : Int32,
  discarded : Bool,
  inexact : Bool,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let precision = ctx.precision_
  let mut magnitude = magnitude
  let mut exponent = exponent
  if magnitude.digits10() > precision {
    // the rounding carried into 10^precision
    exponent += 1
    magnitude = match exact_divide_by_power_of_ten_repr(magnitude, 1) {
      Some(value) => value
      None => abort("gda_plain_finish expected an exact divide by 10")
    }
  }
  let value = finite_with_exponent_repr(
    negative, magnitude, exponent, precision,
  )
  if !discarded {
    return Completed(value, ctx, GdaFlags::new())
  }
  complete_gda_raised(
    value,
    ctx,
    if inexact {
      gda_flags_rounded_inexact
    } else {
      gda_flags_rounded_only
    },
  )
}

///|
fn gda_mul_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  guard gda_plain_context_ok(ctx) &&
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
  let precision = ctx.precision_
  let exact = dec_coeff_multiply_repr(lhs.coefficient, rhs.coefficient)
  let digits = exact.digits10()
  let adjusted = exponent64 + digits.to_int64() - 1L
  guard adjusted >= ctx.e_min_.to_int64() && adjusted < ctx.e_max_.to_int64() else {
    return None
  }
  let negative = lhs.negative != rhs.negative
  if digits <= precision {
    return Some(
      gda_plain_finish(negative, exact, exponent64.to_int(), false, false, ctx),
    )
  }
  let discard = digits - precision
  let inexact = dec_coeff_discards_nonzero(exact, discard)
  let magnitude = dec_coeff_round_pow10_coeff(
    exact,
    discard,
    negative,
    ctx.decimal_.decimal_rounding.kernel(),
  )
  Some(
    gda_plain_finish(
      negative,
      magnitude,
      exponent64.to_int() + discard,
      true,
      inexact,
      ctx,
    ),
  )
}

///|
fn gda_div_plain(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  guard gda_plain_context_ok(ctx) &&
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
  let precision = ctx.precision_
  let lhs_digits = lhs.coefficient.digits10()
  let rhs_digits = rhs.coefficient.digits10()
  let extra = Int32::max(0, precision + 2 + rhs_digits - lhs_digits)
  let negative = lhs.negative != rhs.negative
  let numerator = if extra == 0 {
    lhs.coefficient
  } else {
    dec_coeff_shift_power10_repr(lhs.coefficient, extra)
  }
  let (quotient, finite_expansion) = dec_coeff_round_div_expansion(
    numerator,
    rhs.coefficient,
    negative,
    DecCoeffRounding::ZeroFiveUp,
  )
  if finite_expansion {
    return None
  }
  let digits = quotient.digits10()
  guard digits > precision else { return None }
  let exponent64 = difference - extra.to_int64()
  let adjusted = exponent64 + digits.to_int64() - 1L
  guard adjusted >= ctx.e_min_.to_int64() && adjusted < ctx.e_max_.to_int64() else {
    return None
  }
  let discard = digits - precision
  let magnitude = dec_coeff_round_pow10_coeff(
    quotient,
    discard,
    negative,
    ctx.decimal_.decimal_rounding.kernel(),
  )
  Some(
    gda_plain_finish(
      negative,
      magnitude,
      exponent64.to_int() + discard,
      true,
      true,
      ctx,
    ),
  )
}
