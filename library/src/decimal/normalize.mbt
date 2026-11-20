///|
fn should_increment_decimal_repr(
  quotient : DecCoeff,
  remainder : DecCoeff,
  divisor : DecCoeff,
  negative : Bool,
  mode : DecimalRound,
) -> Bool {
  dec_coeff_should_increment(
    quotient,
    remainder,
    divisor,
    negative,
    mode.kernel(),
  )
}

///|
#warnings("-unused_value")
fn round_positive_decimal_div(
  numerator : BigInt,
  denominator : BigInt,
  negative : Bool,
  mode : DecimalRound,
) -> BigInt {
  dec_coeff_round_div_bigint(numerator, denominator, negative, mode.kernel())
}

///|
fn round_positive_decimal_div_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
  negative : Bool,
  mode : DecimalRound,
) -> DecCoeff {
  dec_coeff_round_div(numerator, denominator, negative, mode.kernel())
}

///|
fn round_positive_decimal_div_pow10_repr(
  numerator : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecimalRound,
) -> (DecCoeff, Bool) {
  dec_coeff_round_div_pow10(numerator, shift, negative, mode.kernel())
}

///|
fn normalize_decimal_parts(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode : DecimalRound,
) -> Decimal {
  normalize_decimal_parts_gda(negative, magnitude, exponent10, precision, mode)
}

///|
fn normalize_decimal_parts_gda(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode : DecimalRound,
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
  magnitude : DecCoeff,
  exponent10 : Int32,
  precision : Int32,
  mode : DecimalRound,
) -> Decimal {
  let precision = Int32::max(1, precision)
  if magnitude.is_zero() {
    return finite_with_exponent_repr(negative, dec_coeff_zero(), 0, precision)
  }
  if exponent10.to_int64() + (magnitude.digits10() - 1).to_int64() >=
    2147483647L {
    // At the top of `Int` a carry would wrap the exponent: round in `Int64`
    // and overflow as IEEE 754 §7.4 prescribes for the rounding mode.
    return context_free_round_wide(
      negative,
      magnitude,
      exponent10.to_int64(),
      precision,
      round_to_precision=true,
      reduce=true,
      mode~,
    )
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
  preferred_exponent : Int32,
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
      dec_coeff_shift_power10_repr(value.coefficient, shift),
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
  exponent10 : Int32,
  precision : Int32,
) -> Decimal {
  {
    class: FpClass::Finite,
    negative,
    coefficient: coeff_from_bigint(magnitude),
    exponent10,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
  }
}

///|
fn finite_with_exponent_repr(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int32,
  precision : Int32,
) -> Decimal {
  {
    class: FpClass::Finite,
    negative,
    coefficient: magnitude,
    exponent10,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
  }
}

///|
fn finite_precision_for(magnitude : BigInt, ctx : DecimalContext) -> Int32 {
  if ctx.precision == 0 {
    Int32::max(1, digits10(magnitude))
  } else {
    Int32::max(1, ctx.precision)
  }
}

///|
fn decimal_int_from_int64_clamped(value : Int64) -> Int32 {
  if value < -2_147_483_648L {
    -2_147_483_648
  } else if value > 2_147_483_647L {
    2_147_483_647
  } else {
    value.to_int()
  }
}

///|
/// `finite_precision_for` of a zero or one-digit magnitude, without building
/// the `BigInt`.
fn finite_precision_for_default(ctx : DecimalContext) -> Int32 {
  if ctx.precision == 0 {
    1
  } else {
    Int32::max(1, ctx.precision)
  }
}

///|
/// The smallest exponent of the context, `e_min - precision + 1` clamped to
/// `Int32`: the `etiny` of `DecimalExponentBounds`, without building one (nor
/// the `BigInt` one that gives the default precision).
fn etiny(ctx : DecimalContext) -> Int32 {
  decimal_int_from_int64_clamped(
    ctx.e_min.to_int64() - finite_precision_for_default(ctx).to_int64() + 1L,
  )
}

///|
fn adjusted_exponent64(x : Decimal) -> Int64 {
  if x.class != FpClass::Finite || x.coefficient.is_zero() {
    x.exponent10.to_int64()
  } else {
    x.exponent10.to_int64() + x.coefficient.digits10().to_int64() - 1L
  }
}

///|
/// `e_max - precision + 1` clamped to `Int32`: the `etop` of
/// `DecimalExponentBounds`, without building one.
fn etop(ctx : DecimalContext, precision : Int32) -> Int32 {
  decimal_int_from_int64_clamped(
    ctx.e_max.to_int64() - precision.to_int64() + 1L,
  )
}

///|
fn tiny_for_underflow(ctx : DecimalContext, before_adjusted : Int64) -> Bool {
  before_adjusted < ctx.e_min.to_int64()
}

///|
fn decimal_round_coeff_to_digits_repr(
  magnitude : DecCoeff,
  exponent10 : Int32,
  target_digits : Int32,
  negative : Bool,
  mode : DecimalRound,
) -> (DecCoeff, Int32, Bool, Bool) {
  dec_coeff_round_to_digits(
    magnitude,
    exponent10,
    target_digits,
    negative,
    mode.kernel(),
  )
}

///|
fn adjusted_exponent(x : Decimal) -> Int32 {
  if x.class != FpClass::Finite || x.coefficient.is_zero() {
    x.exponent10
  } else {
    decimal_int_from_int64_clamped(
      x.exponent10.to_int64() + x.coefficient.digits10().to_int64() - 1L,
    )
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
        etop(ctx, value.precision_)
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
            dec_coeff_zero(),
            clamped_exponent,
            value.precision_,
          ),
          flags,
        )
      }
    }
    return (value, flags)
  }
  let unrounded_adjusted = adjusted_exponent64(value)
  let adjusted = unrounded_adjusted

  if adjusted > ctx.e_max.to_int64() {
    let (overflowed, overflow_flags) = decimal_overflow_result(
      value.negative,
      ctx,
    )
    return (overflowed, flags.combine(overflow_flags))
  }
  let mut value = value
  let mut flags = flags
  let tiny_limit = etiny(ctx)
  if ctx.precision > 0 && value.exponent10 < tiny_limit {
    let shift = decimal_int_from_int64_clamped(
      tiny_limit.to_int64() - value.exponent10.to_int64(),
    )
    let target_digits = value.coefficient.digits10() - shift
    let (magnitude, next_exponent, _, inexact) = decimal_round_coeff_to_digits_repr(
      value.coefficient,
      value.exponent10,
      target_digits,
      value.negative,
      ctx.decimal_rounding,
    )
    let tiny = tiny_for_underflow(ctx, unrounded_adjusted)
    if inexact {
      flags = { ..flags, inexact: true, }
      if tiny {
        flags = { ..flags, underflow: true, }
      }
    }
    value = finite_with_exponent_repr(
      value.negative,
      magnitude,
      next_exponent,
      value.precision_,
    )
    if value.coefficient.is_zero() {
      return (value, flags)
    }
  }
  if adjusted_exponent64(value) < ctx.e_min.to_int64() && flags.inexact {
    flags = { ..flags, underflow: true, }
  }
  if ctx.clamp && ctx.precision > 0 {
    let e_top = etop(ctx, ctx.precision)
    if value.exponent10 > e_top {
      let shift = decimal_int_from_int64_clamped(
        value.exponent10.to_int64() - e_top.to_int64(),
      )
      value = finite_with_exponent_repr(
        value.negative,
        dec_coeff_shift_power10_repr(value.coefficient, shift),
        e_top,
        value.precision_,
      )
    }
  }
  (value, flags)
}

///|
fn normalize_decimal_parts_ctx_repr(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int32,
  ctx : DecimalContext,
  apply_etiny~ : Bool = true,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(magnitude, ctx)
  let mut flags = DecimalFlags::new()
  let mut magnitude = magnitude
  let mut exponent10 = exponent10
  let tiny_limit = etiny(ctx)
  let initial_digits = magnitude.digits10()
  // Round to the subnormal grid only when the exact value is itself below the
  // normal range. A longer coefficient whose exponent is below Etiny but whose
  // magnitude is normal is rounded once, to `precision` digits, below; rounding
  // it to Etiny first and then to `precision` digits would round twice.
  if apply_etiny &&
    ctx.precision > 0 &&
    !magnitude.is_zero() &&
    exponent10.to_int64() + Int32::max(0, initial_digits - precision).to_int64() <
    tiny_limit.to_int64() {
    let unrounded_adjusted = exponent10.to_int64() +
      (initial_digits - 1).to_int64()
    let etiny_value = tiny_limit
    let shift = decimal_int_from_int64_clamped(
      etiny_value.to_int64() - exponent10.to_int64(),
    )
    let target_digits = initial_digits - shift
    let (rounded_magnitude0, next_exponent0, _, inexact) = decimal_round_coeff_to_digits_repr(
      magnitude,
      exponent10,
      target_digits,
      negative,
      ctx.decimal_rounding,
    )
    let (rounded_magnitude, next_exponent) = if !rounded_magnitude0.is_zero() &&
      etiny_value.to_int64() < next_exponent0.to_int64() {
      let restore_shift = decimal_int_from_int64_clamped(
        next_exponent0.to_int64() - etiny_value.to_int64(),
      )
      let restored = dec_coeff_shift_power10_repr(
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
    let tiny_result = tiny_for_underflow(ctx, unrounded_adjusted)
    if inexact {
      flags = { ..flags, inexact: true, }
      if tiny_result {
        flags = { ..flags, underflow: true, }
      }
    }
    magnitude = rounded_magnitude
    exponent10 = next_exponent
  }
  let mut digits = magnitude.digits10()
  let magnitude = if ctx.precision > 0 &&
    !magnitude.is_zero() &&
    digits > precision {
    let max_drop = digits - precision
    let (trimmed, trimmed_exp, dropped) = trim_trailing_decimal_zeros_repr(
      magnitude,
      exponent10,
      max_drop~,
    )
    if dropped > 0 {
      exponent10 = trimmed_exp
      digits = trimmed.digits10()
    }
    trimmed
  } else {
    magnitude
  }
  let magnitude = if ctx.precision > 0 &&
    !magnitude.is_zero() &&
    digits > precision {
    let (rounded_magnitude, next_exponent, _, inexact) = decimal_round_coeff_to_digits_repr(
      magnitude,
      exponent10,
      precision,
      negative,
      ctx.decimal_rounding,
    )
    exponent10 = next_exponent
    if inexact {
      flags = { ..flags, inexact: true, }
    }
    digits = rounded_magnitude.digits10()
    rounded_magnitude
  } else {
    magnitude
  }
  let magnitude = if ctx.precision > 0 && digits > precision {
    // The carry into 10^p moves the exponent up by one; at the top of `Int` it
    // would wrap, and such a value is beyond e_max anyway.
    if exponent10 == 2147483647 {
      return decimal_overflow_result(negative, ctx)
    }
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
// Exponents are stored as `Int`, but the exponent of an exact product or of a
// literal can lie outside it. Exponent arithmetic on such values is done in
// `Int64` and brought back here.
fn exponent10_from_int64(value : Int64) -> Int32? {
  if value < -2147483648L || value > 2147483647L {
    None
  } else {
    Some(value.to_int())
  }
}

///|
// Represents `magnitude * 10^exponent10` with an `Int` exponent. Digits below
// 10^(Int::min_value + 1) are folded into the last kept digit with ZeroFiveUp
// rounding (the last digit is 0 or 5 only when the fold is exact), so any
// later rounding at a higher position gives the same result as rounding the
// exact value once. The flag reports whether non-zero digits were folded.
// Exponents above `Int` are saturated; callers reject them first.
fn fold_exponent10_into_int_repr(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int64,
) -> (DecCoeff, Int32, Bool) {
  if exponent10_from_int64(exponent10) is Some(exponent) {
    return (magnitude, exponent, false)
  }
  if exponent10 > 0L || magnitude.is_zero() {
    return (magnitude, scaleb_int64_to_int(exponent10), false)
  }
  let floor_exponent = -2147483647
  let shift = floor_exponent.to_int64() - exponent10
  if shift >= magnitude.digits10().to_int64() {
    return (dec_coeff_from_int(1), floor_exponent, true)
  }
  let (folded, inexact) = round_positive_decimal_div_pow10_repr(
    magnitude,
    shift.to_int(),
    negative,
    DecimalRound::ZeroFiveUp,
  )
  (folded, floor_exponent, inexact)
}

///|
// `normalize_decimal_parts_ctx_repr` for an exact result whose exponent may
// lie outside `Int`. A result whose unrounded adjusted exponent reaches the
// top of `Int` overflows every context; a result below `Int` is folded first.
fn normalize_decimal_parts_ctx_wide_repr(
  negative : Bool,
  magnitude : DecCoeff,
  exponent10 : Int64,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if !magnitude.is_zero() {
    let adjusted = exponent10 + (magnitude.digits10() - 1).to_int64()
    if adjusted >= 2147483647L && adjusted > ctx.e_max.to_int64() {
      return decimal_overflow_result(negative, ctx)
    }
  }
  let (folded, exponent, inexact) = fold_exponent10_into_int_repr(
    negative, magnitude, exponent10,
  )
  let (value, flags) = normalize_decimal_parts_ctx_repr(
    negative, folded, exponent, ctx,
  )
  if inexact {
    (value, { ..flags, inexact: true, })
  } else {
    (value, flags)
  }
}

///|
fn with_underflow_for_inexact_subnormal(
  value : Decimal,
  flags : DecimalFlags,
  ctx : DecimalContext,
) -> DecimalFlags {
  if flags.inexact &&
    value.class == FpClass::Finite &&
    adjusted_exponent64(value) < ctx.e_min.to_int64() {
    { ..flags, underflow: true, }
  } else {
    flags
  }
}

///|
fn expand_finite_cohort_toward_target_exponent(
  value : Decimal,
  target : Int32,
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
      dec_coeff_shift_power10_repr(value.coefficient, shift),
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
  preferred_exponent : Int32,
  ctx : DecimalContext,
) -> Decimal {
  guard value.class == FpClass::Finite &&
    ctx.precision > 0 &&
    !value.coefficient.is_zero() &&
    preferred_exponent < value.exponent10 else {
    return value
  }
  let digits = value.coefficient.digits10()
  let available_shift = Int32::max(0, ctx.precision - digits)
  let wanted_shift = value.exponent10 - preferred_exponent
  let shift = Int32::min(wanted_shift, available_shift)
  if shift > 0 {
    finite_with_exponent_repr(
      value.negative,
      dec_coeff_shift_power10_repr(value.coefficient, shift),
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
  pad_precision~ : Bool = false,
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
    if shift > 0 && shift <= precision - digits {
      return finite_with_exponent_repr(
        value.negative,
        dec_coeff_shift_power10_repr(value.coefficient, shift),
        target,
        value.precision_,
      )
    }
  }
  guard pad_precision && adjusted_exponent64(value) >= ctx.e_min.to_int64() else {
    return value
  }
  let shift = precision - digits
  if shift > 0 {
    finite_with_exponent_repr(
      value.negative,
      dec_coeff_shift_power10_repr(value.coefficient, shift),
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
        DecimalRound::HalfEven,
      )
    _ => self
  }
}

///|
pub fn Decimal::with_precision(
  self : Decimal,
  precision : Int32,
  mode : DecimalRoundingMode,
) -> Decimal {
  let precision = decimal_check_precision("with_precision", precision)
  self.with_precision_round(precision, mode.round())
}

///|
fn Decimal::with_precision_round(
  self : Decimal,
  precision : Int32,
  mode : DecimalRound,
) -> Decimal {
  match self.class {
    FpClass::Finite =>
      normalize_decimal_parts_gda_repr(
        self.negative,
        self.coefficient,
        self.exponent10,
        precision,
        mode,
      )
    FpClass::Infinity => { ..self, precision_: precision, }
    FpClass::NaN => { ..self, precision_: precision, }
  }
}
