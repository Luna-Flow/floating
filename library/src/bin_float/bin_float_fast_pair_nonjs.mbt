///|
/// Two-word fast paths for `BinFloat::add` and `mul` on operands whose
/// coefficients take at most two machine words (up to 128 bits) at a result
/// precision of at most 128 bits, the range just above the one-word paths of
/// `bin_float_fast_nonjs.mbt`. The arithmetic runs on `UInt64` words (a
/// 192-bit sum, a 256-bit product) and only the result is allocated. Each
/// function returns `None` outside its range and the wider paths answer, so
/// the results, which are the results of `add_ctx`/`mul_ctx` with
/// `BinaryContext::unbounded(max precision)` (round to nearest even), are bit
/// for bit those of the general path.

///|
let binary_pair_precision_limit : Int32 = 128

///|
/// The two words of an operand coefficient, `None` for a zero or a heap
/// coefficient.
fn binary_pair_words(value : BinFloat) -> (UInt64, UInt64)? {
  if value.class != FpClass::Finite {
    return None
  }
  match value.coefficient_.repr {
    Inline64(low) => if low == 0UL { None } else { Some((0UL, low)) }
    Inline128(high, low) => Some((high, low))
    Heap(_, _) => None
  }
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
    low = binary_pair_shr_word(word3, word2, word1, word0, shift, 0)
    high = binary_pair_shr_word(word3, word2, word1, word0, shift, 1)
    // the bit below the kept ones and the sticky bits under it
    let round_index = shift - 1
    let round_word = binary_pair_shr_word(
      word3, word2, word1, word0, round_index, 0,
    )
    if (round_word & 1UL) == 1UL {
      let sticky = binary_pair_low_nonzero(
        word3, word2, word1, word0, round_index,
      )
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
  finite_normalized(
    negative,
    bin_coeff_inline(high, low),
    result_exponent,
    precision,
  )
}

///|
fn binary_pair_add(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= binary_pair_precision_limit else { return None }
  guard binary_pair_words(left) is Some((left_high, left_low)) &&
    binary_pair_words(right) is Some((right_high, right_low)) else {
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
  let left2 = binary_pair_shl_word(left_high, left_low, left_shift, 2)
  let left1 = binary_pair_shl_word(left_high, left_low, left_shift, 1)
  let left0 = binary_pair_shl_word(left_high, left_low, left_shift, 0)
  let right2 = binary_pair_shl_word(right_high, right_low, right_shift, 2)
  let right1 = binary_pair_shl_word(right_high, right_low, right_shift, 1)
  let right0 = binary_pair_shl_word(right_high, right_low, right_shift, 0)
  if left.negative == right.negative {
    let word0 = left0 + right0
    let carry0 = if word0 < left0 { 1UL } else { 0UL }
    let partial1 = left1 + right1
    let carry1a = if partial1 < left1 { 1UL } else { 0UL }
    let word1 = partial1 + carry0
    let carry1b = if word1 < partial1 { 1UL } else { 0UL }
    let word2 = left2 + right2 + carry1a + carry1b
    Some(
      binary_pair_round(
        left.negative,
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
          left.negative,
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
          right.negative,
          0UL,
          word2,
          word1,
          word0,
          target,
          precision,
        ),
      )
    }
  }
}

///|
fn binary_pair_mul(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= binary_pair_precision_limit else { return None }
  guard binary_pair_words(left) is Some((left_high, left_low)) &&
    binary_pair_words(right) is Some((right_high, right_low)) else {
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
      left.negative != right.negative,
      word3,
      word2,
      word1,
      word0,
      left_exponent + right_exponent,
      precision,
    ),
  )
}
