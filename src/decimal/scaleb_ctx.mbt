///|
// Public scale-by-power-of-ten context operation.

fn scaleb_count(rhs : Decimal, ctx : DecimalContext) -> Int? {
  guard rhs.class == FpClass::Finite && rhs.exponent10 == 0 else { return None }
  let precision = finite_precision_for(bigint_one(), ctx)
  let limit = 2 * (ctx.e_max + precision)
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
  if !value.coefficient.is_zero() && adjusted_exponent(value) > ctx.e_max {
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
fn huge_shift_rounded_unit(
  coefficient : BigInt,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> BigInt {
  guard !coefficient.is_zero() else { return bigint_zero() }
  match mode {
    Down | HalfEven | HalfUp | HalfDown => bigint_zero()
    Up | ZeroFiveUp => bigint_one()
    Ceiling => if negative { bigint_zero() } else { bigint_one() }
    Floor => if negative { bigint_one() } else { bigint_zero() }
  }
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
fn scaleb_finite_result_ctx(
  value : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let target_exponent = BigInt::from_int(value.exponent10) +
    BigInt::from_int(count)
  if value.coefficient.is_zero() {
    return (
      finite_with_exponent(
        value.negative,
        bigint_zero(),
        target_exponent.to_int(),
        precision,
      ),
      DecimalFlags::new(),
    )
  }
  let adjusted = target_exponent +
    BigInt::from_int(value.coefficient.digits10() - 1)
  if adjusted > BigInt::from_int(ctx.e_max) {
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
  if target_exponent < BigInt::from_int(tiny) {
    let shift_big = BigInt::from_int(tiny) - target_exponent
    if shift_big > BigInt::from_int(value.coefficient.digits10() + 2) {
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
      target_exponent.to_int(),
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
  let precision = finite_precision_for(bigint_one(), ctx)
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
