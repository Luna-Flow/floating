///|
// Public unary context application operations.

pub fn Decimal::plus_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (operand, operand_flags) = prepare_operand_for_context(self, ctx)
  let result = match operand.class {
    FpClass::NaN => quiet_nan_operand(operand, ctx)
    FpClass::Infinity =>
      (
        operand.with_precision_round(
          finite_precision_for(bigint_zero(), ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite =>
      if operand.coefficient.is_zero() {
        // plus(x) is add(0, x) with the zero taking x's exponent, so
        // plus(-0) adds zeros of opposite signs: -0 under Floor
        // (roundTowardNegative), else +0.
        normalize_decimal_parts_ctx_repr(
          operand.negative && ctx.decimal_rounding == DecimalRound::Floor,
          operand.coefficient,
          operand.exponent10,
          ctx,
        )
      } else {
        let (value, flags) = normalize_decimal_parts_ctx_repr(
          operand.negative,
          operand.coefficient,
          operand.exponent10,
          ctx,
        )
        (value, flags)
      }
  }
  (result.0, operand_flags.combine(result.1))
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
pub fn Decimal::minus_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (operand, operand_flags) = prepare_operand_for_context(self, ctx)
  let result = match operand.class {
    FpClass::NaN => quiet_nan_operand(operand, ctx)
    FpClass::Finite if operand.coefficient.is_zero() =>
      // minus(x) is subtract(0, x) with the zero taking x's exponent, so
      // minus(+0) subtracts zeros of the same sign: -0 under Floor
      // (roundTowardNegative), else +0; minus(-0) is 0 + 0 = +0.
      normalize_decimal_parts_ctx_repr(
        !operand.negative && ctx.decimal_rounding == DecimalRound::Floor,
        operand.coefficient,
        operand.exponent10,
        ctx,
      )
    _ => operand.neg().plus_ctx(ctx)
  }
  (result.0, operand_flags.combine(result.1))
}

///|
pub fn Decimal::abs_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (operand, operand_flags) = prepare_operand_for_context(self, ctx)
  let result = match operand.class {
    FpClass::NaN => quiet_nan_operand(operand, ctx)
    _ => operand.abs().plus_ctx(ctx)
  }
  (result.0, operand_flags.combine(result.1))
}
