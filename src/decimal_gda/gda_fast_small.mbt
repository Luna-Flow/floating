///|
/// Fast paths for `add`, `subtract`, `multiply` and `divide` on operands whose
/// coefficients are single-limb values (`DecCoeff::Small`, below 10^18) in an
/// extended context of at most 18 digits (17 for the quotient). The exact sum,
/// product or guarded quotient is computed on `UInt64` pairs, rounded once to
/// the precision with the context's rounding mode, and the result is built
/// directly, instead of going through the operand preparation, the
/// normalization chain, the finalizer and their flag records. Each function
/// returns `None` outside its range (a NaN, an infinity, a zero, a wide
/// coefficient or precision, a non-extended context, a result whose exponent
/// would be clamped, subnormal or beyond the exponent range, exponents far
/// apart or near the implementation limits, an exact zero sum, an exact
/// quotient, the `ZeroFiveUp` mode), and the general path then answers, so
/// the value, the flags and the next context are those of the general path.

///|
/// `10^0` to `10^19`.
let gda_fast_pow10 : FixedArray[UInt64] = [
  1UL, 10UL, 100UL, 1000UL, 10000UL, 100000UL, 1000000UL, 10000000UL, 100000000UL,
  1000000000UL, 10000000000UL, 100000000000UL, 1000000000000UL, 10000000000000UL,
  100000000000000UL, 1000000000000000UL, 10000000000000000UL, 100000000000000000UL,
  1000000000000000000UL, 10000000000000000000UL,
]

///|
/// High and low words of `10^0` to `10^38`.
let gda_fast_pow10_high : FixedArray[UInt64] = gda_fast_build_pow10(true)

///|
let gda_fast_pow10_low : FixedArray[UInt64] = gda_fast_build_pow10(false)

///|
fn gda_fast_build_pow10(high : Bool) -> FixedArray[UInt64] {
  let table = FixedArray::make(39, 0UL)
  let mut current_high = 0UL
  let mut current_low = 1UL
  for index in 0..<39 {
    table.unsafe_set(index, if high { current_high } else { current_low })
    let carry = gda_fast_mul_high(current_low, 10UL)
    current_high = current_high * 10UL + carry
    current_low = current_low * 10UL
  }
  table
}

///|
/// Operand exponents are limited to this magnitude, far inside the exponent
/// range of every context, so exponent sums never overflow.
let gda_fast_exponent_limit : Int32 = 536870912

///|
/// High word of the 128-bit product of two words.
fn gda_fast_mul_high(left : UInt64, right : UInt64) -> UInt64 {
  let mask = 0xffff_ffffUL
  let left_low = left & mask
  let left_high = left >> 32
  let right_low = right & mask
  let right_high = right >> 32
  let low_low = left_low * right_low
  let high_low = left_high * right_low
  let low_high = left_low * right_high
  let high_high = left_high * right_high
  let middle = (low_low >> 32) + (high_low & mask) + (low_high & mask)
  high_high + (high_low >> 32) + (low_high >> 32) + (middle >> 32)
}

///|
fn gda_fast_bits(value : UInt64) -> Int32 {
  64 - value.reinterpret_as_int64().clz()
}

///|
/// Number of decimal digits of a nonzero word.
fn gda_fast_digits64(value : UInt64) -> Int32 {
  let estimate = (gda_fast_bits(value) * 1233) >> 12
  if value >= gda_fast_pow10.unsafe_get(estimate) {
    estimate + 1
  } else {
    estimate
  }
}

///|
/// Number of decimal digits of the nonzero `high * 2^64 + low`.
fn gda_fast_digits128(high : UInt64, low : UInt64) -> Int32 {
  if high == 0UL {
    return gda_fast_digits64(low)
  }
  let estimate = ((64 + gda_fast_bits(high)) * 1233) >> 12
  let power_high = gda_fast_pow10_high.unsafe_get(estimate)
  if high > power_high ||
    (high == power_high && low >= gda_fast_pow10_low.unsafe_get(estimate)) {
    estimate + 1
  } else {
    estimate
  }
}

///|
/// `floor((high * 2^64 + low) / divisor)` for `high < divisor` (Hacker's
/// Delight, `divlu`): the quotient fits one word.
fn gda_fast_div_wide(high : UInt64, low : UInt64, divisor : UInt64) -> UInt64 {
  let mask = 0xffff_ffffUL
  let base = 0x1_0000_0000UL
  let shift = gda_fast_leading_zeros(divisor)
  let normalized = divisor << shift
  let high_part = if shift == 0 {
    high
  } else {
    (high << shift) | (low >> (64 - shift))
  }
  let low_part = low << shift
  let divisor_high = normalized >> 32
  let divisor_low = normalized & mask
  let digit_high = low_part >> 32
  let digit_low = low_part & mask
  let mut quotient_high = high_part / divisor_high
  let mut remainder = high_part - quotient_high * divisor_high
  while quotient_high >= base ||
        quotient_high * divisor_low > ((remainder << 32) | digit_high) {
    quotient_high -= 1UL
    remainder += divisor_high
    if remainder >= base {
      break
    }
  }
  let middle = (high_part << 32) + digit_high - quotient_high * normalized
  let mut quotient_low = middle / divisor_high
  remainder = middle - quotient_low * divisor_high
  while quotient_low >= base ||
        quotient_low * divisor_low > ((remainder << 32) | digit_low) {
    quotient_low -= 1UL
    remainder += divisor_high
    if remainder >= base {
      break
    }
  }
  (quotient_high << 32) + quotient_low
}

///|
fn gda_fast_leading_zeros(value : UInt64) -> Int32 {
  value.reinterpret_as_int64().clz()
}

///|
/// The coefficient of a finite, nonzero, single-limb operand whose exponent
/// is within the limit.
fn gda_fast_operand(value : Decimal) -> UInt64? {
  if value.class != FpClass::Finite ||
    value.exponent10 > gda_fast_exponent_limit ||
    value.exponent10 < -gda_fast_exponent_limit {
    return None
  }
  match value.coefficient {
    DecCoeff::Small(small) => if small == 0UL { None } else { Some(small) }
    _ => None
  }
}

///|
/// Whether the context is inside the range of the fast paths: extended,
/// `1 <= precision <= limit`, and a rounding mode with a plain increment rule.
fn gda_fast_context_ok(ctx : GdaContext, limit : Int32) -> Bool {
  ctx.extended_ &&
  ctx.precision_ >= 1 &&
  ctx.precision_ <= limit &&
  ctx.rounding_ != GdaRoundingMode::ZeroFiveUp
}

///|
/// Whether the quotient `kept` (with the discarded part `remainder` of
/// `half * 2`, plus `sticky` for a nonzero part below it) is incremented.
fn gda_fast_increment(
  mode : GdaRoundingMode,
  negative : Bool,
  kept : UInt64,
  remainder : UInt64,
  half : UInt64,
  sticky : Bool,
) -> Bool {
  if remainder == 0UL && !sticky {
    return false
  }
  match mode {
    GdaRoundingMode::Down => false
    GdaRoundingMode::Up => true
    GdaRoundingMode::Ceiling => !negative
    GdaRoundingMode::Floor => negative
    GdaRoundingMode::HalfUp => remainder >= half
    GdaRoundingMode::HalfDown =>
      remainder > half || (remainder == half && sticky)
    GdaRoundingMode::HalfEven =>
      remainder > half || (remainder == half && (sticky || (kept & 1UL) == 1UL))
    GdaRoundingMode::ZeroFiveUp => false
  }
}

///|
/// Rounds the positive `high * 2^64 + low` times `10^exponent`, plus a tiny
/// positive amount when `sticky`, to the precision of `ctx`, and completes the
/// operation. `None` if the result needs more than the plain case: more than
/// 19 digits discarded, a sticky amount on a value that already fits, or an
/// exponent that is clamped, subnormal or beyond the range of the context.
fn gda_fast_finish(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent : Int32,
  sticky : Bool,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  let precision = ctx.precision_
  let digits = gda_fast_digits128(high, low)
  let mut coefficient = low
  let mut result_exponent = exponent
  let mut rounded = false
  let mut inexact = false
  if digits > precision {
    let drop = digits - precision
    guard drop <= 19 else { return None }
    let divisor = gda_fast_pow10.unsafe_get(drop)
    let kept = if high == 0UL {
      low / divisor
    } else {
      gda_fast_div_wide(high, low, divisor)
    }
    let remainder = low - kept * divisor
    let half = divisor >> 1
    rounded = true
    inexact = remainder != 0UL || sticky
    coefficient = if gda_fast_increment(
        ctx.rounding_,
        negative,
        kept,
        remainder,
        half,
        sticky,
      ) {
      kept + 1UL
    } else {
      kept
    }
    result_exponent += drop
    if coefficient == gda_fast_pow10.unsafe_get(precision) {
      // the increment carried into 10^precision
      coefficient = gda_fast_pow10.unsafe_get(precision - 1)
      result_exponent += 1
    }
  } else if sticky {
    return None
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
  let value = finite_with_exponent_repr(
    negative,
    DecCoeff::Small(coefficient),
    result_exponent,
    precision,
  )
  if rounded {
    Some(
      complete_decimal_gda(value, ctx, {
        ..DecimalFlags::new(),
        rounded: true,
        inexact,
      }),
    )
  } else {
    Some(gda_completed_exact(value, ctx))
  }
}

///|
/// `lhs + rhs`, or `lhs - rhs` when `subtract_rhs`.
fn gda_fast_sum(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
  subtract_rhs : Bool,
) -> GdaOutcome[Decimal]? {
  guard gda_fast_context_ok(ctx, 18) &&
    gda_fast_operand(lhs) is Some(left) &&
    gda_fast_operand(rhs) is Some(right) else {
    return None
  }
  let right_negative = rhs.negative != subtract_rhs
  let left_exponent = lhs.exponent10
  let right_exponent = rhs.exponent10
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  guard left_shift <= 19 && right_shift <= 19 else { return None }
  let left_power = gda_fast_pow10.unsafe_get(left_shift)
  let right_power = gda_fast_pow10.unsafe_get(right_shift)
  let left_high = gda_fast_mul_high(left, left_power)
  let left_low = left * left_power
  let right_high = gda_fast_mul_high(right, right_power)
  let right_low = right * right_power
  if lhs.negative == right_negative {
    let low = left_low + right_low
    let carry = if low < left_low { 1UL } else { 0UL }
    gda_fast_finish(
      lhs.negative,
      left_high + right_high + carry,
      low,
      target,
      false,
      ctx,
    )
  } else if left_high > right_high ||
    (left_high == right_high && left_low > right_low) {
    let borrow = if left_low < right_low { 1UL } else { 0UL }
    gda_fast_finish(
      lhs.negative,
      left_high - right_high - borrow,
      left_low - right_low,
      target,
      false,
      ctx,
    )
  } else if left_high == right_high && left_low == right_low {
    None
  } else {
    let borrow = if right_low < left_low { 1UL } else { 0UL }
    gda_fast_finish(
      right_negative,
      right_high - left_high - borrow,
      right_low - left_low,
      target,
      false,
      ctx,
    )
  }
}

///|
fn gda_fast_product(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  guard gda_fast_context_ok(ctx, 18) &&
    gda_fast_operand(lhs) is Some(left) &&
    gda_fast_operand(rhs) is Some(right) else {
    return None
  }
  gda_fast_finish(
    lhs.negative != rhs.negative,
    gda_fast_mul_high(left, right),
    left * right,
    lhs.exponent10 + rhs.exponent10,
    false,
    ctx,
  )
}

///|
/// The quotient of the coefficients scaled to carry at least `precision + 1`
/// digits, with a sticky bit from the remainder. An exact quotient (zero
/// remainder) is left to the general path, which also settles the preferred
/// exponent of an exact result.
fn gda_fast_quotient(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal]? {
  guard gda_fast_context_ok(ctx, 17) &&
    gda_fast_operand(lhs) is Some(dividend) &&
    gda_fast_operand(rhs) is Some(divisor) else {
    return None
  }
  let precision = ctx.precision_
  let dividend_digits = gda_fast_digits64(dividend)
  let divisor_digits = gda_fast_digits64(divisor)
  let scale = Int32::max(0, precision + 1 + divisor_digits - dividend_digits)
  guard scale <= 19 else { return None }
  let power = gda_fast_pow10.unsafe_get(scale)
  let high = gda_fast_mul_high(dividend, power)
  let low = dividend * power
  guard high < divisor else { return None }
  let quotient = gda_fast_div_wide(high, low, divisor)
  let remainder = low - quotient * divisor
  guard remainder != 0UL && quotient >= gda_fast_pow10.unsafe_get(precision) else {
    return None
  }
  gda_fast_finish(
    lhs.negative != rhs.negative,
    0UL,
    quotient,
    lhs.exponent10 - rhs.exponent10 - scale,
    true,
    ctx,
  )
}
