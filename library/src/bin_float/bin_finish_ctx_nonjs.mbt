// The word route of the contextual operations (F2 of the performance plan): the
// exact result of one-word operands is formed in two words, ONE rounding
// decision is taken on the words, and the value and the flags are built from that
// decision by two consumers. No `Coeff` is built and the only objects of an
// operation are the result `BinFloat` and the pair `(BinFloat, BinaryFlags)`.
//
// The route covers contexts of the default exponent range (the extendable
// precision format of IEEE 754-2019 3.7, the contexts of `BinaryContext::new`
// without `e_max`) of at most 62 bits and results far from both ends of the range
// (`binary_fast_exponent_limit`), so that nothing overflows or underflows and the
// only flag is `inexact`. Everything else takes the general route
// (`binary_round_dyadic`); `bin_finish_ctx_nonjs_wbtest.mbt` ties the two.

///|
/// The packed rounding decision of the positive 128-bit value `high:low` rounded
/// to `precision` bits in `mode` (`negative` is the sign of the result, which the
/// directed modes depend on): bits 0 to 7 hold the shift that drops the bits below
/// the kept ones (the number of dropped bits, 0 when the value fits), bit 8 the
/// increment of the kept bits, bit 9 whether the result is inexact. Bits 10 to 12
/// are reserved for the bounded exponent range (PR F2b of the performance plan):
/// 10 overflow, 11 tiny before rounding, 12 tiny after rounding; they are 0 in
/// this route, where nothing overflows or underflows, so the word does not change
/// shape when the range is added.
fn binary_round_decision_words(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> UInt64 {
  let width = if high != 0UL {
    64 + binary_fast_bits(high)
  } else {
    binary_fast_bits(low)
  }
  if width <= precision {
    return 0UL
  }
  let shift = width - precision
  let round_index = shift - 1
  let round_bit = if round_index < 64 {
    ((low >> round_index) & 1UL) == 1UL
  } else {
    ((high >> (round_index - 64)) & 1UL) == 1UL
  }
  let sticky = if round_index == 0 {
    false
  } else if round_index <= 64 {
    (if round_index == 64 { low } else { low & ((1UL << round_index) - 1UL) }) !=
    0UL
  } else {
    low != 0UL || (high & ((1UL << (round_index - 64)) - 1UL)) != 0UL
  }
  let inexact = round_bit || sticky
  let lowest_kept = if shift < 64 {
    ((low >> shift) & 1UL) == 1UL
  } else {
    ((high >> (shift - 64)) & 1UL) == 1UL
  }
  let increment = match mode {
    RoundTiesToEven => round_bit && (sticky || lowest_kept)
    RoundTiesToAway => round_bit
    RoundTowardZero => false
    RoundTowardPositive => !negative && inexact
    RoundTowardNegative => negative && inexact
  }
  shift.to_int64().reinterpret_as_uint64() |
  (if increment { 256UL } else { 0UL }) |
  (if inexact { 512UL } else { 0UL })
}

///|
/// The value consumer of the decision: the kept bits of `high:low * 2^exponent`
/// incremented when the decision says so, in normal form (odd coefficient) with
/// `precision` as the result precision.
fn binary_value_from_decision(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent : Int32,
  precision : Int32,
  decision : UInt64,
) -> BinFloat {
  let shift = (decision & 255UL).reinterpret_as_int64().to_int()
  let mut quotient = low
  if shift > 0 {
    quotient = if shift < 64 {
      (low >> shift) | (high << (64 - shift))
    } else {
      high >> (shift - 64)
    }
    if (decision & 256UL) != 0UL {
      quotient += 1UL
    }
  }
  let zeros = quotient.reinterpret_as_int64().ctz()
  bin_repr_word(
    negative,
    quotient >> zeros,
    exponent + shift + zeros,
    precision,
  )
}

///|
/// The flag consumer of the decision (this route has no overflow and no
/// underflow): `inexact` only.
fn binary_flags_from_decision(decision : UInt64) -> BinaryFlags {
  if (decision & 512UL) != 0UL {
    binary_inexact_flags(false)
  } else {
    BinaryFlags::new()
  }
}

///|
/// `left + right` (`right` negated when `flip`) of two finite one-word operands in
/// `context`, or `None` when the word route does not apply (a wide, zero or
/// far-apart operand, a context of the bounded range or of more than 62 bits, an
/// exact cancellation). An `Option` of a pair is the bare pointer: the only
/// allocations are the result and the pair.
fn binary_ctx_add_words(
  left : BinFloat,
  right : BinFloat,
  flip : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let precision = context.precision
  guard precision <= 62 &&
    context.range_e_max() == binary_implementation_e_max &&
    context.range_e_min() == binary_implementation_e_min else {
    return None
  }
  guard binary_fast_is_word(left) && binary_fast_is_word(right) else {
    return None
  }
  let right_negative = right.negative() != flip
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
  let mut negative = left.negative()
  let mut high = 0UL
  let mut low = 0UL
  if left.negative() == right_negative {
    low = left_low + right_low
    let carry = if low < left_low { 1UL } else { 0UL }
    high = left_high + right_high + carry
  } else {
    if left_high == right_high && left_low == right_low {
      return None
    }
    let left_larger = left_high > right_high ||
      (left_high == right_high && left_low > right_low)
    if left_larger {
      let borrow = if left_low < right_low { 1UL } else { 0UL }
      high = left_high - right_high - borrow
      low = left_low - right_low
    } else {
      let borrow = if right_low < left_low { 1UL } else { 0UL }
      negative = right_negative
      high = right_high - left_high - borrow
      low = right_low - left_low
    }
  }
  let decision = binary_round_decision_words(
    negative,
    high,
    low,
    precision,
    context.rounding,
  )
  Some(
    (
      binary_value_from_decision(
        negative, high, low, target, precision, decision,
      ),
      binary_flags_from_decision(decision),
    ),
  )
}

///|
/// `left * right` of two finite one-word operands in `context`, or `None` when
/// the word route does not apply (see `binary_ctx_add_words`; a zero or wide
/// operand).
fn binary_ctx_mul_words(
  left : BinFloat,
  right : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let precision = context.precision
  guard precision <= 62 &&
    context.range_e_max() == binary_implementation_e_max &&
    context.range_e_min() == binary_implementation_e_min else {
    return None
  }
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
  let negative = left.negative() != right.negative()
  let high = binary_fast_mul_high(left_word, right_word)
  let low = left_word * right_word
  let decision = binary_round_decision_words(
    negative,
    high,
    low,
    precision,
    context.rounding,
  )
  Some(
    (
      binary_value_from_decision(
        negative,
        high,
        low,
        left_exponent + right_exponent,
        precision,
        decision,
      ),
      binary_flags_from_decision(decision),
    ),
  )
}

///|
/// `left / right` of two finite non-zero one-word operands in `context` of at
/// most 60 bits (the quotient of `dividend * 2^k / divisor` has at least
/// `precision + 2` bits, and one more low bit stands for "the remainder is not
/// zero"), or `None`.
fn binary_ctx_div_words(
  left : BinFloat,
  right : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let precision = context.precision
  guard precision <= 60 &&
    context.range_e_max() == binary_implementation_e_max &&
    context.range_e_min() == binary_implementation_e_min else {
    return None
  }
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
  let dividend_bits = binary_fast_bits(dividend)
  let divisor_bits = binary_fast_bits(divisor)
  let scale = Int32::max(0, precision + 2 + divisor_bits - dividend_bits)
  guard dividend_bits + scale <= 126 else { return None }
  let high = binary_fast_shl_high(dividend, scale)
  let low = binary_fast_shl_low(dividend, scale)
  guard high < divisor else { return None }
  let quotient = binary_fast_div_wide(high, low, divisor)
  let remainder = low - quotient * divisor
  let sticky = if remainder != 0UL { 1UL } else { 0UL }
  let negative = left.negative() != right.negative()
  let quotient_high = quotient >> 63
  let quotient_low = (quotient << 1) | sticky
  let decision = binary_round_decision_words(
    negative,
    quotient_high,
    quotient_low,
    precision,
    context.rounding,
  )
  Some(
    (
      binary_value_from_decision(
        negative,
        quotient_high,
        quotient_low,
        left_exponent - right_exponent - scale - 1,
        precision,
        decision,
      ),
      binary_flags_from_decision(decision),
    ),
  )
}
