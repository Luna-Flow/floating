///|
/// Allocation-light paths for `BinFloat::add`, `mul` and `div` on operands whose
/// coefficients are a single machine word. The general path builds several
/// `Coeff` values, a context, a flags record and a result tuple for each
/// operation; here the arithmetic runs on `UInt64` pairs and only the result is
/// allocated. Each function returns `None` outside its range (a NaN, an
/// infinity, a zero, a coefficient or precision that is too wide, exponents
/// near the implementation limits, an exact zero sum), and the general path
/// then answers, so the results, which are the results of
/// `add_ctx`/`mul_ctx`/`div_ctx` with `binary_working_context(max precision)`
/// (round to nearest even), are bit for bit those of the general path.

///|
/// Operand exponents are limited to this magnitude, far inside the
/// implementation exponent range, so the fast paths never overflow or
/// underflow.
let binary_fast_exponent_limit : Int32 = 268435456

///|
/// Whether `value` is finite with a nonzero one-word coefficient. A function
/// returning `UInt64?` allocates a box for the `Some`, so the test and the word
/// are two functions that return scalars.
fn binary_fast_is_word(value : BinFloat) -> Bool {
  value.class() == FpClass::Finite &&
  (match value.coefficient_().0 {
    Inline64(word) => word != 0UL
    _ => false
  })
}

///|
/// The one-word coefficient of a value for which `binary_fast_is_word` holds.
fn binary_fast_word_of(value : BinFloat) -> UInt64 {
  match value.coefficient_().0 {
    Inline64(word) => word
    _ => 0UL
  }
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
    Coeff::from_uint64(quotient >> zeros),
    result_exponent + zeros,
    precision,
  )
}

///|
fn binary_fast_add_signed(
  left : BinFloat,
  right : BinFloat,
  flip : Bool,
) -> BinFloat? {
  // `right` with its sign flipped when `flip` (a subtraction), without a new value
  let right_negative = right.negative() != flip
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= 62 else { return None }
  guard binary_fast_is_word(left) && binary_fast_is_word(right) else {
    return None
  }
  let left_word = binary_fast_word_of(left)
  let right_word = binary_fast_word_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
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
  if left.negative() == right_negative {
    let low = left_low + right_low
    let carry = if low < left_low { 1UL } else { 0UL }
    binary_fast_round_some(
      left.negative(),
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
        left.negative(),
        left_high - right_high - borrow,
        left_low - right_low,
        target,
        precision,
      )
    } else {
      let borrow = if right_low < left_low { 1UL } else { 0UL }
      binary_fast_round_some(
        right_negative,
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
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= 62 else { return None }
  guard binary_fast_is_word(left) && binary_fast_is_word(right) else {
    return None
  }
  let left_word = binary_fast_word_of(left)
  let right_word = binary_fast_word_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  Some(
    binary_fast_round(
      left.negative() != right.negative(),
      binary_fast_mul_high(left_word, right_word),
      left_word * right_word,
      left_exponent + right_exponent,
      precision,
    ),
  )
}

///|
fn binary_fast_div_words(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= 60 else { return None }
  guard binary_fast_is_word(left) && binary_fast_is_word(right) else {
    return None
  }
  let dividend = binary_fast_word_of(left)
  let divisor = binary_fast_word_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
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
      left.negative() != right.negative(),
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
fn binary_fast_isqrt(high : UInt64, low : UInt64) -> UInt64 {
  let estimate = (high.to_double() * 18446744073709551616.0 + low.to_double()).sqrt()
  let mut root = estimate.to_uint64()
  if root == 0UL {
    root = 1UL
  }
  guard high < root else { return 0UL }
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
    return root
  }
  0UL
}

///|
fn binary_fast_sqrt_words(value : BinFloat) -> BinFloat? {
  let precision = value.precision_()
  guard precision <= 60 && !value.negative() else { return None }
  guard binary_fast_is_word(value) else { return None }
  let word = binary_fast_word_of(value)
  let exponent = value.exponent2_()
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
  let root = binary_fast_isqrt(high, low)
  guard root != 0UL else { return None }
  let exact = binary_fast_mul_high(root, root) == high && root * root == low
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

///|
/// Coefficients up to this value are exactly representable as binary64.
let binary_fast_double_limit : UInt64 = 0x20_0000_0000_0000UL

///|
/// The result `mantissa * 2^(exponent + e)` of a positive normal binary64 `value`
/// (`mantissa * 2^e` its exact value) as a 53-bit `BinFloat` with an odd
/// coefficient.
fn binary_fast_from_double(
  negative : Bool,
  value : Double,
  exponent : Int32,
) -> BinFloat {
  let bits = value.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7ffUL).to_int()
  let mantissa = (bits & 0xf_ffff_ffff_ffffUL) | 0x10_0000_0000_0000UL
  let zeros = mantissa.reinterpret_as_int64().ctz()
  finite_normalized(
    negative,
    Coeff::from_uint64(mantissa >> zeros),
    exponent + (biased - 1075) + zeros,
    53,
  )
}

///|
/// At precision 53 the quotient of two coefficients of at most 53 bits is
/// formed by one binary64 division: both operands are exact binary64 numbers,
/// the IEEE 754 division returns the correctly rounded (to nearest even) 53-bit
/// quotient, which is the result of the general path, and scaling by a power of
/// two does not change a rounding decision without an exponent range.
fn binary_fast_div(left : BinFloat, right : BinFloat) -> BinFloat? {
  if Int32::max(left.precision_(), right.precision_()) == 53 &&
    binary_fast_is_word(left) &&
    binary_fast_is_word(right) &&
    binary_fast_word_of(left) <= binary_fast_double_limit &&
    binary_fast_word_of(right) <= binary_fast_double_limit &&
    left.exponent2_() <= binary_fast_exponent_limit &&
    left.exponent2_() >= -binary_fast_exponent_limit &&
    right.exponent2_() <= binary_fast_exponent_limit &&
    right.exponent2_() >= -binary_fast_exponent_limit {
    return Some(
      binary_fast_from_double(
        left.negative() != right.negative(),
        binary_fast_word_of(left).to_double() /
        binary_fast_word_of(right).to_double(),
        left.exponent2_() - right.exponent2_(),
      ),
    )
  }
  binary_fast_div_words(left, right)
}

///|
/// At precision 53 the square root of a coefficient of at most 53 bits, times
/// 2 for an odd exponent, is one binary64 square root (correctly rounded to
/// nearest even by IEEE 754): the same reasoning as for the division.
fn binary_fast_sqrt(value : BinFloat) -> BinFloat? {
  if value.precision_() == 53 &&
    !value.negative() &&
    binary_fast_is_word(value) &&
    binary_fast_word_of(value) <= binary_fast_double_limit &&
    value.exponent2_() <= binary_fast_exponent_limit &&
    value.exponent2_() >= -binary_fast_exponent_limit {
    let odd = value.exponent2_() & 1
    let radicand = binary_fast_word_of(value).to_double() *
      (if odd == 1 { 2.0 } else { 1.0 })
    return Some(
      binary_fast_from_double(
        false,
        radicand.sqrt(),
        (value.exponent2_() - odd) / 2,
      ),
    )
  }
  binary_fast_sqrt_words(value)
}
