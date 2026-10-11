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
          divide_integer_zero_result(
            self.negative != other.negative,
            DecimalFlags::new(),
            ctx,
          )
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
fn decimal_remainder_extended_fast_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.extended else { return None }
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  guard !finite_integer_quotient_is_zero(dividend, divisor) else { return None }
  let quotient_digits = integer_quotient_digit_count(dividend, divisor)
  if ctx.precision > 0 && quotient_digits > ctx.precision {
    return Some(
      (
        Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
        div_impossible_flags(),
      ),
    )
  }
  // The integer quotient is internal: only its digit count matters
  // (division impossible). Its rounding, overflow or clamping to the context
  // describes no delivered result, so none of its flags reach the remainder.
  let scale = dividend.exponent10 - divisor.exponent10
  let (magnitude, target) = if scale >= 0 {
    (
      dec_coeff_shift_power10_mod_repr(
        dividend.coefficient,
        scale,
        divisor.coefficient,
      ),
      divisor.exponent10,
    )
  } else {
    let denominator = dec_coeff_shift_power10_repr(divisor.coefficient, -scale)
    (
      dec_coeff_div_rem_repr(dividend.coefficient, denominator).1,
      dividend.exponent10,
    )
  }
  let (value, flags) = normalize_decimal_parts_ctx_repr(
    dividend.negative,
    magnitude,
    target,
    ctx,
  )
  Some((value, flags))
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
  if lhs.class == FpClass::Finite && rhs.class == FpClass::Finite {
    match decimal_remainder_extended_fast_result(lhs, rhs, ctx) {
      Some((value, flags)) => return (value, operand_flags.combine(flags))
      None => ()
    }
  }
  let (quotient, quotient_flags0) = decimal_integer_quotient(
    lhs,
    rhs,
    ctx,
    clamp_zero=false,
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
      // The quotient rounded to the context may have overflowed or been
      // clamped, and its flags describe it, not the remainder. The remainder
      // is taken with the exact integer quotient, under the operand flags.
      let exact_quotient = decimal_exact_integer_quotient_repr(lhs, rhs)
      let (lhs_units, rhs_units, target) = decimal_division_common_magnitude_units(
        lhs, rhs,
      )
      let product = dec_coeff_multiply_repr(exact_quotient, rhs_units)
      // lhs - q * rhs with q of sign lhs.negative != rhs.negative, so the
      // subtracted term has the sign of -lhs.
      let (exact_negative, exact_magnitude) = dec_coeff_signed_add_repr(
        lhs.negative,
        lhs_units,
        !lhs.negative,
        product,
      )
      if exact_magnitude.is_zero() && !ctx.extended {
        return (
          Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
          operand_flags,
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
      (value, operand_flags.combine(flags))
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
  let quotient_flags = operand_flags.combine(
    divide_integer_zero_quotient_flags(lhs, rhs, ctx),
  )
  if finite_nearest_integer_quotient_is_zero(lhs, rhs) {
    let (value, flags) = zero_quotient_remainder_result(lhs, rhs, ctx)
    return (value, quotient_flags.combine(flags))
  }
  match (lhs.class, rhs.class) {
    (FpClass::Finite, FpClass::Finite) => {
      let (exact_negative, exact_magnitude, target) = decimal_nearest_remainder_parts(
        lhs, rhs,
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
  self.remainder_near(other, ctx.ieee754())
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
        dec_coeff_zero(),
        target,
        precision,
      ),
      DecimalFlags::new(),
    )
  }
  let mut flags = DecimalFlags::new()
  let exponent_delta = target.to_int64() - value.exponent10.to_int64()
  let coeff = if exponent_delta > 0L {
    let (rounded, inexact) = if exponent_delta >
      value.coefficient.digits10().to_int64() {
      let increment = match ctx.decimal_rounding {
        Down | HalfEven | HalfUp | HalfDown => false
        Ceiling => !negative
        Floor => negative
        Up => true
        ZeroFiveUp => true
      }
      (if increment { dec_coeff_from_int(1) } else { dec_coeff_zero() }, true)
    } else {
      round_positive_decimal_div_pow10_repr(
        value.coefficient,
        exponent_delta.to_int(),
        negative,
        ctx.decimal_rounding,
      )
    }
    flags = { ..flags, rounded: true, inexact, }
    rounded
  } else if exponent_delta < 0L {
    let shift64 = -exponent_delta
    if ctx.precision > 0 &&
      shift64 > (ctx.precision - value.coefficient.digits10()).to_int64() {
      return (Decimal::nan(precision~), invalid_flags())
    }
    let shift = shift64.to_int()
    dec_coeff_shift_power10_repr(value.coefficient, shift)
  } else {
    value.coefficient
  }
  if ctx.precision > 0 && coeff.digits10() > ctx.precision {
    return (Decimal::nan(precision~), invalid_flags())
  }
  if target.to_int64() > ctx.e_max.to_int64() - coeff.digits10().to_int64() + 1L {
    return (Decimal::nan(precision~), invalid_flags())
  }
  let (result, final_flags) = finalize_finite_ctx(
    finite_with_exponent_repr(negative, coeff, target, precision),
    flags,
    ctx,
  )
  let final_flags = { ..final_flags, underflow: false, }
  if !ctx.extended && result.coefficient.is_zero() {
    (
      finite_with_exponent_repr(false, dec_coeff_zero(), target, precision),
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
      } else if !ctx.extended && self.exponent10 >= 0 {
        self.apply_ctx(ctx)
      } else {
        to_integral_finite(self, ctx)
      }
  }
}

///|
// roundToIntegral of a finite operand. IEEE 754-2019 §5.9 defines it for an
// operand in the destination format (at most p digits), and for such an
// operand this is its result. An operand longer than the precision is not a
// value of the format, so §5.9 does not cover it and the result is
// implementation-defined. The behaviour chosen here is GDA-style (General
// Decimal Arithmetic rounds at the operand's own precision): an operand with
// a non-negative exponent is already an integer and is returned unchanged,
// and an operand with a fraction is quantized to exponent 0 at a working
// precision of max(p, its digit count), so the integral part is never rounded
// to the context precision and the result is never invalid. In a subset
// context the operand is first rounded to the precision (lost digits).
fn to_integral_finite(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (operand, operand_flags) = prepare_operand_for_context(value, ctx)
  if operand.class != FpClass::Finite {
    return (operand, operand_flags)
  }
  if operand.exponent10 >= 0 {
    // Within the precision `apply_ctx` only applies the exponent range
    // (the clamp fold-down of interchange formats); a longer integer is
    // returned as it is instead of being rounded.
    if ctx.precision <= 0 || operand.coefficient.digits10() <= ctx.precision {
      let (result, flags) = operand.apply_ctx(ctx)
      return (result, operand_flags.combine(flags))
    }
    return (
      {
        ..operand,
        precision_: finite_precision_for_coeff(operand.coefficient, ctx),
      },
      operand_flags,
    )
  }
  let work_ctx = if ctx.precision > 0 {
    {
      ..ctx,
      precision: Int::max(ctx.precision, operand.coefficient.digits10()),
    }
  } else {
    ctx
  }
  let (result, flags) = operand.quantize(
    Decimal::one(precision=finite_precision_for(bigint_one(), ctx)),
    work_ctx,
  )
  (result, operand_flags.combine(flags))
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
      } else if !ctx.extended && self.exponent10 >= 0 {
        self.apply_ctx(ctx)
      } else {
        let (value, flags) = to_integral_finite(self, ctx)
        // Only the rounding to an integer is silent; digits lost by a
        // subset operand are still reported.
        if flags.lost_digits {
          (value, flags)
        } else {
          (value, { ..flags, rounded: false, inexact: false, })
        }
      }
  }
}
