///|
/// Coefficient-level fast paths for `Binary::add`, `mul`, `div` and `sqrt`
/// on operands that are wider than one machine word. They run the same
/// exact integer arithmetic as the general path
/// (`add_ctx`/`mul_ctx`/`div_ctx`/`sqrt_ctx` with
/// `binary_working_context(max precision)`, round to nearest even) but skip
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
  bin_coeff_sqrt_rem_scaled,
  bin_words_sqrt_scaled_rounded,
  bin_coeff_div_scaled_ok,
  bin_coeff_div_short_ok,
  bin_words_div_short_quotient,
  bin_coeff_short_division_guard_bits,
  bin_words_div_scaled_quotient,
  bin_words_mul,
  bin_words_mul_short,
  bin_coeff_mul_short_ok,
  bin_coeff_short_product_limbs,
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
) -> Binary {
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
/// Rounds a kernel result that is an array (the first `count` limbs, the top
/// ones possibly zero) to `precision` bits and builds the value: rounded in place, no
/// coefficient box between the kernel and the result. The array must be fresh
/// (the array forms of the kernel guarantee it).
fn binary_coeff_fast_finish_array(
  negative : Bool,
  words : FixedArray[UInt64],
  count : Int32,
  exponent : Int32,
  precision : Int32,
  inexact : Bool,
) -> Binary {
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
/// The bit length of the value in the first `count` limbs of `words` (not all
/// zero).
fn binary_coeff_fast_words_bits(
  words : FixedArray[UInt64],
  count : Int32,
) -> Int32 {
  let mut top = count - 1
  while words.unsafe_get(top) == 0UL {
    top -= 1
  }
  64 * top + binary_fast_bits(words.unsafe_get(top))
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
/// `binary_coeff_fast_operands_ok` on scalars already read: the precision of the
/// result and the two exponents of finite non-zero operands.
fn binary_coeff_fast_scalars_ok(
  precision : Int32,
  left_exponent : Int32,
  right_exponent : Int32,
) -> Bool {
  precision <= binary_coeff_fast_bits_limit &&
  left_exponent <= binary_fast_exponent_limit &&
  left_exponent >= -binary_fast_exponent_limit &&
  right_exponent <= binary_fast_exponent_limit &&
  right_exponent >= -binary_fast_exponent_limit
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
fn binary_coeff_fast_add_signed(
  left : Binary,
  right : Binary,
  flip : Bool,
) -> Binary? {
  // `right` with its sign flipped when `flip` (a subtraction), without a new value.
  // Two wide operands are read by one match; any other pair through the
  // accessors (a small operand builds its coefficient once).
  match (left.0, right.0) {
    (
      FinBig(
        negative=left_negative,
        coefficient=left_coefficient,
        exponent2=left_exponent,
        precision=left_precision,
      ),
      FinBig(
        negative=right_negative,
        coefficient=right_coefficient,
        exponent2=right_exponent,
        precision=right_precision,
      ),
    ) =>
      binary_coeff_fast_add_parts(
        left_negative,
        left_coefficient,
        left_exponent,
        left_precision,
        right_negative != flip,
        right_coefficient,
        right_exponent,
        right_precision,
      )
    _ => {
      guard left.class() == FpClass::Finite && right.class() == FpClass::Finite else {
        return None
      }
      guard !left.coefficient_is_zero() && !right.coefficient_is_zero() else {
        return None
      }
      binary_coeff_fast_add_parts(
        left.negative(),
        left.coefficient_(),
        left.exponent2_(),
        left.precision_(),
        right.negative() != flip,
        right.coefficient_(),
        right.exponent2_(),
        right.precision_(),
      )
    }
  }
}

///|
/// The sum of two finite non-zero operands given by their parts.
fn binary_coeff_fast_add_parts(
  left_negative : Bool,
  left_coefficient : Coeff,
  left_exponent : Int32,
  left_precision : Int32,
  right_negative : Bool,
  right_coefficient : Coeff,
  right_exponent : Int32,
  right_precision : Int32,
) -> Binary? {
  let precision = Int32::max(left_precision, right_precision)
  guard binary_coeff_fast_scalars_ok(precision, left_exponent, right_exponent) else {
    return None
  }
  let left_bits = left_coefficient.bit_length()
  let right_bits = right_coefficient.bit_length()
  guard left_bits <= binary_coeff_fast_bits_limit &&
    right_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  let left_top = left_exponent + left_bits
  let right_top = right_exponent + right_bits
  let left_is_x = left_top >= right_top
  let x_coefficient = if left_is_x {
    left_coefficient
  } else {
    right_coefficient
  }
  let y_coefficient = if left_is_x {
    right_coefficient
  } else {
    left_coefficient
  }
  let x_exponent = if left_is_x { left_exponent } else { right_exponent }
  let y_exponent = if left_is_x { right_exponent } else { left_exponent }
  let x_negative = if left_is_x { left_negative } else { right_negative }
  let y_negative = if left_is_x { right_negative } else { left_negative }
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
  let borrow = bin_limbs_window_combine(
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
fn binary_coeff_fast_mul(left : Binary, right : Binary) -> Binary? {
  match (left.0, right.0) {
    (
      FinBig(
        negative=left_negative,
        coefficient=left_coefficient,
        exponent2=left_exponent,
        precision=left_precision,
      ),
      FinBig(
        negative=right_negative,
        coefficient=right_coefficient,
        exponent2=right_exponent,
        precision=right_precision,
      ),
    ) =>
      binary_coeff_fast_mul_parts(
        left_negative != right_negative,
        left_coefficient,
        left_exponent,
        left_precision,
        right_coefficient,
        right_exponent,
        right_precision,
      )
    _ => {
      guard left.class() == FpClass::Finite && right.class() == FpClass::Finite else {
        return None
      }
      guard !left.coefficient_is_zero() && !right.coefficient_is_zero() else {
        return None
      }
      binary_coeff_fast_mul_parts(
        left.negative() != right.negative(),
        left.coefficient_(),
        left.exponent2_(),
        left.precision_(),
        right.coefficient_(),
        right.exponent2_(),
        right.precision_(),
      )
    }
  }
}

///|
/// The product of two finite non-zero operands given by their parts.
fn binary_coeff_fast_mul_parts(
  negative : Bool,
  left_coefficient : Coeff,
  left_exponent : Int32,
  left_precision : Int32,
  right_coefficient : Coeff,
  right_exponent : Int32,
  right_precision : Int32,
) -> Binary? {
  let precision = Int32::max(left_precision, right_precision)
  guard binary_coeff_fast_scalars_ok(precision, left_exponent, right_exponent) else {
    return None
  }
  let left_bits = left_coefficient.bit_length()
  let right_bits = right_coefficient.bit_length()
  guard left_bits <= binary_coeff_fast_bits_limit &&
    right_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  let exponent = left_exponent + right_exponent
  // short product: the high limbs only, used when its rounding is certain
  if bin_coeff_mul_short_ok(left_coefficient, right_coefficient, precision) {
    let approximate = bin_words_mul_short(
      left_coefficient, right_coefficient, precision,
    )
    if approximate.length() > 0 {
      // a fresh array (`bin_words_mul_short`), rounded in place
      return Some(
        binary_coeff_fast_finish_array(
          negative,
          approximate,
          bin_coeff_short_product_limbs(precision),
          exponent +
          left_bits +
          right_bits -
          64 * bin_coeff_short_product_limbs(precision),
          precision,
          false,
        ),
      )
    }
  }
  let product = bin_words_mul(left_coefficient, right_coefficient)
  Some(
    binary_coeff_fast_finish_array(
      negative,
      product,
      product.length(),
      exponent,
      precision,
      false,
    ),
  )
}

///|
fn binary_coeff_fast_div(left : Binary, right : Binary) -> Binary? {
  match (left.0, right.0) {
    (
      FinBig(
        negative=left_negative,
        coefficient=dividend,
        exponent2=left_exponent,
        precision=left_precision,
      ),
      FinBig(
        negative=right_negative,
        coefficient=divisor,
        exponent2=right_exponent,
        precision=right_precision,
      ),
    ) =>
      binary_coeff_fast_div_parts(
        left_negative != right_negative,
        dividend,
        left_exponent,
        left_precision,
        divisor,
        right_exponent,
        right_precision,
      )
    _ => {
      guard left.class() == FpClass::Finite && right.class() == FpClass::Finite else {
        return None
      }
      guard !left.coefficient_is_zero() && !right.coefficient_is_zero() else {
        return None
      }
      binary_coeff_fast_div_parts(
        left.negative() != right.negative(),
        left.coefficient_(),
        left.exponent2_(),
        left.precision_(),
        right.coefficient_(),
        right.exponent2_(),
        right.precision_(),
      )
    }
  }
}

///|
/// The quotient of two finite non-zero operands given by their parts.
fn binary_coeff_fast_div_parts(
  negative : Bool,
  dividend : Coeff,
  left_exponent : Int32,
  left_precision : Int32,
  divisor : Coeff,
  right_exponent : Int32,
  right_precision : Int32,
) -> Binary? {
  let precision = Int32::max(left_precision, right_precision)
  guard binary_coeff_fast_scalars_ok(precision, left_exponent, right_exponent) else {
    return None
  }
  let exponent = left_exponent - right_exponent
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
    let approximate = bin_words_div_short_quotient(
      dividend, short_scale, divisor, precision,
    )
    if approximate.length() > 0 {
      return Some(
        binary_coeff_fast_finish_array(
          negative,
          approximate,
          approximate.length(),
          exponent - short_scale,
          precision,
          false,
        ),
      )
    }
  }
  if bin_coeff_div_scaled_ok(dividend, scale, divisor) {
    // the lowest bit of the quotient is the inexact flag
    let packed = bin_words_div_scaled_quotient(dividend, scale, divisor)
    return Some(
      binary_coeff_fast_finish_array(
        negative,
        packed,
        packed.length(),
        exponent - scale - 1,
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
      negative,
      quotient,
      exponent - scale,
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
/// `(root, remainder)` of `magnitude * 2^scale` (`scale >= 0`), the radicand
/// shifted once into the limb array that the root recursion works on.
fn binary_sqrt_rem_scaled(magnitude : Coeff, scale : Int32) -> (Coeff, Coeff) {
  bin_coeff_sqrt_rem_scaled(magnitude, scale)
}

///|
fn binary_coeff_fast_sqrt(value : Binary) -> Binary? {
  let precision = value.precision_()
  guard precision <= binary_coeff_fast_bits_limit &&
    value.class() == FpClass::Finite &&
    !value.negative() &&
    !value.coefficient_is_zero() else {
    return None
  }
  let exponent = value.exponent2_()
  guard exponent <= binary_fast_exponent_limit &&
    exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let bits = value.coefficient_bits()
  guard bits <= binary_coeff_fast_bits_limit else { return None }
  // radicand coefficient * 2^scale with an even exponent and at least
  // 2 * precision - 1 bits, so that the root has at least precision bits
  let mut scale = Int32::max(0, 2 * precision - 1 - bits)
  if (exponent - scale) % 2 != 0 {
    scale += 1
  }
  let packed = bin_words_sqrt_scaled_rounded(
    value.coefficient_(),
    scale,
    precision,
  )
  // a root of exactly `precision` bits comes back rounded, at its own
  // exponent; a longer one carries its round and sticky bits two below it
  let adjust = if binary_coeff_fast_words_bits(packed, packed.length()) <=
    precision + 1 {
    0
  } else {
    -2
  }
  Some(
    binary_coeff_fast_finish_array(
      false,
      packed,
      packed.length(),
      (exponent - scale) / 2 + adjust,
      precision,
      false,
    ),
  )
}
