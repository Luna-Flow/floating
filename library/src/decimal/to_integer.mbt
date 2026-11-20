///|
/// Rounds a finite value to an integer in the context's direction and returns
/// its sign and magnitude when the magnitude is at most `negative_limit`
/// (negative values) or `positive_limit` (positive values). A NaN, an infinity
/// and an out-of-range result give `None` with the invalid operation
/// exception; `exact` adds inexact when rounding changed the value.
///
/// The power of ten of the exponent is never formed: a value of 21 or more
/// integer digits is out of range for every integer format (2^64 has 20
/// digits), and a fractional part of more than `digits + 1` places only tells
/// that the value is below 0.1, which the kernel's rounding decision sees
/// with a shift of `digits + 1`.
fn decimal_to_integer_parts(
  value : Decimal,
  ctx : DecimalContext,
  exact : Bool,
  negative_limit : UInt64,
  positive_limit : UInt64,
) -> ((Bool, UInt64)?, DecimalFlags) {
  guard value.class == FpClass::Finite else { return (None, invalid_flags()) }
  if value.coefficient.is_zero() {
    return (Some((false, 0UL)), DecimalFlags::new())
  }
  let digits = value.coefficient.digits10()
  let (magnitude, changed) = if value.exponent10 >= 0 {
    if digits.to_int64() + value.exponent10.to_int64() > 20L {
      return (None, invalid_flags())
    }
    (dec_coeff_shift_power10_repr(value.coefficient, value.exponent10), false)
  } else {
    let places = -value.exponent10.to_int64()
    let shift = if places > digits.to_int64() + 1L {
      digits + 1
    } else {
      places.to_int()
    }
    dec_coeff_round_div_pow10(
      value.coefficient,
      shift,
      value.negative,
      ctx.decimal_rounding.kernel(),
    )
  }
  if magnitude.digits10() > 20 {
    return (None, invalid_flags())
  }
  let limit = if value.negative { negative_limit } else { positive_limit }
  let magnitude = coeff_bigint(magnitude)
  if magnitude > BigInt::from_uint64(limit) {
    return (None, invalid_flags())
  }
  (
    Some((value.negative && !magnitude.is_zero(), magnitude.to_uint64())),
    if exact && changed {
      { ..DecimalFlags::new(), inexact: true, }
    } else {
      DecimalFlags::new()
    },
  )
}

///|
/// IEEE 754-2019 convertToInteger (§5.4.1, §5.8) to `Int` in the context's
/// rounding direction: "Conversion to integer shall round as specified in
/// Clause 4; the rounding direction is indicated by the operation name." The
/// ties-to-even, toward-zero, toward-positive, toward-negative and
/// ties-to-away directions are those of the context; the other `decimal`
/// directions (half-down, away from zero, round-05up) round the same way they
/// round a decimal result. A NaN, an infinity and a value outside the range of
/// `Int` give `None` and the invalid operation flag: "the invalid operation
/// exception shall be signaled". With `exact=true` this is
/// convertToIntegerExact, which also signals inexact when the result differs
/// from the operand. The result of a negative value that rounds to zero is 0.
pub fn Decimal::to_int_ctx(
  self : Decimal,
  ctx : DecimalContext,
  exact~ : Bool = false,
) -> (Int32?, DecimalFlags) {
  let (parts, flags) = decimal_to_integer_parts(
    self, ctx, exact, 0x80000000UL, 0x7FFFFFFFUL,
  )
  match parts {
    Some((negative, magnitude)) => {
      let value = magnitude.reinterpret_as_int64()
      (Some((if negative { -value } else { value }).to_int()), flags)
    }
    None => (None, flags)
  }
}

///|
/// convertToInteger to `Int64`; see `to_int_ctx`.
pub fn Decimal::to_int64_ctx(
  self : Decimal,
  ctx : DecimalContext,
  exact~ : Bool = false,
) -> (Int64?, DecimalFlags) {
  let (parts, flags) = decimal_to_integer_parts(
    self, ctx, exact, 0x8000000000000000UL, 0x7FFFFFFFFFFFFFFFUL,
  )
  match parts {
    // Two's complement negation maps 2^63 onto the Int64 minimum.
    Some((negative, magnitude)) =>
      (
        Some(
          if negative {
            (0UL - magnitude).reinterpret_as_int64()
          } else {
            magnitude.reinterpret_as_int64()
          },
        ),
        flags,
      )
    None => (None, flags)
  }
}

///|
/// convertToInteger to `UInt`; a negative value that rounds to zero gives 0,
/// any other negative value is out of range.
pub fn Decimal::to_uint_ctx(
  self : Decimal,
  ctx : DecimalContext,
  exact~ : Bool = false,
) -> (UInt32?, DecimalFlags) {
  let (parts, flags) = decimal_to_integer_parts(
    self, ctx, exact, 0UL, 0xFFFFFFFFUL,
  )
  (parts.map(fn(parts) { parts.1.to_uint() }), flags)
}

///|
/// convertToInteger to `UInt64`; see `to_uint_ctx`.
pub fn Decimal::to_uint64_ctx(
  self : Decimal,
  ctx : DecimalContext,
  exact~ : Bool = false,
) -> (UInt64?, DecimalFlags) {
  let (parts, flags) = decimal_to_integer_parts(
    self, ctx, exact, 0UL, 0xFFFFFFFFFFFFFFFFUL,
  )
  (parts.map(fn(parts) { parts.1 }), flags)
}
