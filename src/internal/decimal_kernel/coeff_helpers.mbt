///|
// Exact coefficient helpers that the decimal packages build their roots,
// logarithm series and exact-result checks on. Every function is an exact
// function of its arguments; none knows a context, a flag or a rounding
// mode other than through DecCoeffRounding.

///|
pub fn compare_finite_magnitude_repr(
  lhs_coefficient : DecCoeff,
  lhs_exponent10 : Int32,
  rhs_coefficient : DecCoeff,
  rhs_exponent10 : Int32,
) -> Int32 {
  if lhs_coefficient.is_zero() || rhs_coefficient.is_zero() {
    // zero compares below every nonzero magnitude
    return if lhs_coefficient.is_zero() {
      if rhs_coefficient.is_zero() {
        0
      } else {
        -1
      }
    } else {
      1
    }
  }
  let lhs_digits = lhs_coefficient.digits10()
  let rhs_digits = rhs_coefficient.digits10()
  // Adjusted exponents in Int64: the coefficient of an operand that is doubled
  // (nearest-quotient test) can gain a digit at the top of the `Int` range.
  let lhs_adjusted = lhs_exponent10.to_int64() + lhs_digits.to_int64() - 1L
  let rhs_adjusted = rhs_exponent10.to_int64() + rhs_digits.to_int64() - 1L
  if lhs_adjusted != rhs_adjusted {
    return if lhs_adjusted < rhs_adjusted { -1 } else { 1 }
  }
  if lhs_exponent10 <= rhs_exponent10 {
    dec_coeff_compare_scaled_repr(
      lhs_coefficient,
      rhs_coefficient,
      rhs_exponent10 - lhs_exponent10,
    )
  } else {
    -dec_coeff_compare_scaled_repr(
      rhs_coefficient,
      lhs_coefficient,
      lhs_exponent10 - rhs_exponent10,
    )
  }
}

///|
pub fn dec_coeff_integer_sqrt_rem_repr(n : DecCoeff) -> (DecCoeff, DecCoeff) {
  if dec_coeff_small_value(n) is Some(small) {
    if small <= 1UL {
      return (n, dec_coeff_zero())
    }
    let mut approximation = dec_coeff_small_powers10[(n.digits10() + 1) / 2]
    while true {
      let next = (approximation + small / approximation) / 2UL
      if next >= approximation {
        let square = approximation * approximation
        return (DecCoeff::Small(approximation), DecCoeff::Small(small - square))
      }
      approximation = next
    } nobreak {
      abort("small coefficient square-root iteration must terminate")
    }
  }
  if dec_coeff_compare_repr(n, dec_coeff_from_int(1)) <= 0 {
    return (n, dec_coeff_zero())
  }
  // Exact-integer specialization of GDA SquareRoot's Newton step
  // a = 0.5 * (a + f/a), using the same decimal Unit primitives
  // (decNumber.c lines 2965-2978).
  let mut approximation = dec_coeff_power10_repr((n.digits10() + 1) / 2)
  while true {
    let (quotient, _) = dec_coeff_div_rem_repr(n, approximation)
    let sum = dec_coeff_magnitude_add_repr(approximation, quotient)
    let next = dec_coeff_div_rem_by_unit_repr(sum, 2).0
    if dec_coeff_compare_repr(next, approximation) >= 0 {
      let square = dec_coeff_square_repr(approximation)
      return (approximation, dec_coeff_magnitude_sub_repr(n, square))
    }
    approximation = next
  } nobreak {
    (approximation, dec_coeff_zero())
  }
}

///|
pub fn has_finite_decimal_expansion_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Bool {
  guard !denominator.is_zero() else {
    abort("has_finite_decimal_expansion_repr expects denominator > 0")
  }
  let (without_tens, _, _) = trim_trailing_decimal_zeros_repr(denominator, 0)
  let without_twos = dec_coeff_remove_factor_unit_repr(without_tens, 2)
  let without_fives = dec_coeff_remove_factor_unit_repr(without_twos, 5)
  if dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 {
    return true
  }
  dec_coeff_div_rem_repr(numerator, without_fives).1.is_zero()
}

///|
pub fn decimal_small_pow10(shift : Int32) -> Int32 {
  guard shift >= 0 && shift < dec_coeff_dpun else {
    abort("decimal_small_pow10 shift exceeds one coefficient limb")
  }
  dec_coeff_powers[shift]
}

///|
pub fn is_power_of_ten_coeff(coeff : DecCoeff) -> Bool {
  let (reduced, _, dropped) = trim_trailing_decimal_zeros_repr(coeff, 0)
  dropped > 0 && dec_coeff_compare_repr(reduced, dec_coeff_from_int(1)) == 0
}

///|
/// `coeff * 10^shift mod modulus` for a shift beyond `Int`, reduced in chunks.
pub fn dec_coeff_shift_power10_mod_wide_repr(
  coeff : DecCoeff,
  shift : Int64,
  modulus : DecCoeff,
) -> DecCoeff {
  let mut value = dec_coeff_shift_power10_mod_repr(coeff, 0, modulus)
  let mut remaining = shift
  while remaining > 0L {
    let step = Int64::min(remaining, 1073741824L)
    value = dec_coeff_shift_power10_mod_repr(value, step.to_int(), modulus)
    remaining = remaining - step
  }
  value
}

///|
pub fn dec_coeff_to_bounded_int(coeff : DecCoeff, limit : Int32) -> Int32? {
  guard limit >= 0 else { return None }
  let unit_count = dec_coeff_d2u(coeff.digits10())
  let mut value = 0
  for i = unit_count - 1; i >= 0; i = i - 1 {
    let unit = dec_coeff_limb_at(coeff, i).reinterpret_as_int()
    let remaining = limit - unit
    guard remaining >= 0 && value <= remaining / dec_coeff_base else {
      return None
    }
    value = value * dec_coeff_base + unit
  }
  Some(value)
}

///|
pub fn decimal_round_scaled_coeff(
  value : SignedDecCoeff,
  shift : Int32,
) -> SignedDecCoeff {
  if shift <= 0 {
    return signed_dec_coeff(
      value.negative,
      dec_coeff_shift_power10_repr(value.magnitude, -shift),
    )
  }
  signed_dec_coeff(
    value.negative,
    dec_coeff_round_div_pow10(
      value.magnitude,
      shift,
      value.negative,
      DecCoeffRounding::HalfEven,
    ).0,
  )
}

///|
pub fn decimal_ln_atanh_scaled_coeff(
  numerator : DecCoeff,
  denominator : DecCoeff,
  scale : Int32,
) -> SignedDecCoeff {
  guard !numerator.is_zero() && !denominator.is_zero() else {
    abort("decimal_ln_atanh_scaled_coeff expects positive rational input")
  }
  let comparison = dec_coeff_compare_repr(numerator, denominator)
  if comparison == 0 {
    return signed_dec_coeff_zero()
  }
  let extra_digits = 8
  let work_scale = scale + extra_digits
  let negative = comparison < 0
  let delta = if negative {
    dec_coeff_magnitude_sub_repr(denominator, numerator)
  } else {
    dec_coeff_magnitude_sub_repr(numerator, denominator)
  }
  let sum = dec_coeff_magnitude_add_repr(numerator, denominator)
  let scale_factor = dec_coeff_power10_repr(work_scale)
  let delta2 = dec_coeff_square_repr(delta)
  let sum2 = dec_coeff_square_repr(sum)
  let mut power_num = delta
  let mut power_den = sum
  let mut divisor_index = 1
  let mut total = dec_coeff_zero()
  let stop_threshold = dec_coeff_power10_repr(extra_digits)
  let mut active = true
  while active {
    let divisor = dec_coeff_multiply_repr(
      power_den,
      dec_coeff_from_nonnegative_int(divisor_index),
    )
    let scaled_power = dec_coeff_multiply_repr(scale_factor, power_num)
    let term_numerator = dec_coeff_multiply_by_unit_repr(scaled_power, 2)
    let term = dec_coeff_div_rem_repr(term_numerator, divisor).0
    total = dec_coeff_magnitude_add_repr(total, term)
    if dec_coeff_compare_repr(term, stop_threshold) <= 0 {
      active = false
    } else {
      power_num = dec_coeff_multiply_repr(power_num, delta2)
      power_den = dec_coeff_multiply_repr(power_den, sum2)
      divisor_index += 2
    }
  }
  decimal_round_scaled_coeff(signed_dec_coeff(negative, total), extra_digits)
}

///|
pub fn decimal_floor_div_scaled_repr(
  negative : Bool,
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Int32 {
  guard !denominator.is_zero() else {
    abort("decimal_floor_div_scaled_repr expects a positive denominator")
  }
  let (quotient0, remainder) = dec_coeff_div_rem_repr(numerator, denominator)
  let quotient = if negative && !remainder.is_zero() {
    dec_coeff_magnitude_add_unit(quotient0, 1)
  } else {
    quotient0
  }
  let magnitude = match dec_coeff_to_bounded_int(quotient, 999_999_999) {
    Some(value) => value
    None =>
      abort("decimal_floor_div_scaled_repr quotient exceeds GDA math bounds")
  }
  if negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// floor(value^(1 / degree)) for degree >= 2 and a nonzero `value`, as
/// `bin_float`'s `binary_floor_nth_root` computes it in binary. Small roots
/// are found by bisection; larger ones by integer Newton steps from an
/// overestimate taken from the root of the leading digits, which needs a few
/// full-size products and divisions instead of one power per root digit.
pub fn dec_coeff_floor_nth_root_repr(
  value : DecCoeff,
  degree : Int32,
) -> DecCoeff {
  let digits = value.digits10()
  // The root is below 10^root_digits.
  let root_digits = (digits + degree - 1) / degree
  if root_digits <= 18 {
    let one = dec_coeff_from_int(1)
    let mut lower = dec_coeff_zero()
    let mut upper = dec_coeff_power10_repr(root_digits)
    while dec_coeff_compare_repr(
            dec_coeff_magnitude_sub_repr(upper, lower),
            one,
          ) >
          0 {
      let midpoint = dec_coeff_div_rem_by_unit_repr(
          dec_coeff_magnitude_add_repr(lower, upper),
          2,
        ).0
      // A power longer than `value` is certainly above it.
      match dec_coeff_exact_power_if_fits_repr(midpoint, degree, digits) {
        Some(power) if dec_coeff_compare_repr(power, value) <= 0 =>
          lower = midpoint
        _ => upper = midpoint
      }
    }
    return lower
  }
  // With high = floor((value / 10^(degree * half))^(1 / degree)), value is
  // below ((high + 1) * 10^half)^degree, so that start exceeds the root.
  let half = root_digits / 2
  let high = dec_coeff_floor_nth_root_repr(
    dec_coeff_div_rem_repr(value, dec_coeff_power10_repr(half * degree)).0,
    degree,
  )
  let mut root = dec_coeff_shift_power10_repr(
    dec_coeff_magnitude_add_repr(high, dec_coeff_from_int(1)),
    half,
  )
  // From any x above the root, y = floor(((degree - 1) x +
  // floor(value / x^(degree - 1))) / degree) satisfies root <= y < x (AM-GM),
  // and at x = root the step does not decrease.
  while true {
    let quotient = dec_coeff_div_rem_repr(
        value,
        dec_coeff_exact_power_repr(root, degree - 1),
      ).0
    let next = dec_coeff_div_rem_by_unit_repr(
        dec_coeff_magnitude_add_repr(
          dec_coeff_multiply_by_unit_repr(root, degree - 1),
          quotient,
        ),
        degree,
      ).0
    if dec_coeff_compare_repr(next, root) >= 0 {
      break
    }
    root = next
  }
  root
}

///|
/// The exact `degree`-th root of `value`, or `None` when `value` is not a
/// perfect `degree`-th power. Even degrees take exact square roots first,
/// which stop at the first nonzero remainder.
pub fn dec_coeff_exact_nth_root_repr(
  value : DecCoeff,
  degree : Int32,
) -> DecCoeff? {
  guard degree > 1 && !value.is_zero() else { return None }
  let one = dec_coeff_from_int(1)
  let mut current = value
  let mut remaining = degree
  while remaining % 2 == 0 && dec_coeff_compare_repr(current, one) != 0 {
    let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(current)
    guard remainder.is_zero() else { return None }
    current = root
    remaining = remaining / 2
  }
  if remaining == 1 || dec_coeff_compare_repr(current, one) == 0 {
    return Some(current)
  }
  let root = dec_coeff_floor_nth_root_repr(current, remaining)
  match
    dec_coeff_exact_power_if_fits_repr(root, remaining, current.digits10()) {
    Some(power) if dec_coeff_compare_repr(power, current) == 0 => Some(root)
    _ => None
  }
}

///|
pub fn dec_coeff_integer_sqrt_floor_repr(n : DecCoeff) -> DecCoeff {
  dec_coeff_integer_sqrt_rem_repr(n).0
}
