///|
// Shared internal decimal helpers.

fn max_precision(a : Decimal, b : Decimal) -> Int {
  Int::max(a.precision_, b.precision_)
}

///|
fn coeff_from_bigint(magnitude : BigInt) -> DecCoeff {
  dec_coeff_from_bigint_repr(abs_bigint(magnitude))
}

///|
fn coeff_bigint(coeff : DecCoeff) -> BigInt {
  dec_coeff_to_bigint_repr(coeff)
}

///|
fn coeff_digits(coeff : DecCoeff) -> Int {
  coeff.digits10()
}

///|
fn finite_precision_for_coeff(coeff : DecCoeff, ctx : DecimalContext) -> Int {
  if ctx.precision == 0 {
    Int::max(1, coeff_digits(coeff))
  } else {
    Int::max(1, ctx.precision)
  }
}

///|
fn coeff_trailing_decimal_zeros(coeff : DecCoeff) -> Int {
  let (_, _, dropped) = trim_trailing_decimal_zeros_repr(coeff, 0)
  dropped
}

///|
fn make_special(
  class : FpClass,
  negative : Bool,
  payload : BigInt,
  precision : Int,
  signaling_nan : Bool,
) -> Decimal {
  make_special_repr(
    class,
    negative,
    coeff_from_bigint(payload),
    precision,
    signaling_nan,
  )
}

///|
fn make_special_repr(
  class : FpClass,
  negative : Bool,
  payload : DecCoeff,
  precision : Int,
  signaling_nan : Bool,
) -> Decimal {
  {
    class,
    negative,
    coefficient: payload,
    exponent10: 0,
    precision_: Int::max(1, precision),
    signaling_nan,
  }
}

///|
fn dec_coeff_integer_sqrt_floor_repr(n : DecCoeff) -> DecCoeff {
  dec_coeff_integer_sqrt_rem_repr(n).0
}

///|
fn dec_coeff_integer_sqrt_rem_repr(n : DecCoeff) -> (DecCoeff, DecCoeff) {
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
fn exact_finite_sqrt(value : Decimal, precision : Int) -> Decimal? {
  guard value.class == FpClass::Finite else { return None }
  if value.coefficient.is_zero() {
    let preferred_exponent = if value.exponent10 >= 0 {
      value.exponent10 / 2
    } else {
      -((-value.exponent10 + 1) / 2)
    }
    return Some(
      finite_with_exponent_repr(
        value.negative,
        dec_coeff_zero(),
        preferred_exponent,
        precision,
      ),
    )
  }
  guard !value.negative else { return None }
  let (normalized_coeff0, normalized_exp) = remove_factor10_repr(
    value.coefficient,
    value.exponent10,
  )
  let (radicand, exponent10) = if (normalized_exp & 1) == 0 {
    (normalized_coeff0, normalized_exp)
  } else {
    (dec_coeff_multiply_by_unit_repr(normalized_coeff0, 10), normalized_exp - 1)
  }
  let root = dec_coeff_integer_sqrt_floor_repr(radicand)
  if dec_coeff_compare_repr(dec_coeff_square_repr(root), radicand) == 0 {
    let exact = finite_with_exponent_repr(
      false,
      root,
      exponent10 / 2,
      precision,
    )
    let preferred_exponent = if value.exponent10 >= 0 {
      value.exponent10 / 2
    } else {
      -((-value.exponent10 + 1) / 2)
    }
    let extra_zeros = exact.exponent10 - preferred_exponent
    let available_zeros = Int::max(0, precision - exact.coefficient.digits10())
    let zeros_to_add = Int::min(extra_zeros, available_zeros)
    if zeros_to_add > 0 {
      Some(
        finite_with_exponent_repr(
          false,
          dec_coeff_shift_power10_repr(exact.coefficient, zeros_to_add),
          exact.exponent10 - zeros_to_add,
          precision,
        ),
      )
    } else {
      Some(exact)
    }
  } else {
    None
  }
}

///|
fn exact_result_rounding_flags(
  value : Decimal,
  preferred_exponent : Int,
  ctx : DecimalContext,
) -> DecimalFlags {
  guard value.class == FpClass::Finite else { return DecimalFlags::new() }
  guard ctx.precision > 0 && !value.coefficient.is_zero() else {
    return DecimalFlags::new()
  }
  let shift = Int::max(0, value.exponent10 - preferred_exponent)
  let effective_digits = value.coefficient.digits10() + shift
  let extra_digits = effective_digits - ctx.precision
  guard extra_digits > 0 else { return DecimalFlags::new() }
  let trailing_zeros = coeff_trailing_decimal_zeros(value.coefficient)
  let effective_trailing_zeros = trailing_zeros + shift
  {
    ..DecimalFlags::new(),
    rounded: true,
    inexact: effective_trailing_zeros < extra_digits,
  }
}

///|
fn has_finite_decimal_expansion_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Bool {
  guard !denominator.is_zero() else {
    abort("has_finite_decimal_expansion_repr expects denominator > 0")
  }
  let gcd = dec_coeff_gcd_repr(numerator, denominator)
  let (divisor, remainder) = dec_coeff_div_rem_repr(denominator, gcd)
  guard remainder.is_zero() else {
    abort("has_finite_decimal_expansion_repr expected an exact gcd division")
  }
  let without_twos = dec_coeff_remove_factor_unit_repr(divisor, 2)
  let without_fives = dec_coeff_remove_factor_unit_repr(without_twos, 5)
  dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0
}

///|
fn exact_decimal_reciprocal(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let (without_twos, twos) = dec_coeff_count_factor_unit_repr(
    value.coefficient,
    2,
  )
  let (without_fives, fives) = dec_coeff_count_factor_unit_repr(without_twos, 5)
  guard dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 else {
    return None
  }
  let scale = Int::max(twos, fives)
  let magnitude = dec_coeff_multiply_repr(
    dec_coeff_pow_unit_repr(2, scale - twos),
    dec_coeff_pow_unit_repr(5, scale - fives),
  )
  Some(
    normalize_decimal_parts_ctx_repr(
      value.negative,
      magnitude,
      -scale - value.exponent10,
      ctx,
    ),
  )
}

///|
fn exact_division_by_power_of_ten_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  let power = match decimal_power_of_ten_exponent(divisor) {
    Some(value) => value
    None => return None
  }
  let precision = finite_precision_for(bigint_one(), ctx)
  let negative = dividend.negative != divisor.negative
  let preferred_exponent = dividend.exponent10 - divisor.exponent10
  let exact_unrounded = normalize_decimal_parts_gda_repr(
    negative,
    dividend.coefficient,
    dividend.exponent10 - power,
    dividend.coefficient.digits10(),
    ctx.decimal_rounding,
  )
  let exact_rounding = exact_result_rounding_flags(
    exact_unrounded, preferred_exponent, ctx,
  )
  let rounded_value = normalize_decimal_parts_gda_repr(
    negative,
    dividend.coefficient,
    dividend.exponent10 - power,
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
// GDA decDivideOp keeps the integer quotient in its Unit accumulator `acc`
// and tracks its width with `accdigits`; no binary-integer materialization is
// part of the algorithm (libdecnumber/decNumber.c lines 4394-4406, 4564-4607).
fn integer_quotient_by_power_of_ten_repr(
  dividend : Decimal,
  divisor : Decimal,
  nearest : Bool,
) -> DecCoeff? {
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  let power = match decimal_power_of_ten_exponent(divisor) {
    Some(value) => value
    None => return None
  }
  let shift = dividend.exponent10 - power
  if shift >= 0 {
    return Some(dec_coeff_shift_power10_repr(dividend.coefficient, shift))
  }
  match exact_divide_by_power_of_ten_repr(dividend.coefficient, -shift) {
    Some(exact) if !nearest => return Some(exact)
    _ => ()
  }
  if !nearest {
    let (quotient0, _) = dec_coeff_div_rem_repr(
      dividend.coefficient,
      dec_coeff_power10_repr(-shift),
    )
    return Some(quotient0)
  }
  let (quotient0, _) = round_positive_decimal_div_pow10_repr(
    dividend.coefficient,
    -shift,
    false,
    DecimalRoundingMode::HalfEven,
  )
  Some(quotient0)
}

///|
fn has_finite_decimal_unit_magnitude(value : Decimal) -> Bool {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return false
  }
  let (reduced, _, dropped) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    0,
  )
  dec_coeff_compare_repr(reduced, dec_coeff_from_int(1)) == 0 &&
  value.exponent10 + dropped == 0
}

///|
fn is_finite_decimal_one(value : Decimal) -> Bool {
  !value.negative && has_finite_decimal_unit_magnitude(value)
}

///|
fn is_finite_decimal_negative_one(value : Decimal) -> Bool {
  value.negative && has_finite_decimal_unit_magnitude(value)
}

///|
fn decimal_small_pow10(shift : Int) -> Int {
  guard shift >= 0 && shift < dec_coeff_dpun else {
    abort("decimal_small_pow10 shift exceeds one coefficient limb")
  }
  dec_coeff_powers[shift]
}

///|
fn decimal_exact_aligned_sum_result(
  lhs : Decimal,
  rhs : Decimal,
  target : Int,
) -> (Bool, DecCoeff) {
  guard lhs.class == FpClass::Finite && rhs.class == FpClass::Finite else {
    abort("decimal_exact_aligned_sum_result expects finite operands")
  }
  ignore(target)
  let (low, high) = if lhs.exponent10 <= rhs.exponent10 {
    (lhs, rhs)
  } else {
    (rhs, lhs)
  }
  let low_units = dec_coeff_copy_limbs(low.coefficient)
  let low_unit_len = dec_coeff_unit_len(low.coefficient)

  let high_units = dec_coeff_copy_limbs(high.coefficient)
  let high_unit_len = dec_coeff_unit_len(high.coefficient)
  let padding = high.exponent10 - low.exponent10
  // GDA decAddOp splits decimal padding into a whole-unit shift and a
  // power-of-ten multiplier, then calls decUnitAddSub directly
  // (libdecnumber/decNumber.c lines 3978-4018 and 4055-4059).
  let bshift = (padding + dec_coeff_dpun) / dec_coeff_dpun - 1
  let mult = decimal_small_pow10(padding - bshift * dec_coeff_dpun)

  let acc : Array[UInt] = []
  let mut pad = 0
  while pad < Int::max(low_unit_len, high_unit_len + bshift) + 2 {
    acc.push(0U)
    pad += 1
  }

  let len = if low.negative == high.negative {
    dec_coeff_unit_add_sub(
      low_units, low_unit_len, high_units, high_unit_len, bshift, acc, mult,
    )
  } else {
    let calc = dec_coeff_unit_add_sub(
      low_units,
      low_unit_len,
      high_units,
      high_unit_len,
      bshift,
      acc,
      -mult,
    )
    if calc < 0 {
      -calc
    } else {
      calc
    }
  }

  let compact : Array[UInt] = []
  let mut index = 0
  while index < len {
    compact.push(acc[index])
    index += 1
  }
  let magnitude = dec_coeff_from_unit_accumulator(compact, len)
  let negative = if magnitude.is_zero() {
    false
  } else if low.negative == high.negative {
    low.negative
  } else {
    (
      compare_finite_magnitude_repr(
        low.coefficient,
        low.exponent10,
        high.coefficient,
        high.exponent10,
      ) >
      0 &&
      low.negative
    ) ||
    (
      compare_finite_magnitude_repr(
        high.coefficient,
        high.exponent10,
        low.coefficient,
        low.exponent10,
      ) >
      0 &&
      high.negative
    )
  }
  (negative, magnitude)
}

///|
fn add_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  match quiet_nan_pair_plain(a, b) {
    Some(value) => return value
    None => ()
  }
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision~)
    (FpClass::Infinity, FpClass::Infinity) =>
      if a.sign() == b.sign() {
        a.with_precision(precision, RoundingMode::ToNearestEven)
      } else {
        Decimal::nan(precision~)
      }
    (FpClass::Infinity, _) =>
      a.with_precision(precision, RoundingMode::ToNearestEven)
    (_, FpClass::Infinity) =>
      b.with_precision(precision, RoundingMode::ToNearestEven)
    (FpClass::Finite, FpClass::Finite) if a.is_zero() && b.is_zero() =>
      if a.negative && b.negative {
        Decimal::negative_zero(precision~)
      } else {
        Decimal::zero(precision~)
      }
    (FpClass::Finite, FpClass::Finite) => {
      let target = Int::min(a.exponent10, b.exponent10)
      // Same Unit padding + decUnitAddSub mapping as GDA decAddOp
      // (decNumber.c lines 3978-4059), without a binary-integer detour.
      let (negative, magnitude) = decimal_exact_aligned_sum_result(a, b, target)
      normalize_decimal_parts_gda_repr(
        negative,
        magnitude,
        target,
        precision,
        DecimalRoundingMode::HalfEven,
      )
    }
  }
}

///|
fn mul_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  match quiet_nan_pair_plain(a, b) {
    Some(value) => return value
    None => ()
  }
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision~)
    (FpClass::Infinity, FpClass::Finite)
    | (FpClass::Finite, FpClass::Infinity) =>
      if a.is_zero() || b.is_zero() {
        Decimal::nan(precision~)
      } else {
        Decimal::inf(
          if a.sign() == b.sign() {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision~,
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      Decimal::inf(
        if a.sign() == b.sign() {
          Sign::Positive
        } else {
          Sign::Negative
        },
        precision~,
      )
    (FpClass::Finite, FpClass::Finite) if a.is_zero() || b.is_zero() =>
      if (a.is_zero() && !b.is_zero() && a.is_negative_zero()) ||
        (b.is_zero() && !a.is_zero() && b.is_negative_zero()) ||
        (a.is_zero() && b.is_zero() && a.negative != b.negative) {
        Decimal::negative_zero(precision~)
      } else {
        Decimal::zero(precision~)
      }
    (FpClass::Finite, FpClass::Finite) =>
      {
        class: FpClass::Finite,
        negative: a.negative != b.negative,
        coefficient: dec_coeff_multiply_repr(a.coefficient, b.coefficient),
        exponent10: a.exponent10 + b.exponent10,
        precision_: precision,
        signaling_nan: false,
      }
  }
}

///|
fn div_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  match quiet_nan_pair_plain(a, b) {
    Some(value) => return value
    None => ()
  }
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision~)
    (_, FpClass::Finite) if b.is_zero() =>
      if a.is_zero() {
        Decimal::nan(precision~)
      } else {
        Decimal::inf(
          if a.sign() == b.sign() {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision~,
        )
      }
    (FpClass::Infinity, FpClass::Infinity) => Decimal::nan(precision~)
    (FpClass::Infinity, _) =>
      Decimal::inf(
        if a.sign() == b.sign() {
          Sign::Positive
        } else {
          Sign::Negative
        },
        precision~,
      )
    (_, FpClass::Infinity) => Decimal::zero(precision~)
    (FpClass::Finite, FpClass::Finite) if a.is_zero() =>
      if a.negative != b.negative {
        Decimal::negative_zero(precision~)
      } else {
        Decimal::zero(precision~)
      }
    (FpClass::Finite, FpClass::Finite) => {
      let extra = precision + b.coefficient.digits10() + 2
      let numerator = dec_coeff_shift_power10_repr(a.coefficient, extra)
      // GDA decDivideOp performs non-restoring long division directly over
      // Unit arrays and stores the quotient in its decimal accumulator
      // (decNumber.c lines 4159-4201 and 4394-4607).
      let q = round_positive_decimal_div_repr(
        numerator,
        b.coefficient,
        a.sign() != b.sign(),
        DecimalRoundingMode::HalfEven,
      )
      normalize_decimal_parts_gda_repr(
        a.sign() != b.sign(),
        q,
        a.exponent10 - b.exponent10 - extra,
        precision,
        DecimalRoundingMode::HalfEven,
      )
    }
  }
}

///|
fn compare_magnitude_to_half_ulp(value : Decimal, ulp_exponent : Int) -> Int {
  let adjusted = adjusted_exponent(value)
  if adjusted < ulp_exponent - 1 {
    return -1
  }
  if adjusted > ulp_exponent - 1 {
    return 1
  }
  let digits = value.coefficient.digits10()
  dec_coeff_compare_repr(
    value.coefficient,
    dec_coeff_multiply_by_unit_repr(dec_coeff_power10_repr(digits - 1), 5),
  )
}

///|
fn exact_units_at_quantum_repr(value : Decimal, quantum : Int) -> DecCoeff {
  let shift = value.exponent10 - quantum
  guard shift >= 0 else {
    abort("exact_units_at_quantum_repr requires an exact non-negative shift")
  }
  dec_coeff_shift_power10_repr(value.coefficient, shift)
}

///|
fn is_power_of_ten_coeff(coeff : DecCoeff) -> Bool {
  let (reduced, _, dropped) = trim_trailing_decimal_zeros_repr(coeff, 0)
  dropped > 0 && dec_coeff_compare_repr(reduced, dec_coeff_from_int(1)) == 0
}

///|
fn exact_base_small_addend_step(
  base_is_odd : Bool,
  base_ends_zero_or_five : Bool,
  base_negative : Bool,
  low_negative : Bool,
  cmp_half : Int,
  mode : DecimalRoundingMode,
) -> Int {
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
fn exact_base_small_addend_result(
  base : Decimal,
  ulp_exponent : Int,
  low : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let cmp_half = compare_magnitude_to_half_ulp(low, ulp_exponent)
  let base_units_repr = exact_units_at_quantum_repr(base, ulp_exponent)
  // GDA decAddOp carries a residue into decFinish/decApplyRound; a nearest
  // result below half makes no coefficient step, while a half-even tie reads
  // the retained coefficient LSD. Both decisions are unit-native here.
  let step = exact_base_small_addend_step(
    dec_coeff_is_odd(base_units_repr),
    dec_coeff_limb_at(base_units_repr, 0).reinterpret_as_int() % 10 == 0 ||
    dec_coeff_limb_at(base_units_repr, 0).reinterpret_as_int() % 10 == 5,
    base.negative,
    low.negative,
    cmp_half,
    ctx.decimal_rounding,
  )
  let (negative, magnitude) = if step == 0 {
    (base.negative, base_units_repr)
  } else {
    dec_coeff_signed_step_unit_repr(base.negative, base_units_repr, step > 0)
  }
  let (value, adjust_flags) = normalize_decimal_parts_ctx_repr(
    negative, magnitude, ulp_exponent, ctx,
  )
  let mut flags = adjust_flags.combine({
    ..DecimalFlags::new(),
    rounded: true,
    inexact: true,
  })
  if low.negative != base.negative &&
    adjusted_exponent(base) == ctx.e_min &&
    is_power_of_ten_coeff(base_units_repr) {
    flags = { ..flags, subnormal: true, underflow: true }
  }
  (value, flags)
}

///|
fn absorbed_sum_result(
  high : Decimal,
  base : Decimal,
  base_flags : DecimalFlags,
  low : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let flags = base_flags
  let high_base_cmp = high.compare(base)
  let exact_is_greater = if high_base_cmp > 0 {
    true
  } else if high_base_cmp < 0 {
    false
  } else {
    !low.negative
  }
  let exact_negative = high.negative
  let zero_five_up_moves = base.class == FpClass::Finite &&
    !base.coefficient.is_zero() &&
    (
      dec_coeff_limb_at(base.coefficient, 0).reinterpret_as_int() % 10 == 0 ||
      dec_coeff_limb_at(base.coefficient, 0).reinterpret_as_int() % 10 == 5
    )
  let move_toward_positive = match ctx.decimal_rounding {
    Ceiling =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        !exact_negative
      } else {
        exact_is_greater
      }
    Floor => false
    Down =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        false
      } else if base.class == FpClass::Finite && base.negative {
        exact_is_greater
      } else {
        false
      }
    Up =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        !exact_negative
      } else if base.class == FpClass::Finite && base.negative {
        false
      } else {
        exact_is_greater
      }
    ZeroFiveUp => zero_five_up_moves && exact_is_greater
    HalfEven | HalfUp | HalfDown => false
  }
  let move_toward_negative = match ctx.decimal_rounding {
    Floor =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        exact_negative
      } else {
        !exact_is_greater
      }
    Ceiling => false
    Down =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        false
      } else if base.class == FpClass::Finite && base.negative {
        false
      } else {
        !exact_is_greater
      }
    Up =>
      if base.class == FpClass::Finite && base.coefficient.is_zero() {
        exact_negative
      } else if base.class == FpClass::Finite && base.negative {
        !exact_is_greater
      } else {
        false
      }
    ZeroFiveUp => zero_five_up_moves && !exact_is_greater
    HalfEven | HalfUp | HalfDown => false
  }
  let (value, flags) = if move_toward_positive {
    let (next, next_flags) = decimal_next(base, ctx, true)
    (next, flags.combine(next_flags))
  } else if move_toward_negative {
    let (next, next_flags) = decimal_next(base, ctx, false)
    (next, flags.combine(next_flags))
  } else {
    (base, flags)
  }
  let flags = { ..flags, rounded: true, inexact: true }
  if value.class == FpClass::Finite &&
    (value.coefficient.is_zero() || adjusted_exponent(value) < ctx.e_min) {
    (
      value,
      {
        ..flags,
        subnormal: true,
        underflow: true,
        clamped: flags.clamped ||
        (value.coefficient.is_zero() && value.exponent10 <= etiny(ctx)),
      },
    )
  } else {
    (value, flags)
  }
}

///|
fn nan_operand_flags(a : Decimal, b : Decimal) -> DecimalFlags {
  if a.is_signaling_nan() || b.is_signaling_nan() {
    { ..DecimalFlags::new(), invalid_operation: true }
  } else {
    DecimalFlags::new()
  }
}

///|
fn invalid_flags() -> DecimalFlags {
  { ..DecimalFlags::new(), invalid_operation: true }
}

///|
fn invalid_context_flags() -> DecimalFlags {
  { ..DecimalFlags::new(), invalid_context: true }
}

///|
fn invalid_context_result(ctx : DecimalContext) -> (Decimal, DecimalFlags) {
  (
    Decimal::nan(precision=finite_precision_for(bigint_zero(), ctx)),
    invalid_context_flags(),
  )
}

///|
fn math_context_is_restricted(ctx : DecimalContext) -> Bool {
  ctx.precision > 999_999 || ctx.e_max > 999_999 || ctx.e_min < -999_999
}

///|
fn gda_context_is_restricted(ctx : DecimalContext) -> Bool {
  ctx.precision > 999_999_999 ||
  ctx.e_max > 999_999_999 ||
  ctx.e_min < -999_999_999
}

///|
fn decimal_compare_result(value : Int, ctx : DecimalContext) -> Decimal {
  Decimal::from_int(value, precision=finite_precision_for(bigint_one(), ctx))
}

///|
fn div_zero_flags(division_undefined : Bool) -> DecimalFlags {
  if division_undefined {
    { ..DecimalFlags::new(), invalid_operation: true, division_undefined: true }
  } else {
    { ..DecimalFlags::new(), division_by_zero: true }
  }
}

///|
fn div_impossible_flags() -> DecimalFlags {
  { ..DecimalFlags::new(), invalid_operation: true, division_impossible: true }
}

///|
fn decimal_order_sign(x : Decimal) -> Int {
  if x.negative {
    -1
  } else {
    1
  }
}

///|
fn compare_int(a : Int, b : Int) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn abs_int(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn integer_quotient_digit_lower_bound(
  dividend : Decimal,
  divisor : Decimal,
) -> Int {
  let scale = dividend.exponent10 - divisor.exponent10
  let numerator_extra = if scale > 0 { scale } else { 0 }
  let denominator_extra = if scale < 0 { -scale } else { 0 }
  let numerator_digits = dividend.coefficient.digits10() + numerator_extra
  let denominator_digits = divisor.coefficient.digits10() + denominator_extra
  numerator_digits - denominator_digits
}

///|
fn round_operand_for_subset(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::Finite else {
    abort("round_operand_for_subset expects a finite operand")
  }
  if ctx.precision <= 0 || value.coefficient.is_zero() {
    return (value, DecimalFlags::new())
  }
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let digits = value.coefficient.digits10()
  if digits <= precision {
    return (value, DecimalFlags::new())
  }
  let mut flags = DecimalFlags::new()
  let mut exponent10 = value.exponent10
  let max_drop = digits - precision
  // GDA subset decDivideOp rounds oversized decNumber operands before the
  // Unit long-division loop (decNumber.c lines 4263-4272).
  let (trimmed, trimmed_exp, dropped) = trim_trailing_decimal_zeros_repr(
    value.coefficient,
    exponent10,
    max_drop~,
  )
  let magnitude = if dropped > 0 {
    exponent10 = trimmed_exp
    flags = { ..flags, rounded: true }
    trimmed
  } else {
    trimmed
  }
  let magnitude = if magnitude.digits10() > precision {
    let (rounded_magnitude, next_exponent, _, inexact) = decimal_round_coeff_to_digits_repr(
      magnitude,
      exponent10,
      precision,
      value.negative,
      ctx.decimal_rounding,
    )
    exponent10 = next_exponent
    flags = { ..flags, rounded: true }
    if inexact {
      flags = { ..flags, inexact: true, lost_digits: true }
    }
    rounded_magnitude
  } else {
    magnitude
  }
  let rounded = finite_with_exponent_repr(
    value.negative,
    magnitude,
    exponent10,
    finite_precision_for_coeff(magnitude, ctx),
  )
  if adjusted_exponent(rounded) > ctx.e_max {
    let (overflowed, overflow_flags) = decimal_overflow_result(
      rounded.negative,
      ctx,
    )
    (overflowed, flags.combine(overflow_flags))
  } else {
    (rounded, flags)
  }
}

///|
fn prepare_operand_for_context(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if !ctx.extended && value.class == FpClass::Finite {
    round_operand_for_subset(value, ctx)
  } else {
    (value, DecimalFlags::new())
  }
}

///|
fn prepare_binary_operands_for_context(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
) -> (Decimal, Decimal, DecimalFlags) {
  let (lhs, lhs_flags) = prepare_operand_for_context(lhs, ctx)
  let (rhs, rhs_flags) = prepare_operand_for_context(rhs, ctx)
  (lhs, rhs, lhs_flags.combine(rhs_flags))
}

///|
fn divide_integer_zero_quotient_flags(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> DecimalFlags {
  if ctx.extended {
    return DecimalFlags::new()
  }
  let (_rounded_dividend, dividend_flags) = round_operand_for_subset(
    dividend, ctx,
  )
  let (_rounded_divisor, divisor_flags) = round_operand_for_subset(divisor, ctx)
  let combined = dividend_flags.combine(divisor_flags)
  if !dividend_flags.inexact &&
    divisor_flags.inexact &&
    coeff_trailing_decimal_zeros(divisor.coefficient) > 0 {
    { ..combined, inexact: false }
  } else {
    combined
  }
}

///|
fn decimal_division_common_magnitude_units(
  dividend : Decimal,
  divisor : Decimal,
) -> (DecCoeff, DecCoeff, Int) {
  let scale = dividend.exponent10 - divisor.exponent10
  if scale >= 0 {
    (
      dec_coeff_shift_power10_repr(dividend.coefficient, scale),
      divisor.coefficient,
      divisor.exponent10,
    )
  } else {
    (
      dividend.coefficient,
      dec_coeff_shift_power10_repr(divisor.coefficient, -scale),
      dividend.exponent10,
    )
  }
}

///|
fn decimal_nearest_remainder_parts(
  dividend : Decimal,
  divisor : Decimal,
) -> (Bool, DecCoeff, Int) {
  let scale = dividend.exponent10 - divisor.exponent10
  let (quotient_odd, remainder, denominator, target) = if scale >= 0 {
    let denominator = divisor.coefficient
    let doubled_denominator = dec_coeff_multiply_by_unit_repr(denominator, 2)
    let residue = dec_coeff_shift_power10_mod_repr(
      dividend.coefficient,
      scale,
      doubled_denominator,
    )
    if dec_coeff_compare_repr(residue, denominator) >= 0 {
      (
        true,
        dec_coeff_magnitude_sub_repr(residue, denominator),
        denominator,
        divisor.exponent10,
      )
    } else {
      (false, residue, denominator, divisor.exponent10)
    }
  } else {
    let denominator = dec_coeff_shift_power10_repr(divisor.coefficient, -scale)
    let (quotient, remainder) = dec_coeff_div_rem_repr(
      dividend.coefficient,
      denominator,
    )
    (dec_coeff_is_odd(quotient), remainder, denominator, dividend.exponent10)
  }
  let twice_remainder = dec_coeff_multiply_by_unit_repr(remainder, 2)
  let half_compare = dec_coeff_compare_repr(twice_remainder, denominator)
  let increment = half_compare > 0 || (half_compare == 0 && quotient_odd)
  let magnitude = if increment {
    dec_coeff_magnitude_sub_repr(denominator, remainder)
  } else {
    remainder
  }
  let negative = !magnitude.is_zero() && dividend.negative != increment
  (negative, magnitude, target)
}

///|
fn finite_integer_quotient_is_zero(
  dividend : Decimal,
  divisor : Decimal,
) -> Bool {
  guard dividend.class == FpClass::Finite && divisor.class == FpClass::Finite else {
    return false
  }
  guard !dividend.coefficient.is_zero() && !divisor.coefficient.is_zero() else {
    return false
  }
  compare_finite_magnitude_repr(
    dividend.coefficient,
    dividend.exponent10,
    divisor.coefficient,
    divisor.exponent10,
  ) <
  0
}

///|
fn compare_twice_dividend_to_divisor(
  dividend : Decimal,
  divisor : Decimal,
) -> Int {
  guard dividend.class == FpClass::Finite && divisor.class == FpClass::Finite else {
    return 0
  }
  compare_finite_magnitude_repr(
    dec_coeff_multiply_by_unit_repr(dividend.coefficient, 2),
    dividend.exponent10,
    divisor.coefficient,
    divisor.exponent10,
  )
}

///|
fn finite_nearest_integer_quotient_is_zero(
  dividend : Decimal,
  divisor : Decimal,
) -> Bool {
  guard dividend.class == FpClass::Finite && divisor.class == FpClass::Finite else {
    return false
  }
  guard !dividend.coefficient.is_zero() && !divisor.coefficient.is_zero() else {
    return false
  }
  compare_twice_dividend_to_divisor(dividend, divisor) <= 0
}

///|
fn decimal_integer_quotient(
  dividend : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_one(), ctx)
  match (dividend.class, other.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) =>
      (Decimal::nan(precision~), nan_operand_flags(dividend, other))
    (_, FpClass::Finite) if other.is_zero() =>
      if dividend.is_zero() {
        (Decimal::nan(precision~), div_zero_flags(true))
      } else {
        (
          Decimal::inf(
            if dividend.negative != other.negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision~,
          ),
          div_zero_flags(false),
        )
      }
    (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
      if dividend.class == FpClass::Finite && other.class == FpClass::Infinity {
        if !ctx.extended {
          (Decimal::zero(precision~), DecimalFlags::new())
        } else if dividend.negative != other.negative {
          (Decimal::negative_zero(precision~), DecimalFlags::new())
        } else {
          (Decimal::zero(precision~), DecimalFlags::new())
        }
      } else {
        (Decimal::nan(precision~), invalid_flags())
      }
    (FpClass::Finite, FpClass::Finite) => {
      if finite_integer_quotient_is_zero(dividend, other) {
        let flags = divide_integer_zero_quotient_flags(dividend, other, ctx)
        return if !ctx.extended {
          (Decimal::zero(precision~), flags)
        } else if dividend.negative != other.negative {
          (Decimal::negative_zero(precision~), flags)
        } else {
          (Decimal::zero(precision~), flags)
        }
      }
      if ctx.precision > 0 &&
        integer_quotient_digit_lower_bound(dividend, other) > ctx.precision {
        return (Decimal::nan(precision~), div_impossible_flags())
      }
      let quotient = match
        integer_quotient_by_power_of_ten_repr(dividend, other, false) {
        Some(value) => value
        None => {
          let scale = dividend.exponent10 - other.exponent10
          let numerator = if scale >= 0 {
            dec_coeff_shift_power10_repr(dividend.coefficient, scale)
          } else {
            dividend.coefficient
          }
          let denominator = if scale >= 0 {
            other.coefficient
          } else {
            dec_coeff_shift_power10_repr(other.coefficient, -scale)
          }
          let (quotient, _) = dec_coeff_div_rem_repr(numerator, denominator)
          quotient
        }
      }
      if ctx.precision > 0 &&
        !quotient.is_zero() &&
        quotient.digits10() > ctx.precision {
        return (Decimal::nan(precision~), div_impossible_flags())
      }
      let (value, flags) = finalize_finite_ctx(
        finite_with_exponent_repr(
          dividend.negative != other.negative,
          quotient,
          0,
          precision,
        ),
        DecimalFlags::new(),
        ctx,
      )
      if quotient.is_zero() &&
        ctx.extended &&
        !dividend.coefficient.is_zero() &&
        dividend.exponent10 >= 0 {
        (value, { ..flags, rounded: true, inexact: true })
      } else {
        (value, flags)
      }
    }
  }
}

///|
fn zero_quotient_remainder_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if !ctx.extended && dividend.coefficient.is_zero() {
    return (
      Decimal::zero(precision=finite_precision_for(bigint_one(), ctx)),
      DecimalFlags::new(),
    )
  }
  if dividend.coefficient.is_zero() {
    let target = Int::min(dividend.exponent10, divisor.exponent10)
    let zero = finite_with_exponent(
      if ctx.extended {
        dividend.negative
      } else {
        false
      },
      bigint_zero(),
      target,
      finite_precision_for(bigint_zero(), ctx),
    )
    return finalize_finite_ctx(zero, DecimalFlags::new(), ctx)
  }
  let (base, base_flags) = apply_finite_ctx(dividend, ctx)
  guard base_flags.has_error() == false &&
    base.class == FpClass::Finite &&
    !base.coefficient.is_zero() else {
    return (base, base_flags)
  }
  let preferred_exponent = Int::min(dividend.exponent10, divisor.exponent10)
  if preferred_exponent < base.exponent10 {
    let digits = base.coefficient.digits10()
    let wanted_shift = base.exponent10 - preferred_exponent
    let actual_shift = if ctx.precision == 0 {
      wanted_shift
    } else {
      Int::min(wanted_shift, Int::max(0, ctx.precision - digits))
    }
    if actual_shift > 0 {
      let shifted = finite_with_exponent_repr(
        base.negative,
        dec_coeff_shift_power10_repr(base.coefficient, actual_shift),
        base.exponent10 - actual_shift,
        base.precision_,
      )
      let shifted_flags = if actual_shift < wanted_shift {
        { ..base_flags, rounded: true }
      } else {
        base_flags
      }
      return finalize_finite_ctx(shifted, shifted_flags, ctx)
    }
    if wanted_shift > 0 {
      return (base, { ..base_flags, rounded: true })
    }
  }
  (base, base_flags)
}
