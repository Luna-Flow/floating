///|
// Public arithmetic and sqrt APIs.

///|
/// The largest adjusted exponent of a stored finite value: `exponent + digits -
/// 1 <= decimal_value_e_max` (a zero has one digit). It is the `e_max` of the
/// working context of the plain operators (S1), the largest the 32-bit exponent
/// field allows once `e_max`, `e_min` and `etiny = e_min - p + 1` have to be
/// representable in it. A context is narrower than what can be stored (see
/// `decimal_context_e_max_limit`): a value outside every context range can
/// still be stored and is rounded when a context operation reads it.
pub let decimal_value_e_max : Int32 = 2147483646

///|
/// The smallest exponent of a stored finite value, the `etiny` of the working
/// context of the plain operators: `exponent >= decimal_value_e_tiny` (the
/// least digit of a stored value; a context's `etiny` is higher).
pub let decimal_value_e_tiny : Int32 = -2147483645

///|
/// The private context of the plain operators `+ - * /` and `sqrt`: the format
/// of the larger precision label with the storage range of a value, round half
/// even, no fold (IEEE 754-2019 5.4.1). A plain operation is the `_ctx`
/// operation in this context with the flags dropped, so a sum beyond the range
/// is an infinity and a result below it rounds to a zero like any context
/// result.
fn decimal_plain_context(precision : Int32) -> DecimalContext {
  DecimalContext::raw(
    precision,
    decimal_value_e_tiny + precision - 1,
    decimal_value_e_max,
  )
}

///|
pub fn Decimal::add(self : Decimal, other : Decimal) -> Decimal {
  let ctx = decimal_plain_context(max_precision(self, other))
  if decimal_add_plain(self, other, ctx, false) is Some(result) {
    return result.0
  }
  if self.class == FpClass::Finite && other.class == FpClass::Finite {
    // the finite case of `add_ctx` without its operand and NaN preparation
    add_finite_values_ctx(self, other, ctx).0
  } else {
    self.add_ctx(other, ctx).0
  }
}

///|
pub fn Decimal::sub(self : Decimal, other : Decimal) -> Decimal {
  let ctx = decimal_plain_context(max_precision(self, other))
  if decimal_add_plain(self, other, ctx, true) is Some(result) {
    return result.0
  }
  if self.class == FpClass::Finite && other.class == FpClass::Finite {
    add_finite_values_ctx(self, other.neg(), ctx).0
  } else {
    self.sub_ctx(other, ctx).0
  }
}

///|
fn add_finite_values_ctx(
  lhs_value : Decimal,
  rhs_value : Decimal,
  ctx : DecimalContext,
  allow_shortcuts~ : Bool = true,
) -> (Decimal, DecimalFlags) {
  guard lhs_value.class == FpClass::Finite && rhs_value.class == FpClass::Finite else {
    abort("add_finite_ctx expects finite operands")
  }
  if lhs_value.is_zero() && rhs_value.is_zero() {
    let precision = finite_precision_for_default(ctx)
    let negative = if ctx.decimal_rounding == DecimalRound::Floor {
      lhs_value.negative || rhs_value.negative
    } else {
      lhs_value.negative && rhs_value.negative
    }
    let preferred_zero_exponent = Int32::min(
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
    return finalize_finite_ctx(zero, DecimalFlags::new(), ctx)
  }
  if lhs_value.is_zero() || rhs_value.is_zero() {
    let zero = if lhs_value.is_zero() { lhs_value } else { rhs_value }
    let nonzero = if lhs_value.is_zero() { rhs_value } else { lhs_value }
    if ctx.precision > 0 {
      // The exact sum is the nonzero operand, with the smaller exponent as its
      // ideal exponent. Moving it towards that exponent by at most p + 1 -
      // digits places and normalizing once rounds and clamps the delivered
      // result only, so an exact product in fma no longer reports a clamp
      // that its own exponent would have needed.
      let preferred = Int32::min(zero.exponent10, nonzero.exponent10)
      let room = Int32::max(
        0,
        ctx.precision + 1 - nonzero.coefficient.digits10(),
      )
      let shift = Int64::min(
        nonzero.exponent10.to_int64() - preferred.to_int64(),
        room.to_int64(),
      ).to_int()
      return normalize_decimal_parts_ctx_repr(
        nonzero.negative,
        dec_coeff_shift_power10_repr(nonzero.coefficient, shift),
        nonzero.exponent10 - shift,
        ctx,
      )
    }
    let (base, base_flags) = apply_finite_ctx(nonzero, ctx)
    guard base_flags.has_error() == false &&
      base.class == FpClass::Finite &&
      !base.coefficient.is_zero() else {
      return (base, base_flags)
    }
    let preferred_exponent = Int32::min(zero.exponent10, base.exponent10)
    if preferred_exponent < base.exponent10 && ctx.precision > 0 {
      let digits = base.coefficient.digits10()
      let wanted_shift = base.exponent10 - preferred_exponent
      if digits + wanted_shift <= ctx.precision {
        let shifted = finite_with_exponent_repr(
          base.negative,
          dec_coeff_shift_power10_repr(base.coefficient, wanted_shift),
          preferred_exponent,
          base.precision_,
        )
        return finalize_finite_ctx(shifted, base_flags, ctx)
      }
      let available_shift = Int32::max(0, ctx.precision - digits)
      let shifted = if available_shift > 0 {
        finite_with_exponent_repr(
          base.negative,
          dec_coeff_shift_power10_repr(base.coefficient, available_shift),
          base.exponent10 - available_shift,
          base.precision_,
        )
      } else {
        base
      }
      return finalize_finite_ctx(shifted, base_flags, ctx)
    }
    return (base, base_flags)
  }
  // The shortcut forms these exponents in `Int`, with `p` the precision and
  // `A` the larger adjusted exponent of the operands: `target_exponent =
  // A - p + 1`, `target_exponent - 1` (`compare_magnitude_to_half_ulp`,
  // decimal.mbt:776), `target_exponent - 2` and `sticky_limit - 1`
  // (`sticky_limit` is at most `target_exponent - 2`, and at least the stored
  // exponent of `high`, which does not wrap), and the lowest, `target_exponent
  // - p = A - 2p + 1` (`can_absorb`). `exact_base_small_addend_result`
  // (decimal.mbt:818) forms only `target_exponent` and `target_exponent - 1`
  // from its argument, and `exact_units_at_quantum_repr` the shift
  // `exponent10 - target_exponent`, which is a stored exponent minus a value
  // not below `A - 2p + 1`. So `A - 2p - 4 >= -2^31` keeps every one of them
  // inside `Int` with a margin of 5; otherwise the exact path runs (issue 676).
  let shortcut_exponents_fit = ctx.precision > 0 &&
    Int64::max(
      adjusted_exponent(lhs_value).to_int64(),
      adjusted_exponent(rhs_value).to_int64(),
    ) -
    2L * ctx.precision.to_int64() -
    4L >=
    -2147483648L
  if ctx.precision > 0 && allow_shortcuts && shortcut_exponents_fit {
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
      ctx.decimal_rounding != DecimalRound::ZeroFiveUp {
      let (base, base_flags) = apply_finite_ctx(high, ctx)
      // IEEE 754-2019 7.4: overflow is signaled for the rounded result of the
      // operation, here the sum, not for `high` alone. An addend of the same
      // sign only moves the sum away from zero, so the sum overflows whenever
      // `high` does. An addend of the opposite sign can pull the sum back below
      // Nmax, and only when precision >= 2 and `high` is at least two decades
      // beyond e_max is the sum (more than 0.9 * 10^adj(high)) certain to stay
      // beyond it. Every other extended case takes the exact path below. A
      // non-extended context rounds each operand to the precision first, so an
      // operand cannot round past e_max inside the operation.
      let overflow_is_certain = low.negative == high.negative ||
        (precision >= 2 && high_adjusted >= ctx.e_max + 2)

      if base_flags.overflow && overflow_is_certain {
        return (base, base_flags)
      }
      // `high` is used as it is when applying the context left no trace: no
      // flag, no rounded or clamped digit (the representation is unchanged) and
      // no tiny value (a tiny sum raises underflow, which this path does not).
      if base_flags == DecimalFlags::new() &&
        decimal_same_representation(base, high) &&
        !base.is_subnormal(ctx) &&
        base.class == FpClass::Finite &&
        !base.coefficient.is_zero() &&
        !(low.negative != base.negative &&
        dec_coeff_compare_repr(
          remove_factor10_repr(base.coefficient, 0).0,
          dec_coeff_from_int(1),
        ) ==
        0) {
        return exact_base_small_addend_result(base, target_exponent, low, ctx)
      }
    }
    let can_absorb = low_adjusted < target_exponent - precision
    // Absorb the low operand as a sticky unit. Every rounding boundary of the
    // sum (the result grid, its midpoints, and those of the grid one digit
    // finer that a cancellation can reach) and every digit of `high` lies on
    // the grid of 10^sticky_limit. A nonzero `low` below that grid therefore
    // places the sum strictly between the same two neighbours as
    // `high + sign(low) * 10^(sticky_limit - 1)`, so rounding the latter
    // rounds the sum correctly in every mode.
    let sticky_limit = Int32::min(high.exponent10, target_exponent - 2)
    if can_absorb && low_adjusted < sticky_limit {
      let sticky_exponent = sticky_limit - 1
      let units = dec_coeff_shift_power10_repr(
        high.coefficient,
        high.exponent10 - sticky_exponent,
      )
      let magnitude = if low.negative == high.negative {
        dec_coeff_magnitude_add_unit(units, 1)
      } else {
        dec_coeff_magnitude_sub_unit(units, 1)
      }
      let (value, flags) = normalize_decimal_parts_ctx_repr(
        high.negative,
        magnitude,
        sticky_exponent,
        ctx,
      )
      let sticky_adjusted = sticky_exponent.to_int64() +
        magnitude.digits10().to_int64() -
        1L
      return if sticky_adjusted < ctx.e_min.to_int64() && flags.inexact {
        (value, { ..flags, underflow: true, })
      } else {
        (value, flags)
      }
    }
  }
  if exact_aligned_gap_too_large(lhs_value, rhs_value) {
    return not_computed_result(ctx)
  }
  let target = Int32::min(lhs_value.exponent10, rhs_value.exponent10)
  let (exact_negative, exact_magnitude) = decimal_exact_aligned_sum_result(
    lhs_value, rhs_value, target,
  )
  let exact_digits = exact_magnitude.digits10()
  let exact_adjusted = if exact_magnitude.is_zero() {
    0
  } else {
    decimal_int_from_int64_clamped(
      target.to_int64() + exact_digits.to_int64() - 1L,
    )
  }
  let negative = if exact_magnitude.is_zero() {
    ctx.decimal_rounding == DecimalRound::Floor &&
    (lhs_value.negative || rhs_value.negative)
  } else {
    exact_negative
  }

  let tiny_limit = etiny(ctx)
  let zero_below_tiny = exact_magnitude.is_zero() &&
    ctx.precision > 0 &&
    target < tiny_limit
  let zero_target = if zero_below_tiny { tiny_limit } else { target }
  let (value, flags) = normalize_decimal_parts_ctx_repr(
    negative, exact_magnitude, zero_target, ctx,
  )
  if exact_adjusted.to_int64() < ctx.e_min.to_int64() && flags.inexact {
    (value, { ..flags, underflow: true, })
  } else {
    (value, flags)
  }
}

///|
pub fn Decimal::mul(self : Decimal, other : Decimal) -> Decimal {
  self.decimal_mul_ctx_impl(
    other,
    decimal_plain_context(max_precision(self, other)),
  ).0
}

///|
pub fn Decimal::add_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if decimal_add_plain(self, other, ctx, false) is Some(result) {
    return result
  }
  match quiet_nan_pair(self, other, ctx) {
    Some(result) => return result
    None => ()
  }
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) if self.negative != other.negative =>
      (
        Decimal::nan(precision=finite_precision_for_default(ctx)),
        invalid_flags(),
      )
    (FpClass::Infinity, _) =>
      (
        self.with_precision_round(
          finite_precision_for_default(ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    (_, FpClass::Infinity) =>
      (
        other.with_precision_round(
          finite_precision_for_default(ctx),
          ctx.decimal_rounding,
        ),
        DecimalFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) =>
      add_finite_values_ctx(self, other, ctx)
    (FpClass::NaN, _) | (_, FpClass::NaN) =>
      // Covered by quiet_nan_pair; keep the match total if the enum grows.
      (
        Decimal::nan(precision=finite_precision_for_default(ctx)),
        invalid_flags(),
      )
  }
}

///|
pub fn Decimal::sub_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if decimal_add_plain(self, other, ctx, true) is Some(result) {
    return result
  }
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
  self.decimal_mul_ctx_impl(other, ctx)
}

///|
fn Decimal::decimal_mul_ctx_impl(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match decimal_mul_plain(self, other, ctx) {
    Some(result) => result
    None => self.decimal_mul_ctx_general(other, ctx)
  }
}

///|
/// The general route of `mul_ctx`: the definition of its behavior, which the
/// plain case must agree with.
fn Decimal::decimal_mul_ctx_general(
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
            negative=!(self.negative == other.negative),
            precision=finite_precision_for_default(ctx),
          ),
          DecimalFlags::new(),
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      (
        Decimal::inf(
          negative=!(self.negative == other.negative),
          precision=finite_precision_for_default(ctx),
        ),
        DecimalFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) if self.is_zero() || other.is_zero() =>
      finalize_finite_ctx(
        finite_with_exponent(
          self.negative != other.negative,
          bigint_zero(),
          scaleb_int64_to_int(
            self.exponent10.to_int64() + other.exponent10.to_int64(),
          ),
          finite_precision_for_default(ctx),
        ),
        DecimalFlags::new(),
        ctx,
      )
    (FpClass::Finite, FpClass::Finite) => {
      let exact = dec_coeff_multiply_repr(self.coefficient, other.coefficient)
      normalize_decimal_parts_ctx_wide_repr(
        self.negative != other.negative,
        exact,
        self.exponent10.to_int64() + other.exponent10.to_int64(),
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
  self.decimal_div_ctx_impl(other, ctx)
}

///|
// Quotients whose exponent arithmetic would leave `Int`. The adjusted exponent
// of a / b is adj(a) - adj(b) or one less, so a quotient above e_max always
// overflows, and one below 10^(etiny - 1) rounds like 10^(etiny - 2).
fn division_beyond_exponent_range(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let difference = dividend.exponent10.to_int64() -
    divisor.exponent10.to_int64()
  let guard_digits = (finite_precision_for_default(ctx) +
  divisor.coefficient.digits10() +
  2).to_int64()
  guard difference > 2147483647L || difference - guard_digits < -2147483648L else {
    return None
  }
  let negative = dividend.negative != divisor.negative
  let adjusted = difference +
    (dividend.coefficient.digits10() - divisor.coefficient.digits10()).to_int64()
  if adjusted - 1L > ctx.e_max.to_int64() {
    return Some(decimal_overflow_result(negative, ctx))
  }
  let tiny = etiny(ctx).to_int64()
  if adjusted <= tiny - 2L {
    return Some(
      normalize_decimal_parts_ctx_wide_repr(
        negative,
        dec_coeff_from_int(1),
        tiny - 2L,
        ctx,
      ),
    )
  }
  None
}

///|
fn Decimal::decimal_div_ctx_impl(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match decimal_div_plain(self, other, ctx) {
    Some(result) => result
    None => self.decimal_div_ctx_general(other, ctx)
  }
}

///|
/// The general route of `div_ctx`: the definition of its behavior, which the
/// plain case must agree with.
fn Decimal::decimal_div_ctx_general(
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
          Decimal::inf(negative=!(self.negative == other.negative), precision~),
          DecimalFlags::new(),
        )
      } else if self.is_zero() {
        (Decimal::nan(precision~), div_zero_flags(true))
      } else {
        (
          Decimal::inf(negative=!(self.negative == other.negative), precision~),
          div_zero_flags(false),
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      (Decimal::nan(precision~), invalid_flags())
    (FpClass::Infinity, _) =>
      (
        Decimal::inf(negative=!(self.negative == other.negative), precision~),
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
        DecimalFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) if self.is_zero() =>
      finalize_finite_ctx(
        finite_with_exponent(
          self.negative != other.negative,
          bigint_zero(),
          scaleb_int64_to_int(
            self.exponent10.to_int64() - other.exponent10.to_int64(),
          ),
          precision,
        ),
        DecimalFlags::new(),
        ctx,
      )
    (FpClass::Finite, FpClass::Finite) => {
      match division_beyond_exponent_range(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      match exact_division_by_power_of_ten_result(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      match exact_decimal_division_result(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      match bounded_inexact_decimal_division_result(self, other, ctx) {
        Some(result) => return result
        None => ()
      }
      let denominator = other.coefficient
      let extra = precision + denominator.digits10() + 2
      let numerator = dec_coeff_shift_power10_repr(self.coefficient, extra)
      // The guarded quotient is rounded with `ZeroFiveUp` so that a nonzero
      // remainder always leaves the retained low digit off 0 and 5. Rounding it
      // with the target mode here could manufacture an exact tie that the exact
      // quotient had already decided, and the final rounding would then apply
      // the tie rule to it (decNumber uses DEC_ROUND_05UP for the same reason).
      let q = round_positive_decimal_div_repr(
        numerator,
        denominator,
        self.negative != other.negative,
        DecimalRound::ZeroFiveUp,
      )
      // With a bounded precision, round the guarded quotient once, straight
      // to its final grid: to `precision` digits when it is normal and to
      // Etiny when it is subnormal. Rounding to `precision` digits first and
      // then to Etiny would round a subnormal quotient twice.
      // The guarded quotient keeps the exact quotient's tininess: ZeroFiveUp
      // never carries it across 10^e_min, and its sticky low digit lets the
      // p-digit rounding used by after-rounding detection see the exact
      // value. Its normalization flags are therefore the quotient's, while
      // the delivered value alone cannot tell a tiny quotient that rounded up
      // to 10^e_min from a normal one.
      let (value, flags) = if ctx.precision > 0 {
        // The exponent of the guarded quotient is formed in 64 bits: the
        // difference of two stored exponents plus the guard digits leaves
        // `Int` (issue 676).
        let (value, flags) = normalize_decimal_parts_ctx_wide_repr(
          self.negative != other.negative,
          q,
          self.exponent10.to_int64() -
          other.exponent10.to_int64() -
          extra.to_int64(),
          ctx,
        )
        (value, { ..flags, inexact: true, })
      } else {
        let value = finalize_finite_ctx(
            normalize_decimal_parts_gda_repr(
              self.negative != other.negative,
              q,
              self.exponent10 - other.exponent10 - extra,
              precision,
              ctx.decimal_rounding,
            ),
            DecimalFlags::new(),
            ctx,
          ).0
        (
          value,
          with_underflow_for_inexact_subnormal(
            value,
            { ..DecimalFlags::new(), inexact: true, },
            ctx,
          ),
        )
      }
      (expand_inexact_division_cohort(value, ctx, pad_precision=true), flags)
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
          negative=self.negative != multiplier.negative,
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
        negative=self.negative != multiplier.negative,
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
      let product_coeff = dec_coeff_multiply_repr(
        self.coefficient,
        multiplier.coefficient,
      )
      let product_negative = self.negative != multiplier.negative
      let product_exponent = self.exponent10.to_int64() +
        multiplier.exponent10.to_int64()
      if addend.class == FpClass::Finite &&
        !product_coeff.is_zero() &&
        !addend.coefficient.is_zero() {
        let product_adjusted = product_exponent +
          (product_coeff.digits10() - 1).to_int64()
        let addend_adjusted = addend.exponent10.to_int64() +
          (addend.coefficient.digits10() - 1).to_int64()
        // An adjusted exponent exactly at e_max + 1 can still round back to
        // the largest finite value after an opposite-sign addend.  Only a
        // product at least one full decade farther out is unconditionally
        // beyond the finite boundary.
        if product_adjusted >= ctx.e_max.to_int64() + 2L &&
          product_adjusted - addend_adjusted > precision.to_int64() + 2L {
          return decimal_overflow_result(product_negative, ctx)
        }
      }
      // A product whose adjusted exponent exceeds `Int` is at least 10^(2^31),
      // which no finite addend (adjusted exponent at most 2^31 - 1) brings back
      // below e_max.
      if addend.class == FpClass::Finite &&
        !product_coeff.is_zero() &&
        product_exponent + (product_coeff.digits10() - 1).to_int64() >
        2147483647L {
        return decimal_overflow_result(product_negative, ctx)
      }
      if addend.class == FpClass::Finite &&
        !product_coeff.is_zero() &&
        product_exponent < -2147483648L {
        if addend.is_zero() {
          return normalize_decimal_parts_ctx_wide_repr(
            product_negative, product_coeff, product_exponent, ctx,
          )
        }
        // The sum is rounded at a position R >= etiny, and, since a product
        // this small moves the adjusted exponent by at most one, R >=
        // adj(addend) - p. Every rounding boundary is then a multiple of
        // 10^m with m = min(addend exponent, max(etiny, adj(addend) - p) - 1),
        // and so is the addend. A product of magnitude below 10^m therefore
        // rounds like any other value strictly between 0 and 10^m with its
        // sign; 10^(m-1) keeps the alignment with the addend short.
        let addend_adjusted = addend.exponent10.to_int64() +
          (addend.coefficient.digits10() - 1).to_int64()
        // Product and addend both below 10^(Etiny - 1): the sum is tiny and
        // carries the sign of the operand with the larger adjusted exponent
        // (the product's exponent is the smaller one only when its adjusted
        // exponent is, which it is not always). Equal adjusted exponents with
        // opposite signs may cancel; they are left to the exact path.
        if ctx.precision > 0 && addend_adjusted <= etiny(ctx).to_int64() - 2L {
          let product_adjusted_tiny = product_exponent +
            (product_coeff.digits10() - 1).to_int64()
          if product_adjusted_tiny != addend_adjusted {
            return decimal_power_tiny_result(
              if product_adjusted_tiny > addend_adjusted {
                product_negative
              } else {
                addend.negative
              },
              ctx,
            )
          } else if product_negative == addend.negative {
            return decimal_power_tiny_result(addend.negative, ctx)
          }
        }
        let lowest_rounding = if ctx.precision > 0 {
          Int64::max(
            etiny(ctx).to_int64(),
            addend_adjusted - ctx.precision.to_int64(),
          )
        } else {
          etiny(ctx).to_int64()
        }
        let m = Int64::min(addend.exponent10.to_int64(), lowest_rounding - 1L)
        let product_adjusted = product_exponent +
          (product_coeff.digits10() - 1).to_int64()
        if product_adjusted < m && m - 1L >= -2147483648L {
          return add_finite_values_ctx(
            finite_with_exponent_repr(
              product_negative,
              dec_coeff_from_int(1),
              (m - 1L).to_int(),
              1,
            ),
            addend,
            ctx,
            allow_shortcuts=false,
          )
        }
      }
      // An exact zero product only contributes its exponent, which is
      // clamped to etiny anyway; keep it there instead of below `Int`.
      let product_exponent = if product_coeff.is_zero() &&
        product_exponent < -2147483648L {
        Int64::max(product_exponent, etiny(ctx).to_int64() - 1L)
      } else {
        product_exponent
      }
      let (product_coeff, product_exponent, _) = fold_exponent10_into_int_repr(
        product_negative, product_coeff, product_exponent,
      )
      let exact_product = finite_with_exponent_repr(
        product_negative,
        product_coeff,
        product_exponent,
        finite_precision_for_coeff(product_coeff, decimal_exact_work_context()),
      )
      match addend.class {
        FpClass::Finite =>
          add_finite_values_ctx(
            exact_product,
            addend,
            ctx,
            allow_shortcuts=true,
          )
        FpClass::Infinity =>
          (
            addend.with_precision_round(precision, ctx.decimal_rounding),
            DecimalFlags::new(),
          )
        FpClass::NaN =>
          (Decimal::nan(precision~), nan_operand_flags(self, addend))
      }
    }
  }
}

///|
pub fn Decimal::div(self : Decimal, other : Decimal) -> Decimal {
  self.decimal_div_ctx_impl(
    other,
    decimal_plain_context(max_precision(self, other)),
  ).0
}

///|
/// The square root under the format of the operand (`sqrt_ctx` in the context
/// of its precision label): a negative non-zero operand gives NaN (IEEE
/// 754-2019 7.2), no flags are returned. `sqrt_checked` reports it as `Err`.
pub fn Decimal::sqrt(self : Decimal) -> Decimal {
  self.sqrt_ctx(decimal_plain_context(self.precision_)).0
}

///|
fn decimal_sqrt_should_increment(
  quotient : DecCoeff,
  midpoint_cmp : Int32,
  inexact : Bool,
  mode : DecimalRound,
) -> Bool {
  dec_coeff_sqrt_should_increment(
    quotient,
    midpoint_cmp,
    inexact,
    mode.kernel(),
  )
}

///|
fn decimal_sqrt_fixed_result(
  operand : Decimal,
  ctx : DecimalContext,
  precision : Int32,
) -> (Decimal, DecimalFlags) {
  let adjusted = adjusted_exponent(operand)
  let root_adjusted = adjusted >> 1
  // Round directly at the representable subnormal precision.  Rounding first
  // at the nominal context precision and then again in normalization can
  // double-round a tiny square root (for example 1.2E-19 at p=2).
  let root_exponent = Int32::max(etiny(ctx), root_adjusted - precision + 1)
  let scale = operand.exponent10 - root_exponent * 2
  let (quotient0, inexact, midpoint_cmp) = if scale >= 0 {
    let radicand = dec_coeff_shift_power10_repr(operand.coefficient, scale)
    let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(radicand)
    let inexact = !remainder.is_zero()
    let midpoint = dec_coeff_magnitude_add_unit(
      dec_coeff_multiply_by_unit_repr(root, 2),
      1,
    )
    (
      root,
      inexact,
      if inexact {
        dec_coeff_compare_repr(
          dec_coeff_multiply_by_unit_repr(radicand, 4),
          dec_coeff_square_repr(midpoint),
        )
      } else {
        0
      },
    )
  } else {
    let denominator_digits = -scale
    let odd_scale = denominator_digits % 2 == 1
    let normalized_radicand = if odd_scale {
      dec_coeff_multiply_by_unit_repr(operand.coefficient, 10)
    } else {
      operand.coefficient
    }
    let (root, root_remainder) = dec_coeff_integer_sqrt_rem_repr(
      normalized_radicand,
    )
    let parity_adjustment = if odd_scale { 1 } else { 0 }
    let root_divisor = dec_coeff_power10_repr(
      (denominator_digits + parity_adjustment) / 2,
    )
    let (quotient, discarded) = dec_coeff_div_rem_repr(root, root_divisor)
    let denominator = dec_coeff_power10_repr(denominator_digits)
    let inexact = !root_remainder.is_zero() || !discarded.is_zero()
    let midpoint = dec_coeff_magnitude_add_unit(
      dec_coeff_multiply_by_unit_repr(quotient, 2),
      1,
    )
    (
      quotient,
      inexact,
      if inexact {
        dec_coeff_compare_repr(
          dec_coeff_multiply_by_unit_repr(operand.coefficient, 4),
          dec_coeff_multiply_repr(dec_coeff_square_repr(midpoint), denominator),
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
    dec_coeff_magnitude_add_unit(quotient0, 1)
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
    inexact: normalized_flags.inexact || inexact,
  }
  // An inexact root below 10^e_min is tiny, detected before rounding (IEEE
  // 754-2019 7.5: for decimal formats tininess is detected before rounding).
  let tiny = inexact && root_adjusted < ctx.e_min
  let flags = if tiny {
    { ..flags, underflow: true, }
  } else {
    with_underflow_for_inexact_subnormal(value, flags, ctx)
  }
  (value, flags)
}

///|
/// A positive operand whose square root has an adjusted exponent of at most
/// `Etiny - 2` is below `10^(Etiny - 1)`, a tenth of the smallest subnormal,
/// so the root is tiny and inexact and rounds like any such value (zero in the
/// nearest modes). Deciding it from the adjusted exponent avoids forming
/// coefficients with an exponent distance of billions of digits.
fn decimal_sqrt_tiny_result(
  operand : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 &&
    operand.class == FpClass::Finite &&
    !operand.negative &&
    !operand.coefficient.is_zero() else {
    return None
  }
  if adjusted_exponent64(operand) >> 1 <= etiny(ctx).to_int64() - 2L {
    Some(decimal_power_tiny_result(false, ctx))
  } else {
    None
  }
}

///|
pub fn Decimal::sqrt_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_default(ctx)
  match self.class {
    FpClass::NaN => quiet_nan_operand(self, ctx)
    FpClass::Infinity =>
      if self.negative {
        (Decimal::nan(precision~), invalid_flags())
      } else {
        (Decimal::inf(precision~), DecimalFlags::new())
      }
    FpClass::Finite =>
      if self.negative && !self.coefficient.is_zero() {
        (Decimal::nan(precision~), invalid_flags())
      } else if decimal_sqrt_tiny_result(self, ctx) is Some(tiny) {
        tiny
      } else {
        match exact_finite_sqrt(self, precision) {
          Some(root) =>
            if root.coefficient.is_zero() {
              finalize_finite_ctx(root, DecimalFlags::new(), ctx)
            } else {
              normalize_decimal_parts_ctx_repr(
                root.negative,
                root.coefficient,
                root.exponent10,
                ctx,
              )
            }
          None => decimal_sqrt_fixed_result(self, ctx, precision)
        }
      }
  }
}

///|
