///|
// Public min/max family operations and helpers.

fn decimal_selected_extrema_result(
  selected : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if ctx.extended &&
    selected.class == FpClass::Finite &&
    selected.coefficient.is_zero() {
    return normalize_decimal_parts_ctx_repr(
      selected.negative,
      selected.coefficient,
      selected.exponent10,
      ctx,
    )
  }
  selected.plus_ctx(ctx)
}

///|
fn decimal_ieee_extrema_ctx(
  lhs0 : Decimal,
  rhs0 : Decimal,
  ctx : DecimalContext,
  magnitude : Bool,
  select_minimum : Bool,
  number_variant : Bool,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    lhs0, rhs0, ctx,
  )
  let lhs_nan = lhs.is_nan()
  let rhs_nan = rhs.is_nan()
  if lhs_nan || rhs_nan {
    let has_signaling = lhs.is_signaling_nan() || rhs.is_signaling_nan()
    if number_variant && lhs_nan != rhs_nan {
      let selected = if lhs_nan { rhs } else { lhs }
      let (value, flags) = decimal_selected_extrema_result(selected, ctx)
      return (
        value,
        operand_flags.combine(
          if has_signaling {
            { ..flags, invalid_operation: true, }
          } else {
            flags
          },
        ),
      )
    }
    let selected_nan = if lhs_nan { lhs } else { rhs }
    let (value, flags) = quiet_nan_operand(selected_nan, ctx)
    return (
      value,
      operand_flags.combine(
        if has_signaling {
          { ..flags, invalid_operation: true, }
        } else {
          flags
        },
      ),
    )
  }
  let cmp = if magnitude {
    lhs.abs().compare(rhs.abs())
  } else {
    lhs.compare(rhs)
  }
  let selected = if cmp < 0 {
    if select_minimum {
      lhs
    } else {
      rhs
    }
  } else if cmp > 0 {
    if select_minimum {
      rhs
    } else {
      lhs
    }
  } else {
    let total = lhs.compare_total(rhs)
    if select_minimum {
      if total <= 0 {
        lhs
      } else {
        rhs
      }
    } else if total >= 0 {
      lhs
    } else {
      rhs
    }
  }
  let (value, flags) = decimal_selected_extrema_result(selected, ctx)
  (value, operand_flags.combine(flags))
}

///|
pub fn Decimal::minimum_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, false, true, false)
}

///|
pub fn Decimal::minimum_number_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, false, true, true)
}

///|
pub fn Decimal::maximum_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, false, false, false)
}

///|
pub fn Decimal::maximum_number_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, false, false, true)
}

///|
pub fn Decimal::minimum_magnitude_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, true, true, false)
}

///|
pub fn Decimal::minimum_number_magnitude_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, true, true, true)
}

///|
pub fn Decimal::maximum_magnitude_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, true, false, false)
}

///|
pub fn Decimal::maximum_number_magnitude_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_ieee_extrema_ctx(self, other, ctx, true, false, true)
}
