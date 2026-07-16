///|
// Finite result normalization and finalization helpers.

fn should_increment_decimal(
  quotient : BigInt,
  remainder : BigInt,
  divisor : BigInt,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> Bool {
  if remainder.is_zero() {
    return false
  }
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    HalfEven => {
      let twice = remainder * BigInt::from_int(2)
      if twice > divisor {
        true
      } else if twice < divisor {
        false
      } else {
        !(quotient % BigInt::from_int(2)).is_zero()
      }
    }
    HalfUp => remainder * BigInt::from_int(2) >= divisor
    HalfDown => remainder * BigInt::from_int(2) > divisor
    ZeroFiveUp => {
      let last = quotient % BigInt::from_int(10)
      last.is_zero() || last == BigInt::from_int(5)
    }
  }
}

///|
// Mirrors decNumber's coefficient-first rounding step: compare the remainder
// against one-half ulp, then apply the mode-specific increment rule.
fn should_increment_decimal_repr(
  quotient : GdaCoeff,
  remainder : GdaCoeff,
  divisor : GdaCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> Bool {
  if remainder.is_zero() {
    return false
  }
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    HalfEven => {
      let half_cmp = gda_coeff_compare_repr(
        gda_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      )
      half_cmp > 0 || (half_cmp == 0 && gda_coeff_is_odd(quotient))
    }
    HalfUp =>
      gda_coeff_compare_repr(
        gda_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      ) >=
      0
    HalfDown =>
      gda_coeff_compare_repr(
        gda_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      ) >
      0
    ZeroFiveUp => {
      let last = gda_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10
      last == 0 || last == 5
    }
  }
}

///|
#warnings("-unused_value")
fn round_positive_decimal_div(
  numerator : BigInt,
  denominator : BigInt,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> BigInt {
  guard numerator >= bigint_zero() else {
    abort("round_positive_decimal_div expects non-negative numerator")
  }
  guard denominator > bigint_zero() else {
    abort("denominator must be positive")
  }
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  if should_increment_decimal(quotient, remainder, denominator, negative, mode) {
    quotient + bigint_one()
  } else {
    quotient
  }
}

///|
fn round_positive_decimal_div_repr(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> GdaCoeff {
  guard !denominator.is_zero() else {
    abort("round_positive_decimal_div_repr expects denominator > 0")
  }
  let (quotient, remainder) = gda_coeff_div_rem_repr(numerator, denominator)
  if should_increment_decimal_repr(
      quotient, remainder, denominator, negative, mode,
    ) {
    gda_coeff_magnitude_add_unit(quotient, 1)
  } else {
    quotient
  }
}

///|
fn round_positive_decimal_div_pow10_repr(
  numerator : GdaCoeff,
  shift : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (GdaCoeff, Bool) {
  guard shift >= 0 else {
    abort("round_positive_decimal_div_pow10_repr expects non-negative shift")
  }
  let (quotient, has_remainder, half_cmp) = gda_coeff_div_pow10_round_info_repr(
    numerator, shift,
  )
  if !has_remainder {
    return (quotient, false)
  }
  let should_increment = match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    ZeroFiveUp => {
      let last = gda_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10
      last == 0 || last == 5
    }
    HalfEven => half_cmp > 0 || (half_cmp == 0 && gda_coeff_is_odd(quotient))
    HalfUp => half_cmp >= 0
    HalfDown => half_cmp > 0
  }
  (
    if should_increment {
      gda_coeff_magnitude_add_unit(quotient, 1)
    } else {
      quotient
    },
    has_remainder,
  )
}

///|
fn normalize_decimal(
  coefficient : BigInt,
  exponent10 : Int,
  precision : Int,
  mode : RoundingMode,
) -> Decimal {
  normalize_decimal_parts(
    coefficient < bigint_zero(),
    abs_bigint(coefficient),
    exponent10,
    precision,
    mode,
  )
}

///|
fn normalize_decimal_parts(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int,
  precision : Int,
  mode : RoundingMode,
) -> Decimal {
  normalize_decimal_parts_gda(
    negative,
    magnitude,
    exponent10,
    precision,
    DecimalRoundingMode::from_arithmetic(mode),
  )
}

///|
fn normalize_decimal_parts_gda(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int,
  precision : Int,
  mode : DecimalRoundingMode,
) -> Decimal {
  normalize_decimal_parts_gda_repr(
    negative,
    coeff_from_bigint(abs_bigint(magnitude)),
    exponent10,
    precision,
    mode,
  )
}

///|
fn normalize_decimal_parts_gda_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  exponent10 : Int,
  precision : Int,
  mode : DecimalRoundingMode,
) -> Decimal {
  let precision = Int::max(1, precision)
  if magnitude.is_zero() {
    return finite_with_exponent_repr(negative, gda_coeff_zero(), 0, precision)
  }
  let (magnitude0, exp0) = remove_factor10_repr(magnitude, exponent10)
  let digits = magnitude0.digits10()
  let (magnitude1, exp1) = if digits > precision {
    let shift = digits - precision
    (
      round_positive_decimal_div_pow10_repr(magnitude0, shift, negative, mode).0,
      exp0 + shift,
    )
  } else {
    (magnitude0, exp0)
  }
  let (magnitude2, exp2) = remove_factor10_repr(magnitude1, exp1)
  finite_with_exponent_repr(negative, magnitude2, exp2, precision)
}

///|
fn expand_exact_cohort_toward_preferred_exponent(
  value : Decimal,
  preferred_exponent : Int,
  ctx : DecimalContext,
) -> Decimal {
  guard value.class == FpClass::Finite else { return value }
  guard ctx.precision > 0 &&
    !value.coefficient.is_zero() &&
    preferred_exponent < value.exponent10 else {
    return value
  }
  let shift = value.exponent10 - preferred_exponent
  let digits = value.coefficient.digits10()
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  if digits + shift <= precision {
    finite_with_exponent_repr(
      value.negative,
      gda_coeff_shift_power10_repr(value.coefficient, shift),
      preferred_exponent,
      value.precision_,
    )
  } else {
    value
  }
}

///|
fn finite_with_exponent(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int,
  precision : Int,
) -> Decimal {
  {
    class: FpClass::Finite,
    negative,
    coefficient: coeff_from_bigint(magnitude),
    exponent10,
    precision_: Int::max(1, precision),
    signaling_nan: false,
  }
}

///|
fn finite_with_exponent_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  exponent10 : Int,
  precision : Int,
) -> Decimal {
  {
    class: FpClass::Finite,
    negative,
    coefficient: magnitude,
    exponent10,
    precision_: Int::max(1, precision),
    signaling_nan: false,
  }
}

///|
fn finite_precision_for_digits(digits : Int, ctx : DecimalContext) -> Int {
  if ctx.precision == 0 {
    Int::max(1, digits)
  } else {
    Int::max(1, ctx.precision)
  }
}

///|
fn finite_precision_for_default(ctx : DecimalContext) -> Int {
  finite_precision_for_digits(1, ctx)
}

///|
fn etiny(ctx : DecimalContext) -> Int {
  ctx.e_min - finite_precision_for_default(ctx) + 1
}

///|
fn tiny_for_underflow(
  ctx : DecimalContext,
  before_adjusted : Int64,
  after_adjusted : Int64,
) -> Bool {
  match ctx.tininess {
    DecimalTininessDetection::BeforeRounding =>
      before_adjusted < ctx.e_min.to_int64()
    DecimalTininessDetection::AfterRounding =>
      after_adjusted < ctx.e_min.to_int64()
  }
}

///|
fn decimal_round_coeff_to_digits_repr(
  magnitude : GdaCoeff,
  exponent10 : Int,
  target_digits : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (GdaCoeff, Int, Bool, Bool) {
  if magnitude.is_zero() {
    return (gda_coeff_zero(), 0, false, false)
  }
  let discard = magnitude.digits10() - target_digits
  if discard <= 0 {
    return (magnitude, exponent10, false, false)
  }
  let (rounded_magnitude, inexact) = round_positive_decimal_div_pow10_repr(
    magnitude, discard, negative, mode,
  )
  (rounded_magnitude, exponent10 + discard, true, inexact)
}

///|
fn adjusted_exponent(x : Decimal) -> Int {
  if x.class != FpClass::Finite || x.coefficient.is_zero() {
    x.exponent10
  } else {
    x.exponent10 + x.coefficient.digits10() - 1
  }
}

///|
fn finalize_finite_ctx(
  value : Decimal,
  flags : DecimalFlags,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else { return (value, flags) }
  if value.coefficient.is_zero() {
    if ctx.precision > 0 {
      let lower = etiny(ctx)
      let upper = if ctx.clamp {
        ctx.e_max - value.precision_ + 1
      } else {
        ctx.e_max
      }
      let clamped_exponent = if value.exponent10 < lower {
        lower
      } else if value.exponent10 > upper {
        upper
      } else {
        value.exponent10
      }
      if clamped_exponent != value.exponent10 {
        return (
          finite_with_exponent_repr(
            value.negative,
            gda_coeff_zero(),
            clamped_exponent,
            value.precision_,
          ),
          { ..flags, clamped: true },
        )
      }
    }
    return (value, flags)
  }
  let unrounded_adjusted = value.exponent10.to_int64() +
    (value.coefficient.digits10() - 1).to_int64()
  let adjusted = adjusted_exponent(value)
  if !ctx.extended && adjusted < ctx.e_min {
    return (
      finite_with_exponent_repr(false, gda_coeff_zero(), 0, value.precision_),
      {
        ..flags,
        underflow: true,
        subnormal: true,
        inexact: true,
        rounded: true,
        clamped: false,
      },
    )
  }
  if adjusted > ctx.e_max {
    let (overflowed, overflow_flags) = decimal_overflow_result(
      value.negative,
      ctx,
    )
    return (overflowed, flags.combine(overflow_flags))
  }
  let mut value = value
  let mut flags = flags
  if ctx.precision > 0 && value.exponent10 < etiny(ctx) {
    let tiny = etiny(ctx)
    let shift = tiny - value.exponent10
    let target_digits = value.coefficient.digits10() - shift
    let (magnitude, next_exponent, _, inexact) = decimal_round_coeff_to_digits_repr(
      value.coefficient,
      value.exponent10,
      target_digits,
      value.negative,
      ctx.decimal_rounding,
    )
    flags = { ..flags, rounded: true }
    let rounded_adjusted = if magnitude.is_zero() {
      ctx.e_min.to_int64() - 1L
    } else {
      next_exponent.to_int64() + (magnitude.digits10() - 1).to_int64()
    }
    let tiny = tiny_for_underflow(ctx, unrounded_adjusted, rounded_adjusted)
    if tiny {
      flags = { ..flags, subnormal: true }
    }
    if inexact {
      flags = { ..flags, inexact: true }
      if tiny {
        flags = { ..flags, underflow: true }
      }
    }
    value = finite_with_exponent_repr(
      value.negative,
      magnitude,
      next_exponent,
      value.precision_,
    )
    if value.coefficient.is_zero() {
      return (value, { ..flags, clamped: true, rounded: true })
    }
  }
  let adjusted2 = adjusted_exponent(value)
  if adjusted2 < ctx.e_min {
    flags = { ..flags, subnormal: true }
    if flags.inexact {
      flags = { ..flags, underflow: true }
    } else if !ctx.extended {
      flags = { ..flags, rounded: true, inexact: true, underflow: true }
    }
  }
  if ctx.clamp && ctx.precision > 0 {
    let e_top = ctx.e_max - ctx.precision + 1
    if value.exponent10 > e_top {
      let shift = value.exponent10 - e_top
      value = finite_with_exponent_repr(
        value.negative,
        gda_coeff_shift_power10_repr(value.coefficient, shift),
        e_top,
        value.precision_,
      )
      flags = { ..flags, clamped: true }
    }
  }
  (value, flags)
}

///|
fn normalize_decimal_parts_ctx_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  exponent10 : Int,
  ctx : DecimalContext,
  apply_etiny? : Bool = true,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(magnitude, ctx)
  let mut flags = DecimalFlags::new()
  let mut magnitude = magnitude
  let mut exponent10 = exponent10
  if apply_etiny &&
    ctx.precision > 0 &&
    !magnitude.is_zero() &&
    exponent10 < etiny(ctx) {
    let unrounded_adjusted = exponent10.to_int64() +
      (magnitude.digits10() - 1).to_int64()
    let etiny_value = etiny(ctx)
    let shift = etiny_value - exponent10
    let target_digits = magnitude.digits10() - shift
    let (rounded_magnitude0, next_exponent0, _, inexact) = decimal_round_coeff_to_digits_repr(
      magnitude,
      exponent10,
      target_digits,
      negative,
      ctx.decimal_rounding,
    )
    let (rounded_magnitude, next_exponent) = if !rounded_magnitude0.is_zero() &&
      etiny_value < next_exponent0 {
      let restore_shift = next_exponent0 - etiny_value
      let restored = gda_coeff_shift_power10_repr(
        rounded_magnitude0, restore_shift,
      )
      if restored.digits10() <= precision {
        (restored, etiny_value)
      } else {
        (rounded_magnitude0, next_exponent0)
      }
    } else {
      (rounded_magnitude0, next_exponent0)
    }
    flags = { ..flags, rounded: true }
    let rounded_adjusted = if rounded_magnitude0.is_zero() {
      ctx.e_min.to_int64() - 1L
    } else {
      next_exponent0.to_int64() + (rounded_magnitude0.digits10() - 1).to_int64()
    }
    let tiny_result = tiny_for_underflow(
      ctx, unrounded_adjusted, rounded_adjusted,
    )
    if tiny_result {
      flags = { ..flags, subnormal: true }
    }
    if inexact {
      flags = { ..flags, inexact: true }
      if tiny_result {
        flags = { ..flags, underflow: true }
      }
    }
    magnitude = rounded_magnitude
    if magnitude.is_zero() {
      flags = { ..flags, clamped: true }
    }
    exponent10 = next_exponent
  }
  let magnitude = if ctx.precision > 0 && !magnitude.is_zero() {
    let digits = magnitude.digits10()
    if digits > precision {
      let max_drop = digits - precision
      let (trimmed, trimmed_exp, dropped) = trim_trailing_decimal_zeros_repr(
        magnitude,
        exponent10,
        max_drop~,
      )
      if dropped > 0 {
        exponent10 = trimmed_exp
        flags = { ..flags, rounded: true }
      }
      trimmed
    } else {
      magnitude
    }
  } else {
    magnitude
  }
  let magnitude = if ctx.precision > 0 && !magnitude.is_zero() {
    let digits = magnitude.digits10()
    if digits > precision {
      let (rounded_magnitude, next_exponent, _, inexact) = decimal_round_coeff_to_digits_repr(
        magnitude,
        exponent10,
        precision,
        negative,
        ctx.decimal_rounding,
      )
      exponent10 = next_exponent
      flags = { ..flags, rounded: true }
      if inexact {
        flags = { ..flags, inexact: true }
      }
      rounded_magnitude
    } else {
      magnitude
    }
  } else {
    magnitude
  }
  let final_digits = if ctx.precision > 0 && !magnitude.is_zero() {
    magnitude.digits10()
  } else {
    1
  }
  let magnitude = if ctx.precision > 0 && final_digits > precision {
    exponent10 += 1
    match exact_divide_by_power_of_ten_repr(magnitude, 1) {
      Some(value) => value
      None =>
        abort("normalize_decimal_parts_ctx_repr expected exact divide by 10")
    }
  } else {
    magnitude
  }
  let value = finite_with_exponent_repr(
    negative, magnitude, exponent10, precision,
  )
  finalize_finite_ctx(value, flags, ctx)
}

///|
fn with_underflow_for_inexact_subnormal(
  value : Decimal,
  flags : DecimalFlags,
  ctx : DecimalContext,
) -> DecimalFlags {
  if flags.inexact &&
    value.class == FpClass::Finite &&
    adjusted_exponent(value) < ctx.e_min {
    { ..flags, subnormal: true, underflow: true }
  } else {
    flags
  }
}

///|
fn expand_finite_cohort_toward_target_exponent(
  value : Decimal,
  target : Int,
  ctx : DecimalContext,
) -> Decimal {
  guard value.class == FpClass::Finite &&
    ctx.precision > 0 &&
    !value.coefficient.is_zero() &&
    target < value.exponent10 else {
    return value
  }
  let shift = value.exponent10 - target
  let digits = value.coefficient.digits10()
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  if digits + shift <= precision {
    finite_with_exponent_repr(
      value.negative,
      gda_coeff_shift_power10_repr(value.coefficient, shift),
      target,
      value.precision_,
    )
  } else {
    value
  }
}

///|
fn expand_rounded_exact_cohort_toward_preferred_exponent(
  value : Decimal,
  preferred_exponent : Int,
  ctx : DecimalContext,
) -> Decimal {
  guard value.class == FpClass::Finite &&
    ctx.precision > 0 &&
    !value.coefficient.is_zero() &&
    preferred_exponent < value.exponent10 else {
    return value
  }
  let digits = value.coefficient.digits10()
  let available_shift = Int::max(0, ctx.precision - digits)
  let wanted_shift = value.exponent10 - preferred_exponent
  let shift = Int::min(wanted_shift, available_shift)
  if shift > 0 {
    finite_with_exponent_repr(
      value.negative,
      gda_coeff_shift_power10_repr(value.coefficient, shift),
      value.exponent10 - shift,
      value.precision_,
    )
  } else {
    value
  }
}

///|
fn expand_inexact_division_cohort(
  value : Decimal,
  ctx : DecimalContext,
  pad_precision? : Bool = false,
) -> Decimal {
  guard value.class == FpClass::Finite &&
    ctx.precision > 0 &&
    !value.coefficient.is_zero() else {
    return value
  }
  let target = etiny(ctx)
  let digits = value.coefficient.digits10()
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  if target < value.exponent10 {
    let shift = value.exponent10 - target
    if digits + shift <= precision {
      return finite_with_exponent_repr(
        value.negative,
        gda_coeff_shift_power10_repr(value.coefficient, shift),
        target,
        value.precision_,
      )
    }
  }
  guard pad_precision && adjusted_exponent(value) >= ctx.e_min else {
    return value
  }
  let shift = precision - digits
  if shift > 0 {
    finite_with_exponent_repr(
      value.negative,
      gda_coeff_shift_power10_repr(value.coefficient, shift),
      value.exponent10 - shift,
      value.precision_,
    )
  } else {
    value
  }
}

///|
fn apply_finite_ctx(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("apply_finite_ctx expects a finite operand")
  }
  normalize_decimal_parts_ctx_repr(
    value.negative,
    value.coefficient,
    value.exponent10,
    ctx,
  )
}

///|
pub fn Decimal::normalized(self : Decimal) -> Decimal {
  match self.class {
    FpClass::Finite =>
      normalize_decimal_parts_gda_repr(
        self.negative,
        self.coefficient,
        self.exponent10,
        self.precision_,
        DecimalRoundingMode::HalfEven,
      )
    _ => self
  }
}

///|
pub fn Decimal::trim(self : Decimal) -> Decimal {
  trim_finite_fractional_zeros(self)
}

///|
fn trim_finite_fractional_zeros(value : Decimal) -> Decimal {
  guard value.class == FpClass::Finite else { return value }
  if value.coefficient.is_zero() {
    return finite_with_exponent_repr(
      value.negative,
      value.coefficient,
      0,
      value.precision_,
    )
  }
  let max_drop = if value.exponent10 > 0 {
    value.coefficient.digits10() - 1
  } else if value.exponent10 < 0 {
    -value.exponent10
  } else {
    0
  }
  let (coefficient, exponent10, _) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    value.exponent10,
    max_drop~,
  )
  finite_with_exponent_repr(
    value.negative,
    coefficient,
    exponent10,
    value.precision_,
  )
}

///|
fn finish_subset_finite_result(
  value : Decimal,
  ctx : DecimalContext,
  trim_fractional : Bool,
) -> Decimal {
  guard !ctx.extended && value.class == FpClass::Finite else { return value }
  if value.coefficient.is_zero() {
    return finite_with_exponent_repr(
      false,
      value.coefficient,
      0,
      value.precision_,
    )
  }
  let value = if value.exponent10 >= 0 &&
    ctx.precision >= value.exponent10 + value.coefficient.digits10() {
    finite_with_exponent_repr(
      value.negative,
      gda_coeff_shift_power10_repr(value.coefficient, value.exponent10),
      0,
      value.precision_,
    )
  } else {
    value
  }
  if trim_fractional {
    trim_finite_fractional_zeros(value)
  } else {
    value
  }
}

///|
fn finish_context_result(
  value : Decimal,
  flags : DecimalFlags,
  ctx : DecimalContext,
  trim_fractional : Bool,
) -> (Decimal, DecimalFlags) {
  let value = finish_subset_finite_result(value, ctx, trim_fractional)
  let flags = if !ctx.extended && value.is_zero() && flags.underflow {
    { ..flags, clamped: false }
  } else {
    flags
  }
  (value, flags)
}

///|
fn reduce_finite_cohort_ctx(value : Decimal, ctx : DecimalContext) -> Decimal {
  guard value.class == FpClass::Finite else { return value }
  guard !value.coefficient.is_zero() else { return value.normalized() }
  let upper = if ctx.clamp && ctx.precision > 0 {
    ctx.e_max - finite_precision_for_default(ctx) + 1
  } else {
    ctx.e_max
  }
  let max_drop = if value.exponent10 < upper {
    upper - value.exponent10
  } else {
    0
  }
  let (coefficient0, exponent10, _) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    value.exponent10,
    max_drop~,
  )
  finite_with_exponent_repr(
    value.negative,
    coefficient0,
    exponent10,
    value.precision_,
  )
}

///|
pub fn Decimal::reduce_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if self.class == FpClass::Finite && self.coefficient.is_zero() {
    let (rounded, flags) = apply_finite_ctx(self, ctx)
    let negative = ctx.extended && self.negative
    return (
      finite_with_exponent(negative, bigint_zero(), 0, rounded.precision_),
      flags,
    )
  }
  let (rounded, flags) = if self.class == FpClass::Finite {
    apply_finite_ctx(self, ctx)
  } else {
    self.plus_ctx(ctx)
  }
  match rounded.class {
    FpClass::Finite => (reduce_finite_cohort_ctx(rounded, ctx), flags)
    FpClass::NaN | FpClass::Infinity => (rounded, flags)
  }
}

///|
pub fn Decimal::normalize_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.reduce_ctx(ctx)
}

///|
pub fn Decimal::with_precision(
  self : Decimal,
  precision : Int,
  mode : RoundingMode,
) -> Decimal {
  match self.class {
    FpClass::Finite =>
      normalize_decimal_parts_gda_repr(
        self.negative,
        self.coefficient,
        self.exponent10,
        precision,
        DecimalRoundingMode::from_arithmetic(mode),
      )
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}
