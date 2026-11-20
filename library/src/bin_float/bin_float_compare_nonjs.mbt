///|
/// `high:low << shift` truncated to 128 bits, high word (`0 <= shift < 128`).
fn binary_shl128_high(high : UInt64, low : UInt64, shift : Int32) -> UInt64 {
  if shift == 0 {
    high
  } else if shift < 64 {
    (high << shift) | (low >> (64 - shift))
  } else if shift == 64 {
    low
  } else {
    low << (shift - 64)
  }
}

///|
/// `high:low << shift` truncated to 128 bits, low word.
fn binary_shl128_low(low : UInt64, shift : Int32) -> UInt64 {
  if shift >= 64 {
    0UL
  } else {
    low << shift
  }
}

///|
/// Order of the magnitudes of two finite non-zero values of at most 128
/// coefficient bits, decided on the words without building a coefficient: -1, 0
/// or 1; 2 when an operand is wider (the caller takes the general path).
/// The two operands are read by one match (`bin_repr_nonjs.mbt` has the forms).
fn binary_compare_pair_magnitude(left : BinFloat, right : BinFloat) -> Int32 {
  match (left.0, right.0) {
    (
      Fin64(word=left_low, exponent2=left_exponent, ..),
      Fin64(word=right_low, exponent2=right_exponent, ..),
    ) =>
      binary_compare_words(
        0UL, left_low, left_exponent, 0UL, right_low, right_exponent,
      )
    (
      Fin64(word=left_low, exponent2=left_exponent, ..),
      Fin128(high=right_high, low=right_low, exponent2=right_exponent, ..),
    ) =>
      binary_compare_words(
        0UL, left_low, left_exponent, right_high, right_low, right_exponent,
      )
    (
      Fin128(high=left_high, low=left_low, exponent2=left_exponent, ..),
      Fin64(word=right_low, exponent2=right_exponent, ..),
    ) =>
      binary_compare_words(
        left_high, left_low, left_exponent, 0UL, right_low, right_exponent,
      )
    (
      Fin128(high=left_high, low=left_low, exponent2=left_exponent, ..),
      Fin128(high=right_high, low=right_low, exponent2=right_exponent, ..),
    ) =>
      binary_compare_words(
        left_high, left_low, left_exponent, right_high, right_low, right_exponent,
      )
    _ => 2
  }
}

///|
/// The order of `left_high:left_low * 2^left_exponent` and the same of the right,
/// for non-zero odd coefficients of at most 128 bits.
///
/// Coefficients are odd, so equal values have equal exponents and equal
/// coefficients (the form of a value is unique). Different leading-bit
/// exponents decide the order; with equal ones the operand of the larger
/// exponent has the shorter coefficient, and shifting it left by the exponent
/// difference gives a number of the other operand's length (at most 128 bits),
/// which is compared with the other coefficient.
fn binary_compare_words(
  left_high : UInt64,
  left_low : UInt64,
  left_exponent : Int32,
  right_high : UInt64,
  right_low : UInt64,
  right_exponent : Int32,
) -> Int32 {
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
  let left_top = left_exponent + left_bits
  let right_top = right_exponent + right_bits
  if left_top != right_top {
    return if left_top < right_top { -1 } else { 1 }
  }
  let mut high_a = left_high
  let mut low_a = left_low
  let mut high_b = right_high
  let mut low_b = right_low
  if left_exponent > right_exponent {
    let shift = left_exponent - right_exponent
    let high = binary_shl128_high(high_a, low_a, shift)
    low_a = binary_shl128_low(low_a, shift)
    high_a = high
  } else if right_exponent > left_exponent {
    let shift = right_exponent - left_exponent
    let high = binary_shl128_high(high_b, low_b, shift)
    low_b = binary_shl128_low(low_b, shift)
    high_b = high
  }
  if high_a != high_b {
    return if high_a < high_b { -1 } else { 1 }
  }
  if low_a != low_b {
    return if low_a < low_b { -1 } else { 1 }
  }
  0
}

///|
/// The order of two finite values of at most 128 coefficient bits, signs
/// included, read by one match: -1, 0 or 1; 2 when an operand is not such a
/// value (infinity, NaN or a wider coefficient), which the caller handles.
fn binary_compare_pair(left : BinFloat, right : BinFloat) -> Int32 {
  match (left.0, right.0) {
    (
      Fin64(negative=ln, word=ll, exponent2=le, ..),
      Fin64(negative=rn, word=rl, exponent2=re, ..),
    ) => binary_compare_signed_words(ln, 0UL, ll, le, rn, 0UL, rl, re)
    (
      Fin64(negative=ln, word=ll, exponent2=le, ..),
      Fin128(negative=rn, high=rh, low=rl, exponent2=re, ..),
    ) => binary_compare_signed_words(ln, 0UL, ll, le, rn, rh, rl, re)
    (
      Fin128(negative=ln, high=lh, low=ll, exponent2=le, ..),
      Fin64(negative=rn, word=rl, exponent2=re, ..),
    ) => binary_compare_signed_words(ln, lh, ll, le, rn, 0UL, rl, re)
    (
      Fin128(negative=ln, high=lh, low=ll, exponent2=le, ..),
      Fin128(negative=rn, high=rh, low=rl, exponent2=re, ..),
    ) => binary_compare_signed_words(ln, lh, ll, le, rn, rh, rl, re)
    _ => 2
  }
}

///|
/// Signs, zeros, then the magnitudes (`binary_compare_words`).
fn binary_compare_signed_words(
  left_negative : Bool,
  left_high : UInt64,
  left_low : UInt64,
  left_exponent : Int32,
  right_negative : Bool,
  right_high : UInt64,
  right_low : UInt64,
  right_exponent : Int32,
) -> Int32 {
  let left_zero = left_high == 0UL && left_low == 0UL
  let right_zero = right_high == 0UL && right_low == 0UL
  if left_zero && right_zero {
    return 0
  }
  if left_negative != right_negative {
    return if left_negative { -1 } else { 1 }
  }
  let magnitude = if left_zero {
    -1
  } else if right_zero {
    1
  } else {
    binary_compare_words(
      left_high, left_low, left_exponent, right_high, right_low, right_exponent,
    )
  }
  if left_negative {
    -magnitude
  } else {
    magnitude
  }
}
