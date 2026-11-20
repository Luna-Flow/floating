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
using @bin_kernel {
  bin_coeff_sqrt_scaled_rounded,
  bin_coeff_div_scaled_ok,
  bin_coeff_div_short_ok,
  bin_coeff_div_short_quotient,
  bin_coeff_short_division_guard_bits,
  bin_coeff_div_scaled_quotient,
}

///|
/// Coefficients wider than this, and precisions above it, are left to the
/// general path.
let binary_coeff_fast_bits_limit : Int32 = 1048576

///|
/// Rounds the nonzero `magnitude * 2^exponent`, plus a tiny positive amount
/// when `inexact` (only allowed when `magnitude` has more than `precision`
/// bits), to `precision` bits, to nearest even, and builds the result with an
/// odd coefficient. The magnitude is copied once into a fresh array, which
/// `bin_finish_words` rounds and normalises in place and keeps.
fn binary_coeff_fast_finish(
  negative : Bool,
  magnitude : Coeff,
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
  let count = (bits + 63) / 64
  let words = FixedArray::make(count, 0UL)
  match magnitude.0 {
    Heap(source, _) => FixedArray::unsafe_blit(words, 0, source, 0, count)
    _ =>
      for index in 0..<count {
        words.unsafe_set(index, bin_coeff_word(magnitude, index))
      }
  }
  bin_finish_words(
    negative,
    words,
    count,
    exponent,
    precision,
    inexact,
    BinaryRoundingMode::RoundTiesToEven,
  )
}

///|
/// The little-endian words of `value`: the array of a heap coefficient itself
/// (not to be modified), a fresh small array otherwise. The count comes from
/// `binary_coeff_fast_len`; a returned tuple would be a heap object.
fn binary_coeff_fast_array(value : Coeff) -> FixedArray[UInt64] {
  match value.0 {
    Heap(words, _) => words
    Inline64(low) => [low]
    Inline128(high, low) => [low, high]
  }
}

///|
fn binary_coeff_fast_len(value : Coeff) -> Int32 {
  match value.0 {
    Heap(_, len) => len
    Inline64(_) => 1
    Inline128(_, _) => 2
  }
}

///|
/// `Some(precision)` when both operands are finite, nonzero, narrow enough,
/// and have exponents far from the implementation limits.
fn binary_coeff_fast_operands(left : BinFloat, right : BinFloat) -> Int32? {
  if binary_coeff_fast_operands_ok(left, right) {
    Some(Int32::max(left.precision_, right.precision_))
  } else {
    None
  }
}

///|
/// Whether both operands are finite, nonzero, narrow enough, and have
/// exponents far from the implementation limits (the test of
/// `binary_coeff_fast_operands`, without an option of a scalar).
fn binary_coeff_fast_operands_ok(left : BinFloat, right : BinFloat) -> Bool {
  let precision = Int32::max(left.precision_, right.precision_)
  precision <= binary_coeff_fast_bits_limit &&
  left.class == FpClass::Finite &&
  right.class == FpClass::Finite &&
  left.exponent2 <= binary_fast_exponent_limit &&
  left.exponent2 >= -binary_fast_exponent_limit &&
  right.exponent2 <= binary_fast_exponent_limit &&
  right.exponent2 >= -binary_fast_exponent_limit &&
  !left.coefficient_.is_zero() &&
  !right.coefficient_.is_zero()
}

///|
/// Word `index` of the window: `words` (`len` limbs) placed so that its bit 0
/// is bit `64 * word_shift + bit_shift` of the window (`0 <= bit_shift < 64`;
/// `word_shift` is negative when the operand is cut at the window bottom).
/// Limbs outside the operand read as zero.
fn bin_window_word(
  words : FixedArray[UInt64],
  len : Int32,
  word_shift : Int32,
  bit_shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - word_shift
  let low = if source >= 0 && source < len {
    words.unsafe_get(source)
  } else {
    0UL
  }
  if bit_shift == 0 {
    return low
  }
  let below = if source >= 1 && source <= len {
    words.unsafe_get(source - 1)
  } else {
    0UL
  }
  (low << bit_shift) | (below >> (64 - bit_shift))
}

///|
/// One pass over `count` limbs: `words = x + y + carry_in`, or
/// `x - y - carry_in` (a borrow) when `subtract`; both operands are read
/// through their shifts, and `y_len = 0` reads nothing of `y`. Returns the
/// carry or borrow out of the top limb. A subtraction is the addition of the
/// complement, `x + !y + (1 - borrow)`, so that one loop serves both. The
/// limbs of the window where every source limb exists are read without any
/// bounds test (a shifted limb is `(v[i] << b) | (v[i - 1] >> (64 - b))`,
/// written with two shifts so that `b = 0` needs no branch); the few limbs at
/// either end go through `bin_window_word`.
fn bin_window_combine(
  words : FixedArray[UInt64],
  count : Int32,
  x : FixedArray[UInt64],
  x_len : Int32,
  x_word_shift : Int32,
  x_bit_shift : Int32,
  y : FixedArray[UInt64],
  y_len : Int32,
  y_word_shift : Int32,
  y_bit_shift : Int32,
  subtract : Bool,
  carry_in : UInt64,
) -> UInt64 {
  let mask = if subtract { 0xFFFFFFFFFFFFFFFFUL } else { 0UL }
  let mut carry = if subtract { 1UL - carry_in } else { carry_in }
  let use_y = y_len > 0
  let mut low = x_word_shift + 1
  let mut high = x_word_shift + x_len
  if use_y {
    low = Int32::max(low, y_word_shift + 1)
    high = Int32::min(high, y_word_shift + y_len)
  }
  low = Int32::max(0, Int32::min(low, count))
  high = Int32::min(count, Int32::max(high, low))
  for index in 0..<low {
    let a = bin_window_word(x, x_len, x_word_shift, x_bit_shift, index)
    let b = bin_window_word(y, y_len, y_word_shift, y_bit_shift, index) ^ mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  let x_down = 63 - x_bit_shift
  if low < high {
    // the previous source limb of each operand is carried in a register
    let mut x_previous = x.unsafe_get(low - x_word_shift - 1)
    if use_y {
      let y_down = 63 - y_bit_shift
      let mut y_previous = y.unsafe_get(low - y_word_shift - 1)
      for index in low..<high {
        let x_current = x.unsafe_get(index - x_word_shift)
        let y_current = y.unsafe_get(index - y_word_shift)
        let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
        let b = ((y_current << y_bit_shift) | (y_previous >> 1 >> y_down)) ^
          mask
        x_previous = x_current
        y_previous = y_current
        let partial = a + b
        let sum = partial + carry
        let first = if partial < a { 1UL } else { 0UL }
        let second = if sum < partial { 1UL } else { 0UL }
        carry = first | second
        words.unsafe_set(index, sum)
      }
    } else {
      for index in low..<high {
        let x_current = x.unsafe_get(index - x_word_shift)
        let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
        x_previous = x_current
        let partial = a + mask
        let sum = partial + carry
        let first = if partial < a { 1UL } else { 0UL }
        let second = if sum < partial { 1UL } else { 0UL }
        carry = first | second
        words.unsafe_set(index, sum)
      }
    }
  }
  for index in high..<count {
    let a = bin_window_word(x, x_len, x_word_shift, x_bit_shift, index)
    let b = bin_window_word(y, y_len, y_word_shift, y_bit_shift, index) ^ mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  if subtract {
    1UL - carry
  } else {
    carry
  }
}

///|
/// `words = -words` modulo `2^(64 * count)`.
fn bin_window_negate(words : FixedArray[UInt64], count : Int32) -> Unit {
  let mut carry = 1UL
  for index in 0..<count {
    let value = words.unsafe_get(index).lnot() + carry
    carry = if carry == 1UL && value == 0UL { 1UL } else { 0UL }
    words.unsafe_set(index, value)
  }
}

///|
/// Sum of two finite non-zero operands, rounded to nearest even at the
/// larger precision, for coefficients wider than one word. The operand `x`
/// with the larger top bit is placed in a window of `count` limbs whose bit 0
/// has weight `2^base`, `base = max(min(e_x, e_y), top - (p + 3))`: `y` is
/// read through its shift in the same pass, and when it reaches below the
/// window its dropped part is non-zero (its coefficient is odd) and becomes
/// the sticky bit; when it lies entirely below, none of its limbs is read.
/// The window then holds the exact sum, or a truncated one with at least
/// `p + 2` bits and the sticky bit, and `bin_finish_words` rounds it in place
/// (design page, "Finishing a wide result in place", and the note on far-apart
/// operands). Returns `None` for an exact zero sum and outside the range of
/// the coefficient paths; the general path then answers.
fn binary_coeff_fast_add(left : BinFloat, right : BinFloat) -> BinFloat? {
  guard binary_coeff_fast_operands_ok(left, right) else { return None }
  let precision = Int32::max(left.precision_, right.precision_)
  let left_bits = left.coefficient_.bit_length()
  let right_bits = right.coefficient_.bit_length()
  guard left_bits <= binary_coeff_fast_bits_limit &&
    right_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  let left_top = left.exponent2 + left_bits
  let right_top = right.exponent2 + right_bits
  let left_is_x = left_top >= right_top
  let x_coefficient = if left_is_x {
    left.coefficient_
  } else {
    right.coefficient_
  }
  let y_coefficient = if left_is_x {
    right.coefficient_
  } else {
    left.coefficient_
  }
  let x_exponent = if left_is_x { left.exponent2 } else { right.exponent2 }
  let y_exponent = if left_is_x { right.exponent2 } else { left.exponent2 }
  let x_negative = if left_is_x { left.negative } else { right.negative }
  let y_negative = if left_is_x { right.negative } else { left.negative }
  let top = Int32::max(left_top, right_top)
  let y_top = Int32::min(left_top, right_top)
  let base = Int32::max(
    Int32::min(x_exponent, y_exponent),
    top - (precision + 3),
  )
  let count = (top - base) / 64 + 1
  let x_shift = x_exponent - base
  let y_shift = y_exponent - base
  let sticky = y_shift < 0
  let y_word_shift = if y_shift >= 0 {
    y_shift / 64
  } else {
    -((63 - y_shift) / 64)
  }
  let y_bit_shift = y_shift - 64 * y_word_shift
  let subtract = x_negative != y_negative
  let words = FixedArray::make(count, 0UL)
  let borrow = bin_window_combine(
    words,
    count,
    binary_coeff_fast_array(x_coefficient),
    binary_coeff_fast_len(x_coefficient),
    x_shift / 64,
    x_shift % 64,
    binary_coeff_fast_array(y_coefficient),
    if y_top > base {
      binary_coeff_fast_len(y_coefficient)
    } else {
      0
    },
    y_word_shift,
    y_bit_shift,
    subtract,
    if subtract && sticky {
      1UL
    } else {
      0UL
    },
  )
  if !subtract {
    return Some(
      bin_finish_words(
        x_negative,
        words,
        count,
        base,
        precision,
        sticky,
        BinaryRoundingMode::RoundTiesToEven,
      ),
    )
  }
  // equal tops: the result is exact, and may be zero or negative
  if y_top == top {
    let mut nonzero = false
    for index in 0..<count {
      if words.unsafe_get(index) != 0UL {
        nonzero = true
        break
      }
    }
    if !nonzero {
      return None
    }
  }
  let negative = if borrow != 0UL {
    bin_window_negate(words, count)
    y_negative
  } else {
    x_negative
  }
  Some(
    bin_finish_words(
      negative,
      words,
      count,
      base,
      precision,
      sticky,
      BinaryRoundingMode::RoundTiesToEven,
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
  // short division: an approximate quotient with guard bits, used only when
  // its rounding is certain (the exact division handles every other case)
  let short_scale = scale + bin_coeff_short_division_guard_bits
  if bin_coeff_div_short_ok(dividend, short_scale, divisor) {
    let approximate = bin_coeff_div_short_quotient(
      dividend, short_scale, divisor, precision,
    )
    if !approximate.is_zero() {
      return Some(
        binary_coeff_fast_finish(
          left.negative != right.negative,
          approximate,
          left.exponent2 - right.exponent2 - short_scale,
          precision,
          false,
        ),
      )
    }
  }
  if bin_coeff_div_scaled_ok(dividend, scale, divisor) {
    // the lowest bit of the quotient is the inexact flag
    return Some(
      binary_coeff_fast_finish(
        left.negative != right.negative,
        bin_coeff_div_scaled_quotient(dividend, scale, divisor),
        left.exponent2 - right.exponent2 - scale - 1,
        precision,
        false,
      ),
    )
  }
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
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff)? {
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
  let packed = bin_coeff_sqrt_scaled_rounded(
    value.coefficient_,
    scale,
    precision,
  )
  // a root of exactly `precision` bits comes back rounded, at its own
  // exponent; a longer one carries its round and sticky bits two below it
  let adjust = if packed.bit_length() <= precision + 1 { 0 } else { -2 }
  Some(
    binary_coeff_fast_finish(
      false,
      packed,
      (exponent - scale) / 2 + adjust,
      precision,
      false,
    ),
  )
}
