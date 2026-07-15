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
        operand.with_precision(
          finite_precision_for(bigint_zero(), ctx),
          ctx.rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite =>
      if operand.coefficient.is_zero() {
        if !ctx.extended {
          (
            Decimal::zero(precision=finite_precision_for(bigint_zero(), ctx)),
            DecimalFlags::new(),
          )
        } else {
          normalize_decimal_parts_ctx_repr(
            false,
            operand.coefficient,
            operand.exponent10,
            ctx,
          )
        }
      } else {
        let (value, flags) = normalize_decimal_parts_ctx_repr(
          operand.negative,
          operand.coefficient,
          operand.exponent10,
          ctx,
        )
        finish_context_result(value, flags, ctx, false)
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
        self.with_precision(
          finite_precision_for(bigint_zero(), ctx),
          ctx.rounding,
        ),
        DecimalFlags::new(),
      )
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        if !ctx.extended {
          return (
            Decimal::zero(precision=finite_precision_for(bigint_zero(), ctx)),
            DecimalFlags::new(),
          )
        }
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
      if !ctx.extended {
        (
          Decimal::zero(precision=finite_precision_for(bigint_zero(), ctx)),
          DecimalFlags::new(),
        )
      } else {
        normalize_decimal_parts_ctx_repr(
          false,
          operand.coefficient,
          operand.exponent10,
          ctx,
        )
      }
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
    _ => operand.copy_abs().plus_ctx(ctx)
  }
  (result.0, operand_flags.combine(result.1))
}
