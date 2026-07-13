///|
// Public context-aware mathematical operations.

pub fn Decimal::log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return (
      Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
      invalid_flags(),
    )
  }
  if math_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  if decimal_math_operand_out_of_range(self) {
    return (
      Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
      invalid_flags(),
    )
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => quiet_nan_operand(value, ctx)
    FpClass::Infinity =>
      if value.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if value.coefficient.is_zero() {
        if ctx.extended {
          (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
        } else {
          (Decimal::nan(precision~), invalid_flags())
        }
      } else if value.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else if dec_coeff_compare_repr(
          remove_factor10_repr(value.coefficient, 0).0,
          dec_coeff_from_int(1),
        ) ==
        0 {
        logb_finite_result_ctx(adjusted_exponent(value), ctx)
      } else {
        decimal_log10_positive_finite_result(value, ctx)
      }
  }
  (result.0, operand_flags.combine(result.1))
}

///|
pub fn Decimal::exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if math_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  if decimal_math_operand_out_of_range(self) {
    return (
      Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
      invalid_flags(),
    )
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => quiet_nan_operand(value, ctx)
    FpClass::Infinity =>
      if value.negative {
        (Decimal::zero(precision~), DecimalFlags::new())
      } else {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if value.coefficient.is_zero() {
        Decimal::one(precision~).plus_ctx(ctx)
      } else {
        match decimal_exp_extreme_half_even_result(value, ctx) {
          Some(result) => result
          None => decimal_exp_finite_result(value, ctx)
        }
      }
  }
  (result.0, operand_flags.combine(result.1))
}

///|
pub fn Decimal::ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return (
      Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
      invalid_flags(),
    )
  }
  if math_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  if decimal_math_operand_out_of_range(self) {
    return (
      Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
      invalid_flags(),
    )
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => quiet_nan_operand(value, ctx)
    FpClass::Infinity =>
      if value.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if value.coefficient.is_zero() {
        if ctx.extended {
          (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
        } else {
          (Decimal::nan(precision~), invalid_flags())
        }
      } else if value.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else if is_finite_decimal_one(value) {
        (Decimal::zero(precision~), DecimalFlags::new())
      } else {
        decimal_ln_positive_finite_result(value, ctx)
      }
  }
  (result.0, operand_flags.combine(result.1))
}

///|
pub fn Decimal::power_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if gda_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  let (base, rounded_exponent, operand_flags) = prepare_binary_operands_for_context(
    self, exponent, ctx,
  )
  let (result, flags) = base.power_ctx_impl(rounded_exponent, ctx)
  (result, operand_flags.combine(flags))
}

///|
fn Decimal::power_ctx_impl(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match decimal_power_simple_ten_result(self, exponent, ctx) {
    Some(result) => return decimal_power_finalize_result(result, ctx)
    None => ()
  }
  match decimal_power_exact_ten_result(self, exponent, ctx) {
    Some(result) => return decimal_power_finalize_result(result, ctx)
    None => ()
  }
  match decimal_power_of_ten_extreme_result(self, exponent, ctx) {
    Some(result) => return decimal_power_finalize_result(result, ctx)
    None => ()
  }
  match quiet_nan_pair(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  let precision = finite_precision_for_coeff(dec_coeff_from_int(1), ctx)
  match decimal_power_infinite_exponent_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match
    decimal_power_infinite_base_noninteger_result(self, exponent, precision) {
    Some(result) => return result
    None => ()
  }
  match
    decimal_power_finite_noninteger_operand_range_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match decimal_power_finite_noninteger_domain_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  if decimal_power_gda_integer_count(exponent) is None &&
    math_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  match decimal_power_one_finite_exponent_result(self, exponent, ctx) {
    Some(result) => return decimal_power_finalize_result(result, ctx)
    None => ()
  }
  if decimal_power_positive_integer_restricted(exponent) &&
    (ctx.precision > 999_999 || ctx.e_max > 999_999 || ctx.e_min < -999_999) {
    return invalid_context_result(ctx)
  }
  match decimal_power_positive_noninteger_result(self, exponent, ctx) {
    Some(result) => return decimal_power_finalize_result(result, ctx)
    None => ()
  }
  if decimal_power_operand_out_of_range(exponent) {
    return (Decimal::nan(precision~), invalid_flags())
  }
  match decimal_power_integer_is_odd(exponent) {
    Some(odd) =>
      if is_finite_decimal_one(self) {
        return Decimal::one(precision~).plus_ctx(ctx)
      } else if is_finite_decimal_negative_one(self) {
        return (
          finite_with_exponent_repr(odd, dec_coeff_from_int(1), 0, precision),
          DecimalFlags::new(),
        )
      }
    None => ()
  }
  let count = match decimal_power_gda_integer_count(exponent) {
    Some(value) => value
    None => return (Decimal::nan(precision~), invalid_flags())
  }
  match self.class {
    FpClass::NaN =>
      // Covered by quiet_nan_pair; keep the match total if the enum grows.
      (Decimal::nan(precision~), invalid_flags())
    FpClass::Infinity =>
      if count == 0 {
        (Decimal::one(precision~), DecimalFlags::new())
      } else if count < 0 {
        let negative = self.negative && (-count & 1) == 1
        (
          finite_with_exponent_repr(negative, dec_coeff_zero(), 0, precision),
          DecimalFlags::new(),
        )
      } else if self.negative && (count & 1) == 1 {
        (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
      } else {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        if count == 0 {
          if !ctx.extended {
            return (Decimal::one(precision~), DecimalFlags::new())
          }
          return (Decimal::nan(precision~), invalid_flags())
        }
        let negative = self.negative && (abs_int(count) & 1) == 1
        if count < 0 {
          if !ctx.extended {
            return (Decimal::nan(precision~), invalid_flags())
          }
          (
            Decimal::inf(
              if negative {
                Sign::Negative
              } else {
                Sign::Positive
              },
              precision~,
            ),
            DecimalFlags::new(),
          )
        } else {
          (
            finite_with_exponent_repr(negative, dec_coeff_zero(), 0, precision),
            DecimalFlags::new(),
          )
        }
      } else if count == 0 {
        Decimal::one(precision~).plus_ctx(ctx)
      } else {
        decimal_power_integer_finite_result(self, count, ctx)
      }
  }
}
