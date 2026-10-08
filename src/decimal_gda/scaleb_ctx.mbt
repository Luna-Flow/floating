///|
// Public scale-by-power-of-ten context operation.

fn scaleb_count(rhs : Decimal, ctx : DecimalContext) -> Int? {
  guard rhs.class == FpClass::Finite && rhs.exponent10 == 0 else { return None }
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let limit64 = 2L * (ctx.e_max.to_int64() + precision.to_int64())
  let limit = if limit64 <= 0L {
    0
  } else if limit64 >= 2147483647L {
    2147483647
  } else {
    limit64.to_int()
  }
  match gda_coeff_to_bounded_int(rhs.coefficient, limit) {
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
fn huge_shift_rounded_unit_repr(
  coefficient : GdaCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> GdaCoeff {
  guard !coefficient.is_zero() else { return gda_coeff_zero() }
  match mode {
    Down | HalfEven | HalfUp | HalfDown => gda_coeff_zero()
    Up | ZeroFiveUp => gda_coeff_from_int(1)
    Ceiling => if negative { gda_coeff_zero() } else { gda_coeff_from_int(1) }
    Floor => if negative { gda_coeff_from_int(1) } else { gda_coeff_zero() }
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
    // A zero keeps its sign; its exponent is clamped into the range the
    // context can represent, as for every other finalized zero.
    let (lower64, upper64) = if ctx.precision > 0 {
      (
        etiny(ctx).to_int64(),
        (if ctx.clamp { ctx.e_max - precision + 1 } else { ctx.e_max }).to_int64(),
      )
    } else {
      (-2147483648L, 2147483647L)
    }
    let exponent64 = if target_exponent64 < lower64 {
      lower64
    } else if target_exponent64 > upper64 {
      upper64
    } else {
      target_exponent64
    }
    return (
      finite_with_exponent_repr(
        value.negative,
        gda_coeff_zero(),
        scaleb_int64_to_int(exponent64),
        precision,
      ),
      {
        ..DecimalFlags::new(),
        clamped: ctx.precision > 0 && exponent64 != target_exponent64,
      },
    )
  }
  let adjusted64 = target_exponent64 +
    (value.coefficient.digits10() - 1).to_int64()
  if adjusted64 > ctx.e_max.to_int64() {
    // Overflow honours the rounding direction (IEEE 754-2019 7.4).
    return decimal_overflow_result(value.negative, ctx)
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
  // The exponent now lies between Etiny - digits - 2 and e_max, so it fits in
  // an Int. Round the scaled value once like any other context result: to the
  // context precision, or to Etiny when it is subnormal.
  normalize_decimal_parts_ctx_repr(
    value.negative,
    value.coefficient,
    target_exponent64.to_int(),
    ctx,
  )
}

///|
pub fn Decimal::scaleb_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
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
