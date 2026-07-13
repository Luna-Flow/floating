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
priv enum DecimalExtremaOp {
  Minimum
  Maximum
  MinimumMagnitude
  MaximumMagnitude
}

///|
fn decimal_extrema_ctx(
  lhs0 : Decimal,
  rhs0 : Decimal,
  ctx : DecimalContext,
  op : DecimalExtremaOp,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    lhs0, rhs0, ctx,
  )
  match decimal_minmax_nan_result(lhs, rhs, ctx) {
    Some((value, flags)) => return (value, operand_flags.combine(flags))
    None => ()
  }
  let magnitude = match op {
    MinimumMagnitude | MaximumMagnitude => true
    Minimum | Maximum => false
  }
  let cmp = if magnitude {
    lhs.copy_abs().compare(rhs.copy_abs())
  } else {
    lhs.compare(rhs)
  }
  let select_minimum = match op {
    Minimum | MinimumMagnitude => true
    Maximum | MaximumMagnitude => false
  }
  let selected = if cmp == 0 && !ctx.extended {
    lhs
  } else if cmp < 0 {
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
fn decimal_minmax_nan_result(
  lhs : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  if lhs.is_signaling_nan() || other.is_signaling_nan() {
    if lhs.is_signaling_nan() {
      return Some(quiet_nan_operand(lhs, ctx))
    }
    return Some(quiet_nan_operand(other, ctx))
  }
  if lhs.is_nan() && other.is_nan() {
    return Some(quiet_nan_operand(lhs, ctx))
  }
  if lhs.is_nan() {
    let (value, flags) = decimal_selected_extrema_result(other, ctx)
    return Some((value, flags))
  }
  if other.is_nan() {
    let (value, flags) = decimal_selected_extrema_result(lhs, ctx)
    return Some((value, flags))
  }
  None
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
            { ..flags, invalid_operation: true }
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
          { ..flags, invalid_operation: true }
        } else {
          flags
        },
      ),
    )
  }
  let cmp = if magnitude {
    lhs.copy_abs().compare(rhs.copy_abs())
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
pub fn Decimal::min_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_extrema_ctx(self, other, ctx, Minimum)
}

///|
pub fn Decimal::max_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_extrema_ctx(self, other, ctx, Maximum)
}

///|
pub fn Decimal::min_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_extrema_ctx(self, other, ctx, MinimumMagnitude)
}

///|
pub fn Decimal::max_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_extrema_ctx(self, other, ctx, MaximumMagnitude)
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

///|
pub fn Decimal::minimum_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.minimum_magnitude_ctx(other, ctx)
}

///|
pub fn Decimal::minimum_number_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.minimum_number_magnitude_ctx(other, ctx)
}

///|
pub fn Decimal::maximum_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.maximum_magnitude_ctx(other, ctx)
}

///|
pub fn Decimal::maximum_number_mag_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.maximum_number_magnitude_ctx(other, ctx)
}
