///|
/// IEEE 754 nextUp in `context`: the least value representable at the
/// context precision and exponent range that compares greater than `self`.
/// The operation is quiet; only a signaling NaN raises invalid. Operands with
/// more bits than the context precision are accepted.
pub fn BinFloat::next_up_ctx(
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
        if self.negative {
          binary_max_finite(true, context)
        } else {
          self
        },
        BinaryFlags::new(),
      )
    FpClass::Finite => {
      // A positive bit below every representable step next to `self`: adding
      // it and rounding upward lands on the next representable value.
      let precision = context.precision.to_int64()
      let floor = context.range_e_min().to_int64() - precision
      let position = if self.coefficient_.is_zero() {
        floor
      } else {
        let top = binary_exact_top(self.coefficient_, self.exponent2).to_int64()
        Int64::min(
          floor,
          Int64::min(self.exponent2.to_int64(), top - precision),
        )
      }
      let step = finite_normalized(
        false,
        BinCoeff::one(),
        (position - 2L).to_int(),
        1,
      )
      let upward = { ..context, rounding: RoundTowardPositive, }
      (self.add_ctx(step, upward).0, BinaryFlags::new())
    }
  }
}

///|
/// IEEE 754 nextDown: `-next_up(-self)`.
pub fn BinFloat::next_down_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let (value, flags) = self.neg().next_up_ctx(context)
  (value.neg(), flags)
}
