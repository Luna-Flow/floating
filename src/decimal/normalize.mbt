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
  quotient : DecCoeff,
  remainder : DecCoeff,
  divisor : DecCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> Bool {
  if remainder.is_zero() {
    return false
  }
  let half_cmp = dec_coeff_compare_repr(
    dec_coeff_multiply_by_unit_repr(remainder, 2),
    divisor,
  )
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    HalfEven => half_cmp > 0 || (half_cmp == 0 && dec_coeff_is_odd(quotient))
    HalfUp => half_cmp >= 0
    HalfDown => half_cmp > 0
    ZeroFiveUp => {
      let last = quotient.units[0] % 10
      last == 0 || last == 5
    }
  }
}

///|
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
  numerator : DecCoeff,
  denominator : DecCoeff,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> DecCoeff {
  guard !denominator.is_zero() else {
    abort("round_positive_decimal_div_repr expects denominator > 0")
  }
  let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, denominator)
  if should_increment_decimal_repr(
      quotient, remainder, denominator, negative, mode,
    ) {
    dec_coeff_magnitude_add_unit(quotient, 1)
  } else {
    quotient
  }
}

///|
fn round_positive_decimal_div_pow10_repr(
  numerator : DecCoeff,
  shift : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (DecCoeff, Bool) {
  guard shift >= 0 else {
    abort("round_positive_decimal_div_pow10_repr expects non-negative shift")
  }
  if numerator.is_zero() || shift == 0 {
    return (numerator, false)
  }
  let digits = numerator.digits10()
  if shift < digits {
    let divisor = dec_coeff_shift_power10_repr(dec_coeff_from_int(1), shift)
    let (_, remainder) = dec_coeff_div_rem_repr(numerator, divisor)
    return (
      round_positive_decimal_div_repr(numerator, divisor, negative, mode),
      !remainder.is_zero(),
    )
  }
  let has_remainder = true
  let should_increment = match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    ZeroFiveUp => true
    HalfEven =>
      if shift != digits {
        false
      } else {
        dec_coeff_compare_repr(
          numerator,
          dec_coeff_multiply_by_unit_repr(
            dec_coeff_shift_power10_repr(dec_coeff_from_int(1), digits - 1),
            5,
          ),
        ) >
        0
      }
    HalfUp =>
      if shift != digits {
        false
      } else {
        dec_coeff_compare_repr(
          numerator,
          dec_coeff_multiply_by_unit_repr(
            dec_coeff_shift_power10_repr(dec_coeff_from_int(1), digits - 1),
            5,
          ),
        ) >=
        0
      }
    HalfDown =>
      if shift != digits {
        false
      } else {
        dec_coeff_compare_repr(
          numerator,
          dec_coeff_multiply_by_unit_repr(
            dec_coeff_shift_power10_repr(dec_coeff_from_int(1), digits - 1),
            5,
          ),
        ) >
        0
      }
  }
  (
    if should_increment {
      dec_coeff_from_int(1)
    } else {
      dec_coeff_zero()
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
  magnitude : DecCoeff,
  exponent10 : Int,
  precision : Int,
  mode : DecimalRoundingMode,
) -> Decimal {
  let precision = Int::max(1, precision)
  if magnitude.is_zero() {
    return finite_with_exponent_repr(negative, dec_coeff_zero(), 0, precision)
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
  magnitude : DecCoeff,
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
fn finite_precision_for(magnitude : BigInt, ctx : DecimalContext) -> Int {
  if ctx.precision == 0 {
    Int::max(1, digits10(magnitude))
  } else {
    Int::max(1, ctx.precision)
  }
}

///|
fn etiny(ctx : DecimalContext) -> Int {
  ctx.e_min - finite_precision_for(bigint_one(), ctx) + 1
}

///|
let decimal_coeff_residue_map : Array[Int] = [0, 3, 3, 3, 3, 5, 7, 7, 7, 7]

///|
fn decimal_round_should_bump(
  units : Array[Int],
  residue : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> Bool {
  if residue == 0 {
    return false
  }
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    HalfEven => residue > 5 || (residue == 5 && (units[0] & 0x01) == 1)
    HalfUp => residue >= 5
    HalfDown => residue > 5
    ZeroFiveUp => units[0] % 5 == 0
  }
}

///|
fn decimal_coeff_all_nines(units : Array[Int], digits : Int) -> Bool {
  let mut remaining = digits
  let mut index = 0
  while remaining > 0 {
    let width = Int::min(3, remaining)
    let nine_limit = if width == 3 { 999 } else if width == 2 { 99 } else { 9 }
    if units[index] != nine_limit {
      return false
    }
    remaining -= width
    index += 1
  }
  true
}

///|
fn decimal_coeff_make_one_followed_by_zeros(
  units : Array[Int],
  digits : Int,
) -> Unit {
  let unit_len = (digits + 2) / 3
  let mut index = 0
  while index < unit_len {
    units[index] = 0
    index += 1
  }
  let msu_index = unit_len - 1
  let msu_digits = digits - (unit_len - 1) * 3
  units[msu_index] = if msu_digits == 1 {
    1
  } else if msu_digits == 2 {
    10
  } else {
    100
  }
}

///|
fn decimal_coeff_bump_positive(
  units : Array[Int],
  digits : Int,
  exponent10 : Int,
) -> (Int, Int) {
  if decimal_coeff_all_nines(units, digits) {
    decimal_coeff_make_one_followed_by_zeros(units, digits)
    return (digits, exponent10 + 1)
  }
  let one = [1]
  ignore(dec_coeff_unit_add_sub(units, (digits + 2) / 3, one, 1, 0, units, 1))
  (digits, exponent10)
}

///|
fn decimal_round_coeff_to_digits_repr(
  magnitude : DecCoeff,
  exponent10 : Int,
  target_digits : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (DecCoeff, Int, Bool, Bool) {
  if magnitude.is_zero() {
    return (dec_coeff_zero(), 0, false, false)
  }
  let source_units = magnitude.units
  let source_digits = magnitude.digits
  let discard = source_digits - target_digits
  if discard <= 0 {
    return (magnitude, exponent10, false, false)
  }

  let kept_digits = if target_digits > 0 { target_digits } else { 1 }
  let kept_units = (kept_digits + 2) / 3
  let units : Array[Int] = []
  let mut pad = 0
  while pad < kept_units + 1 {
    units.push(0)
    pad += 1
  }

  let mut next_exponent = exponent10 + discard
  let mut residue = 0

  if discard > source_digits {
    let mut any_nonzero = false
    let mut index = 0
    while index < source_units.length() {
      if source_units[index] != 0 {
        any_nonzero = true
        break
      }
      index += 1
    }
    if any_nonzero {
      residue = 1
    }
    units[0] = 0
  } else {
    let mut count = 0
    let mut up = 0
    while true {
      count += 3
      if count >= discard {
        break
      }
      if source_units[up] != 0 {
        residue = 1
      }
      up += 1
    }

    let mut cut = discard - (count - 3) - 1
    if cut == 2 {
      let half = 500
      if source_units[up] >= half {
        if source_units[up] > half {
          residue = 7
        } else {
          residue += 5
        }
      } else if source_units[up] != 0 {
        residue = 3
      }
      if target_digits > 0 {
        let mut remaining = target_digits
        up += 1
        let mut target = 0
        while remaining > 0 {
          units[target] = source_units[up]
          target += 1
          up += 1
          remaining -= 3
        }
      }
    } else {
      let mut quot = if cut == 0 {
        source_units[up]
      } else {
        let divisor = if cut == 1 { 10 } else { 100 }
        let rem = source_units[up] % divisor
        let high = source_units[up] / divisor
        if rem != 0 {
          residue = 1
        }
        high
      }
      let discard1 = quot % 10
      quot = quot / 10
      residue += decimal_coeff_residue_map[discard1]
      cut += 1
      if target_digits > 0 {
        let mut remaining = target_digits
        let mut target = 0
        while true {
          units[target] = quot
          remaining -= 3 - cut
          if remaining <= 0 {
            break
          }
          up += 1
          let current = source_units[up]
          let divisor = if cut == 1 { 10 } else { 100 }
          let rem = current % divisor
          quot = current / divisor
          let multiplier = if cut == 1 { 100 } else { 10 }
          units[target] = units[target] + rem * multiplier
          remaining -= cut
          if remaining <= 0 {
            break
          }
          target += 1
        }
      }
    }
  }

  let rounded = true
  let inexact = residue != 0
  if decimal_round_should_bump(units, residue, negative, mode) {
    let (digits_after_bump, exponent_after_bump) = decimal_coeff_bump_positive(
      units, kept_digits, next_exponent,
    )
    next_exponent = exponent_after_bump
    let unit_len = dec_coeff_d2u(digits_after_bump)
    return (
      { units, digits: dec_coeff_get_digits(units, unit_len) },
      next_exponent,
      rounded,
      inexact,
    )
  }
  let unit_len = dec_coeff_d2u(kept_digits)
  (
    { units, digits: dec_coeff_get_digits(units, unit_len) },
    next_exponent,
    rounded,
    inexact,
  )
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
            dec_coeff_zero(),
            clamped_exponent,
            value.precision_,
          ),
          { ..flags, clamped: true },
        )
      }
    }
    return (value, flags)
  }
  let unrounded_adjusted = adjusted_exponent(value)
  let adjusted = adjusted_exponent(value)
  if !ctx.extended && adjusted < ctx.e_min {
    return (
      finite_with_exponent_repr(false, dec_coeff_zero(), 0, value.precision_),
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
    if unrounded_adjusted < ctx.e_min {
      flags = { ..flags, subnormal: true }
    }
    if inexact {
      flags = { ..flags, inexact: true }
      if unrounded_adjusted < ctx.e_min {
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
        dec_coeff_shift_power10_repr(value.coefficient, shift),
        e_top,
        value.precision_,
      )
      flags = { ..flags, clamped: true }
    }
  }
  (value, flags)
}

///|
fn normalize_decimal_parts_ctx(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int,
  ctx : DecimalContext,
  apply_etiny? : Bool = true,
) -> (Decimal, DecimalFlags) {
  normalize_decimal_parts_ctx_repr(
    negative,
    coeff_from_bigint(abs_bigint(magnitude)),
    exponent10,
    ctx,
    apply_etiny~,
  )
}

///|
fn normalize_decimal_parts_ctx_repr(
  negative : Bool,
  magnitude : DecCoeff,
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
    let unrounded_adjusted = exponent10 + magnitude.digits10() - 1
    let tiny = etiny(ctx)
    let shift = tiny - exponent10
    let target_digits = magnitude.digits10() - shift
    let (rounded_magnitude0, next_exponent0, _, inexact) = decimal_round_coeff_to_digits_repr(
      magnitude,
      exponent10,
      target_digits,
      negative,
      ctx.decimal_rounding,
    )
    let (rounded_magnitude, next_exponent) = if !rounded_magnitude0.is_zero() &&
      tiny < next_exponent0 {
      let restore_shift = next_exponent0 - tiny
      let restored = dec_coeff_shift_power10_repr(
        rounded_magnitude0, restore_shift,
      )
      if restored.digits10() <= precision {
        (restored, tiny)
      } else {
        (rounded_magnitude0, next_exponent0)
      }
    } else {
      (rounded_magnitude0, next_exponent0)
    }
    flags = { ..flags, rounded: true }
    if unrounded_adjusted < ctx.e_min {
      flags = { ..flags, subnormal: true }
    }
    if inexact {
      flags = { ..flags, inexact: true }
      if unrounded_adjusted < ctx.e_min {
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
        dec_coeff_shift_power10_repr(value.coefficient, shift),
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
      dec_coeff_shift_power10_repr(value.coefficient, value.exponent10),
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
    ctx.e_max - finite_precision_for(bigint_zero(), ctx) + 1
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
