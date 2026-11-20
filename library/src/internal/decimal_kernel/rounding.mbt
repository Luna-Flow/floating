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
pub fn dec_coeff_should_increment_bigint(
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
/// `numerator / 10^shift` rounded to an integer in the given direction, and
/// whether the division was inexact. The comparison of twice the remainder
/// with `10^shift` is done on the limbs by `dec_coeff_div_pow10_round_info_repr`.
pub fn dec_coeff_round_div_pow10(
  numerator : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Bool) {
  guard shift >= 0 else {
    abort("dec_coeff_round_div_pow10 expects non-negative shift")
  }
  let (quotient, has_remainder, half_cmp) = dec_coeff_div_pow10_round_info_repr(
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
      let last = dec_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10
      last == 0 || last == 5
    }
    HalfEven => half_cmp > 0 || (half_cmp == 0 && dec_coeff_is_odd(quotient))
    HalfUp => half_cmp >= 0
    HalfDown => half_cmp > 0
  }
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
