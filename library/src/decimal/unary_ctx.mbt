///|
// Public unary context application operations.

fn Decimal::plus_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision_round(
          finite_precision_for(bigint_zero(), ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        // plus(x) is add(0, x) with the zero taking x's exponent, so
        // plus(-0) adds zeros of opposite signs: -0 under Floor
        // (roundTowardNegative), else +0.
        normalize_decimal_parts_ctx_repr(
          self.negative && ctx.decimal_rounding == DecimalRound::Floor,
          self.coefficient,
          self.exponent10,
          ctx,
        )
      } else {
        let (value, flags) = normalize_decimal_parts_ctx_repr(
          self.negative,
          self.coefficient,
          self.exponent10,
          ctx,
        )
        (value, flags)
      }
  }
}

///|
pub fn Decimal::apply_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      (
        self.with_precision_round(
          finite_precision_for(bigint_zero(), ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        return normalize_decimal_parts_ctx_repr(
          self.negative,
          self.coefficient,
          self.exponent10,
          ctx,
        )
      }
      let (value, flags) = normalize_decimal_parts_ctx_repr(
        self.negative,
        self.coefficient,
        self.exponent10,
        ctx,
      )
      (value, flags)
    }
  }
}

///|
pub fn Decimal::abs_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    _ => self.abs().plus_ctx(ctx)
  }
}
