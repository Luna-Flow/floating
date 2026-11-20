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
/// Floor square root of a word below 10^18 and its remainder. The hardware
/// root of the nearest double is within one of the answer (the word has at
/// most 60 bits, the double 53), and two comparisons with exact products
/// settle it; the root is below 10^9 so the products fit one word.
fn dec_coeff_isqrt_word(value : UInt64) -> (UInt64, UInt64) {
  let mut root = value.to_double().sqrt().to_uint64()
  while root * root > value {
    root -= 1UL
  }
  while (root + 1UL) * (root + 1UL) <= value {
    root += 1UL
  }
  (root, value - root * root)
}

///|
/// Floor square root `s` of `n` and the remainder `n - s*s`.
///
/// A coefficient of `D` digits is split as `n = hi * 10^(2t) + low` with
/// `t` about `D/4`; the root of `hi` is found the same way, one level down
/// (a word at the bottom, where the hardware root gives the answer), so that
/// `(root(hi) + 1) * 10^t` is an overestimate of the root of `n` with about
/// half of its digits right. Because `n < (hi + 1) * 10^(2t)` and
/// `hi + 1 <= (root(hi) + 1)^2` the overestimate is never below the root.
/// Newton's step `x -> (x + n / x) / 2` from a value at or above the floor
/// root decreases monotonically to it and stays at or above it, so the
/// iteration needs no start near a power of ten, and the working size doubles
/// from the bottom up instead of every step running at full size.
///
/// The step's division also decides when to stop: for `x` at or above the
/// root, `q = n / x` (floor) reaches `x` exactly when `x` is the root, and
/// then `n = x*q + r` gives the remainder `r + x*(q - x)` with `q - x` in
/// {0, 1, 2}, with no squaring.
pub fn dec_coeff_integer_sqrt_rem_repr(n : DecCoeff) -> (DecCoeff, DecCoeff) {
  if dec_coeff_small_value(n) is Some(small) {
    if small <= 1UL {
      return (n, dec_coeff_zero())
    }
    let (root, remainder) = dec_coeff_isqrt_word(small)
    return (DecCoeff::Small(root), DecCoeff::Small(remainder))
  }
  if dec_coeff_compare_repr(n, dec_coeff_from_int(1)) <= 0 {
    return (n, dec_coeff_zero())
  }
  let digits = n.digits10()
  let half_shift = if digits / 4 > 1 { digits / 4 } else { 1 }
  let high = dec_coeff_div_pow10_round_info_repr(n, 2 * half_shift).0
  let (high_root, _) = dec_coeff_integer_sqrt_rem_repr(high)
  let mut approximation = dec_coeff_shift_power10_repr(
    dec_coeff_magnitude_add_unit(high_root, 1),
    half_shift,
  )
  while true {
    let (quotient, remainder) = dec_coeff_div_rem_repr(n, approximation)
    if dec_coeff_compare_repr(quotient, approximation) >= 0 {
      let excess = dec_coeff_magnitude_sub_repr(quotient, approximation)
      let units = match dec_coeff_small_value(excess) {
        Some(value) => value.to_int()
        None => abort("square-root quotient exceeds its root by more than two")
      }
      let tail = if units == 0 {
        remainder
      } else {
        dec_coeff_magnitude_add_repr(
          remainder,
          dec_coeff_multiply_by_unit_repr(approximation, units),
        )
      }
      return (approximation, tail)
    }
    let sum = dec_coeff_magnitude_add_repr(approximation, quotient)
    approximation = dec_coeff_div_rem_by_unit_repr(sum, 2).0
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
/// `numerator / denominator` rounded to an integer in the given direction,
/// and whether the exact quotient has a finite decimal expansion (the same
/// answer as `has_finite_decimal_expansion_repr(numerator, denominator)`),
/// from one division.
///
/// Write `denominator = 2^a 5^b u` with `u` prime to 10. The expansion is
/// finite iff `u` divides `numerator`, and since 10 is invertible modulo `u`
/// that holds iff `u` divides `numerator * 10^k` for any `k`. The division
/// here runs on `numerator`, a caller's `coefficient * 10^k`, so `u` divides
/// the numerator exactly when it divides the remainder: `u` divides the
/// denominator, and the remainder is the numerator modulo the denominator.
pub fn dec_coeff_round_div_expansion(
  numerator : DecCoeff,
  denominator : DecCoeff,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Bool) {
  guard !denominator.is_zero() else {
    abort("dec_coeff_round_div_expansion expects denominator > 0")
  }
  let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, denominator)
  let finite = if remainder.is_zero() {
    true
  } else {
    let (without_tens, _, _) = trim_trailing_decimal_zeros_repr(denominator, 0)
    let without_twos = dec_coeff_remove_factor_unit_repr(without_tens, 2)
    let without_fives = dec_coeff_remove_factor_unit_repr(without_twos, 5)
    dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 ||
    dec_coeff_div_rem_repr(remainder, without_fives).1.is_zero()
  }
  let rounded = if dec_coeff_should_increment(
      quotient, remainder, denominator, negative, mode,
    ) {
    dec_coeff_magnitude_add_unit(quotient, 1)
  } else {
    quotient
  }
  (rounded, finite)
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
/// The quotient of `coefficient * 10^shift` by `denominator`, for a caller
/// that rounds it once more (`ZeroFiveUp` as the general division of the
/// decimal packages does): the integer quotient, incremented by one when a
/// nonzero remainder leaves its last digit 0 or 5. Returns zero when the
/// decimal expansion of the exact quotient is finite (the remainder is zero,
/// or the part of the divisor prime to 10 divides it): the caller then takes
/// its general route. Zero is free as that signal because a quotient of zero
/// with a nonzero remainder leaves as 1 after the `ZeroFiveUp` increment, so
/// no returned quotient is zero. The answer is the one of
/// `dec_coeff_round_div_expansion(coefficient * 10^shift, denominator, _,
/// ZeroFiveUp)`; for the usual case (a divisor of at least two limbs that
/// takes Knuth's algorithm) it is computed on one scratch array per operand,
/// with the shift and the normalization done in place, the quotient written
/// once and no remainder object unless the finite-expansion test needs one.
pub fn dec_coeff_div_scaled_inexact(
  coefficient : DecCoeff,
  shift : Int32,
  denominator : DecCoeff,
) -> DecCoeff {
  guard !coefficient.is_zero() && !denominator.is_zero() && shift >= 0 else {
    abort(
      "dec_coeff_div_scaled_inexact expects nonzero operands and shift >= 0",
    )
  }
  let denominator_len = dec_coeff_unit_len(denominator)
  let whole = shift / dec_coeff_dpun
  let coefficient_len = dec_coeff_unit_len(coefficient)
  // an upper bound of the limbs of the scaled numerator, and the exact count
  // below; the algorithm is chosen on the exact count
  let bound = whole + coefficient_len + 1
  let lean = denominator_len >= 2 &&
    dec_coeff_division_algorithm_for(bound, denominator) is Knuth &&
    dec_coeff_division_algorithm_for(bound - 1, denominator) is Knuth
  if !lean {
    let (quotient, finite) = dec_coeff_round_div_expansion(
      dec_coeff_shift_power10_repr(coefficient, shift),
      denominator,
      false,
      DecCoeffRounding::ZeroFiveUp,
    )
    return if finite { dec_coeff_zero() } else { quotient }
  }
  let normalization = dec_coeff_wide_base /
    (dec_coeff_limb_at(denominator, denominator_len - 1).to_uint64() + 1UL)
  let normalized_denominator : FixedArray[UInt64] = FixedArray::make(
    denominator_len + 1,
    0UL,
  )
  dec_coeff_knuth_load(denominator, normalization, normalized_denominator)
  // the scaled numerator: coefficient * 10^(shift mod 9), moved up `whole` limbs
  let normalized_numerator : FixedArray[UInt64] = FixedArray::make(
    bound + 1,
    0UL,
  )
  let scale = dec_coeff_small_powers10[shift - whole * dec_coeff_dpun]
  let mut carry = 0UL
  for index in 0..<coefficient_len {
    let current = dec_coeff_limb_at(coefficient, index).to_uint64() * scale +
      carry
    carry = current / dec_coeff_wide_base
    normalized_numerator.unsafe_set(
      whole + index,
      current - carry * dec_coeff_wide_base,
    )
  }
  normalized_numerator.unsafe_set(whole + coefficient_len, carry)
  let numerator_len = if carry == 0UL { whole + coefficient_len } else { bound }
  guard numerator_len >= denominator_len else {
    let (quotient, finite) = dec_coeff_round_div_expansion(
      dec_coeff_shift_power10_repr(coefficient, shift),
      denominator,
      false,
      DecCoeffRounding::ZeroFiveUp,
    )
    return if finite { dec_coeff_zero() } else { quotient }
  }
  // normalize in place; the carry limb sits at index `numerator_len`
  let mut multiply_carry = 0UL
  for index in 0..<numerator_len {
    let current = normalized_numerator.unsafe_get(index) * normalization +
      multiply_carry
    multiply_carry = current / dec_coeff_wide_base
    normalized_numerator.unsafe_set(
      index,
      current - multiply_carry * dec_coeff_wide_base,
    )
  }
  normalized_numerator.unsafe_set(numerator_len, multiply_carry)
  let quotient = Array::make(numerator_len - denominator_len + 1, 0U)
  dec_coeff_knuth_core(
    normalized_numerator, numerator_len, normalized_denominator, denominator_len,
    quotient,
  )
  let mut remainder_zero = true
  for index in 0..<denominator_len {
    if normalized_numerator.unsafe_get(index) != 0UL {
      remainder_zero = false
      break
    }
  }
  if remainder_zero {
    return dec_coeff_zero()
  }
  // the quotient is below the exact one: is the expansion of the exact one
  // finite? It is iff the part `u` of the divisor prime to 10 divides the
  // remainder (`u` divides the dividend `coefficient * 10^shift` iff it divides
  // the remainder, because `u` divides the divisor). The valuations of 2 and 5
  // of the divisor are those of its lowest limb when they are below 9.
  let low = dec_coeff_limb_at(denominator, 0).reinterpret_as_int()
  let mut twos = 0
  let mut fives = 0
  let mut rest = low
  while rest != 0 && rest % 2 == 0 {
    twos += 1
    rest = rest / 2
  }
  rest = low
  while rest != 0 && rest % 5 == 0 {
    fives += 1
    rest = rest / 5
  }
  let mut finite = false
  if low == 0 || twos >= dec_coeff_dpun || fives >= dec_coeff_dpun {
    let remainder = dec_coeff_knuth_denormalize(
      normalized_numerator, denominator_len, normalization,
    )
    finite = dec_coeff_has_finite_expansion_after(
      denominator,
      dec_coeff_from_unit_accumulator(remainder, remainder.length()),
    )
  } else if twos > 0 || fives > 0 {
    let mut unit = 1
    for _ in 0..<twos {
      unit *= 2
    }
    for _ in 0..<fives {
      unit *= 5
    }
    let part = dec_coeff_div_rem_by_unit_repr(denominator, unit).0
    let remainder_units = dec_coeff_knuth_denormalize(
      normalized_numerator, denominator_len, normalization,
    )
    let remainder = dec_coeff_from_unit_accumulator(
      remainder_units,
      remainder_units.length(),
    )
    finite = dec_coeff_compare_repr(remainder, part) >= 0 &&
      dec_coeff_div_rem_repr(remainder, part).1.is_zero()
  }
  if finite {
    return dec_coeff_zero()
  }
  // ZeroFiveUp: a nonzero remainder bumps a last digit of 0 or 5
  let last = quotient[0].reinterpret_as_int() % 10
  if last == 0 || last == 5 {
    quotient[0] = quotient[0] + 1U
  }
  dec_coeff_from_unit_accumulator(quotient, quotient.length())
}

///|
/// The exact finite-expansion test the general division uses, for a nonzero
/// remainder: strip the factors 2 and 5 of the divisor and test whether the
/// rest divides the remainder.
fn dec_coeff_has_finite_expansion_after(
  denominator : DecCoeff,
  remainder : DecCoeff,
) -> Bool {
  let (without_tens, _, _) = trim_trailing_decimal_zeros_repr(denominator, 0)
  let without_twos = dec_coeff_remove_factor_unit_repr(without_tens, 2)
  let without_fives = dec_coeff_remove_factor_unit_repr(without_twos, 5)
  dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 ||
  dec_coeff_div_rem_repr(remainder, without_fives).1.is_zero()
}
