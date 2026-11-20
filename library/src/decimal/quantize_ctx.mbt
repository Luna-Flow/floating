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
// IEEE 754 remainder: the quotient is rounded to nearest, ties to even, and
// the remainder is formed from the exact unrounded operands.
pub fn Decimal::remainder_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => return result
    None => ()
  }
  if self.class == FpClass::Finite &&
    other.class == FpClass::Finite &&
    other.is_zero() {
    let precision = finite_precision_for(bigint_one(), ctx)
    return if self.is_zero() {
      (Decimal::nan(precision~), div_zero_flags(true))
    } else {
      (Decimal::nan(precision~), invalid_flags())
    }
  }
  if self.class == FpClass::Finite && other.class == FpClass::Infinity {
    let (value, flags) = if self.class == FpClass::Finite {
      apply_finite_ctx(self, ctx)
    } else {
      (self, DecimalFlags::new())
    }
    return (value, flags)
  }
  if self.class == FpClass::Infinity {
    return (
      Decimal::nan(precision=finite_precision_for(bigint_one(), ctx)),
      invalid_flags(),
    )
  }
  let quotient_flags = divide_integer_zero_quotient_flags()
  if finite_nearest_integer_quotient_is_zero(self, other) {
    let (value, flags) = zero_quotient_remainder_result(self, other, ctx)
    return (value, quotient_flags.combine(flags))
  }
  match (self.class, other.class) {
    (FpClass::Finite, FpClass::Finite) => {
      let (exact_negative, exact_magnitude, target) = decimal_nearest_remainder_parts(
        self, other,
      )

      let negative = if exact_magnitude.is_zero() {
        self.negative
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
pub fn Decimal::quantize_ctx(
  self : Decimal,
  quantum : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.quantize_impl(quantum, quantum, ctx)
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
          (
            self.with_precision_round(precision, ctx.decimal_rounding),
            DecimalFlags::new(),
          )
        (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
          (Decimal::nan(precision~), invalid_flags())
        (FpClass::Finite, FpClass::Finite) => {
          let target = original_quantum.exponent10
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
  target : Int32,
  precision : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("quantize_finite_to_exponent expects a finite operand")
  }
  let lower = etiny(ctx)
  guard target >= lower && target <= ctx.e_max else {
    return (Decimal::nan(precision~), invalid_flags())
  }
  let negative = value.negative
  if value.coefficient.is_zero() {
    // A zero result above `e_max - precision + 1` is not a member of the
    // format: its exponent is folded down (issue 234).
    if ctx.clamp && ctx.precision > 0 {
      let top = etop(ctx, precision)
      if target > top {
        return (
          finite_with_exponent_repr(negative, dec_coeff_zero(), top, precision),
          DecimalFlags::new(),
        )
      }
    }
    return (
      finite_with_exponent_repr(negative, dec_coeff_zero(), target, precision),
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
    flags = { ..flags, inexact, }
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
  (result, final_flags)
}

///|
pub fn Decimal::to_integral_exact_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision_round(
          finite_precision_for(bigint_one(), ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite => to_integral_finite(self, ctx)
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
  if value.class != FpClass::Finite {
    return (value, DecimalFlags::new())
  }
  if value.exponent10 >= 0 {
    // Within the precision `apply_ctx` only applies the exponent range
    // (the clamp fold-down of interchange formats); a longer integer is
    // returned as it is instead of being rounded.
    if ctx.precision <= 0 || value.coefficient.digits10() <= ctx.precision {
      return value.apply_ctx(ctx)
    }
    return (
      {
        ..value,
        precision_: finite_precision_for_coeff(value.coefficient, ctx),
      },
      DecimalFlags::new(),
    )
  }
  let work_ctx = if ctx.precision > 0 {
    {
      ..ctx,
      precision: Int32::max(ctx.precision, value.coefficient.digits10()),
    }
  } else {
    ctx
  }
  value.quantize_ctx(
    Decimal::one(precision=finite_precision_for(bigint_one(), ctx)),
    work_ctx,
  )
}

///|
pub fn Decimal::to_integral_value_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision_round(
          finite_precision_for(bigint_one(), ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite => {
      // Only the rounding to an integer is silent.
      let (value, flags) = to_integral_finite(self, ctx)
      (value, { ..flags, inexact: false, })
    }
  }
}
