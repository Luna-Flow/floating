///|
// Public quantum, remainder, and integral context operations.

pub fn Decimal::same_quantum(self : Decimal, other : Decimal) -> Bool {
  match (self.class, other.class) {
    (FpClass::Finite, FpClass::Finite) => self.exponent10 == other.exponent10
    (FpClass::Infinity, FpClass::Infinity) => true
    (FpClass::NaN, FpClass::NaN) => true
    _ => false
  }
}

///|
pub fn Decimal::divide_integer(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  let result = lhs.divide_integer_impl(rhs, ctx)
  (result.0, operand_flags.combine(result.1))
}

///|
fn Decimal::divide_integer_impl(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_one(), ctx)
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => result
    None =>
      match (self.class, other.class) {
        (FpClass::Infinity, FpClass::Finite) if other.is_zero() =>
          (
            Decimal::inf(
              if self.negative != other.negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision~,
            ),
            DecimalFlags::new(),
          )
        (_, FpClass::Finite) if other.is_zero() =>
          if self.is_zero() {
            (Decimal::nan(precision~), div_zero_flags(true))
          } else {
            (
              Decimal::inf(
                if self.negative != other.negative {
                  Sign::Negative
                } else {
                  Sign::Positive
                },
                precision~,
              ),
              div_zero_flags(false),
            )
          }
        (FpClass::Infinity, FpClass::Finite) =>
          (
            Decimal::inf(
              if self.negative != other.negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision~,
            ),
            DecimalFlags::new(),
          )
        (FpClass::Finite, FpClass::Infinity) =>
          if self.negative != other.negative {
            (Decimal::negative_zero(precision~), DecimalFlags::new())
          } else {
            (Decimal::zero(precision~), DecimalFlags::new())
          }
        (FpClass::Infinity, FpClass::Infinity) =>
          (Decimal::nan(precision~), invalid_flags())
        (FpClass::Finite, FpClass::Finite) =>
          decimal_integer_quotient(self, other, ctx)
        (FpClass::NaN, _) | (_, FpClass::NaN) =>
          (Decimal::nan(precision~), invalid_flags())
      }
  }
}

///|
pub fn Decimal::remainder(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  match quiet_nan_pair(lhs, rhs, ctx) {
    Some((value, flags)) => return (value, operand_flags.combine(flags))
    None => ()
  }
  if lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    rhs.is_zero() {
    let precision = finite_precision_for(bigint_one(), ctx)
    return if lhs.is_zero() {
      (Decimal::nan(precision~), operand_flags.combine(div_zero_flags(true)))
    } else {
      (Decimal::nan(precision~), operand_flags.combine(invalid_flags()))
    }
  }
  if lhs.class == FpClass::Finite && rhs.class == FpClass::Infinity {
    let (value, flags) = if lhs.class == FpClass::Finite {
      apply_finite_ctx(lhs, ctx)
    } else {
      (lhs, DecimalFlags::new())
    }
    return (value, operand_flags.combine(flags))
  }
  if lhs.class == FpClass::Infinity {
    return (
      Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
      operand_flags.combine(invalid_flags()),
    )
  }
  let (quotient, quotient_flags0) = decimal_integer_quotient(lhs, rhs, ctx)
  let quotient_flags = operand_flags.combine(quotient_flags0)
  if quotient.class == FpClass::NaN || quotient_flags.has_error() {
    return (quotient, quotient_flags)
  }
  match (lhs.class, rhs.class) {
    (FpClass::Finite, FpClass::Finite) => {
      if quotient.is_zero() {
        let (value, flags) = zero_quotient_remainder_result(lhs, rhs, ctx)
        return (value, quotient_flags.combine(flags))
      }
      let (lhs_units, rhs_units, target) = decimal_division_common_magnitude_units(
        lhs, rhs,
      )
      let product = gda_coeff_multiply_repr(quotient.coefficient, rhs_units)
      let (exact_negative, exact_magnitude) = gda_coeff_signed_add_repr(
        lhs.negative,
        lhs_units,
        !(quotient.negative != rhs.negative),
        product,
      )
      if exact_magnitude.is_zero() && !ctx.extended {
        return (
          Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
          quotient_flags,
        )
      }
      let negative = if exact_magnitude.is_zero() {
        lhs.negative && ctx.extended
      } else {
        exact_negative
      }
      let (value, flags) = normalize_decimal_parts_ctx_repr(
        negative, exact_magnitude, target, ctx,
      )
      (value, quotient_flags.combine(flags))
    }
    _ =>
      (
        Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
        invalid_flags(),
      )
  }
}

///|
pub fn Decimal::remainder_near(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  match quiet_nan_pair(lhs, rhs, ctx) {
    Some((value, flags)) => return (value, operand_flags.combine(flags))
    None => ()
  }
  if lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    rhs.is_zero() {
    let precision = finite_precision_for(bigint_one(), ctx)
    return if lhs.is_zero() {
      (Decimal::nan(precision~), operand_flags.combine(div_zero_flags(true)))
    } else {
      (Decimal::nan(precision~), operand_flags.combine(invalid_flags()))
    }
  }
  if lhs.class == FpClass::Finite && rhs.class == FpClass::Infinity {
    let (value, flags) = if lhs.class == FpClass::Finite {
      apply_finite_ctx(lhs, ctx)
    } else {
      (lhs, DecimalFlags::new())
    }
    return (value, operand_flags.combine(flags))
  }
  if lhs.class == FpClass::Infinity {
    return (
      Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
      operand_flags.combine(invalid_flags()),
    )
  }
  let (quotient, quotient_flags0) = decimal_nearest_integer_quotient(
    lhs, rhs, ctx, true,
  )
  let quotient_flags = operand_flags.combine(quotient_flags0)
  if quotient.class == FpClass::NaN || quotient_flags.has_error() {
    return (quotient, quotient_flags)
  }
  match (lhs.class, rhs.class) {
    (FpClass::Finite, FpClass::Finite) => {
      if quotient.is_zero() {
        let (value, flags) = zero_quotient_remainder_result(lhs, rhs, ctx)
        return (value, quotient_flags.combine(flags))
      }
      let (lhs_units, rhs_units, target) = decimal_division_common_magnitude_units(
        lhs, rhs,
      )
      let product = gda_coeff_multiply_repr(quotient.coefficient, rhs_units)
      let (exact_negative, exact_magnitude) = gda_coeff_signed_add_repr(
        lhs.negative,
        lhs_units,
        !(quotient.negative != rhs.negative),
        product,
      )
      if exact_magnitude.is_zero() && !ctx.extended {
        return (
          Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
          quotient_flags,
        )
      }
      let negative = if exact_magnitude.is_zero() {
        lhs.negative && ctx.extended
      } else {
        exact_negative
      }
      let (value, flags) = normalize_decimal_parts_ctx_repr(
        negative, exact_magnitude, target, ctx,
      )
      (value, quotient_flags.combine(flags))
    }
    _ =>
      (
        Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
        invalid_flags(),
      )
  }
}

///|
// IEEE 754 remainder: the quotient is rounded to nearest, ties to even, and
// the remainder is formed from the exact unrounded operands.
pub fn Decimal::remainder_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.remainder_near(other, ctx)
}

///|
pub fn Decimal::quantize(
  self : Decimal,
  quantum : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, quantum, ctx,
  )
  let result = lhs.quantize_impl(rhs, quantum, ctx)
  (result.0, operand_flags.combine(result.1))
}

///|
fn Decimal::quantize_impl(
  self : Decimal,
  quantum : Decimal,
  original_quantum : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(self.coefficient, ctx)
  match quiet_nan_pair(self, quantum, ctx) {
    Some(result) => result
    None =>
      match (self.class, quantum.class) {
        (FpClass::Infinity, FpClass::Infinity) =>
          (self.with_precision(precision, ctx.rounding), DecimalFlags::new())
        (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
          (Decimal::nan(precision~), invalid_flags())
        (FpClass::Finite, FpClass::Finite) => {
          let target = if !ctx.extended &&
            original_quantum.class == FpClass::Finite &&
            !original_quantum.coefficient.is_zero() &&
            original_quantum.exponent10 < -999_999_999 {
            0
          } else {
            original_quantum.exponent10
          }
          quantize_finite_to_exponent(self, target, precision, ctx)
        }
        (FpClass::NaN, _) | (_, FpClass::NaN) =>
          (Decimal::nan(precision~), invalid_flags())
      }
  }
}

///|
fn quantize_finite_to_exponent(
  value : Decimal,
  target : Int,
  precision : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("quantize_finite_to_exponent expects a finite operand")
  }
  let lower = if ctx.extended { etiny(ctx) } else { ctx.e_min }
  guard target >= lower && target <= ctx.e_max else {
    return (Decimal::nan(precision~), invalid_flags())
  }
  let negative = value.negative
  if value.coefficient.is_zero() {
    return (
      finite_with_exponent_repr(
        negative && ctx.extended,
        gda_coeff_zero(),
        target,
        precision,
      ),
      DecimalFlags::new(),
    )
  }
  let mut flags = DecimalFlags::new()
  let coeff = if value.exponent10 < target {
    let shift = target - value.exponent10
    let (rounded, inexact) = round_positive_decimal_div_pow10_repr(
      value.coefficient,
      shift,
      negative,
      ctx.decimal_rounding,
    )
    flags = { ..flags, rounded: true, inexact }
    rounded
  } else if value.exponent10 > target {
    let shift = value.exponent10 - target
    if ctx.precision > 0 && shift > ctx.precision - value.coefficient.digits10() {
      return (Decimal::nan(precision~), invalid_flags())
    }
    gda_coeff_shift_power10_repr(value.coefficient, shift)
  } else {
    value.coefficient
  }
  if ctx.precision > 0 && coeff.digits10() > ctx.precision {
    return (Decimal::nan(precision~), invalid_flags())
  }
  if target > ctx.e_max - coeff.digits10() + 1 {
    return (Decimal::nan(precision~), invalid_flags())
  }
  let (result, final_flags) = finalize_finite_ctx(
    finite_with_exponent_repr(negative, coeff, target, precision),
    flags,
    ctx,
  )
  let final_flags = { ..final_flags, underflow: false }
  if !ctx.extended && result.coefficient.is_zero() {
    (
      finite_with_exponent_repr(false, gda_coeff_zero(), target, precision),
      final_flags,
    )
  } else {
    (result, final_flags)
  }
}

///|
pub fn Decimal::rescale(
  self : Decimal,
  quantum : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, quantum, ctx,
  )
  let result = lhs.rescale_impl(rhs, quantum, ctx)
  (result.0, operand_flags.combine(result.1))
}

///|
fn Decimal::rescale_impl(
  self : Decimal,
  quantum : Decimal,
  original_quantum : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(self.coefficient, ctx)
  match quiet_nan_pair(self, quantum, ctx) {
    Some(result) => result
    None =>
      match (self.class, quantum.class) {
        (FpClass::Infinity, FpClass::Infinity) =>
          (self.with_precision(precision, ctx.rounding), DecimalFlags::new())
        (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
          (Decimal::nan(precision~), invalid_flags())
        (FpClass::Finite, FpClass::Finite) =>
          match decimal_power_gda_integer_count(original_quantum) {
            Some(target) =>
              quantize_finite_to_exponent(self, target, precision, ctx)
            None => (Decimal::nan(precision~), invalid_flags())
          }
        (FpClass::NaN, _) | (_, FpClass::NaN) =>
          (Decimal::nan(precision~), invalid_flags())
      }
  }
}

///|
pub fn Decimal::to_integral_exact(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision(
          finite_precision_for(bigint_one(), ctx),
          ctx.rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite =>
      if !ctx.extended && self.coefficient.is_zero() {
        (
          Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
          DecimalFlags::new(),
        )
      } else if self.exponent10 >= 0 {
        self.apply_ctx(ctx)
      } else {
        self.quantize(
          Decimal::one(precision=finite_precision_for(bigint_one(), ctx)),
          ctx,
        )
      }
  }
}

///|
pub fn Decimal::to_integral_value(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision(
          finite_precision_for(bigint_one(), ctx),
          ctx.rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite =>
      if !ctx.extended && self.coefficient.is_zero() {
        (
          Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
          DecimalFlags::new(),
        )
      } else if self.exponent10 >= 0 {
        self.apply_ctx(ctx)
      } else {
        let (value, flags) = self.to_integral_exact(ctx)
        (value, { ..flags, rounded: false, inexact: false })
      }
  }
}
