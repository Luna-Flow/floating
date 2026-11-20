///|
/// The integer value of the second operand of scaleB as an `Int32`, or `None`
/// when it is not an integer. An integer beyond the `Int32` range is clamped:
/// every finite value then overflows or underflows exactly as it would for the
/// clamped count, because the exponent range of a format is far inside it.
fn scaleb_count(n : BinFloat) -> Int32? {
  let wide = BinaryContext::new(precision=n.precision())
  let (integral, flags) = n.to_integral_exact_ctx(wide)
  guard !flags.inexact else { return None }
  if integral.is_zero() {
    return Some(0)
  }
  if integral.exact_top() >= 31 {
    return Some(if integral.negative() { -2147483647 - 1 } else { 2147483647 })
  }
  integral.to_int_ctx(wide, exact=true).0
}

///|
/// IEEE 754 scaleB: `self * 2^n` rounded once under `context`, with the usual
/// overflow, underflow, and subnormal handling. `n` is the same floating-point
/// kind as `logb_ctx` returns (the `logBFormat` of this library) and must be an
/// integer: a NaN `n` propagates, an infinite or non-integer `n` gives a NaN
/// with `invalid_operation`, as `Decimal::scaleb_ctx` does.
pub fn BinFloat::scaleb_ctx(
  self : BinFloat,
  n : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_nan_pair(self, n, context.precision) {
    Some(result) => return result
    None => ()
  }
  if n.class() == FpClass::Infinity {
    return (
      BinFloat::nan_raw(precision=context.precision),
      binary_invalid_flags(),
    )
  }
  if self.class() == FpClass::Infinity {
    return (self, BinaryFlags::new())
  }
  let count = match scaleb_count(n) {
    Some(count) => count
    None =>
      return (
        BinFloat::nan_raw(precision=context.precision),
        binary_invalid_flags(),
      )
  }
  if self.coefficient_is_zero() {
    (finite_zero(self.negative(), context.precision), BinaryFlags::new())
  } else {
    binary_round_dyadic(
      self.negative(),
      self.coefficient_(),
      binary_add_sat(self.exponent2_(), count),
      context,
    )
  }
}

///|
/// IEEE 754 logB: the exponent of the leading bit, `floor(log2 |self|)`, as an
/// integral value. logB(0) is -inf with division-by-zero, logB(inf) is +inf,
/// and NaN propagates.
pub fn BinFloat::logb_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.class() {
    FpClass::NaN =>
      (
        binary_quiet_nan(self, context.precision),
        if self.signaling() {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      )
    FpClass::Infinity =>
      (
        BinFloat::inf_raw(Sign::Positive, precision=context.precision),
        BinaryFlags::new(),
      )
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        (
          BinFloat::inf_raw(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        )
      } else {
        // An Int needs at most 32 bits, so the result is exact.
        (
          BinFloat::from_int_raw(
            self.exact_top(),
            precision=Int32::max(context.precision, 32),
          ),
          BinaryFlags::new(),
        )
      }
  }
}
