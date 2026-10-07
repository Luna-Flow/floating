///|
/// Rounds to an integer in the context's direction and returns its sign and
/// magnitude when the magnitude is at most `negative_limit` (negative values)
/// or `positive_limit` (positive values). NaN, infinities, and out-of-range
/// results give `None` with invalid; `exact` adds inexact for a changed value.
fn binary_to_integer_parts(
  value : BinFloat,
  context : BinaryContext,
  exact : Bool,
  negative_limit : UInt64,
  positive_limit : UInt64,
) -> ((Bool, UInt64)?, BinaryFlags) {
  guard value.class == FpClass::Finite else {
    return (None, binary_invalid_flags())
  }
  let (integral, changed) = binary_round_to_integral(value, context.rounding)
  let magnitude = if integral.coefficient_.is_zero() {
    Some(0UL)
  } else if integral.exponent2 + integral.coefficient_.bit_length() > 64 {
    None
  } else {
    integral.coefficient_.shift_left(integral.exponent2).to_uint64()
  }
  let limit = if integral.negative { negative_limit } else { positive_limit }
  match magnitude {
    Some(magnitude) if magnitude <= limit =>
      (
        Some((integral.negative && magnitude != 0UL, magnitude)),
        if exact && changed {
          binary_inexact_flags(false)
        } else {
          BinaryFlags::new()
        },
      )
    _ => (None, binary_invalid_flags())
  }
}

///|
/// IEEE 754 convertToInteger to `Int` in the context's rounding direction.
/// With `exact=true` this is convertToIntegerExact, which also raises
/// inexact when rounding changed the value.
pub fn BinFloat::to_int_ctx(
  self : BinFloat,
  context : BinaryContext,
  exact? : Bool = false,
) -> (Int?, BinaryFlags) {
  let (parts, flags) = binary_to_integer_parts(
    self, context, exact, 0x80000000UL, 0x7FFFFFFFUL,
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
pub fn BinFloat::to_int64_ctx(
  self : BinFloat,
  context : BinaryContext,
  exact? : Bool = false,
) -> (Int64?, BinaryFlags) {
  let (parts, flags) = binary_to_integer_parts(
    self, context, exact, 0x8000000000000000UL, 0x7FFFFFFFFFFFFFFFUL,
  )
  match parts {
    // Two's complement negation maps 2^63 onto Int64 minimum.
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
/// convertToInteger to `UInt`; negative values that round to zero give 0.
pub fn BinFloat::to_uint_ctx(
  self : BinFloat,
  context : BinaryContext,
  exact? : Bool = false,
) -> (UInt?, BinaryFlags) {
  let (parts, flags) = binary_to_integer_parts(
    self, context, exact, 0UL, 0xFFFFFFFFUL,
  )
  (parts.map(fn(parts) { parts.1.to_uint() }), flags)
}

///|
/// convertToInteger to `UInt64`; negative values that round to zero give 0.
pub fn BinFloat::to_uint64_ctx(
  self : BinFloat,
  context : BinaryContext,
  exact? : Bool = false,
) -> (UInt64?, BinaryFlags) {
  let (parts, flags) = binary_to_integer_parts(
    self, context, exact, 0UL, 0xFFFFFFFFFFFFFFFFUL,
  )
  (parts.map(fn(parts) { parts.1 }), flags)
}
