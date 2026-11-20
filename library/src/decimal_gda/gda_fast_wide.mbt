///|
/// The fast path of `add` and `subtract` for coefficients of up to four limbs
/// (at most 36 digits) in an extended context of at most 36 digits, the size
/// between `gda_fast_sum` (one limb) and `gda_add_plain` (any size): the
/// operands are read into 128-bit binary words, aligned, summed and rounded
/// once there, and the result is written to its limbs in one array, instead of
/// the limb accumulators, their rounding in place and the copies of
/// `gda_add_plain`. Each function returns `None` outside its range (an
/// aligned sum of 2^128 or more, a shift above 19 places, more than 19 digits
/// discarded, an exact zero sum, a result whose exponent would be clamped,
/// subnormal or beyond the range, the modes and contexts that `gda_fast_sum`
/// excludes), and the next route answers, so the value, the conditions and the
/// next context are those of the general route.

///|
/// The coefficient of a finite, nonzero operand of at most four limbs whose
/// exponent is within the limit: its limb count, or 0 for any other operand.
fn gda_fast_wide_limbs(value : Decimal) -> Int32 {
  if value.class != FpClass::Finite ||
    value.exponent10 > gda_fast_exponent_limit ||
    value.exponent10 < -gda_fast_exponent_limit {
    return 0
  }
  match value.coefficient {
    DecCoeff::Small(small) => if small == 0UL { 0 } else { 2 }
    DecCoeff::Limbs(units, _) =>
      if units.length() <= 4 {
        units.length()
      } else {
        0
      }
  }
}

///|
/// `lhs + rhs`, or `lhs - rhs` when `subtract_rhs`.
fn gda_fast_wide_sum(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
  subtract_rhs : Bool,
) -> GdaOutcome[Decimal]? {
  let left_limbs = gda_fast_wide_limbs(lhs)
  let right_limbs = gda_fast_wide_limbs(rhs)
  guard left_limbs != 0 && right_limbs != 0 && gda_fast_context_ok(ctx, 36) else {
    return None
  }
  let right_negative = rhs.negative != subtract_rhs
  let target = Int32::min(lhs.exponent10, rhs.exponent10)
  let left_shift = lhs.exponent10 - target
  let right_shift = rhs.exponent10 - target
  guard left_shift <= 19 && right_shift <= 19 else { return None }
  // Width 1, the conversion: a coefficient of at most four limbs is below
  // 10^36 < 2^120 (2^120 = 1.33e36), so the Horner steps `value * 10^9 + limb`
  // from the top limb never leave 128 bits (each step is a word times 10^9 with
  // `gda_fast_mul_high` for the carry into the high word, plus a limb).
  let mut left_high = 0UL
  let mut left_low = 0UL
  let mut index = left_limbs - 1
  while index >= 0 {
    let carry = gda_fast_mul_high(left_low, 1000000000UL)
    left_high = left_high * 1000000000UL + carry
    left_low = left_low * 1000000000UL
    let limb = dec_coeff_limb_at(lhs.coefficient, index).to_uint64()
    left_low += limb
    if left_low < limb {
      left_high += 1UL
    }
    index -= 1
  }
  let mut right_high = 0UL
  let mut right_low = 0UL
  index = right_limbs - 1
  while index >= 0 {
    let carry = gda_fast_mul_high(right_low, 1000000000UL)
    right_high = right_high * 1000000000UL + carry
    right_low = right_low * 1000000000UL
    let limb = dec_coeff_limb_at(rhs.coefficient, index).to_uint64()
    right_low += limb
    if right_low < limb {
      right_high += 1UL
    }
    index -= 1
  }
  // Width 2, the alignment: the operand with the larger exponent is multiplied
  // by 10^shift (shift at most 19, so the power is one word), and the product
  // must stay below 2^128 = 3.40e38: `gda_fast_mul_high(high, power) == 0` and
  // no carry out of `high * power + carry` say so before any other arithmetic.
  // What fits: a 36-digit operand (below 10^36) always fits at the exponent gap
  // 2 (below 10^38); at the gap 3 it fits only below 3.40e35 (10^35 times 10^3
  // is 10^38: taken; 36 nines times 10^3 is above 2^128: declined). The same
  // shape for a 34-digit operand: always at the gap 4, at the gap 5 only below
  // 3.40e33. Shorter operands fit larger gaps.
  // Everything else returns `None` here, with nothing computed on the sum.
  if left_shift > 0 {
    let power = gda_fast_pow10.unsafe_get(left_shift)
    guard gda_fast_mul_high(left_high, power) == 0UL else { return None }
    let carry = gda_fast_mul_high(left_low, power)
    let high = left_high * power + carry
    guard high >= carry else { return None }
    left_high = high
    left_low = left_low * power
  }
  if right_shift > 0 {
    let power = gda_fast_pow10.unsafe_get(right_shift)
    guard gda_fast_mul_high(right_high, power) == 0UL else { return None }
    let carry = gda_fast_mul_high(right_low, power)
    let high = right_high * power + carry
    guard high >= carry else { return None }
    right_high = high
    right_low = right_low * power
  }
  if lhs.negative == right_negative {
    let low = left_low + right_low
    let carry = if low < left_low { 1UL } else { 0UL }
    let partial = left_high + right_high
    let high = partial + carry
    // Width 3, the sum: the aligned operand is below 2^128 and the other one
    // below 10^36, so the sum can still reach 2^128; a carry out of the high
    // word (either addition) declines. The difference of two words never wraps:
    // the smaller is subtracted from the larger by the branches below.
    guard partial >= left_high && high >= partial else { return None }
    gda_fast_wide_finish(lhs.negative, high, low, target, ctx)
  } else if left_high > right_high ||
    (left_high == right_high && left_low > right_low) {
    let borrow = if left_low < right_low { 1UL } else { 0UL }
    gda_fast_wide_finish(
      lhs.negative,
      left_high - right_high - borrow,
      left_low - right_low,
      target,
      ctx,
    )
  } else if left_high == right_high && left_low == right_low {
    None
  } else {
    let borrow = if right_low < left_low { 1UL } else { 0UL }
    gda_fast_wide_finish(
      right_negative,
      right_high - left_high - borrow,
      right_low - left_low,
      target,
      ctx,
    )
  }
}

///|
/// Rounds the positive `high * 2^64 + low` times `10^exponent` to the precision
/// of `ctx` and completes the operation, as `gda_fast_finish` does for a
/// value of up to 128 bits, with the rounded value of up to 36 digits as two
/// words and its limbs written once.
fn gda_fast_wide_finish(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent : Int32,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  let precision = ctx.precision_
  let digits = gda_fast_digits128(high, low)
  let mut kept_high = high
  let mut kept_low = low
  let mut result_exponent = exponent
  let mut rounded = false
  let mut inexact = false
  if digits > precision {
    let drop = digits - precision
    guard drop <= 19 else { return None }
    let divisor = gda_fast_pow10.unsafe_get(drop)
    // Width 4, the division by 10^drop (a word, drop at most 19): the quotient
    // is two words, and `gda_fast_div_wide(high, low, divisor)` returns one
    // word for `high < divisor` (Hacker's Delight `divlu`). It is used within
    // that contract: the high quotient word is `high / divisor` and the
    // remainder of that division is below `divisor`, so it is the `high`
    // argument of the call that gives the low quotient word; the remainder of
    // the whole division is then `low - quotient_low * divisor` modulo 2^64
    // (it is below `divisor`, a word).
    let quotient_high = high / divisor
    let carry_in = high - quotient_high * divisor
    let quotient_low = gda_fast_div_wide(carry_in, low, divisor)
    let remainder = low - quotient_low * divisor
    rounded = true
    inexact = remainder != 0UL
    kept_high = quotient_high
    kept_low = quotient_low
    if gda_fast_increment(
        ctx.rounding_,
        negative,
        quotient_low,
        remainder,
        divisor >> 1,
        false,
      ) {
      kept_low += 1UL
      if kept_low == 0UL {
        kept_high += 1UL
      }
    }
    result_exponent += drop
    if kept_high == gda_fast_pow10_high.unsafe_get(precision) &&
      kept_low == gda_fast_pow10_low.unsafe_get(precision) {
      // the increment carried into 10^precision
      kept_high = gda_fast_pow10_high.unsafe_get(precision - 1)
      kept_low = gda_fast_pow10_low.unsafe_get(precision - 1)
      result_exponent += 1
    }
  }
  // tininess is judged before rounding: the unrounded value must be normal
  let result_digits = if rounded { precision } else { digits }
  let adjusted = result_exponent + result_digits - 1
  guard exponent + digits - 1 >= ctx.e_min_ && adjusted <= ctx.e_max_ else {
    return None
  }
  guard !ctx.clamp_ || result_exponent <= ctx.e_max_ - precision + 1 else {
    return None
  }
  let coefficient = if result_digits <= 18 {
    DecCoeff::Small(kept_low)
  } else {
    // Width 5, the write-out: the rounded value has at most `precision` <= 36
    // digits, so it is below 10^36 and its quotient by 10^18 is below 10^18, a
    // word: `quotient_high` is 0 and `carry_in = kept_high` is below 10^18, the
    // `high` of the contract above. The two halves (below 10^18 each) go into
    // limbs by one word division by 10^9; the digit count is known, so the
    // coefficient is built without scanning the limbs.
    let limb_count = (result_digits + 8) / 9
    let units : Array[UInt32] = Array::make(limb_count, 0U)
    let quotient_high = kept_high / 1000000000000000000UL
    let carry_in = kept_high - quotient_high * 1000000000000000000UL
    let top = gda_fast_div_wide(carry_in, kept_low, 1000000000000000000UL)
    let bottom = kept_low - top * 1000000000000000000UL
    units[0] = (bottom % 1000000000UL).to_uint()
    units[1] = (bottom / 1000000000UL).to_uint()
    units[2] = (top % 1000000000UL).to_uint()
    if limb_count == 4 {
      units[3] = (top / 1000000000UL).to_uint()
    }
    DecCoeff::Limbs(units, result_digits)
  }
  let value = finite_with_exponent_repr(
    negative, coefficient, result_exponent, precision,
  )
  if rounded {
    Some(
      complete_gda_raised(
        value,
        ctx,
        if inexact {
          gda_flags_rounded_inexact
        } else {
          gda_flags_rounded_only
        },
      ),
    )
  } else {
    Some(gda_completed_exact(value, ctx))
  }
}
