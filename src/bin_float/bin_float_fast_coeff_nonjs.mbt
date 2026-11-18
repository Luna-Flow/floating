///|
/// Coefficient-level fast paths for `BinFloat::add`, `mul`, `div` and `sqrt`
/// on operands that are wider than one machine word. They run the same
/// exact integer arithmetic as the general path
/// (`add_ctx`/`mul_ctx`/`div_ctx`/`sqrt_ctx` with
/// `BinaryContext::unbounded(max precision)`, round to nearest even) but skip
/// the context, the exception flags, the result tuple and the repeated
/// rounding decisions: the exact result (or, for a quotient, a truncated
/// result carrying at least two bits more than the precision plus a sticky
/// bit; for a root, the integer root and its remainder) is rounded once, to nearest even, and the value is built
/// directly. Each function returns `None` outside its range (a NaN, an
/// infinity, a zero, a very wide coefficient, a very large precision,
/// exponents near the implementation limits, an exact zero sum, operands
/// whose exponents are far apart), and the general path then answers, so the
/// results are bit for bit those of the general path.

///|
/// Coefficients wider than this, and precisions above it, are left to the
/// general path.
let binary_coeff_fast_bits_limit : Int32 = 1048576

///|
/// Whether any of the lowest `count` bits of `value` is set.
fn binary_coeff_fast_low_nonzero(value : BinCoeff, count : Int32) -> Bool {
  let whole = count / 64
  let rest = count % 64
  for index in 0..<whole {
    if bin_coeff_word(value, index) != 0UL {
      return true
    }
  }
  rest != 0 && (bin_coeff_word(value, whole) & ((1UL << rest) - 1UL)) != 0UL
}

///|
/// Rounds the nonzero `magnitude * 2^exponent`, plus a tiny positive amount
/// when `inexact` (only allowed when `magnitude` has more than `precision`
/// bits), to `precision` bits, to nearest even, and builds the result with an
/// odd coefficient. The kept bits are copied once, into the array that
/// becomes the coefficient.
fn binary_coeff_fast_finish(
  negative : Bool,
  magnitude : BinCoeff,
  exponent : Int32,
  precision : Int32,
  inexact : Bool,
) -> BinFloat {
  let bits = magnitude.bit_length()
  if bits <= precision {
    let zeros = magnitude.ctz()
    if zeros == 0 {
      return finite_normalized(negative, magnitude, exponent, precision)
    }
    return finite_normalized(
      negative,
      magnitude.shift_right(zeros),
      exponent + zeros,
      precision,
    )
  }
  let shift = bits - precision
  let count = (precision + 63) / 64
  let words = FixedArray::make(count, 0UL)
  let word_shift = shift / 64
  let bit_shift = shift % 64
  for index in 0..<count {
    let low = bin_coeff_word(magnitude, word_shift + index)
    words.unsafe_set(
      index,
      if bit_shift == 0 {
        low
      } else {
        (low >> bit_shift) |
        (bin_coeff_word(magnitude, word_shift + index + 1) << (64 - bit_shift))
      },
    )
  }
  let mut result_exponent = exponent + shift
  // the bit below the kept ones and the sticky bits under it
  let round_index = shift - 1
  if ((bin_coeff_word(magnitude, round_index / 64) >> (round_index % 64)) & 1UL) ==
    1UL {
    let sticky = inexact ||
      binary_coeff_fast_low_nonzero(magnitude, round_index)
    if sticky || (words.unsafe_get(0) & 1UL) == 1UL {
      let mut index = 0
      while index < count {
        let next = words.unsafe_get(index) + 1UL
        words.unsafe_set(index, next)
        if next != 0UL {
          break
        }
        index += 1
      }
      if index == count {
        // every kept bit was set: the sum is 2^(64 * count)
        words.unsafe_set(0, 1UL)
        result_exponent += 64 * count
      }
    }
  }
  // odd coefficient
  let mut first = 0
  while words.unsafe_get(first) == 0UL {
    first += 1
  }
  let zeros = 64 * first + words.unsafe_get(first).reinterpret_as_int64().ctz()
  if zeros > 0 {
    let skip = zeros / 64
    let rest = zeros % 64
    for index in 0..<count {
      let low = if index + skip < count {
        words.unsafe_get(index + skip)
      } else {
        0UL
      }
      let high = if index + skip + 1 < count {
        words.unsafe_get(index + skip + 1)
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
    result_exponent += zeros
  }
  finite_normalized(
    negative,
    bin_coeff_from_words(words, count),
    result_exponent,
    precision,
  )
}

///|
/// The little-endian words of `value` and their count: the array of a heap
/// coefficient itself (not to be modified), a fresh small array otherwise.
fn binary_coeff_fast_words(value : BinCoeff) -> (FixedArray[UInt64], Int32) {
  match value.repr {
    Heap(words, len) => (words, len)
    Inline64(low) => ([low], 1)
    Inline128(high, low) => ([low, high], 2)
  }
}

///|
/// Word `index` of `words << shift` (`words` has `len` words).
fn binary_coeff_fast_aligned_word(
  words : FixedArray[UInt64],
  len : Int32,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - shift / 64
  if source < 0 || source > len {
    return 0UL
  }
  let bit_shift = shift % 64
  let word = if source < len { words.unsafe_get(source) } else { 0UL }
  if bit_shift == 0 {
    word
  } else if source == 0 {
    word << bit_shift
  } else {
    (word << bit_shift) | (words.unsafe_get(source - 1) >> (64 - bit_shift))
  }
}

///|
/// `Some(precision)` when both operands are finite, nonzero, narrow enough,
/// and have exponents far from the implementation limits.
fn binary_coeff_fast_operands(left : BinFloat, right : BinFloat) -> Int32? {
  let precision = Int32::max(left.precision_, right.precision_)
  guard precision <= binary_coeff_fast_bits_limit else { return None }
  guard left.class == FpClass::Finite && right.class == FpClass::Finite else {
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
  guard !left.coefficient_.is_zero() && !right.coefficient_.is_zero() else {
    return None
  }
  Some(precision)
}

///|
/// Sums wider than this many words are added with whole-coefficient
/// operations (bulk shifts and one addition), which beat the word loops
/// there.
let binary_coeff_fast_add_words_limit : Int32 = 24

///|
fn binary_coeff_fast_add_wide(
  left : BinFloat,
  right : BinFloat,
  target : Int32,
  left_shift : Int32,
  right_shift : Int32,
  precision : Int32,
) -> BinFloat? {
  let aligned_left = left.coefficient_.shift_left(left_shift)
  let aligned_right = right.coefficient_.shift_left(right_shift)
  if left.negative == right.negative {
    return Some(
      binary_coeff_fast_finish(
        left.negative,
        aligned_left.add(aligned_right),
        target,
        precision,
        false,
      ),
    )
  }
  let comparison = aligned_left.compare(aligned_right)
  if comparison == 0 {
    None
  } else if comparison > 0 {
    Some(
      binary_coeff_fast_finish(
        left.negative,
        aligned_left.sub_checked(aligned_right).unwrap(),
        target,
        precision,
        false,
      ),
    )
  } else {
    Some(
      binary_coeff_fast_finish(
        right.negative,
        aligned_right.sub_checked(aligned_left).unwrap(),
        target,
        precision,
        false,
      ),
    )
  }
}

///|
fn binary_coeff_fast_add(left : BinFloat, right : BinFloat) -> BinFloat? {
  guard binary_coeff_fast_operands(left, right) is Some(precision) else {
    return None
  }
  let left_bits = left.coefficient_.bit_length()
  let right_bits = right.coefficient_.bit_length()
  guard left_bits <= binary_coeff_fast_bits_limit &&
    right_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  let left_exponent = left.exponent2
  let right_exponent = right.exponent2
  let gap = (left_exponent + left_bits - right_exponent - right_bits).to_int64()
  let far = (precision + 3).to_int64()
  guard gap <= far && gap >= -far else { return None }
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  let left_top = left_bits + left_shift
  let right_top = right_bits + right_shift
  let count = Int32::max(left_top, right_top) / 64 + 1
  if count > binary_coeff_fast_add_words_limit {
    return binary_coeff_fast_add_wide(
      left, right, target, left_shift, right_shift, precision,
    )
  }
  let words = FixedArray::make(count, 0UL)
  let (left_words, left_len) = binary_coeff_fast_words(left.coefficient_)
  let (right_words, right_len) = binary_coeff_fast_words(right.coefficient_)
  if left.negative == right.negative {
    let mut carry = 0UL
    for index in 0..<count {
      let a = binary_coeff_fast_aligned_word(
        left_words, left_len, left_shift, index,
      )
      let b = binary_coeff_fast_aligned_word(
        right_words, right_len, right_shift, index,
      )
      let partial = a + b
      let sum = partial + carry
      carry = if partial < a || sum < partial { 1UL } else { 0UL }
      words.unsafe_set(index, sum)
    }
    return Some(
      binary_coeff_fast_finish(
        left.negative,
        bin_coeff_from_words(words, count),
        target,
        precision,
        false,
      ),
    )
  }
  // opposite signs: the larger aligned magnitude minus the smaller
  let mut comparison = if left_top != right_top {
    if left_top > right_top {
      1
    } else {
      -1
    }
  } else {
    0
  }
  let mut index = count - 1
  while comparison == 0 && index >= 0 {
    let a = binary_coeff_fast_aligned_word(
      left_words, left_len, left_shift, index,
    )
    let b = binary_coeff_fast_aligned_word(
      right_words, right_len, right_shift, index,
    )
    if a != b {
      comparison = if a > b { 1 } else { -1 }
    }
    index -= 1
  }
  if comparison == 0 {
    return None
  }
  let negative = if comparison > 0 { left.negative } else { right.negative }
  let mut borrow = 0UL
  for index in 0..<count {
    let left_word = binary_coeff_fast_aligned_word(
      left_words, left_len, left_shift, index,
    )
    let right_word = binary_coeff_fast_aligned_word(
      right_words, right_len, right_shift, index,
    )
    let a = if comparison > 0 { left_word } else { right_word }
    let b = if comparison > 0 { right_word } else { left_word }
    let partial = a - b
    let difference = partial - borrow
    borrow = if a < b || partial < borrow { 1UL } else { 0UL }
    words.unsafe_set(index, difference)
  }
  Some(
    binary_coeff_fast_finish(
      negative,
      bin_coeff_from_words(words, count),
      target,
      precision,
      false,
    ),
  )
}

///|
fn binary_coeff_fast_mul(left : BinFloat, right : BinFloat) -> BinFloat? {
  guard binary_coeff_fast_operands(left, right) is Some(precision) else {
    return None
  }
  guard left.coefficient_.bit_length() <= binary_coeff_fast_bits_limit &&
    right.coefficient_.bit_length() <= binary_coeff_fast_bits_limit else {
    return None
  }
  Some(
    binary_coeff_fast_finish(
      left.negative != right.negative,
      left.coefficient_.mul(right.coefficient_),
      left.exponent2 + right.exponent2,
      precision,
      false,
    ),
  )
}

///|
fn binary_coeff_fast_div(left : BinFloat, right : BinFloat) -> BinFloat? {
  guard binary_coeff_fast_operands(left, right) is Some(precision) else {
    return None
  }
  let dividend = left.coefficient_
  let divisor = right.coefficient_
  let dividend_bits = dividend.bit_length()
  let divisor_bits = divisor.bit_length()
  guard dividend_bits <= binary_coeff_fast_bits_limit &&
    divisor_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  // the quotient of `dividend * 2^scale / divisor` has at least
  // `precision + 2` bits
  let scale = Int32::max(0, precision + 2 + divisor_bits - dividend_bits)
  guard bin_coeff_short_div_rem_checked(dividend.shift_left(scale), divisor)
    is Some((quotient, remainder)) else {
    return None
  }
  Some(
    binary_coeff_fast_finish(
      left.negative != right.negative,
      quotient,
      left.exponent2 - right.exponent2 - scale,
      precision,
      !remainder.is_zero(),
    ),
  )
}

///|
fn bin_coeff_short_div_rem_checked(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff)? {
  if denominator.is_zero() {
    None
  } else {
    Some(bin_coeff_short_div_rem(numerator, denominator))
  }
}

///|
fn binary_coeff_fast_sqrt(value : BinFloat) -> BinFloat? {
  let precision = value.precision_
  guard precision <= binary_coeff_fast_bits_limit &&
    value.class == FpClass::Finite &&
    !value.negative &&
    !value.coefficient_.is_zero() else {
    return None
  }
  let exponent = value.exponent2
  guard exponent <= binary_fast_exponent_limit &&
    exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let bits = value.coefficient_.bit_length()
  guard bits <= binary_coeff_fast_bits_limit else { return None }
  // radicand coefficient * 2^scale with an even exponent and at least
  // 2 * precision - 1 bits, so that the root has at least precision bits
  let mut scale = Int32::max(0, 2 * precision - 1 - bits)
  if (exponent - scale) % 2 != 0 {
    scale += 1
  }
  let (root, remainder) = bin_coeff_sqrt_rem_kernel(
    value.coefficient_.shift_left(scale),
  )
  let result_exponent = (exponent - scale) / 2
  if root.bit_length() == precision {
    // `sqrt(root^2 + remainder)` is at least `root + 1/2` exactly when
    // `remainder > root`, and never equals it, so there are no ties
    let rounded = if remainder.compare(root) > 0 {
      root.add(BinCoeff::one())
    } else {
      root
    }
    return Some(
      binary_coeff_fast_finish(
        false, rounded, result_exponent, precision, false,
      ),
    )
  }
  Some(
    binary_coeff_fast_finish(
      false,
      root,
      result_exponent,
      precision,
      !remainder.is_zero(),
    ),
  )
}
