///|
// Public context-aware mathematical operations.

pub fn Decimal::log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_log10_ctx(ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal log10 evaluation failed")
  }
}

///|
pub fn Decimal::try_log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return Ok(
      (
        Decimal::nan(
          precision=finite_precision_for_coeff(gda_coeff_zero(), ctx),
        ),
        invalid_flags(),
      ),
    )
  }
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::nan(precision~), invalid_flags())
        } else {
          (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok(
        if ctx.extended {
          (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
        } else {
          (Decimal::nan(precision~), invalid_flags())
        },
      )
    FpClass::Finite if value.negative =>
      Ok((Decimal::nan(precision~), invalid_flags()))
    FpClass::Finite if gda_coeff_compare_repr(
        remove_factor10_repr(value.coefficient, 0).0,
        gda_coeff_from_int(1),
      ) ==
      0 => Ok(logb_finite_result_ctx(adjusted_exponent(value), ctx))
    FpClass::Finite => decimal_certified_log10_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
pub fn Decimal::exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_exp_ctx(ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal exp evaluation failed")
  }
}

///|
pub fn Decimal::try_exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::zero(precision~), DecimalFlags::new())
        } else {
          (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok((Decimal::one(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_exp_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
pub fn Decimal::ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_ln_ctx(ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal ln evaluation failed")
  }
}

///|
pub fn Decimal::try_ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return Ok(
      (
        Decimal::nan(
          precision=finite_precision_for_coeff(gda_coeff_zero(), ctx),
        ),
        invalid_flags(),
      ),
    )
  }
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::nan(precision~), invalid_flags())
        } else {
          (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok(
        if ctx.extended {
          (Decimal::inf(Sign::Negative, precision~), DecimalFlags::new())
        } else {
          (Decimal::nan(precision~), invalid_flags())
        },
      )
    FpClass::Finite if value.negative =>
      Ok((Decimal::nan(precision~), invalid_flags()))
    FpClass::Finite if is_finite_decimal_one(value) =>
      Ok((Decimal::zero(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_ln_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
pub fn Decimal::power_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_power_ctx(exponent, ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal power evaluation failed")
  }
}

///|
pub fn Decimal::try_power_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if gda_context_is_restricted(ctx) {
    return Ok(invalid_context_result(ctx))
  }
  let (base, rounded_exponent, operand_flags) = prepare_binary_operands_for_context(
    self, exponent, ctx,
  )
  let half = finite_with_exponent_repr(false, gda_coeff_from_int(5), -1, 1)
  if base.class == FpClass::Finite &&
    !base.negative &&
    rounded_exponent.class == FpClass::Finite &&
    rounded_exponent.compare(half) == 0 {
    if base.coefficient.is_zero() {
      return Ok(
        (
          finite_with_exponent_repr(
            false,
            gda_coeff_zero(),
            0,
            finite_precision_for_coeff(gda_coeff_zero(), ctx),
          ),
          operand_flags,
        ),
      )
    }
    let square_root = decimal_power_noninteger_gda_result(
      base.sqrt_ctx(ctx),
      ctx,
    )
    return Ok((square_root.0, operand_flags.combine(square_root.1)))
  }
  let is_positive_noninteger = base.class == FpClass::Finite &&
    !base.negative &&
    !base.coefficient.is_zero() &&
    rounded_exponent.class == FpClass::Finite &&
    decimal_power_gda_integer_count(rounded_exponent) is None
  if is_positive_noninteger {
    let handled_before_certification = decimal_power_simple_ten_result(
        base, rounded_exponent, ctx,
      )
      is Some(_) ||
      decimal_power_exact_ten_result(base, rounded_exponent, ctx) is Some(_) ||
      decimal_power_of_ten_extreme_result(base, rounded_exponent, ctx)
      is Some(_) ||
      decimal_power_finite_noninteger_operand_range_result(
        base, rounded_exponent, ctx,
      )
      is Some(_) ||
      decimal_power_one_finite_exponent_result(base, rounded_exponent, ctx)
      is Some(_)
    if !handled_before_certification {
      if math_context_is_restricted(ctx) {
        let invalid = invalid_context_result(ctx)
        return Ok((invalid.0, operand_flags.combine(invalid.1)))
      }
      match
        decimal_power_adjacent_one_directed_result(base, rounded_exponent, ctx) {
        Some(result) => {
          let finalized = decimal_power_finalize_result(result, ctx)
          return Ok((finalized.0, operand_flags.combine(finalized.1)))
        }
        None => ()
      }
      return decimal_certified_power_result(base, rounded_exponent, ctx).map(fn(
        result,
      ) {
        let finalized = decimal_power_finalize_result(
          decimal_power_noninteger_gda_result(result, ctx),
          ctx,
        )
        (finalized.0, operand_flags.combine(finalized.1))
      })
    }
  }
  let (result, flags) = base.power_ctx_impl(rounded_exponent, ctx)
  Ok((result, operand_flags.combine(flags)))
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
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
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
          finite_with_exponent_repr(odd, gda_coeff_from_int(1), 0, precision),
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
          finite_with_exponent_repr(negative, gda_coeff_zero(), 0, precision),
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
            finite_with_exponent_repr(negative, gda_coeff_zero(), 0, precision),
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
