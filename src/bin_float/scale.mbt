///|
/// IEEE 754 scaleB: `self * 2^n` rounded once under `context`, with the usual
/// overflow, underflow, and subnormal handling.
pub fn BinFloat::scaleb_ctx(
  self : BinFloat,
  n : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.class {
    FpClass::NaN =>
      (
        binary_quiet_nan(self, context.precision),
        if self.signaling_nan {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      )
    FpClass::Infinity => (self, BinaryFlags::new())
    FpClass::Finite =>
      if self.coefficient_.is_zero() {
        (finite_zero(self.negative, context.precision), BinaryFlags::new())
      } else {
        binary_round_dyadic(
          self.negative,
          self.coefficient_,
          binary_add_sat(self.exponent2, n),
          context,
        )
      }
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
  match self.class {
    FpClass::NaN =>
      (
        binary_quiet_nan(self, context.precision),
        if self.signaling_nan {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      )
    FpClass::Infinity =>
      (
        BinFloat::inf(Sign::Positive, precision=context.precision),
        BinaryFlags::new(),
      )
    FpClass::Finite =>
      if self.coefficient_.is_zero() {
        (
          BinFloat::inf(Sign::Negative, precision=context.precision),
          binary_division_by_zero_flags(),
        )
      } else {
        // An Int needs at most 32 bits, so the result is exact.
        (
          BinFloat::from_int(
            binary_exact_top(self.coefficient_, self.exponent2),
            precision=Int::max(context.precision, 32),
          ),
          BinaryFlags::new(),
        )
      }
  }
}
