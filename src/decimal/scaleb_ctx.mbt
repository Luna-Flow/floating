///|
// Public scale-by-power-of-ten context operation.

fn scaleb_count(rhs : Decimal, ctx : DecimalContext) -> Int? {
  guard rhs.class == FpClass::Finite && rhs.exponent10 == 0 else { return None }
  let precision = finite_precision_for_coeff(dec_coeff_from_int(1), ctx)
  let limit64 = 2L * (ctx.e_max.to_int64() + precision.to_int64())
  let limit = if limit64 <= 0L {
    0
  } else if limit64 >= 2147483647L {
    2147483647
  } else {
    limit64.to_int()
  }
  match dec_coeff_to_bounded_int(rhs.coefficient, limit) {
    Some(value) =>
      Some(
        if rhs.negative && !rhs.coefficient.is_zero() {
          -value
        } else {
          value
        },
      )
    None => None
  }
}

///|
fn finalize_scaleb_finite_ctx(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let adjusted64 = value.exponent10.to_int64() +
    (value.coefficient.digits10() - 1).to_int64()
  if !value.coefficient.is_zero() && adjusted64 > ctx.e_max.to_int64() {
    return (
      Decimal::inf(
        if value.negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=value.precision_,
      ),
      { ..DecimalFlags::new(), overflow: true, rounded: true, inexact: true },
    )
  }
  let tiny = etiny(ctx)
  if value.exponent10 < tiny {
    let shift = tiny - value.exponent10
    let (magnitude_repr, inexact) = round_positive_decimal_div_pow10_repr(
      value.coefficient,
      shift,
      value.negative,
      ctx.decimal_rounding,
    )
    let mut flags = { ..DecimalFlags::new(), subnormal: true, rounded: true }
    if inexact {
      flags = { ..flags, inexact: true, underflow: true }
    }
    if magnitude_repr.is_zero() {
      return (
        finite_with_exponent_repr(
          value.negative,
          magnitude_repr,
          tiny,
          precision,
        ),
        { ..flags, clamped: true },
      )
    }
    if magnitude_repr.digits10() > precision {
      return finalize_scaleb_finite_ctx(
        finite_with_exponent_repr(
          value.negative,
          magnitude_repr,
          tiny,
          precision,
        ),
        ctx,
      )
    }
    return (
      finite_with_exponent_repr(value.negative, magnitude_repr, tiny, precision),
      flags,
    )
  }
  finalize_finite_ctx(value, DecimalFlags::new(), ctx)
}

///|
fn huge_shift_rounded_unit_repr(
  coefficient : DecCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> DecCoeff {
  guard !coefficient.is_zero() else { return dec_coeff_zero() }
  match mode {
    Down | HalfEven | HalfUp | HalfDown => dec_coeff_zero()
    Up | ZeroFiveUp => dec_coeff_from_int(1)
    Ceiling => if negative { dec_coeff_zero() } else { dec_coeff_from_int(1) }
    Floor => if negative { dec_coeff_from_int(1) } else { dec_coeff_zero() }
  }
}

///|
fn scaleb_int64_to_int(value : Int64) -> Int {
  if value > 2147483647L {
    2147483647
  } else if value < -2147483648L {
    -2147483647 - 1
  } else {
    value.to_int()
  }
}

///|
fn scaleb_finite_result_ctx(
  value : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let target_exponent64 = value.exponent10.to_int64() + count.to_int64()
  if value.coefficient.is_zero() {
    return (
      finite_with_exponent_repr(
        value.negative,
        dec_coeff_zero(),
        scaleb_int64_to_int(target_exponent64),
        precision,
      ),
      DecimalFlags::new(),
    )
  }
  let adjusted64 = target_exponent64 +
    (value.coefficient.digits10() - 1).to_int64()
  if adjusted64 > ctx.e_max.to_int64() {
    return (
      Decimal::inf(
        if value.negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=value.precision_,
      ),
      { ..DecimalFlags::new(), overflow: true, rounded: true, inexact: true },
    )
  }
  let tiny = etiny(ctx)
  let tiny64 = tiny.to_int64()
  if target_exponent64 < tiny64 {
    let shift64 = tiny64 - target_exponent64
    if shift64 > (value.coefficient.digits10() + 2).to_int64() {
      let magnitude = huge_shift_rounded_unit_repr(
        value.coefficient,
        value.negative,
        ctx.decimal_rounding,
      )
      let flags = {
        ..DecimalFlags::new(),
        rounded: true,
        inexact: !value.coefficient.is_zero(),
        underflow: !value.coefficient.is_zero(),
        subnormal: true,
        clamped: magnitude.is_zero(),
      }
      return (
        finite_with_exponent_repr(value.negative, magnitude, tiny, precision),
        flags,
      )
    }
  }
  finalize_scaleb_finite_ctx(
    finite_with_exponent_repr(
      value.negative,
      value.coefficient,
      scaleb_int64_to_int(target_exponent64),
      precision,
    ),
    ctx,
  )
}

///|
pub fn Decimal::scaleb_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(dec_coeff_from_int(1), ctx)
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => result
    None =>
      match (self.class, other.class) {
        (_, FpClass::Infinity) => (Decimal::nan(precision~), invalid_flags())
        (FpClass::Infinity, FpClass::Finite) =>
          (self.with_precision(precision, ctx.rounding), DecimalFlags::new())
        (FpClass::Finite, FpClass::Finite) =>
          match scaleb_count(other, ctx) {
            None => (Decimal::nan(precision~), invalid_flags())
            Some(count) => scaleb_finite_result_ctx(self, count, ctx)
          }
        (FpClass::NaN, _) | (_, FpClass::NaN) =>
          (Decimal::nan(precision~), invalid_flags())
      }
  }
}
