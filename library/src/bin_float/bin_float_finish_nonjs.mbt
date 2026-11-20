///|
/// Whether any of the bits below position `count` of `words` is set.
fn bin_finish_low_nonzero(words : FixedArray[UInt64], count : Int32) -> Bool {
  let whole = count / 64
  let rest = count % 64
  for index in 0..<whole {
    if words.unsafe_get(index) != 0UL {
      return true
    }
  }
  rest != 0 && (words.unsafe_get(whole) & ((1UL << rest) - 1UL)) != 0UL
}

///|
/// The rounding decision shared by the finisher: whether the kept bits are
/// incremented. `round_bit` is the bit just below the kept ones, `below`
/// whether anything under it is non-zero (the sticky bit included), `lsb` the
/// last kept bit.
fn bin_finish_round_up(
  mode : BinaryRoundingMode,
  negative : Bool,
  round_bit : Bool,
  below : Bool,
  lsb : Bool,
) -> Bool {
  match mode {
    RoundTiesToEven => round_bit && (below || lsb)
    RoundTiesToAway => round_bit
    RoundTowardZero => false
    RoundTowardPositive => !negative && (round_bit || below)
    RoundTowardNegative => negative && (round_bit || below)
    RoundAwayFromZero => round_bit || below
  }
}

///|
/// Rounds the non-zero magnitude held in `words` (little-endian, the first
/// `count` words, the top ones may be zero) times `2^exponent`, plus a tiny
/// positive amount when `sticky`, to `precision` bits in the direction `mode`,
/// and builds the result with an odd coefficient.
///
/// `sticky` is only allowed when the magnitude has more than `precision`
/// bits. The array is modified and kept by the result: the caller must own it
/// exclusively and must not use it afterwards. The kept bits, the rounding
/// increment (which never needs a carry chain: see below) and the removal of
/// trailing zero bits are one shift of the array into itself.
///
/// With `K` the kept bits and `q` the position of the lowest set bit of the
/// rounded value: without an increment `q` is the lowest set bit of the
/// magnitude at or above the rounding position; with an increment the rounded
/// value is `K + 1`, whose trailing zeros are the trailing ones `t` of `K`,
/// and `(K + 1) >> t = (K >> t) | 1` because bit `t` of `K` is zero, so `q` is
/// the lowest zero bit at or above the rounding position and the coefficient
/// is `(magnitude >> q) | 1` (all kept bits set: `q` is the bit length and
/// the coefficient is 1).
fn bin_finish_words(
  negative : Bool,
  words : FixedArray[UInt64],
  count : Int32,
  exponent : Int32,
  precision : Int32,
  sticky : Bool,
  mode : BinaryRoundingMode,
) -> BinFloat {
  let mut top = count - 1
  while words.unsafe_get(top) == 0UL {
    top -= 1
  }
  let bits = 64 * top + 64 - words.unsafe_get(top).reinterpret_as_int64().clz()
  let mut increment = false
  let mut position = 0
  if bits <= precision {
    let mut first = 0
    while words.unsafe_get(first) == 0UL {
      first += 1
    }
    position = 64 * first + words.unsafe_get(first).reinterpret_as_int64().ctz()
  } else {
    let shift = bits - precision
    let round_index = shift - 1
    let round_bit = (
        (words.unsafe_get(round_index / 64) >> (round_index % 64)) & 1UL
      ) ==
      1UL
    let lsb = ((words.unsafe_get(shift / 64) >> (shift % 64)) & 1UL) == 1UL
    let mut below = sticky
    if !below {
      let needed = match mode {
        RoundTiesToEven => round_bit && !lsb
        RoundTiesToAway | RoundTowardZero => false
        _ => !round_bit
      }
      if needed {
        below = bin_finish_low_nonzero(words, round_index)
      }
    }
    increment = bin_finish_round_up(mode, negative, round_bit, below, lsb)
    let mut index = shift / 64
    let offset = shift % 64
    if increment {
      // lowest zero bit at or above `shift`
      let mut zeros = words.unsafe_get(index).lnot() >> offset << offset
      while zeros == 0UL {
        index += 1
        if index == count {
          // every bit up to the top of the array is set
          break
        }
        zeros = words.unsafe_get(index).lnot()
      }
      position = if zeros == 0UL {
        64 * count
      } else {
        64 * index + zeros.reinterpret_as_int64().ctz()
      }
    } else {
      let mut ones = words.unsafe_get(index) >> offset << offset
      while ones == 0UL {
        index += 1
        ones = words.unsafe_get(index)
      }
      position = 64 * index + ones.reinterpret_as_int64().ctz()
    }
  }
  // the shifted magnitude, in place
  let length = if bits > position { (bits - position + 63) / 64 } else { 1 }
  let skip = position / 64
  let rest = position % 64
  if position != 0 {
    // the limbs whose source and its neighbour above both exist need no test
    let interior = Int32::max(0, Int32::min(length, count - skip - 1))
    if rest == 0 {
      for index in 0..<interior {
        words.unsafe_set(index, words.unsafe_get(skip + index))
      }
    } else {
      let up = 64 - rest
      for index in 0..<interior {
        words.unsafe_set(
          index,
          (words.unsafe_get(skip + index) >> rest) |
          (words.unsafe_get(skip + index + 1) << up),
        )
      }
    }
    for index in interior..<length {
      let source = skip + index
      let low = if source < count { words.unsafe_get(source) } else { 0UL }
      let high = if rest != 0 && source + 1 < count {
        words.unsafe_get(source + 1)
      } else {
        0UL
      }
      words.unsafe_set(
        index,
        if rest == 0 {
          low
        } else {
          (low >> rest) | (high << (64 - rest))
        },
      )
    }
  }
  for index in length..<count {
    words.unsafe_set(index, 0UL)
  }
  if increment {
    words.unsafe_set(0, words.unsafe_get(0) | 1UL)
  }
  finite_normalized(
    negative,
    bin_coeff_from_words(words, length),
    exponent + position,
    precision,
  )
}
