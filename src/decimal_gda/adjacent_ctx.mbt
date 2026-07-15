///|
// Public adjacent-value and logb context operations.

fn signed_units_at_quantum_repr(
  value : Decimal,
  quantum : Int,
) -> ((Bool, GdaCoeff), (Bool, GdaCoeff), Bool) {
  let shift = value.exponent10 - quantum
  if shift >= 0 {
    let units = gda_coeff_shift_power10_repr(value.coefficient, shift)
    let signed = (value.negative, units)
    return (signed, signed, true)
  }
  let scale = -shift
  let (quotient, exact) = if scale >= value.coefficient.digits10() {
    (gda_coeff_zero(), false)
  } else {
    let (quotient0, remainder) = gda_coeff_div_rem_repr(
      value.coefficient,
      gda_coeff_power10_repr(scale),
    )
    (quotient0, remainder.is_zero())
  }
  if value.negative {
    let ceil = if quotient.is_zero() && !exact {
      (false, gda_coeff_zero())
    } else {
      (true, quotient)
    }
    let floor = if exact {
      ceil
    } else {
      (true, gda_coeff_magnitude_add_unit(quotient, 1))
    }
    (floor, ceil, exact)
  } else {
    let floor = (false, quotient)
    let ceil = if exact {
      floor
    } else {
      (false, gda_coeff_magnitude_add_unit(quotient, 1))
    }
    (floor, ceil, exact)
  }
}

///|
fn next_quantum(
  value : Decimal,
  ctx : DecimalContext,
  toward_positive : Bool,
) -> Int {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let moving_away_from_zero = if value.negative {
    !toward_positive
  } else {
    toward_positive
  }
  let boundary_adjust = if !moving_away_from_zero &&
    gda_coeff_compare_repr(
      remove_factor10_repr(value.coefficient, 0).0,
      gda_coeff_from_int(1),
    ) ==
    0 {
    0
  } else {
    1
  }
  Int::max(etiny(ctx), adjusted_exponent(value) - precision + boundary_adjust)
}

///|
fn next_toward_flags(
  source : Decimal,
  result : Decimal,
  ctx : DecimalContext,
) -> DecimalFlags {
  guard source.class == FpClass::Finite else { return DecimalFlags::new() }
  if result.class == FpClass::Infinity {
    return {
      ..DecimalFlags::new(),
      overflow: true,
      rounded: true,
      inexact: true,
    }
  }
  guard result.class == FpClass::Finite else { return DecimalFlags::new() }
  if result.coefficient.is_zero() {
    {
      ..DecimalFlags::new(),
      underflow: true,
      subnormal: true,
      inexact: true,
      rounded: true,
      clamped: !source.coefficient.is_zero(),
    }
  } else if adjusted_exponent(result) < ctx.e_min {
    {
      ..DecimalFlags::new(),
      underflow: true,
      subnormal: true,
      inexact: true,
      rounded: true,
    }
  } else {
    DecimalFlags::new()
  }
}

///|
fn finite_next_candidate_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  quantum : Int,
  precision : Int,
) -> Decimal {
  let extra_digits = magnitude.digits10() - precision
  let (magnitude2, exponent10, _) = if extra_digits > 0 {
    trim_trailing_decimal_zeros_repr(magnitude, quantum, max_drop=extra_digits)
  } else {
    (magnitude, quantum, 0)
  }
  finite_with_exponent_repr(negative, magnitude2, exponent10, precision)
}

///|
fn max_finite_for(ctx : DecimalContext, negative : Bool) -> Decimal {
  let precision = finite_precision_for(bigint_one(), ctx)
  finite_with_exponent(
    negative,
    pow10(precision) - bigint_one(),
    ctx.e_max - precision + 1,
    precision,
  )
}

///|
fn decimal_next(
  value : Decimal,
  ctx : DecimalContext,
  toward_positive : Bool,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_one(), ctx)
  match value.class {
    FpClass::NaN => quiet_nan_operand(value, ctx)
    FpClass::Infinity =>
      if value.negative {
        if toward_positive {
          (max_finite_for(ctx, true), DecimalFlags::new())
        } else {
          (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
        }
      } else if toward_positive {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      } else {
        (max_finite_for(ctx, false), DecimalFlags::new())
      }
    FpClass::Finite =>
      if value.coefficient.is_zero() {
        let zero_quantum = if value.exponent10 < etiny(ctx) {
          value.exponent10
        } else {
          etiny(ctx)
        }
        (
          finite_with_exponent(
            !toward_positive,
            bigint_one(),
            zero_quantum,
            precision,
          ),
          DecimalFlags::new(),
        )
      } else {
        let quantum = next_quantum(value, ctx, toward_positive)
        let (floor_units, ceil_units, exact) = signed_units_at_quantum_repr(
          value, quantum,
        )
        let (units_negative, units_magnitude) = if toward_positive {
          if exact {
            gda_coeff_signed_step_unit_repr(ceil_units.0, ceil_units.1, true)
          } else {
            ceil_units
          }
        } else if exact {
          gda_coeff_signed_step_unit_repr(floor_units.0, floor_units.1, false)
        } else {
          floor_units
        }
        if units_magnitude.is_zero() {
          return (
            finite_with_exponent_repr(
              value.negative,
              gda_coeff_zero(),
              quantum,
              precision,
            ),
            DecimalFlags::new(),
          )
        }
        let candidate = finite_next_candidate_repr(
          units_negative, units_magnitude, quantum, precision,
        )
        if adjusted_exponent(candidate) > ctx.e_max {
          (
            Decimal::inf(
              if candidate.negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision~,
            ),
            DecimalFlags::new(),
          )
        } else {
          (candidate, DecimalFlags::new())
        }
      }
  }
}

///|
fn logb_finite_result_ctx(
  adjusted : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  // GDA decNumberLogB computes rhs->exponent + rhs->digits - 1 and lays that
  // Int out with decNumberFromInt32 (decNumber.c lines 1333-1352). Keep the
  // same adjusted-exponent value and decimal-unit layout throughout here.
  let negative = adjusted < 0
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  let mut magnitude = gda_coeff_from_int_magnitude(adjusted)
  let mut exponent10 = 0
  let mut flags = DecimalFlags::new()
  let digits = magnitude.digits10()
  if ctx.precision > 0 && digits > precision {
    let shift = digits - precision
    let (rounded, inexact) = round_positive_decimal_div_pow10_repr(
      magnitude,
      shift,
      negative,
      ctx.decimal_rounding,
    )
    flags = { ..flags, rounded: true }
    if inexact {
      flags = { ..flags, inexact: true }
    }
    exponent10 += shift
    magnitude = rounded
    if magnitude.digits10() > precision {
      exponent10 += 1
      magnitude = gda_coeff_div_rem_by_unit_repr(magnitude, 10).0
    }
  }
  finalize_finite_ctx(
    finite_with_exponent_repr(negative, magnitude, exponent10, precision),
    flags,
    ctx,
  )
}

///|
pub fn Decimal::next_plus(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_next(self, ctx, true)
}

///|
pub fn Decimal::next_minus(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_next(self, ctx, false)
}

///|
pub fn Decimal::next_toward(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match quiet_nan_pair_for_next_toward(self, other, ctx) {
    Some(result) => result
    None => {
      let cmp = self.compare(other)
      if cmp == 0 {
        if self.class == FpClass::Finite &&
          other.class == FpClass::Finite &&
          self.coefficient.is_zero() &&
          other.coefficient.is_zero() {
          ({ ..self, negative: other.negative }, DecimalFlags::new())
        } else {
          (self, DecimalFlags::new())
        }
      } else {
        let toward_positive = cmp < 0
        let (next, next_flags) = decimal_next(self, ctx, toward_positive)
        (next, next_flags.combine(next_toward_flags(self, next, ctx)))
      }
    }
  }
}

///|
pub fn Decimal::logb_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_zero(), ctx)
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        (
          Decimal::inf(Sign::Negative, precision~),
          { ..DecimalFlags::new(), division_by_zero: true },
        )
      } else {
        let adjusted = adjusted_exponent(self)
        logb_finite_result_ctx(adjusted, ctx)
      }
  }
}
