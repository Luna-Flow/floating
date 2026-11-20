///|
/// Allocation-light paths for `BinFloat::add`, `mul` and `div` on operands whose
/// coefficients are a single machine word. The general path builds several
/// `BinCoeff` values, a context, a flags record and a result tuple for each
/// operation; here the arithmetic runs on `UInt64` pairs and only the result is
/// allocated. Each function returns `None` outside its range (a NaN, an
/// infinity, a zero, a coefficient or precision that is too wide, exponents
/// near the implementation limits, an exact zero sum), and the general path
/// then answers, so the results, which are the results of
/// `add_ctx`/`mul_ctx`/`div_ctx` with `BinaryContext::unbounded(max precision)`
/// (round to nearest even), are bit for bit those of the general path.

///|
/// Operand exponents are limited to this magnitude, far inside the
/// implementation exponent range, so the fast paths never overflow or
/// underflow.
let binary_fast_exponent_limit : Int32 = 268435456

///|
fn binary_fast_bits(value : UInt64) -> Int32 {
  64 - value.reinterpret_as_int64().clz()
}

///|
fn binary_fast_word(value : BinFloat) -> UInt64? {
  if value.class != FpClass::Finite {
    return None
  }
  match value.coefficient_.0 {
    Inline64(word) => if word == 0UL { None } else { Some(word) }
    _ => None
  }
}

///|
/// High word of `value << shift`, `0 <= shift < 128`.
fn binary_fast_shl_high(value : UInt64, shift : Int32) -> UInt64 {
  if shift == 0 {
    0UL
  } else if shift < 64 {
    value >> (64 - shift)
  } else {
    value << (shift - 64)
  }
}

///|
/// Low word of `value << shift`, `0 <= shift < 128`.
fn binary_fast_shl_low(value : UInt64, shift : Int32) -> UInt64 {
  if shift < 64 {
    value << shift
  } else {
    0UL
  }
}

///|
/// High word of the 128-bit product of two words.
fn binary_fast_mul_high(left : UInt64, right : UInt64) -> UInt64 {
  let left_low = left & bin_coeff_limb_mask
  let left_high = left >> 32
  let right_low = right & bin_coeff_limb_mask
  let right_high = right >> 32
  let low_low = left_low * right_low
  let high_low = left_high * right_low
  let low_high = left_low * right_high
  let high_high = left_high * right_high
  let middle = (low_low >> 32) +
    (high_low & bin_coeff_limb_mask) +
    (low_high & bin_coeff_limb_mask)
  high_high + (high_low >> 32) + (low_high >> 32) + (middle >> 32)
}

///|
/// `floor((high * 2^64 + low) / divisor)` for `high < divisor` (Hacker's
/// Delight, `divlu`): the quotient fits one word.
fn binary_fast_div_wide(
  high : UInt64,
  low : UInt64,
  divisor : UInt64,
) -> UInt64 {
  let shift = 64 - binary_fast_bits(divisor)
  let normalized = divisor << shift
  let high_part = if shift == 0 {
    high
  } else {
    (high << shift) | (low >> (64 - shift))
  }
  let low_part = low << shift
  let divisor_high = normalized >> 32
  let divisor_low = normalized & bin_coeff_limb_mask
  let digit_high = low_part >> 32
  let digit_low = low_part & bin_coeff_limb_mask
  let mut quotient_high = high_part / divisor_high
  let mut remainder = high_part - quotient_high * divisor_high
  while quotient_high >= bin_coeff_limb_base ||
        quotient_high * divisor_low > ((remainder << 32) | digit_high) {
    quotient_high -= 1UL
    remainder += divisor_high
    if remainder >= bin_coeff_limb_base {
      break
    }
  }
  let middle = (high_part << 32) + digit_high - quotient_high * normalized
  let mut quotient_low = middle / divisor_high
  remainder = middle - quotient_low * divisor_high
  while quotient_low >= bin_coeff_limb_base ||
        quotient_low * divisor_low > ((remainder << 32) | digit_low) {
    quotient_low -= 1UL
    remainder += divisor_high
    if remainder >= bin_coeff_limb_base {
      break
    }
  }
  (quotient_high << 32) + quotient_low
}

///|
/// Rounds the positive 128-bit value `high * 2^64 + low` (nonzero) times
/// `2^exponent` to `precision` bits, to nearest even, and builds the result:
/// odd coefficient, adjusted exponent, `precision` as the result precision.
/// `precision` is at most 62.
fn binary_fast_round(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent : Int32,
  precision : Int32,
) -> BinFloat {
  let width = if high != 0UL {
    64 + binary_fast_bits(high)
  } else {
    binary_fast_bits(low)
  }
  let mut quotient = low
  let mut result_exponent = exponent
  if width > precision {
    let shift = width - precision
    quotient = if shift < 64 {
      (low >> shift) | (high << (64 - shift))
    } else {
      high >> (shift - 64)
    }
    // the bit below the kept ones and the sticky bits under it
    let round_index = shift - 1
    let round_bit = if round_index < 64 {
      (low >> round_index) & 1UL
    } else {
      (high >> (round_index - 64)) & 1UL
    }
    let sticky = if round_index == 0 {
      false
    } else if round_index <= 64 {
      (if round_index == 64 { low } else { low & ((1UL << round_index) - 1UL) }) !=
      0UL
    } else {
      low != 0UL || (high & ((1UL << (round_index - 64)) - 1UL)) != 0UL
    }
    if round_bit == 1UL && (sticky || (quotient & 1UL) == 1UL) {
      quotient += 1UL
    }
    result_exponent += shift
  }
  let zeros = quotient.reinterpret_as_int64().ctz()
  finite_normalized(
    negative,
    BinCoeff::from_uint64(quotient >> zeros),
    result_exponent + zeros,
    precision,
  )
}

///|
fn binary_fast_add(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= 62 else { return None }
  guard binary_fast_word(left) is Some(left_word) &&
    binary_fast_word(right) is Some(right_word) else {
    return None
  }
  let left_exponent = left.exponent2
  let right_exponent = right.exponent2
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let left_bits = binary_fast_bits(left_word)
  let right_bits = binary_fast_bits(right_word)
  let gap = (left_exponent + left_bits - right_exponent - right_bits).to_int64()
  let far = (precision + 3).to_int64()
  guard gap <= far && gap >= -far else { return None }
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  guard left_bits + left_shift <= 126 && right_bits + right_shift <= 126 else {
    return None
  }
  let left_high = binary_fast_shl_high(left_word, left_shift)
  let left_low = binary_fast_shl_low(left_word, left_shift)
  let right_high = binary_fast_shl_high(right_word, right_shift)
  let right_low = binary_fast_shl_low(right_word, right_shift)
  if left.negative == right.negative {
    let low = left_low + right_low
    let carry = if low < left_low { 1UL } else { 0UL }
    binary_fast_round_some(
      left.negative,
      left_high + right_high + carry,
      low,
      target,
      precision,
    )
  } else {
    let left_larger = left_high > right_high ||
      (left_high == right_high && left_low > right_low)
    if left_high == right_high && left_low == right_low {
      return None
    }
    if left_larger {
      let borrow = if left_low < right_low { 1UL } else { 0UL }
      binary_fast_round_some(
        left.negative,
        left_high - right_high - borrow,
        left_low - right_low,
        target,
        precision,
      )
    } else {
      let borrow = if right_low < left_low { 1UL } else { 0UL }
      binary_fast_round_some(
        right.negative,
        right_high - left_high - borrow,
        right_low - left_low,
        target,
        precision,
      )
    }
  }
}

///|
fn binary_fast_round_some(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent : Int32,
  precision : Int32,
) -> BinFloat? {
  Some(binary_fast_round(negative, high, low, exponent, precision))
}

///|
fn binary_fast_mul(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= 62 else { return None }
  guard binary_fast_word(left) is Some(left_word) &&
    binary_fast_word(right) is Some(right_word) else {
    return None
  }
  let left_exponent = left.exponent2
  let right_exponent = right.exponent2
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  Some(
    binary_fast_round(
      left.negative != right.negative,
      binary_fast_mul_high(left_word, right_word),
      left_word * right_word,
      left_exponent + right_exponent,
      precision,
    ),
  )
}

///|
fn binary_fast_div(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= 60 else { return None }
  guard binary_fast_word(left) is Some(dividend) &&
    binary_fast_word(right) is Some(divisor) else {
    return None
  }
  let left_exponent = left.exponent2
  let right_exponent = right.exponent2
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  // quotient of `dividend * 2^k / divisor` with at least `precision + 2` bits
  let dividend_bits = binary_fast_bits(dividend)
  let divisor_bits = binary_fast_bits(divisor)
  let scale = Int32::max(0, precision + 2 + divisor_bits - dividend_bits)
  guard dividend_bits + scale <= 126 else { return None }
  let high = binary_fast_shl_high(dividend, scale)
  let low = binary_fast_shl_low(dividend, scale)
  guard high < divisor else { return None }
  let quotient = binary_fast_div_wide(high, low, divisor)
  let remainder = low - quotient * divisor
  // one more low bit stands for "the remainder is not zero"
  let sticky = if remainder != 0UL { 1UL } else { 0UL }
  Some(
    binary_fast_round(
      left.negative != right.negative,
      quotient >> 63,
      (quotient << 1) | sticky,
      left_exponent - right_exponent - scale - 1,
      precision,
    ),
  )
}

///|
/// `floor(sqrt(high * 2^64 + low))` of a nonzero 126-bit value, with `exact`
/// telling whether the value is a perfect square: a double-precision estimate
/// refined by one Newton step on 128-bit arithmetic and settled by exact
/// comparisons with the squares around it. `None` if the estimate is off
/// by more than the comparisons expect (never for the supported range).
fn binary_fast_isqrt(high : UInt64, low : UInt64) -> (UInt64, Bool)? {
  let estimate = (high.to_double() * 18446744073709551616.0 + low.to_double()).sqrt()
  let mut root = estimate.to_uint64()
  if root == 0UL {
    root = 1UL
  }
  guard high < root else { return None }
  let quotient = binary_fast_div_wide(high, low, root)
  root = (root >> 1) + (quotient >> 1) + (root & quotient & 1UL)
  // settle: root^2 <= value < (root + 1)^2
  let mut steps = 0
  while steps < 4 {
    steps += 1
    let square_high = binary_fast_mul_high(root, root)
    let square_low = root * root
    if square_high > high || (square_high == high && square_low > low) {
      root -= 1UL
      continue
    }
    let next = root + 1UL
    let next_high = binary_fast_mul_high(next, next)
    let next_low = next * next
    if next_high < high || (next_high == high && next_low <= low) {
      root = next
      continue
    }
    return Some((root, square_high == high && square_low == low))
  }
  None
}

///|
fn binary_fast_sqrt(value : BinFloat) -> BinFloat? {
  let precision = value.precision_
  guard precision <= 60 && !value.negative else { return None }
  guard binary_fast_word(value) is Some(word) else { return None }
  let exponent = value.exponent2
  guard exponent <= binary_fast_exponent_limit &&
    exponent >= -binary_fast_exponent_limit else {
    return None
  }
  // radicand word * 2^scale with an even exponent and at least 2 * (precision + 2) bits
  let bits = binary_fast_bits(word)
  let mut scale = Int32::max(0, 2 * (precision + 2) - bits)
  if (exponent - scale) % 2 != 0 {
    scale += 1
  }
  guard bits + scale <= 126 else { return None }
  let high = binary_fast_shl_high(word, scale)
  let low = binary_fast_shl_low(word, scale)
  guard binary_fast_isqrt(high, low) is Some((root, exact)) else { return None }
  let sticky = if exact { 0UL } else { 1UL }
  Some(
    binary_fast_round(
      false,
      root >> 63,
      (root << 1) | sticky,
      (exponent - scale) / 2 - 1,
      precision,
    ),
  )
}
