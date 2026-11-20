///|
/// Two-word fast paths for `BinFloat::add` and `mul` on operands whose
/// coefficients take at most two machine words (up to 128 bits) at a result
/// precision of at most 128 bits, the range just above the one-word paths of
/// `bin_float_fast_nonjs.mbt`. The arithmetic runs on `UInt64` words (a
/// 192-bit sum, a 256-bit product) and only the result is allocated. Each
/// function returns `None` outside its range and the wider paths answer, so
/// the results, which are the results of `add_ctx`/`mul_ctx` with
/// `binary_working_context(max precision)` (round to nearest even), are bit
/// for bit those of the general path.

///|
let binary_pair_precision_limit : Int32 = 128

///|
/// Whether `value` is finite with a nonzero coefficient of one or two words.
/// The words come from `binary_pair_high_of` and `binary_pair_low_of`: an
/// option of a tuple would allocate two objects per operand.
fn binary_pair_is_words(value : BinFloat) -> Bool {
  value.is_pair()
}

///|
fn binary_pair_high_of(value : BinFloat) -> UInt64 {
  value.pair_high()
}

///|
fn binary_pair_low_of(value : BinFloat) -> UInt64 {
  value.pair_low()
}

///|
/// Bit length of the 256-bit value `w3:w2:w1:w0` (nonzero).
fn binary_pair_bits(
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
) -> Int32 {
  if word3 != 0UL {
    192 + binary_fast_bits(word3)
  } else if word2 != 0UL {
    128 + binary_fast_bits(word2)
  } else if word1 != 0UL {
    64 + binary_fast_bits(word1)
  } else {
    binary_fast_bits(word0)
  }
}

///|
/// Word `index` (0 to 3) of `high:low << shift`, `0 <= shift < 192`.
fn binary_pair_shl_word(
  high : UInt64,
  low : UInt64,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let word_shift = shift / 64
  let bit_shift = shift % 64
  // the word of the unshifted value that lands in `index`, and the one below
  let source = index - word_shift
  let below = source - 1
  let part = if source == 0 { low } else if source == 1 { high } else { 0UL }
  if bit_shift == 0 {
    return part
  }
  let lower = if below == 0 { low } else if below == 1 { high } else { 0UL }
  (part << bit_shift) | (lower >> (64 - bit_shift))
}

///|
/// Word `index` (0 to 3) of `word3:word2:word1:word0 >> shift`,
/// `0 <= shift < 256`.
fn binary_pair_shr_word(
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let word_shift = shift / 64
  let bit_shift = shift % 64
  let source = index + word_shift
  let part = match source {
    0 => word0
    1 => word1
    2 => word2
    3 => word3
    _ => 0UL
  }
  if bit_shift == 0 {
    return part
  }
  let upper = match source + 1 {
    1 => word1
    2 => word2
    3 => word3
    _ => 0UL
  }
  (part >> bit_shift) | (upper << (64 - bit_shift))
}

///|
/// Whether any of the lowest `count` bits (`0 <= count < 256`) of
/// `word3:word2:word1:word0` is set.
fn binary_pair_low_nonzero(
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
  count : Int32,
) -> Bool {
  let whole = count / 64
  let rest = count % 64
  if (whole > 0 && word0 != 0UL) ||
    (whole > 1 && word1 != 0UL) ||
    (whole > 2 && word2 != 0UL) {
    return true
  }
  if rest == 0 {
    return false
  }
  let partial = match whole {
    0 => word0
    1 => word1
    2 => word2
    _ => word3
  }
  (partial & ((1UL << rest) - 1UL)) != 0UL
}

///|
/// Rounds the positive `word3:word2:word1:word0 * 2^exponent` (nonzero) to
/// `precision` bits, `precision <= 128`, to nearest even, and builds the
/// result: odd coefficient, adjusted exponent, `precision` as the result
/// precision.
fn binary_pair_round(
  negative : Bool,
  word3 : UInt64,
  word2 : UInt64,
  word1 : UInt64,
  word0 : UInt64,
  exponent : Int32,
  precision : Int32,
) -> BinFloat {
  let bits = binary_pair_bits(word3, word2, word1, word0)
  let mut high = word1
  let mut low = word0
  let mut result_exponent = exponent
  if bits > precision {
    let shift = bits - precision
    let mut round_bit = false
    let mut sticky = false
    if word3 == 0UL && shift < 64 {
      // the common case (a sum or a product that is a few bits or at most a
      // word too wide): the kept words and the dropped bits from three words
      let back = 64 - shift
      low = (word0 >> shift) | (word1 << back)
      high = (word1 >> shift) | (word2 << back)
      round_bit = ((word0 >> (shift - 1)) & 1UL) == 1UL
      sticky = shift > 1 && (word0 & ((1UL << (shift - 1)) - 1UL)) != 0UL
    } else {
      low = binary_pair_shr_word(word3, word2, word1, word0, shift, 0)
      high = binary_pair_shr_word(word3, word2, word1, word0, shift, 1)
      // the bit below the kept ones and the sticky bits under it
      let round_index = shift - 1
      round_bit = (
          binary_pair_shr_word(word3, word2, word1, word0, round_index, 0) & 1UL
        ) ==
        1UL
      sticky = round_bit &&
        binary_pair_low_nonzero(word3, word2, word1, word0, round_index)
    }
    if round_bit {
      if sticky || (low & 1UL) == 1UL {
        low += 1UL
        if low == 0UL {
          high += 1UL
          if high == 0UL {
            // 2^128: the kept bits were all ones
            low = 1UL
            result_exponent += 128
          }
        }
      }
    }
    result_exponent += shift
  }
  let zeros = if low == 0UL {
    64 + high.reinterpret_as_int64().ctz()
  } else {
    low.reinterpret_as_int64().ctz()
  }
  if zeros > 0 {
    if zeros >= 64 {
      low = high >> (zeros - 64)
      high = 0UL
    } else {
      low = (low >> zeros) | (high << (64 - zeros))
      high = high >> zeros
    }
    result_exponent += zeros
  }
  bin_repr_pair(negative, high, low, result_exponent, precision)
}

///|
fn binary_pair_add_signed(
  left : BinFloat,
  right : BinFloat,
  flip : Bool,
) -> BinFloat? {
  // `right` with its sign flipped when `flip` (a subtraction), without a new value
  let right_negative = right.negative() != flip
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= binary_pair_precision_limit else { return None }
  guard binary_pair_is_words(left) && binary_pair_is_words(right) else {
    return None
  }
  let left_high = binary_pair_high_of(left)
  let left_low = binary_pair_low_of(left)
  let right_high = binary_pair_high_of(right)
  let right_low = binary_pair_low_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let left_bits = if left_high != 0UL {
    64 + binary_fast_bits(left_high)
  } else {
    binary_fast_bits(left_low)
  }
  let right_bits = if right_high != 0UL {
    64 + binary_fast_bits(right_high)
  } else {
    binary_fast_bits(right_low)
  }
  let gap = (left_exponent + left_bits - right_exponent - right_bits).to_int64()
  let far = (precision + 3).to_int64()
  guard gap <= far && gap >= -far else { return None }
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  // both aligned operands fit 191 bits, so the sum fits three words
  guard left_bits + left_shift <= 191 && right_bits + right_shift <= 191 else {
    return None
  }
  // The operand with the smaller exponent has shift 0 and is its two words;
  // the other is shifted by the exponent difference. A shift below 64 (the
  // common case: the operands overlap) is three shifts of two words; a
  // larger one, three words from `binary_pair_shl_word`.
  let mut left2 = 0UL
  let mut left1 = left_high
  let mut left0 = left_low
  if left_shift != 0 {
    if left_shift < 64 {
      let back = 64 - left_shift
      left2 = left_high >> back
      left1 = (left_high << left_shift) | (left_low >> back)
      left0 = left_low << left_shift
    } else {
      left2 = binary_pair_shl_word(left_high, left_low, left_shift, 2)
      left1 = binary_pair_shl_word(left_high, left_low, left_shift, 1)
      left0 = binary_pair_shl_word(left_high, left_low, left_shift, 0)
    }
  }
  let mut right2 = 0UL
  let mut right1 = right_high
  let mut right0 = right_low
  if right_shift != 0 {
    if right_shift < 64 {
      let back = 64 - right_shift
      right2 = right_high >> back
      right1 = (right_high << right_shift) | (right_low >> back)
      right0 = right_low << right_shift
    } else {
      right2 = binary_pair_shl_word(right_high, right_low, right_shift, 2)
      right1 = binary_pair_shl_word(right_high, right_low, right_shift, 1)
      right0 = binary_pair_shl_word(right_high, right_low, right_shift, 0)
    }
  }
  if left.negative() == right_negative {
    let word0 = left0 + right0
    let carry0 = if word0 < left0 { 1UL } else { 0UL }
    let partial1 = left1 + right1
    let carry1a = if partial1 < left1 { 1UL } else { 0UL }
    let word1 = partial1 + carry0
    let carry1b = if word1 < partial1 { 1UL } else { 0UL }
    let word2 = left2 + right2 + carry1a + carry1b
    Some(
      binary_pair_round(
        left.negative(),
        0UL,
        word2,
        word1,
        word0,
        target,
        precision,
      ),
    )
  } else {
    let left_larger = left2 > right2 ||
      (
        left2 == right2 &&
        (left1 > right1 || (left1 == right1 && left0 > right0))
      )
    if left2 == right2 && left1 == right1 && left0 == right0 {
      return None
    }
    if left_larger {
      let word0 = left0 - right0
      let borrow0 = if left0 < right0 { 1UL } else { 0UL }
      let partial1 = left1 - right1
      let borrow1a = if left1 < right1 { 1UL } else { 0UL }
      let word1 = partial1 - borrow0
      let borrow1b = if partial1 < borrow0 { 1UL } else { 0UL }
      let word2 = left2 - right2 - borrow1a - borrow1b
      Some(
        binary_pair_round(
          left.negative(),
          0UL,
          word2,
          word1,
          word0,
          target,
          precision,
        ),
      )
    } else {
      let word0 = right0 - left0
      let borrow0 = if right0 < left0 { 1UL } else { 0UL }
      let partial1 = right1 - left1
      let borrow1a = if right1 < left1 { 1UL } else { 0UL }
      let word1 = partial1 - borrow0
      let borrow1b = if partial1 < borrow0 { 1UL } else { 0UL }
      let word2 = right2 - left2 - borrow1a - borrow1b
      Some(
        binary_pair_round(
          right_negative, 0UL, word2, word1, word0, target, precision,
        ),
      )
    }
  }
}

///|
fn binary_pair_mul(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= binary_pair_precision_limit else { return None }
  guard binary_pair_is_words(left) && binary_pair_is_words(right) else {
    return None
  }
  let left_high = binary_pair_high_of(left)
  let left_low = binary_pair_low_of(left)
  let right_high = binary_pair_high_of(right)
  let right_low = binary_pair_low_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  // the 256-bit product from the four word products
  let word0 = left_low * right_low
  let high00 = binary_fast_mul_high(left_low, right_low)
  let mut word1 = high00
  let mut word2 = 0UL
  let mut word3 = 0UL
  if right_high != 0UL {
    let low01 = left_low * right_high
    let high01 = binary_fast_mul_high(left_low, right_high)
    word1 += low01
    if word1 < low01 {
      word2 += 1UL
    }
    word2 += high01
    if word2 < high01 {
      word3 += 1UL
    }
  }
  if left_high != 0UL {
    let low10 = left_high * right_low
    let high10 = binary_fast_mul_high(left_high, right_low)
    word1 += low10
    if word1 < low10 {
      word2 += 1UL
      if word2 == 0UL {
        word3 += 1UL
      }
    }
    word2 += high10
    if word2 < high10 {
      word3 += 1UL
    }
    if right_high != 0UL {
      let low11 = left_high * right_high
      let high11 = binary_fast_mul_high(left_high, right_high)
      word2 += low11
      if word2 < low11 {
        word3 += 1UL
      }
      word3 += high11
    }
  }
  Some(
    binary_pair_round(
      left.negative() != right.negative(),
      word3,
      word2,
      word1,
      word0,
      left_exponent + right_exponent,
      precision,
    ),
  )
}

///|
/// Word `index` (0 to 4) of the 128-bit `high:low << shift`, `0 <= shift < 320`.
fn binary_pair_shl_word5(
  high : UInt64,
  low : UInt64,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - shift / 64
  let bit_shift = shift % 64
  let part = if source == 0 { low } else if source == 1 { high } else { 0UL }
  if bit_shift == 0 {
    return part
  }
  let below = source - 1
  let lower = if below == 0 { low } else if below == 1 { high } else { 0UL }
  (part << bit_shift) | (lower >> (64 - bit_shift))
}

///|
/// Division of two operands whose coefficients take at most two words, at a
/// result precision of at most 128 bits, the range above the one-word division
/// of `bin_float_fast_nonjs.mbt`. With `s = 128 - divisor_bits` and `scale`
/// chosen so that the quotient has at least `precision + 2` bits, the
/// dividend `<< (scale + s)` has at most 258 bits (five words) and the
/// divisor `<< s` is a normalised two-word value, so the quotient has at most
/// three words: Knuth's algorithm D with three steps, each dividing three words
/// by two. The remainder is only tested against zero (one sticky bit under the
/// quotient), as in `binary_fast_div`. Nothing is allocated but the result.
fn binary_pair_div(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= binary_pair_precision_limit else { return None }
  guard left.class() == FpClass::Finite && right.class() == FpClass::Finite else {
    return None
  }
  guard left.is_pair() && right.is_pair() else { return None }
  let dividend_high = left.pair_high()
  let dividend_low = left.pair_low()
  let divisor_high = right.pair_high()
  let divisor_low = right.pair_low()
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let dividend_bits = if dividend_high != 0UL {
    64 + binary_fast_bits(dividend_high)
  } else {
    binary_fast_bits(dividend_low)
  }
  let divisor_bits = if divisor_high != 0UL {
    64 + binary_fast_bits(divisor_high)
  } else {
    binary_fast_bits(divisor_low)
  }
  let scale = Int32::max(0, precision + 2 + divisor_bits - dividend_bits)
  let normalization = 128 - divisor_bits
  let shift = scale + normalization
  // the shifted dividend has at most 258 bits: five words
  guard dividend_bits + shift <= 258 else { return None }
  let d1 = binary_pair_shl_word5(divisor_high, divisor_low, normalization, 1)
  let d0 = binary_pair_shl_word5(divisor_high, divisor_low, normalization, 0)
  let n4 = binary_pair_shl_word5(dividend_high, dividend_low, shift, 4)
  let n3 = binary_pair_shl_word5(dividend_high, dividend_low, shift, 3)
  let n2 = binary_pair_shl_word5(dividend_high, dividend_low, shift, 2)
  let n1 = binary_pair_shl_word5(dividend_high, dividend_low, shift, 1)
  let n0 = binary_pair_shl_word5(dividend_high, dividend_low, shift, 0)
  // (n4, n3) < (d1, d0): the quotient has at most 131 bits
  let mut r1 = n4
  let mut r0 = n3
  let mut q2 = 0UL
  let mut q1 = 0UL
  let mut q0 = 0UL
  for step in 0..<3 {
    let u2 = r1
    let u1 = r0
    let u0 = match step {
      0 => n2
      1 => n1
      _ => n0
    }
    let mut trial = 0UL
    let mut trial_remainder = 0UL
    let mut remainder_overflow = false
    if u2 >= d1 {
      trial = 0xFFFF_FFFF_FFFF_FFFFUL
      trial_remainder = u1 + d1
      remainder_overflow = trial_remainder < u1
    } else {
      trial = binary_fast_div_wide(u2, u1, d1)
      trial_remainder = u1 - trial * d1
    }
    while !remainder_overflow {
      let product_high = binary_fast_mul_high(trial, d0)
      let product_low = trial * d0
      if product_high > trial_remainder ||
        (product_high == trial_remainder && product_low > u0) {
        trial -= 1UL
        trial_remainder += d1
        remainder_overflow = trial_remainder < d1
      } else {
        break
      }
    }
    // (u2, u1, u0) - trial * (d1, d0)
    let m0 = trial * d0
    let high0 = binary_fast_mul_high(trial, d0)
    let low1 = trial * d1
    let m1 = low1 + high0
    let m2 = binary_fast_mul_high(trial, d1) +
      (if m1 < low1 { 1UL } else { 0UL })
    let difference0 = u0 - m0
    let borrow0 = if u0 < m0 { 1UL } else { 0UL }
    let partial1 = u1 - m1
    let borrow1a = if u1 < m1 { 1UL } else { 0UL }
    let difference1 = partial1 - borrow0
    let borrow1b = if partial1 < borrow0 { 1UL } else { 0UL }
    let partial2 = u2 - m2
    let borrow2a = if u2 < m2 { 1UL } else { 0UL }
    let borrow1 = borrow1a + borrow1b
    let borrow2b = if partial2 < borrow1 { 1UL } else { 0UL }
    r0 = difference0
    r1 = difference1
    if borrow2a + borrow2b != 0UL {
      // the estimate was one too large: add the divisor back
      trial -= 1UL
      let sum0 = r0 + d0
      let carry0 = if sum0 < r0 { 1UL } else { 0UL }
      r0 = sum0
      r1 = r1 + d1 + carry0
    }
    match step {
      0 => q2 = trial
      1 => q1 = trial
      _ => q0 = trial
    }
  }
  let sticky = if r1 != 0UL || r0 != 0UL { 1UL } else { 0UL }
  // one more low bit stands for "the remainder is not zero"
  Some(
    binary_pair_round(
      left.negative() != right.negative(),
      q2 >> 63,
      (q2 << 1) | (q1 >> 63),
      (q1 << 1) | (q0 >> 63),
      (q0 << 1) | sticky,
      left_exponent - right_exponent - scale - 1,
      precision,
    ),
  )
}
