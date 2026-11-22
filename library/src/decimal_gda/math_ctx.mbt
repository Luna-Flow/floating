///|
/// Total form of a certified evaluation that could not be completed: a quiet
/// NaN with `invalid_operation`, so GDA status and traps apply as for any other
/// invalid result. The `try_*` operations expose the failure detail.
fn decimal_certification_invalid(
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  (
    Decimal::nan_raw(precision=finite_precision_for_default(ctx)),
    invalid_flags(),
  )
}

///|
// Public context-aware mathematical operations.

fn Decimal::log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_log10_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_certification_invalid(ctx)
  }
}

///|
fn Decimal::try_log10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return Ok(
      (
        Decimal::nan_raw(
          precision=finite_precision_for_coeff(dec_coeff_zero(), ctx),
        ),
        invalid_flags(),
      ),
    )
  }
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::nan_raw(precision~), invalid_flags())
        } else {
          (
            Decimal::inf_with_sign(Sign::Positive, precision~),
            DecimalFlags::new(),
          )
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok(
        if ctx.extended {
          (
            Decimal::inf_with_sign(Sign::Negative, precision~),
            DecimalFlags::new(),
          )
        } else {
          (Decimal::nan_raw(precision~), invalid_flags())
        },
      )
    FpClass::Finite if value.negative =>
      Ok((Decimal::nan_raw(precision~), invalid_flags()))
    FpClass::Finite if dec_coeff_compare_repr(
        remove_factor10_repr(value.coefficient, 0).0,
        dec_coeff_from_int(1),
      ) ==
      0 => Ok(logb_finite_result_ctx(adjusted_exponent(value), ctx))
    FpClass::Finite => decimal_certified_log10_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
fn Decimal::exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_exp_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_certification_invalid(ctx)
  }
}

///|
fn Decimal::try_exp_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::zero_raw(precision~), DecimalFlags::new())
        } else {
          (
            Decimal::inf_with_sign(Sign::Positive, precision~),
            DecimalFlags::new(),
          )
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok((Decimal::one_raw(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_exp_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
fn Decimal::ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_ln_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_certification_invalid(ctx)
  }
}

///|
fn Decimal::try_ln_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if !ctx.extended &&
    ctx.precision <= 99_999_999 &&
    self.class == FpClass::Finite &&
    self.coefficient.is_zero() {
    return Ok(
      (
        Decimal::nan_raw(
          precision=finite_precision_for_coeff(dec_coeff_zero(), ctx),
        ),
        invalid_flags(),
      ),
    )
  }
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let result = match value.class {
    FpClass::NaN => Ok(quiet_nan_operand(value, ctx))
    FpClass::Infinity =>
      Ok(
        if value.negative {
          (Decimal::nan_raw(precision~), invalid_flags())
        } else {
          (
            Decimal::inf_with_sign(Sign::Positive, precision~),
            DecimalFlags::new(),
          )
        },
      )
    FpClass::Finite if value.coefficient.is_zero() =>
      Ok(
        if ctx.extended {
          (
            Decimal::inf_with_sign(Sign::Negative, precision~),
            DecimalFlags::new(),
          )
        } else {
          (Decimal::nan_raw(precision~), invalid_flags())
        },
      )
    FpClass::Finite if value.negative =>
      Ok((Decimal::nan_raw(precision~), invalid_flags()))
    FpClass::Finite if is_finite_decimal_one(value) =>
      Ok((Decimal::zero_raw(precision~), DecimalFlags::new()))
    FpClass::Finite => decimal_certified_ln_result(value, ctx)
  }
  result.map(fn(value) { (value.0, operand_flags.combine(value.1)) })
}

///|
fn Decimal::power_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_power_ctx(exponent, ctx) {
    Ok(result) => result
    Err(_) => decimal_certification_invalid(ctx)
  }
}

///|
fn Decimal::try_power_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if gda_context_is_restricted(ctx) {
    return Ok(invalid_context_result(ctx))
  }
  let (prepared_base, prepared_exponent, operand_flags) = prepare_binary_operands_for_context(
    self, exponent, ctx,
  )
  // GDA 1.70, page 55, footnote 45: a positive exponent of an operand is reduced
  // before the operation, so `1.2E+3` and `1200` behave alike (subset only).
  let base = if ctx.extended {
    prepared_base
  } else {
    reduce_positive_exponent_for_subset(prepared_base, ctx)
  }
  let rounded_exponent = if ctx.extended {
    prepared_exponent
  } else {
    reduce_positive_exponent_for_subset(prepared_exponent, ctx)
  }
  let half = finite_with_exponent_repr(false, dec_coeff_from_int(5), -1, 1)
  if base.class == FpClass::Finite &&
    !base.negative &&
    rounded_exponent.class == FpClass::Finite &&
    rounded_exponent.compare(half) == 0 {
    if base.coefficient.is_zero() {
      return Ok(
        (
          finite_with_exponent_repr(
            false,
            dec_coeff_zero(),
            0,
            finite_precision_for_coeff(dec_coeff_zero(), ctx),
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
      // An exactly representable power (4^1.5 = 8) lies on the boundary of
      // its rounding cell in the directed modes, and an exact midpoint does in
      // the half modes, so the certified loop below can never accept it.
      // Decide it exactly first; GDA still reports it as rounded and inexact.
      // A power of ten (a coefficient of 1) has no exact root of a higher
      // order than the digits allow, so `10^(k*y)` is decided separately.
      match decimal_power_ten_noninteger_result(base, rounded_exponent, ctx) {
        Some(result) => {
          let finalized = decimal_power_finalize_result(
            decimal_power_noninteger_gda_result(result, ctx),
            ctx,
          )
          return Ok((finalized.0, operand_flags.combine(finalized.1)))
        }
        None => ()
      }
      match decimal_power_exact_rational_result(base, rounded_exponent, ctx) {
        Some(result) => {
          let finalized = decimal_power_finalize_result(
            decimal_power_noninteger_gda_result(result, ctx),
            ctx,
          )
          return Ok((finalized.0, operand_flags.combine(finalized.1)))
        }
        None => ()
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
  // GDA 1.70, power: "If the right-hand operand is a zero, the result will be
  // 1 and exact." The result is the integer 1 with exponent 0 and no
  // conditions, in every context. decNumber leaves `decNumberPower` here by an
  // early exit before its final rounding and clamping (`decCopyFit`,
  // `decFinish`), and the IEEE interchange encoders fold a result down
  // themselves, at an exponent above 90, 369 or 6111 (decimal32, decimal64,
  // decimal128) that the exponent 0 of `1` never reaches. A context in which
  // the exponent 0 would be folded (`e_max < precision - 1` with `clamp`) has
  // no IEEE format (issue 405).
  if self.class == FpClass::Finite &&
    !self.coefficient.is_zero() &&
    exponent.class == FpClass::Finite &&
    exponent.coefficient.is_zero() {
    let precision = finite_precision_for_coeff(dec_coeff_from_int(1), ctx)
    return (Decimal::one_raw(precision~), DecimalFlags::new())
  }
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
    return (Decimal::nan_raw(precision~), invalid_flags())
  }
  match decimal_power_integer_is_odd(exponent) {
    Some(odd) =>
      if is_finite_decimal_one(self) || is_finite_decimal_negative_one(self) {
        // Repeated multiplication of `+-1` keeps the cohort of the base: the
        // exponent is `n * q` (clipped to the precision) and the sign follows
        // the parity of `n`.
        return match
          decimal_power_preferred_exponent(self.exponent10, exponent) {
          Some(preferred) =>
            decimal_power_ten_cohort_result(
              self.negative && odd,
              0,
              preferred,
              ctx,
            )
          None => Decimal::one_raw(precision~).plus_ctx(ctx)
        }
      }
    None => ()
  }
  let count = match decimal_power_gda_integer_count(exponent) {
    Some(value) => value
    None => return (Decimal::nan_raw(precision~), invalid_flags())
  }
  match self.class {
    FpClass::NaN =>
      // Covered by quiet_nan_pair; keep the match total if the enum grows.
      (Decimal::nan_raw(precision~), invalid_flags())
    FpClass::Infinity =>
      if count == 0 {
        (Decimal::one_raw(precision~), DecimalFlags::new())
      } else if count < 0 {
        let negative = self.negative && (-count & 1) == 1
        (
          finite_with_exponent_repr(negative, dec_coeff_zero(), 0, precision),
          DecimalFlags::new(),
        )
      } else if self.negative && (count & 1) == 1 {
        (
          Decimal::inf_with_sign(Sign::Negative, precision~),
          DecimalFlags::new(),
        )
      } else {
        (
          Decimal::inf_with_sign(Sign::Positive, precision~),
          DecimalFlags::new(),
        )
      }
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        if count == 0 {
          if !ctx.extended {
            return (Decimal::one_raw(precision~), DecimalFlags::new())
          }
          return (Decimal::nan_raw(precision~), invalid_flags())
        }
        let negative = self.negative && (abs_int(count) & 1) == 1
        if count < 0 {
          if !ctx.extended {
            return (Decimal::nan_raw(precision~), invalid_flags())
          }
          (
            Decimal::inf_with_sign(
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
        Decimal::one_raw(precision~).plus_ctx(ctx)
      } else {
        decimal_power_integer_finite_result(self, count, ctx)
      }
  }
}
