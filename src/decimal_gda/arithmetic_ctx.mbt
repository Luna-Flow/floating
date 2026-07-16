///|
// Public arithmetic and sqrt APIs.

pub fn Decimal::add(self : Decimal, other : Decimal) -> Decimal {
  add_decimal_impl(self, other)
}

///|
pub fn Decimal::sub(self : Decimal, other : Decimal) -> Decimal {
  match quiet_nan_pair_plain(self, other) {
    Some(value) => return value
    None => ()
  }
  add_decimal_impl(self, other.neg())
}

///|
fn add_finite_values_ctx(
  lhs_value : Decimal,
  rhs_value : Decimal,
  ctx : DecimalContext,
  allow_shortcuts? : Bool = true,
) -> (Decimal, DecimalFlags) {
  guard lhs_value.class == FpClass::Finite && rhs_value.class == FpClass::Finite else {
    abort("add_finite_ctx expects finite operands")
  }
  if lhs_value.is_zero() && rhs_value.is_zero() {
    let precision = finite_precision_for_default(ctx)
    let negative = if ctx.decimal_rounding == DecimalRoundingMode::Floor {
      lhs_value.negative || rhs_value.negative
    } else {
      lhs_value.negative && rhs_value.negative
    }
    let preferred_zero_exponent = Int::min(
      lhs_value.exponent10,
      rhs_value.exponent10,
    )
    let zero_exponent = if ctx.precision > 0 &&
      preferred_zero_exponent < etiny(ctx) {
      etiny(ctx)
    } else {
      preferred_zero_exponent
    }
    let zero = finite_with_exponent(
      negative,
      bigint_zero(),
      zero_exponent,
      precision,
    )
    let zero_flags = if ctx.precision > 0 &&
      preferred_zero_exponent < etiny(ctx) {
      { ..DecimalFlags::new(), clamped: true }
    } else {
      DecimalFlags::new()
    }
    return finalize_finite_ctx(zero, zero_flags, ctx)
  }
  if lhs_value.is_zero() || rhs_value.is_zero() {
    let zero = if lhs_value.is_zero() { lhs_value } else { rhs_value }
    let nonzero = if lhs_value.is_zero() { rhs_value } else { lhs_value }
    let (base, base_flags) = apply_finite_ctx(nonzero, ctx)
    guard base_flags.has_error() == false &&
      base.class == FpClass::Finite &&
      !base.coefficient.is_zero() else {
      return (base, base_flags)
    }
    let preferred_exponent = if ctx.extended {
      Int::min(zero.exponent10, base.exponent10)
    } else {
      Int::min(base.exponent10, Int::max(0, zero.exponent10))
    }
    if preferred_exponent < base.exponent10 && ctx.precision > 0 {
      let digits = base.coefficient.digits10()
      let wanted_shift = base.exponent10 - preferred_exponent
      if digits + wanted_shift <= ctx.precision {
        let shifted = finite_with_exponent_repr(
          base.negative,
          gda_coeff_shift_power10_repr(base.coefficient, wanted_shift),
          preferred_exponent,
          base.precision_,
        )
        return finalize_finite_ctx(shifted, base_flags, ctx)
      }
      let available_shift = Int::max(0, ctx.precision - digits)
      if ctx.extended {
        let shifted = if available_shift > 0 {
          finite_with_exponent_repr(
            base.negative,
            gda_coeff_shift_power10_repr(base.coefficient, available_shift),
            base.exponent10 - available_shift,
            base.precision_,
          )
        } else {
          base
        }
        return finalize_finite_ctx(
          shifted,
          { ..base_flags, rounded: true },
          ctx,
        )
      }
    }
    return (base, base_flags)
  }
  if ctx.precision > 0 && allow_shortcuts {
    let self_adjusted = adjusted_exponent(lhs_value)
    let other_adjusted = adjusted_exponent(rhs_value)
    let precision = finite_precision_for_default(ctx)
    let (high, high_adjusted, low_adjusted) = if self_adjusted >= other_adjusted {
      (lhs_value, self_adjusted, other_adjusted)
    } else {
      (rhs_value, other_adjusted, self_adjusted)
    }
    let target_exponent = high_adjusted - precision + 1
    let low = if high == lhs_value { rhs_value } else { lhs_value }
    if low_adjusted < target_exponent &&
      ctx.decimal_rounding != DecimalRoundingMode::ZeroFiveUp {
      let (base, base_flags) = apply_finite_ctx(high, ctx)
      if base_flags.overflow {
        return (base, base_flags)
      }
      if base_flags == DecimalFlags::new() &&
        base.class == FpClass::Finite &&
        !base.coefficient.is_zero() &&
        !(low.negative != base.negative &&
        gda_coeff_compare_repr(
          remove_factor10_repr(base.coefficient, 0).0,
          gda_coeff_from_int(1),
        ) ==
        0) {
        return exact_base_small_addend_result(base, target_exponent, low, ctx)
      }
    }
    let can_absorb = low_adjusted < target_exponent - precision
    if can_absorb {
      let preferred_exponent = Int::min(high.exponent10, target_exponent)
      let magnitude = gda_coeff_shift_power10_repr(
        high.coefficient,
        high.exponent10 - preferred_exponent,
      )
      let (base, base_flags) = normalize_decimal_parts_ctx_repr(
        high.negative,
        magnitude,
        preferred_exponent,
        ctx,
      )
      return absorbed_sum_result(high, base, base_flags, low, ctx)
    }
  }
  let target = Int::min(lhs_value.exponent10, rhs_value.exponent10)
  let (exact_negative, exact_magnitude) = decimal_exact_aligned_sum_result(
    lhs_value, rhs_value, target,
  )
  let exact_digits = exact_magnitude.digits10()
  let exact_adjusted = if exact_magnitude.is_zero() {
    0
  } else {
    target + exact_digits - 1
  }
  let negative = if exact_magnitude.is_zero() {
    ctx.decimal_rounding == DecimalRoundingMode::Floor &&
    (lhs_value.negative || rhs_value.negative)
  } else {
    exact_negative
  }
  if !ctx.extended && ctx.precision > 0 {
    let lhs_width = lhs_value.coefficient.digits10() +
      lhs_value.exponent10 -
      target
    let rhs_width = rhs_value.coefficient.digits10() +
      rhs_value.exponent10 -
      target
    let virtual_digits = Int::max(lhs_width, rhs_width)
    let discard = virtual_digits - ctx.precision
    if discard > 0 &&
      virtual_digits > exact_digits &&
      !exact_magnitude.is_zero() {
      let target_digits = exact_digits - discard
      let (magnitude, exponent10, rounded, inexact) = decimal_round_coeff_to_digits_repr(
        exact_magnitude,
        target,
        target_digits,
        exact_negative,
        ctx.decimal_rounding,
      )
      let (magnitude, exponent10) = if virtual_digits > exact_digits &&
        inexact &&
        gda_coeff_compare_repr(
          remove_factor10_repr(magnitude, 0).0,
          gda_coeff_from_int(1),
        ) ==
        0 &&
        magnitude.digits10() < ctx.precision {
        let shift = ctx.precision - magnitude.digits10()
        (gda_coeff_shift_power10_repr(magnitude, shift), exponent10 - shift)
      } else {
        (magnitude, exponent10)
      }
      let (value, flags) = finalize_finite_ctx(
        finite_with_exponent_repr(
          exact_negative,
          magnitude,
          exponent10,
          finite_precision_for_coeff(magnitude, ctx),
        ),
        { ..DecimalFlags::new(), rounded, inexact },
        ctx,
      )
      return (value, flags)
    }
  }
  let zero_target = if exact_magnitude.is_zero() &&
    ctx.precision > 0 &&
    target < etiny(ctx) {
    etiny(ctx)
  } else {
    target
  }
  let (value, flags) = normalize_decimal_parts_ctx_repr(
    negative, exact_magnitude, zero_target, ctx,
  )
  let flags = if exact_magnitude.is_zero() &&
    ctx.precision > 0 &&
    target < etiny(ctx) {
    { ..flags, clamped: true }
  } else {
    flags
  }
  if exact_adjusted < ctx.e_min && flags.inexact {
    (value, { ..flags, subnormal: true, underflow: true })
  } else {
    (value, flags)
  }
}

///|
pub fn Decimal::mul(self : Decimal, other : Decimal) -> Decimal {
  mul_decimal_impl(self, other)
}

///|
pub fn Decimal::add_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  match quiet_nan_pair(lhs, rhs, ctx) {
    Some((value, flags)) => return (value, operand_flags.combine(flags))
    None => ()
  }
  let result = match (lhs.class, rhs.class) {
    (FpClass::Infinity, FpClass::Infinity) if lhs.negative != rhs.negative =>
      (
        Decimal::nan(precision=finite_precision_for_default(ctx)),
        invalid_flags(),
      )
    (FpClass::Infinity, _) =>
      (
        lhs.with_precision(finite_precision_for_default(ctx), ctx.rounding),
        DecimalFlags::new(),
      )
    (_, FpClass::Infinity) =>
      (
        rhs.with_precision(finite_precision_for_default(ctx), ctx.rounding),
        DecimalFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) => add_finite_values_ctx(lhs, rhs, ctx)
    (FpClass::NaN, _) | (_, FpClass::NaN) =>
      // Covered by quiet_nan_pair; keep the match total if the enum grows.
      (
        Decimal::nan(precision=finite_precision_for_default(ctx)),
        invalid_flags(),
      )
  }
  let flags = operand_flags.combine(result.1)
  finish_context_result(result.0, flags, ctx, false)
}

///|
pub fn Decimal::sub_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => return result
    None => ()
  }
  self.add_ctx(other.neg(), ctx)
}

///|
pub fn Decimal::mul_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  let result = lhs.decimal_mul_ctx_impl(rhs, ctx)
  let flags = operand_flags.combine(result.1)
  finish_context_result(result.0, flags, ctx, false)
}

///|
fn Decimal::decimal_mul_ctx_impl(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => return result
    None => ()
  }
  match (self.class, other.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) =>
      (
        Decimal::nan(precision=finite_precision_for_default(ctx)),
        nan_operand_flags(self, other),
      )
    (FpClass::Infinity, FpClass::Finite)
    | (FpClass::Finite, FpClass::Infinity) =>
      if self.is_zero() || other.is_zero() {
        (
          Decimal::nan(precision=finite_precision_for_default(ctx)),
          invalid_flags(),
        )
      } else {
        (
          Decimal::inf(
            if self.negative == other.negative {
              Sign::Positive
            } else {
              Sign::Negative
            },
            precision=finite_precision_for_default(ctx),
          ),
          DecimalFlags::new(),
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      (
        Decimal::inf(
          if self.negative == other.negative {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision=finite_precision_for_default(ctx),
        ),
        DecimalFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) if self.is_zero() || other.is_zero() =>
      finalize_finite_ctx(
        finite_with_exponent_repr(
          self.negative != other.negative,
          gda_coeff_zero(),
          self.exponent10 + other.exponent10,
          finite_precision_for_default(ctx),
        ),
        DecimalFlags::new(),
        ctx,
      )
    (FpClass::Finite, FpClass::Finite) => {
      let exact = gda_coeff_multiply_repr(self.coefficient, other.coefficient)
      normalize_decimal_parts_ctx_repr(
        self.negative != other.negative,
        exact,
        self.exponent10 + other.exponent10,
        ctx,
      )
    }
  }
}

///|
pub fn Decimal::div_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  let result = lhs.decimal_div_ctx_impl(rhs, ctx)
  let flags = operand_flags.combine(result.1)
  finish_context_result(result.0, flags, ctx, true)
}

///|
fn gda_exact_small_division_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard gda_coeff_small_value(dividend.coefficient) is Some(numerator) &&
    gda_coeff_small_value(divisor.coefficient) is Some(denominator) &&
    denominator != 0UL &&
    numerator % denominator == 0UL else {
    return None
  }
  let quotient = GdaCoeff::Small(numerator / denominator)
  let precision = finite_precision_for_default(ctx)
  let negative = dividend.negative != divisor.negative
  let preferred_exponent = dividend.exponent10 - divisor.exponent10
  let exact_unrounded = normalize_decimal_parts_gda_repr(
    negative,
    quotient,
    preferred_exponent,
    quotient.digits10(),
    ctx.decimal_rounding,
  )
  let exact_rounding = exact_result_rounding_flags(
    exact_unrounded, preferred_exponent, ctx,
  )
  let rounded_value = normalize_decimal_parts_gda_repr(
    negative,
    quotient,
    preferred_exponent,
    precision,
    ctx.decimal_rounding,
  )
  if exact_rounding.rounded {
    let prefinal = if exact_unrounded.exponent10 < etiny(ctx) {
      exact_unrounded
    } else if !exact_rounding.inexact {
      expand_rounded_exact_cohort_toward_preferred_exponent(
        rounded_value, preferred_exponent, ctx,
      )
    } else {
      expand_inexact_division_cohort(rounded_value, ctx, pad_precision=true)
    }
    let (value, flags) = finalize_finite_ctx(prefinal, exact_rounding, ctx)
    Some((value, with_underflow_for_inexact_subnormal(value, flags, ctx)))
  } else {
    let exact_value = expand_exact_cohort_toward_preferred_exponent(
      rounded_value, preferred_exponent, ctx,
    )
    Some(finalize_finite_ctx(exact_value, DecimalFlags::new(), ctx))
  }
}

///|
fn Decimal::decimal_div_ctx_impl(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_default(ctx)
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => return result
    None => ()
  }
  match (self.class, other.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) =>
      (Decimal::nan(precision~), nan_operand_flags(self, other))
    (_, FpClass::Finite) if other.is_zero() =>
      if self.class == FpClass::Infinity {
        (
          Decimal::inf(
            if self.negative == other.negative {
              Sign::Positive
            } else {
              Sign::Negative
            },
            precision~,
          ),
          DecimalFlags::new(),
        )
      } else if self.is_zero() {
        (Decimal::nan(precision~), div_zero_flags(true))
      } else {
        (
          Decimal::inf(
            if self.negative == other.negative {
              Sign::Positive
            } else {
              Sign::Negative
            },
            precision~,
          ),
          div_zero_flags(false),
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      (Decimal::nan(precision~), invalid_flags())
    (FpClass::Infinity, _) =>
      (
        Decimal::inf(
          if self.negative == other.negative {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision~,
        ),
        DecimalFlags::new(),
      )
    (_, FpClass::Infinity) =>
      (
        finite_with_exponent(
          self.negative != other.negative,
          bigint_zero(),
          etiny(ctx),
          precision,
        ),
        { ..DecimalFlags::new(), clamped: true },
      )
    (FpClass::Finite, FpClass::Finite) if self.is_zero() =>
      finalize_finite_ctx(
        finite_with_exponent(
          self.negative != other.negative,
          bigint_zero(),
          self.exponent10 - other.exponent10,
          precision,
        ),
        DecimalFlags::new(),
        ctx,
      )
    (FpClass::Finite, FpClass::Finite) => {
      match gda_exact_small_division_result(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      match exact_division_by_power_of_ten_result(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      let denominator = other.coefficient
      let extra = precision + denominator.digits10() + 2
      let numerator = gda_coeff_shift_power10_repr(self.coefficient, extra)
      let exact = has_finite_decimal_expansion_repr(
        self.coefficient,
        other.coefficient,
      )
      let q = round_positive_decimal_div_repr(
        numerator,
        denominator,
        self.negative != other.negative,
        ctx.decimal_rounding,
      )
      let (value, round_flags) = if exact {
        let exact_unrounded = normalize_decimal_parts_gda_repr(
          self.negative != other.negative,
          q,
          self.exponent10 - other.exponent10 - extra,
          q.digits10(),
          ctx.decimal_rounding,
        )
        let exact_rounding = exact_result_rounding_flags(
          exact_unrounded,
          self.exponent10 - other.exponent10,
          ctx,
        )
        let rounded_value = normalize_decimal_parts_gda_repr(
          self.negative != other.negative,
          q,
          self.exponent10 - other.exponent10 - extra,
          precision,
          ctx.decimal_rounding,
        )
        if exact_rounding.rounded {
          let prefinal = if exact_unrounded.exponent10 < etiny(ctx) {
            exact_unrounded
          } else if !exact_rounding.inexact {
            expand_rounded_exact_cohort_toward_preferred_exponent(
              rounded_value,
              self.exponent10 - other.exponent10,
              ctx,
            )
          } else {
            expand_inexact_division_cohort(
              rounded_value,
              ctx,
              pad_precision=true,
            )
          }
          let (value, flags) = finalize_finite_ctx(
            prefinal, exact_rounding, ctx,
          )
          (value, with_underflow_for_inexact_subnormal(value, flags, ctx))
        } else {
          let exact_value = expand_exact_cohort_toward_preferred_exponent(
            rounded_value,
            self.exponent10 - other.exponent10,
            ctx,
          )
          finalize_finite_ctx(exact_value, DecimalFlags::new(), ctx)
        }
      } else {
        finalize_finite_ctx(
          normalize_decimal_parts_gda_repr(
            self.negative != other.negative,
            q,
            self.exponent10 - other.exponent10 - extra,
            precision,
            ctx.decimal_rounding,
          ),
          DecimalFlags::new(),
          ctx,
        )
      }
      let result = if exact {
        (value, round_flags)
      } else {
        let value = expand_inexact_division_cohort(
          value,
          ctx,
          pad_precision=true,
        )
        let flags = with_underflow_for_inexact_subnormal(
          value,
          { ..round_flags, rounded: true, inexact: true },
          ctx,
        )
        (value, flags)
      }
      result
    }
  }
}

///|
pub fn Decimal::fma_ctx(
  self : Decimal,
  multiplier : Decimal,
  addend : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.decimal_fma_ctx_impl(multiplier, addend, ctx)
}

///|
fn Decimal::decimal_fma_ctx_impl(
  self : Decimal,
  multiplier : Decimal,
  addend : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_default(ctx)
  if !ctx.extended {
    return (Decimal::nan(precision~), invalid_flags())
  }
  let invalid_product = (
      self.class == FpClass::Infinity &&
      multiplier.class == FpClass::Finite &&
      multiplier.is_zero()
    ) ||
    (
      multiplier.class == FpClass::Infinity &&
      self.class == FpClass::Finite &&
      self.is_zero()
    )
  if invalid_product {
    match quiet_nan_triplet(self, multiplier, addend, ctx) {
      Some((value, flags)) => return (value, flags.combine(invalid_flags()))
      None => return (Decimal::nan(precision~), invalid_flags())
    }
  }
  match quiet_nan_triplet(self, multiplier, addend, ctx) {
    Some(result) => return result
    None => ()
  }
  if invalid_product {
    return (Decimal::nan(precision~), invalid_flags())
  }
  match (self.class, multiplier.class, addend.class) {
    (FpClass::NaN, _, _) | (_, FpClass::NaN, _) | (_, _, FpClass::NaN) =>
      (
        Decimal::nan(precision~),
        nan_operand_flags(self, multiplier).combine(
          nan_operand_flags(self, addend),
        ),
      )
    (FpClass::Infinity, FpClass::Finite, _)
    | (FpClass::Finite, FpClass::Infinity, _) =>
      if self.is_zero() || multiplier.is_zero() {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        let product = Decimal::inf(
          if self.negative != multiplier.negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision~,
        )
        match addend.class {
          FpClass::Finite => (product, DecimalFlags::new())
          FpClass::Infinity =>
            if product.negative == addend.negative {
              (product, DecimalFlags::new())
            } else {
              (Decimal::nan(precision~), invalid_flags())
            }
          FpClass::NaN =>
            (Decimal::nan(precision~), nan_operand_flags(self, addend))
        }
      }
    (FpClass::Infinity, FpClass::Infinity, _) => {
      let product = Decimal::inf(
        if self.negative != multiplier.negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      )
      match addend.class {
        FpClass::Finite => (product, DecimalFlags::new())
        FpClass::Infinity =>
          if product.negative == addend.negative {
            (product, DecimalFlags::new())
          } else {
            (Decimal::nan(precision~), invalid_flags())
          }
        FpClass::NaN =>
          (Decimal::nan(precision~), nan_operand_flags(self, addend))
      }
    }
    (FpClass::Finite, FpClass::Finite, _) => {
      let product_coeff = gda_coeff_multiply_repr(
        self.coefficient,
        multiplier.coefficient,
      )
      let exact_product = finite_with_exponent_repr(
        self.negative != multiplier.negative,
        product_coeff,
        self.exponent10 + multiplier.exponent10,
        finite_precision_for_coeff(product_coeff, decimal_exact_work_context()),
      )
      match addend.class {
        FpClass::Finite =>
          add_finite_values_ctx(
            exact_product,
            addend,
            ctx,
            allow_shortcuts=false,
          )
        FpClass::Infinity =>
          (addend.with_precision(precision, ctx.rounding), DecimalFlags::new())
        FpClass::NaN =>
          (Decimal::nan(precision~), nan_operand_flags(self, addend))
      }
    }
  }
}

///|
pub fn Decimal::div_checked(
  self : Decimal,
  other : Decimal,
) -> Result[Decimal, @def.ArithmeticError] {
  let ctx = DecimalContext::new(precision=max_precision(self, other))
  let (value, flags) = self.div_ctx(other, ctx)
  if flags.division_by_zero {
    Err(@def.ArithmeticError::division_by_zero("division by zero"))
  } else if flags.division_undefined || flags.invalid_operation {
    Err(@def.ArithmeticError::domain_error("invalid decimal division"))
  } else {
    Ok(value)
  }
}

///|
pub fn Decimal::div(self : Decimal, other : Decimal) -> Decimal {
  div_decimal_impl(self, other)
}

///|
pub fn Decimal::sqrt(self : Decimal) -> Result[Decimal, @def.ArithmeticError] {
  let ctx = DecimalContext::new(precision=self.precision_)
  let (value, flags) = self.sqrt_ctx(ctx)
  if flags.invalid_operation {
    Err(
      @def.ArithmeticError::domain_error("sqrt requires a non-negative value"),
    )
  } else {
    Ok(value)
  }
}

///|
fn decimal_sqrt_should_increment(
  quotient : GdaCoeff,
  midpoint_cmp : Int,
  inexact : Bool,
  mode : DecimalRoundingMode,
) -> Bool {
  guard inexact else { return false }
  match mode {
    Down | Floor => false
    Up | Ceiling => true
    HalfUp => midpoint_cmp >= 0
    HalfDown => midpoint_cmp > 0
    HalfEven =>
      midpoint_cmp > 0 || (midpoint_cmp == 0 && gda_coeff_is_odd(quotient))
    ZeroFiveUp =>
      gda_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10 == 0 ||
      gda_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10 == 5
  }
}

///|
fn decimal_sqrt_fixed_result(
  operand : Decimal,
  ctx : DecimalContext,
  precision : Int,
) -> (Decimal, DecimalFlags) {
  let adjusted = adjusted_exponent(operand)
  let root_adjusted = if adjusted >= 0 {
    adjusted / 2
  } else {
    -((-adjusted + 1) / 2)
  }
  // Round directly at the representable subnormal precision.  Rounding first
  // at the nominal context precision and then again in normalization can
  // double-round a tiny square root (for example 1.2E-19 at p=2).
  let root_exponent = Int::max(etiny(ctx), root_adjusted - precision + 1)
  let scale = operand.exponent10 - root_exponent * 2
  let (quotient0, inexact, midpoint_cmp) = if scale >= 0 {
    let radicand = gda_coeff_shift_power10_repr(operand.coefficient, scale)
    let (root, remainder) = gda_coeff_integer_sqrt_rem_repr(radicand)
    let inexact = !remainder.is_zero()
    let midpoint = gda_coeff_magnitude_add_unit(
      gda_coeff_multiply_by_unit_repr(root, 2),
      1,
    )
    (
      root,
      inexact,
      if inexact {
        gda_coeff_compare_repr(
          gda_coeff_multiply_by_unit_repr(radicand, 4),
          gda_coeff_square_repr(midpoint),
        )
      } else {
        0
      },
    )
  } else {
    let denominator_digits = -scale
    let odd_scale = denominator_digits % 2 == 1
    let normalized_radicand = if odd_scale {
      gda_coeff_multiply_by_unit_repr(operand.coefficient, 10)
    } else {
      operand.coefficient
    }
    let (root, root_remainder) = gda_coeff_integer_sqrt_rem_repr(
      normalized_radicand,
    )
    let parity_adjustment = if odd_scale { 1 } else { 0 }
    let root_divisor = gda_coeff_power10_repr(
      (denominator_digits + parity_adjustment) / 2,
    )
    let (quotient, discarded) = gda_coeff_div_rem_repr(root, root_divisor)
    let denominator = gda_coeff_power10_repr(denominator_digits)
    let inexact = !root_remainder.is_zero() || !discarded.is_zero()
    let midpoint = gda_coeff_magnitude_add_unit(
      gda_coeff_multiply_by_unit_repr(quotient, 2),
      1,
    )
    (
      quotient,
      inexact,
      if inexact {
        gda_coeff_compare_repr(
          gda_coeff_multiply_by_unit_repr(operand.coefficient, 4),
          gda_coeff_multiply_repr(gda_coeff_square_repr(midpoint), denominator),
        )
      } else {
        0
      },
    )
  }
  let quotient = if decimal_sqrt_should_increment(
      quotient0,
      midpoint_cmp,
      inexact,
      ctx.decimal_rounding,
    ) {
    gda_coeff_magnitude_add_unit(quotient0, 1)
  } else {
    quotient0
  }
  let (quotient, result_exponent) = if quotient.digits10() > precision {
    match exact_divide_by_power_of_ten_repr(quotient, 1) {
      Some(value) => (value, root_exponent + 1)
      None => abort("decimal sqrt carry normalization was not exact")
    }
  } else {
    (quotient, root_exponent)
  }
  let (value, normalized_flags) = normalize_decimal_parts_ctx_repr(
    false, quotient, result_exponent, ctx,
  )
  let flags = {
    ..normalized_flags,
    rounded: normalized_flags.rounded || inexact,
    inexact: normalized_flags.inexact || inexact,
  }
  let flags = if inexact && root_adjusted < ctx.e_min {
    {
      ..flags,
      subnormal: true,
      underflow: true,
      clamped: flags.clamped || value.coefficient.is_zero(),
    }
  } else {
    with_underflow_for_inexact_subnormal(value, flags, ctx)
  }
  (value, flags)
}

///|
pub fn Decimal::sqrt_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_default(ctx)
  let (operand, operand_flags) = prepare_operand_for_context(self, ctx)
  let result = match operand.class {
    FpClass::NaN => quiet_nan_operand(operand, ctx)
    FpClass::Infinity =>
      if operand.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if operand.negative && !operand.coefficient.is_zero() {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        match exact_finite_sqrt(operand, precision) {
          Some(root) => {
            let (value, flags) = if root.coefficient.is_zero() {
              finalize_finite_ctx(root, DecimalFlags::new(), ctx)
            } else {
              normalize_decimal_parts_ctx_repr(
                root.negative,
                root.coefficient,
                root.exponent10,
                ctx,
              )
            }
            let ideal_exponent = if operand.exponent10 >= 0 {
              operand.exponent10 / 2
            } else {
              -((-operand.exponent10 + 1) / 2)
            }
            if value.class == FpClass::Finite &&
              !value.coefficient.is_zero() &&
              value.exponent10 > ideal_exponent {
              (value, { ..flags, rounded: true })
            } else {
              (value, flags)
            }
          }
          None => decimal_sqrt_fixed_result(operand, ctx, precision)
        }
      }
  }
  let flags = operand_flags.combine(result.1)
  if !ctx.extended && result.0.is_zero() {
    (Decimal::zero(precision~), flags)
  } else {
    (result.0, flags)
  }
}

///|
