///|
// Public context-aware mathematical operations.

pub fn Decimal::log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_log10_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  match self.class {
    FpClass::NaN => Ok(quiet_nan_operand(self, ctx))
    FpClass::Infinity =>
      Ok(
        if self.negative {
          (Decimal::nan(precision~), invalid_flags())
        } else {
          (Decimal::inf(precision~), DecimalFlags::new())
        },
      )
    // IEEE 754-2019 §9.2.1: log(±0) is -inf and signals divideByZero.
    FpClass::Finite if self.coefficient.is_zero() =>
      Ok(decimal_elementary_division_by_zero(Sign::Negative, ctx))
    FpClass::Finite if self.negative =>
      Ok((Decimal::nan(precision~), invalid_flags()))
    FpClass::Finite if dec_coeff_compare_repr(
        remove_factor10_repr(self.coefficient, 0).0,
        dec_coeff_from_int(1),
      ) ==
      0 => Ok(logb_finite_result_ctx(adjusted_exponent(self), ctx))
    FpClass::Finite => decimal_certified_log10_result(self, ctx)
  }
}

///|
pub fn Decimal::exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_exp_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
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
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  match self.class {
    FpClass::NaN => Ok(quiet_nan_operand(self, ctx))
    FpClass::Infinity =>
      Ok(
        if self.negative {
          (Decimal::zero(precision~), DecimalFlags::new())
        } else {
          (Decimal::inf(precision~), DecimalFlags::new())
        },
      )
    FpClass::Finite if self.coefficient.is_zero() =>
      Ok((Decimal::one(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_exp_result(self, ctx)
  }
}

///|
pub fn Decimal::ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_ln_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  match self.class {
    FpClass::NaN => Ok(quiet_nan_operand(self, ctx))
    FpClass::Infinity =>
      Ok(
        if self.negative {
          (Decimal::nan(precision~), invalid_flags())
        } else {
          (Decimal::inf(precision~), DecimalFlags::new())
        },
      )
    // IEEE 754-2019 §9.2.1: log(±0) is -inf and signals divideByZero.
    FpClass::Finite if self.coefficient.is_zero() =>
      Ok(decimal_elementary_division_by_zero(Sign::Negative, ctx))
    FpClass::Finite if self.negative =>
      Ok((Decimal::nan(precision~), invalid_flags()))
    FpClass::Finite if is_finite_decimal_one(self) =>
      Ok((Decimal::zero(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_ln_result(self, ctx)
  }
}

///|
pub fn Decimal::pow_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_pow_ctx(exponent, ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_pow_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if gda_context_is_restricted(ctx) {
    return Ok(invalid_context_result(ctx))
  }
  let half = finite_with_exponent_repr(false, dec_coeff_from_int(5), -1, 1)
  if self.class == FpClass::Finite &&
    !self.negative &&
    exponent.class == FpClass::Finite &&
    exponent.compare(half) == 0 {
    let square_root = self.sqrt_ctx(ctx)
    return Ok(square_root)
  }
  match decimal_power_integer_is_odd(exponent) {
    Some(odd) =>
      if decimal_power_gda_integer_count(exponent) is None &&
        self.class == FpClass::Finite &&
        !self.coefficient.is_zero() &&
        !is_finite_decimal_one(self) &&
        !is_finite_decimal_negative_one(self) {
        // decNumber's GDA compatibility count is smaller than the native
        // machine count.  Keep ordinary large integer exponents on the
        // bounded square-and-multiply path instead of sending them through
        // the much more expensive non-integral certification route.
        match decimal_power_machine_integer_count(exponent) {
          Some(count) =>
            if count != 0 {
              let (value, flags) = decimal_power_integer_finite_result(
                self, count, ctx,
              )
              return Ok((value, flags))
            }
          None => ()
        }
        if decimal_power_integer_expansion_exceeds_limit(exponent) {
          match
            decimal_power_huge_integer_exponent_result(self, exponent, odd, ctx) {
            Some(result) => return Ok(result)
            None => ()
          }
          return Ok(
            (
              Decimal::nan(
                precision=finite_precision_for_coeff(dec_coeff_from_int(1), ctx),
              ),
              { ..DecimalFlags::new(), invalid_operation: true, },
            ),
          )
        }
        match decimal_power_large_integer_coeff_result(self, exponent, ctx) {
          Some(result) => return Ok(result)
          None => ()
        }
        match decimal_power_large_integer_result(self, exponent, odd, ctx) {
          Some(result) => return result
          None => ()
        }
      }
    None => ()
  }
  let is_positive_noninteger = self.class == FpClass::Finite &&
    !self.negative &&
    !self.coefficient.is_zero() &&
    exponent.class == FpClass::Finite &&
    decimal_power_integer_is_odd(exponent) is None &&
    decimal_power_gda_integer_count(exponent) is None
  if is_positive_noninteger {
    let handled_before_certification = decimal_power_simple_ten_result(
        self, exponent, ctx,
      )
      is Some(_) ||
      decimal_power_exact_ten_result(self, exponent, ctx) is Some(_) ||
      decimal_power_of_ten_extreme_result(self, exponent, ctx) is Some(_) ||
      decimal_power_finite_noninteger_operand_range_result(self, exponent, ctx)
      is Some(_) ||
      decimal_power_one_finite_exponent_result(self, exponent, ctx) is Some(_)
    if !handled_before_certification {
      if math_context_is_restricted(ctx) {
        return Ok(invalid_context_result(ctx))
      }
      match decimal_power_adjacent_one_directed_result(self, exponent, ctx) {
        Some(result) => {
          let finalized = result
          return Ok(finalized)
        }
        None => ()
      }
      return decimal_certified_power_result(self, exponent, ctx).map(fn(
        result,
      ) {
        let finalized = result
        let finalized = if decimal_exact_cohort_adjustable(finalized, ctx) {
          match decimal_power_preferred_exponent(self.exponent10, exponent) {
            Some(preferred) =>
              decimal_power_adjust_exact_cohort(finalized, preferred, ctx)
            None => finalized
          }
        } else {
          finalized
        }
        finalized
      })
    }
  }
  let (result, flags) = self.power_ctx_impl(exponent, ctx)
  Ok((result, flags))
}

///|
fn Decimal::power_ctx_impl(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match decimal_power_ieee_special_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match decimal_power_simple_ten_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match decimal_power_exact_ten_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match decimal_power_of_ten_extreme_result(self, exponent, ctx) {
    Some(result) => return result
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
  if decimal_power_integer_is_odd(exponent) is None &&
    math_context_is_restricted(ctx) {
    return invalid_context_result(ctx)
  }
  match decimal_power_one_finite_exponent_result(self, exponent, ctx) {
    Some(result) => return result
    None => ()
  }
  match decimal_power_positive_noninteger_result(self, exponent, ctx) {
    Some(result) => return result
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
        (Decimal::inf(negative=true, precision~), DecimalFlags::new())
      } else {
        (Decimal::inf(precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        if count == 0 {
          return (Decimal::nan(precision~), invalid_flags())
        }
        let negative = self.negative && (abs_int(count) & 1) == 1
        if count < 0 {
          decimal_elementary_division_by_zero(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            ctx,
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
