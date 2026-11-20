///|
// Rounding decisions as pure functions of a coefficient and the digits that
// were discarded. They answer one question, "does the kept magnitude grow by
// one unit in the last place?", for the eight rounding directions; the
// standard-specific code around them (precision, exponent range, flags,
// subnormal and overflow handling) stays in `decimal` and `decimal_gda`.

///|
/// The eight rounding directions. Each decimal package converts its own
/// rounding-mode type into this one; the kernel does not know either type.
#derive(Eq)
pub(all) enum DecCoeffRounding {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
}

///|
/// Whether `quotient` is incremented when the exact value is
/// `quotient + remainder / divisor` with `0 <= remainder < divisor`.
fn dec_coeff_should_increment_bigint(
  quotient : BigInt,
  remainder : BigInt,
  divisor : BigInt,
  negative : Bool,
  mode : DecCoeffRounding,
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
pub fn dec_coeff_should_increment(
  quotient : DecCoeff,
  remainder : DecCoeff,
  divisor : DecCoeff,
  negative : Bool,
  mode : DecCoeffRounding,
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
      let half_cmp = dec_coeff_compare_repr(
        dec_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      )
      half_cmp > 0 || (half_cmp == 0 && dec_coeff_is_odd(quotient))
    }
    HalfUp =>
      dec_coeff_compare_repr(
        dec_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      ) >=
      0
    HalfDown =>
      dec_coeff_compare_repr(
        dec_coeff_multiply_by_unit_repr(remainder, 2),
        divisor,
      ) >
      0
    ZeroFiveUp => {
      let last = dec_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10
      last == 0 || last == 5
    }
  }
}

///|
/// `numerator / denominator` rounded to an integer in the given direction.
pub fn dec_coeff_round_div_bigint(
  numerator : BigInt,
  denominator : BigInt,
  negative : Bool,
  mode : DecCoeffRounding,
) -> BigInt {
  guard numerator >= BigInt::from_int(0) else {
    abort("dec_coeff_round_div_bigint expects non-negative numerator")
  }
  guard denominator > BigInt::from_int(0) else {
    abort("denominator must be positive")
  }
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  if dec_coeff_should_increment_bigint(
      quotient, remainder, denominator, negative, mode,
    ) {
    quotient + BigInt::from_int(1)
  } else {
    quotient
  }
}

///|
/// `numerator / denominator` rounded to an integer in the given direction.
pub fn dec_coeff_round_div(
  numerator : DecCoeff,
  denominator : DecCoeff,
  negative : Bool,
  mode : DecCoeffRounding,
) -> DecCoeff {
  guard !denominator.is_zero() else {
    abort("dec_coeff_round_div expects denominator > 0")
  }
  let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, denominator)
  if dec_coeff_should_increment(
      quotient, remainder, denominator, negative, mode,
    ) {
    dec_coeff_magnitude_add_unit(quotient, 1)
  } else {
    quotient
  }
}

///|
/// Whether the kept magnitude grows by one unit when `10^shift` divides the
/// numerator with a nonzero remainder: `half_cmp` is the sign of
/// `2 * remainder - 10^shift`, `last_limb` the lowest limb of the quotient.
fn dec_coeff_pow10_round_increment(
  last_limb : UInt32,
  half_cmp : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> Bool {
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    ZeroFiveUp => {
      let last = last_limb.reinterpret_as_int() % 10
      last == 0 || last == 5
    }
    HalfEven => half_cmp > 0 || (half_cmp == 0 && (last_limb & 0x01U) == 1U)
    HalfUp => half_cmp >= 0
    HalfDown => half_cmp > 0
  }
}

///|
/// Shifts the limbs `src[0..src_len)` of a value of `digits` digits right by
/// `shift` digits (`0 < shift < digits`) into `dst` and returns what the
/// rounding needs, packed as `has_remainder + 2 * (half_cmp + 1)`: the digit
/// at position `shift - 1` and the digits below it are read before anything is
/// written, then one pass writes the `ceil((digits - shift) / 9)` limbs of the
/// quotient with one division by `10^(shift mod 9)` per source limb. `dst` may
/// be `src` itself: limb `k` of the result is written after limb `k + 1` of the
/// source was read and the write index never passes the read index.
fn dec_coeff_round_info_bits(src : Array[UInt32], shift : Int32) -> Int32 {
  let position = shift - 1
  let round_limb = position / dec_coeff_dpun
  let round_offset = position - round_limb * dec_coeff_dpun
  let limb = src[round_limb].reinterpret_as_int()
  let scale = dec_coeff_powers[round_offset]
  let round_digit = limb / scale % 10
  let mut lower_nonzero = limb % scale != 0
  if !lower_nonzero {
    for index in 0..<round_limb {
      if src[index] != 0U {
        lower_nonzero = true
        break
      }
    }
  }
  let has_remainder = round_digit != 0 || lower_nonzero
  let half_cmp = if round_digit < 5 {
    -1
  } else if round_digit > 5 || lower_nonzero {
    1
  } else {
    0
  }
  (if has_remainder { 1 } else { 0 }) + 2 * (half_cmp + 1)
}

///|
fn dec_coeff_shift_right_info(
  src : Array[UInt32],
  src_len : Int32,
  digits : Int32,
  shift : Int32,
  dst : Array[UInt32],
) -> Int32 {
  let info = dec_coeff_round_info_bits(src, shift)
  let whole = shift / dec_coeff_dpun
  let cut = shift - whole * dec_coeff_dpun
  let out_len = (digits - shift + dec_coeff_dpun - 1) / dec_coeff_dpun
  if cut == 0 {
    for index in 0..<out_len {
      dst[index] = src[whole + index]
    }
  } else {
    let divisor = dec_coeff_powers[cut]
    let multiplier = dec_coeff_powers[dec_coeff_dpun - cut]
    let mut current = src[whole].reinterpret_as_int() / divisor
    for index in 0..<out_len {
      let next = whole + index + 1
      if next < src_len {
        let value = src[next].reinterpret_as_int()
        let quotient = value / divisor
        dst[index] = (current + (value - quotient * divisor) * multiplier).reinterpret_as_uint()
        current = quotient
      } else {
        dst[index] = current.reinterpret_as_uint()
      }
    }
  }
  info
}

///|
/// Finishes a rounded quotient held in `units[0..len)` (limbs below the base,
/// no leading zero limb): adds the rounding unit in place when `increment`,
/// carrying through the limbs and appending one limb only when every limb
/// carried, and builds the coefficient (two limbs or fewer are always below
/// `10^18`, hence `Small`).
fn dec_coeff_finish_owned_units(
  units : Array[UInt32],
  len : Int32,
  increment : Bool,
) -> DecCoeff {
  let mut len = len
  if units.length() > len {
    units.truncate(len)
  }
  if increment {
    let mut index = 0
    while index < len {
      let value = units[index] + 1U
      if value == 1000000000U {
        units[index] = 0U
        index += 1
      } else {
        units[index] = value
        break
      }
    }
    if index == len {
      units.push(1U)
      len += 1
    }
  }
  if len <= 2 {
    let high = if len == 2 {
      units[1].to_uint64() * dec_coeff_wide_base
    } else {
      0UL
    }
    return Small(units[0].to_uint64() + high)
  }
  let digits = (len - 1) * dec_coeff_dpun +
    dec_coeff_small_digits(units[len - 1].to_uint64())
  Limbs(units, digits)
}

///|
/// `numerator / 10^shift` rounded to an integer in the given direction, and
/// whether the division was inexact. A coefficient of more than one word is
/// shifted and rounded in one pass into one new array (the rounding unit is
/// added there in place); only the whole-value cases (`shift` at least the
/// digit count) take the general path through
/// `dec_coeff_div_pow10_round_info_repr`.
pub fn dec_coeff_round_div_pow10(
  numerator : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Bool) {
  guard shift >= 0 else {
    abort("dec_coeff_round_div_pow10 expects non-negative shift")
  }
  if numerator is Limbs(units, digits) && shift > 0 && shift < digits {
    let out_len = (digits - shift + dec_coeff_dpun - 1) / dec_coeff_dpun
    let result = Array::make(out_len, 0U)
    let info = dec_coeff_shift_right_info(
      units,
      units.length(),
      digits,
      shift,
      result,
    )
    let has_remainder = (info & 1) == 1
    let increment = has_remainder &&
      dec_coeff_pow10_round_increment(
        result[0],
        (info >> 1) - 1,
        negative,
        mode,
      )
    return (
      dec_coeff_finish_owned_units(result, out_len, increment),
      has_remainder,
    )
  }
  let (quotient, has_remainder, half_cmp) = dec_coeff_div_pow10_round_info_repr(
    numerator, shift,
  )
  if !has_remainder {
    return (quotient, false)
  }
  let should_increment = dec_coeff_pow10_round_increment(
    dec_coeff_limb_at(quotient, 0),
    half_cmp,
    negative,
    mode,
  )
  (
    if should_increment {
      dec_coeff_magnitude_add_unit(quotient, 1)
    } else {
      quotient
    },
    has_remainder,
  )
}

///|
/// The same rounding for a caller that owns the limb array of a value of
/// `digits` digits (`units.length() == ceil(digits / 9)`, limbs below the
/// base, no leading zero limb, `shift >= 0`): the array is shifted, rounded
/// and truncated in place and becomes the limbs of the result, so nothing is
/// copied. The caller must not use `units` afterwards.
pub fn dec_coeff_round_div_pow10_owned(
  units : Array[UInt32],
  digits : Int32,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Bool) {
  guard shift >= 0 && digits >= 1 else {
    abort("dec_coeff_round_div_pow10_owned expects shift >= 0 and digits >= 1")
  }
  guard units.length() == (digits + dec_coeff_dpun - 1) / dec_coeff_dpun else {
    abort("dec_coeff_round_div_pow10_owned expects one limb per nine digits")
  }
  if shift == 0 || shift >= digits {
    let value = dec_coeff_from_unit_accumulator(units, units.length())
    return dec_coeff_round_div_pow10(value, shift, negative, mode)
  }
  let out_len = (digits - shift + dec_coeff_dpun - 1) / dec_coeff_dpun
  let info = dec_coeff_shift_right_info(
    units,
    units.length(),
    digits,
    shift,
    units,
  )
  let has_remainder = (info & 1) == 1
  let increment = has_remainder &&
    dec_coeff_pow10_round_increment(units[0], (info >> 1) - 1, negative, mode)
  (dec_coeff_finish_owned_units(units, out_len, increment), has_remainder)
}

///|
/// Rounds `magnitude` to `target_digits` digits. Returns the rounded
/// magnitude, the exponent adjusted by the number of discarded digits, whether
/// any digit was discarded, and whether the result is inexact.
pub fn dec_coeff_round_to_digits(
  magnitude : DecCoeff,
  exponent10 : Int32,
  target_digits : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Int32, Bool, Bool) {
  if magnitude.is_zero() {
    return (dec_coeff_zero(), 0, false, false)
  }
  let discard = magnitude.digits10() - target_digits
  if discard <= 0 {
    return (magnitude, exponent10, false, false)
  }
  let (rounded_magnitude, inexact) = dec_coeff_round_div_pow10(
    magnitude, discard, negative, mode,
  )
  (rounded_magnitude, exponent10 + discard, true, inexact)
}

///|
/// The rounded value (0 or 1) of a nonzero `coefficient` that a shift to the
/// right by more digits than it has leaves behind.
pub fn dec_coeff_huge_shift_rounded_unit(
  coefficient : DecCoeff,
  negative : Bool,
  mode : DecCoeffRounding,
) -> DecCoeff {
  guard !coefficient.is_zero() else { return dec_coeff_zero() }
  match mode {
    Down | HalfEven | HalfUp | HalfDown => dec_coeff_zero()
    Up | ZeroFiveUp => dec_coeff_from_int(1)
    Ceiling => if negative { dec_coeff_zero() } else { dec_coeff_from_int(1) }
    Floor => if negative { dec_coeff_from_int(1) } else { dec_coeff_zero() }
  }
}

///|
/// Whether a square-root quotient is incremented, given the sign of
/// `2 * remainder - (2 * quotient + 1)` as `midpoint_cmp`.
pub fn dec_coeff_sqrt_should_increment(
  quotient : DecCoeff,
  midpoint_cmp : Int32,
  inexact : Bool,
  mode : DecCoeffRounding,
) -> Bool {
  guard inexact else { return false }
  match mode {
    Down | Floor => false
    Up | Ceiling => true
    HalfUp => midpoint_cmp >= 0
    HalfDown => midpoint_cmp > 0
    HalfEven =>
      midpoint_cmp > 0 || (midpoint_cmp == 0 && dec_coeff_is_odd(quotient))
    ZeroFiveUp =>
      dec_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10 == 0 ||
      dec_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10 == 5
  }
}

///|
/// The step (-1, 0 or 1 unit in the last place) that a much smaller addend
/// of one sign moves a base value by, from the comparison of the addend with
/// half a unit and the direction of rounding.
pub fn dec_coeff_addend_rounding_step(
  base_is_odd : Bool,
  base_ends_zero_or_five : Bool,
  base_negative : Bool,
  low_negative : Bool,
  cmp_half : Int32,
  mode : DecCoeffRounding,
) -> Int32 {
  let delta_direction = if low_negative { -1 } else { 1 }
  let away_from_zero_direction = if base_negative { -1 } else { 1 }
  let toward_zero_direction = -away_from_zero_direction
  match mode {
    HalfEven =>
      if cmp_half > 0 {
        delta_direction
      } else if cmp_half < 0 {
        0
      } else if !base_is_odd {
        0
      } else {
        delta_direction
      }
    HalfUp =>
      if cmp_half > 0 {
        delta_direction
      } else if cmp_half < 0 {
        0
      } else if low_negative == base_negative {
        delta_direction
      } else {
        0
      }
    HalfDown =>
      if cmp_half > 0 {
        delta_direction
      } else if cmp_half < 0 {
        0
      } else if low_negative != base_negative {
        delta_direction
      } else {
        0
      }
    Ceiling => if delta_direction > 0 { 1 } else { 0 }
    Floor => if delta_direction < 0 { -1 } else { 0 }
    Up =>
      if low_negative == base_negative {
        away_from_zero_direction
      } else {
        0
      }
    Down =>
      if low_negative != base_negative {
        toward_zero_direction
      } else {
        0
      }
    ZeroFiveUp => if base_ends_zero_or_five { delta_direction } else { 0 }
  }
}

///|
/// Digit count of a limb accumulator (`units[0..unit_len)`, limbs below the
/// base, leading zero limbs allowed; an all-zero accumulator has one digit).
pub fn dec_coeff_accumulator_digits(
  units : Array[UInt32],
  unit_len : Int32,
) -> Int32 {
  guard unit_len >= 1 else {
    abort("dec_coeff_accumulator_digits expects unit_len >= 1")
  }
  dec_coeff_get_digits(units, dec_coeff_trim_units(units, unit_len))
}

///|
/// Whether discarding the lowest `discard` digits (`0 < discard < digits`) of a
/// limb accumulator drops a nonzero digit. Reads the accumulator only.
pub fn dec_coeff_accumulator_discards_nonzero(
  units : Array[UInt32],
  discard : Int32,
) -> Bool {
  guard discard >= 1 else {
    abort("dec_coeff_accumulator_discards_nonzero expects discard >= 1")
  }
  (dec_coeff_round_info_bits(units, discard) & 1) == 1
}

///|
/// Rounds a freshly produced limb accumulator (`units[0..unit_len)`, leading
/// zero limbs allowed) after discarding its lowest `discard` digits, in place
/// and without a copy: the array becomes the limbs of the result. `discard` is
/// below the digit count of the accumulator (`dec_coeff_accumulator_digits`),
/// or 0 for no rounding. The caller must not use `units` afterwards. This is
/// the entry for a producer that owns its array (the aligned sum of an
/// addition); it returns a coefficient only, so it allocates no tuple, and the
/// inexact flag is `dec_coeff_accumulator_discards_nonzero`, read first.
pub fn dec_coeff_round_accumulator(
  units : Array[UInt32],
  unit_len : Int32,
  discard : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> DecCoeff {
  guard unit_len >= 1 && discard >= 0 else {
    abort("dec_coeff_round_accumulator expects unit_len >= 1 and discard >= 0")
  }
  let trimmed = dec_coeff_trim_units(units, unit_len)
  if discard == 0 {
    return dec_coeff_from_unit_accumulator(units, trimmed)
  }
  let digits = dec_coeff_get_digits(units, trimmed)
  guard discard < digits else {
    abort("dec_coeff_round_accumulator expects discard below the digit count")
  }
  if units.length() > trimmed {
    units.truncate(trimmed)
  }
  let out_len = (digits - discard + dec_coeff_dpun - 1) / dec_coeff_dpun
  let info = dec_coeff_shift_right_info(units, trimmed, digits, discard, units)
  let increment = (info & 1) == 1 &&
    dec_coeff_pow10_round_increment(units[0], (info >> 1) - 1, negative, mode)
  dec_coeff_finish_owned_units(units, out_len, increment)
}

///|
/// Whether discarding the lowest `shift` digits (`0 < shift < digits`) of a
/// coefficient drops a nonzero digit. Reads the coefficient only and returns
/// a scalar.
pub fn dec_coeff_discards_nonzero(coeff : DecCoeff, shift : Int32) -> Bool {
  guard shift >= 1 && shift < coeff.digits10() else {
    abort("dec_coeff_discards_nonzero expects 0 < shift < digits")
  }
  match coeff {
    Small(value) => value % dec_coeff_small_powers10[shift] != 0UL
    Limbs(units, _) => (dec_coeff_round_info_bits(units, shift) & 1) == 1
  }
}

///|
/// `numerator / 10^shift` rounded in the given direction (`0 < shift <
/// digits`), as `dec_coeff_round_div_pow10` but returning the coefficient
/// only, so it allocates no tuple; whether the division was inexact is
/// `dec_coeff_discards_nonzero`.
pub fn dec_coeff_round_pow10_coeff(
  numerator : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> DecCoeff {
  guard shift >= 1 && shift < numerator.digits10() else {
    abort("dec_coeff_round_pow10_coeff expects 0 < shift < digits")
  }
  match numerator {
    Limbs(units, digits) => {
      let out_len = (digits - shift + dec_coeff_dpun - 1) / dec_coeff_dpun
      let result = Array::make(out_len, 0U)
      let info = dec_coeff_shift_right_info(
        units,
        units.length(),
        digits,
        shift,
        result,
      )
      let increment = (info & 1) == 1 &&
        dec_coeff_pow10_round_increment(
          result[0],
          (info >> 1) - 1,
          negative,
          mode,
        )
      dec_coeff_finish_owned_units(result, out_len, increment)
    }
    Small(value) => {
      let divisor = dec_coeff_small_powers10[shift]
      let quotient = value / divisor
      let remainder = value % divisor
      let twice = remainder * 2UL
      let half_cmp = if twice < divisor {
        -1
      } else if twice > divisor {
        1
      } else {
        0
      }
      let increment = remainder != 0UL &&
        dec_coeff_pow10_round_increment(
          (quotient % 1000000000UL).to_uint(),
          half_cmp,
          negative,
          mode,
        )
      Small(if increment { quotient + 1UL } else { quotient })
    }
  }
}
