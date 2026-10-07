///|
/// Exact rationals at most this many bits wide are rounded directly; wider
/// ones cannot be exact or decimal ties, and use directed enclosures.
let decimal_format_exact_bits : Int64 = 1L << 20

///|
fn bin_coeff_pow10(exponent : Int) -> BinCoeff {
  BinCoeff::from_uint64(10UL).pow_nat(exponent.reinterpret_as_uint())
}

///|
/// Decimal exponent of the leading digit, `floor(log10 |value|)`, for a finite
/// nonzero value. Starts from a binary estimate and corrects it exactly or with
/// directed bounds.
fn binary_decimal_exponent(value : BinFloat) -> Int {
  let top = binary_exact_top(value.coefficient_, value.exponent2)
  // log10(2) = 0.30102999566...; the estimate is within one of the answer.
  let estimate = (top.to_double() * 0.30102999566398120).floor().to_int()
  let magnitude = value.abs()
  let ten = BinFloat::from_int(10, precision=64)
  let mut exponent = estimate - 1
  for _ in 0..<4 {
    // Is |value| >= 10^(exponent + 1)? Decide with directed bounds of the power.
    let next = exponent + 1
    let work = 64
    let down = BinaryContext::unbounded(work, rounding=RoundTowardNegative)
    let up = BinaryContext::unbounded(work, rounding=RoundTowardPositive)
    let power_low = ten.pow_int_ctx(next, down).0
    let power_high = ten.pow_int_ctx(next, up).0
    if magnitude.compare(power_low) < 0 {
      return exponent
    }
    if magnitude.compare(power_high) >= 0 {
      exponent = next
      continue
    }
    // |value| lies within one rounding of 10^next: compare exactly. Here
    // |value| is close to 10^next, so both sides stay small.
    let scale = if next >= 0 { next } else { -next }
    let power = bin_coeff_pow10(scale)
    let (left, right) = if next >= 0 {
      if magnitude.exponent2 >= 0 {
        (magnitude.coefficient_.shift_left(magnitude.exponent2), power)
      } else {
        (magnitude.coefficient_, power.shift_left(-magnitude.exponent2))
      }
    } else {
      let scaled = magnitude.coefficient_.mul(power)
      if magnitude.exponent2 >= 0 {
        (scaled.shift_left(magnitude.exponent2), BinCoeff::one())
      } else {
        (scaled, BinCoeff::one().shift_left(-magnitude.exponent2))
      }
    }
    if left.compare(right) < 0 {
      return exponent
    }
    exponent = next
  }
  exponent
}

///|
/// `round(value / 10^scale)` as a signed integer magnitude under `mode`, and
/// whether it is inexact.
fn binary_scaled_decimal_integer(
  value : BinFloat,
  scale : Int,
  mode : BinaryRoundingMode,
  digits : Int,
) -> (BinCoeff, Bool) {
  // value / 10^scale = c * 2^(e - scale) * 5^(-scale).
  let coefficient = value.coefficient_
  let exponent = value.exponent2.to_int64() - scale.to_int64()
  let five_bits = (if scale < 0 { -scale } else { scale }).to_int64() * 7L / 3L
  let width = coefficient.bit_length().to_int64() +
    (if exponent < 0L { -exponent } else { exponent }) +
    five_bits
  if width <= decimal_format_exact_bits {
    let five = BinCoeff::from_uint64(5UL).pow_nat(
      (if scale < 0 { -scale } else { scale }).reinterpret_as_uint(),
    )
    let (numerator, denominator) = if scale >= 0 {
      (coefficient, five)
    } else {
      (coefficient.mul(five), BinCoeff::one())
    }
    let (numerator, denominator) = if exponent >= 0L {
      (numerator.shift_left(exponent.to_int()), denominator)
    } else {
      (numerator, denominator.shift_left((-exponent).to_int()))
    }
    let (quotient, remainder) = numerator.div_rem_checked(denominator).unwrap()
    let half = remainder.shift_left(1).compare(denominator)
    let rounded = binary_apply_round_bits(
      quotient,
      half >= 0,
      !remainder.is_zero() && half != 0,
      value.negative,
      mode,
    )
    return (rounded, !remainder.is_zero())
  }
  // No tie and no exact result at this width: enclose and widen until both
  // ends round to one integer.
  let mut work = digits * 4 + 64
  let ten = BinFloat::from_int(10, precision=work)
  while true {
    let down = BinaryContext::unbounded(work, rounding=RoundTowardNegative)
    let up = BinaryContext::unbounded(work, rounding=RoundTowardPositive)
    let magnitude = value.abs()
    let low_value = magnitude.with_precision(work, RoundingMode::TowardNegative)
    let high_value = magnitude.with_precision(
      work,
      RoundingMode::TowardPositive,
    )
    let (low, high) = if scale >= 0 {
      (
        low_value.div_ctx(ten.pow_int_ctx(scale, up).0, down).0,
        high_value.div_ctx(ten.pow_int_ctx(scale, down).0, up).0,
      )
    } else {
      (
        low_value.mul_ctx(ten.pow_int_ctx(-scale, down).0, down).0,
        high_value.mul_ctx(ten.pow_int_ctx(-scale, up).0, up).0,
      )
    }
    let (signed_low, signed_high) = if value.negative {
      (high.neg(), low.neg())
    } else {
      (low, high)
    }
    let rounded_low = binary_round_to_integral(signed_low, mode).0
    let rounded_high = binary_round_to_integral(signed_high, mode).0
    if rounded_low.compare(rounded_high) == 0 {
      let integral = rounded_low.abs()
      let magnitude = if integral.coefficient_.is_zero() {
        BinCoeff::zero()
      } else {
        integral.coefficient_.shift_left(integral.exponent2)
      }
      return (magnitude, true)
    }
    work = work * 2
  }
  panic()
}

///|
/// Significant decimal digits of a finite nonzero value rounded to `digits`
/// digits: the digit string, the decimal exponent of its first digit, and
/// whether rounding was inexact.
fn binary_decimal_digits(
  value : BinFloat,
  digits : Int,
  mode : BinaryRoundingMode,
) -> (String, Int, Bool) {
  let mut exponent = binary_decimal_exponent(value)
  while true {
    let (integer, inexact) = binary_scaled_decimal_integer(
      value,
      exponent - digits + 1,
      mode,
      digits,
    )
    let text = integer.to_string()
    if text.length() <= digits {
      // Rounding may carry into a new leading digit (9.99 -> 10.0).
      return (text, exponent, inexact)
    }
    exponent += 1
  }
  panic()
}

///|
fn binary_special_string(value : BinFloat) -> String? {
  let sign = if value.negative { "-" } else { "" }
  match value.class {
    FpClass::Infinity => Some(sign + "inf")
    FpClass::NaN =>
      Some(sign + (if value.signaling_nan { "snan" } else { "nan" }))
    FpClass::Finite => None
  }
}

///|
/// IEEE 754 convertToDecimalCharacter with a fixed number of significant
/// digits: `d.ddd...e±x`, correctly rounded in the context's direction, with
/// inexact raised when digits were dropped. `inf`, `nan`, and `snan` keep
/// their sign; zero prints as `0.000...e+0` with its sign. The output parses
/// back with `from_string_ctx`.
pub fn BinFloat::to_decimal_string_ctx(
  self : BinFloat,
  digits : Int,
  context : BinaryContext,
) -> (String, BinaryFlags) {
  match binary_special_string(self) {
    Some(text) => return (text, BinaryFlags::new())
    None => ()
  }
  let digits = Int::max(1, digits)
  let sign = if self.negative { "-" } else { "" }
  let (text, exponent, inexact) = if self.coefficient_.is_zero() {
    ("0".repeat(digits), 0, false)
  } else {
    binary_decimal_digits(self, digits, context.rounding)
  }
  let padded = text + "0".repeat(digits - text.length())
  let mantissa = if digits == 1 {
    padded
  } else {
    padded.view(end_offset=1).to_owned() +
    "." +
    padded.view(start_offset=1).to_owned()
  }
  let exponent_text = (if exponent < 0 { "-" } else { "+" }) +
    exponent.abs().to_string()
  (
    sign + mantissa + "e" + exponent_text,
    if inexact {
      binary_inexact_flags(false)
    } else {
      BinaryFlags::new()
    },
  )
}

///|
/// Whether `text` parses back to exactly `value` under `context`.
fn binary_round_trips(
  text : String,
  value : BinFloat,
  context : BinaryContext,
) -> Bool {
  match BinFloat::from_string_ctx(text, context) {
    Ok((parsed, _)) => parsed.compare(value) == 0
    Err(_) => false
  }
}

///|
/// The fewest significant digits that read back as exactly this value when
/// parsed under `context`. Ties between the two
/// adjacent candidates go to the nearer, then to an even last digit.
fn binary_shortest_digits(
  value : BinFloat,
  context : BinaryContext,
) -> (String, Int) {
  let candidates = fn(digits : Int) -> (String, Int)? {
    let (down, down_exponent, _) = binary_decimal_digits(
      value,
      digits,
      RoundTowardZero,
    )
    let (up, up_exponent, _) = binary_decimal_digits(
      value,
      digits,
      RoundAwayFromZero,
    )
    let render = fn(text : String, exponent : Int) {
      (if value.negative { "-" } else { "" }) +
      text +
      "e" +
      (exponent - text.length() + 1).to_string()
    }
    let down_ok = binary_round_trips(
      render(down, down_exponent),
      value,
      context,
    )
    let up_ok = binary_round_trips(render(up, up_exponent), value, context)
    match (down_ok, up_ok) {
      (false, false) => None
      (true, false) => Some((down, down_exponent))
      (false, true) => Some((up, up_exponent))
      (true, true) => {
        // Both read back: take the nearer (round-to-nearest), ties to even.
        let (nearest, nearest_exponent, _) = binary_decimal_digits(
          value,
          digits,
          RoundTiesToEven,
        )
        Some((nearest, nearest_exponent))
      }
    }
  }
  // p bits always round-trip within ceil(p log10 2) + 1 digits, and
  // round-tripping is monotone in the digit count, so bisect.
  let mut low = 1
  let mut high = (context.precision.to_double() * 0.30102999566398120)
    .ceil()
    .to_int() +
    2
  let mut best = candidates(high).unwrap()
  while low < high {
    let middle = (low + high) / 2
    match candidates(middle) {
      Some(found) => {
        best = found
        high = middle
      }
      None => low = middle + 1
    }
  }
  match candidates(low) {
    Some(found) => best = found
    None => ()
  }
  // Drop trailing zeros produced by a shorter exact digit string.
  let (text, exponent) = best
  let mut end = text.length()
  while end > 1 && text.unsafe_get(end - 1) == '0' {
    end -= 1
  }
  (text.view(end_offset=end).to_owned(), exponent)
}

///|
/// Shortest round-trip decimal form under `context`, formatted like
/// ECMAScript `Number#toString`: positional notation for decimal exponents in
/// `[-6, 21)`, otherwise `d.ddde±x`. Parsing the result with
/// `from_string_ctx(text, context)` under round-to-nearest-even returns this
/// value, and unlike ECMAScript, negative zero prints as `-0` so its sign
/// round-trips. The operand should be representable in the context, as doubles are
/// in `BinaryContext::binary64()` (which prints 5e-324 for the smallest
/// subnormal).
pub fn BinFloat::to_shortest_string_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> String {
  let context = { ..context, rounding: RoundTiesToEven, }
  match binary_special_string(self) {
    Some(text) => return text
    None => ()
  }
  let sign = if self.negative { "-" } else { "" }
  if self.coefficient_.is_zero() {
    return sign + "0"
  }
  let (digits, exponent) = binary_shortest_digits(self, context)
  let count = digits.length()
  let body = if exponent >= -6 && exponent < 21 {
    if exponent >= count - 1 {
      digits + "0".repeat(exponent - count + 1)
    } else if exponent >= 0 {
      digits.view(end_offset=exponent + 1).to_owned() +
      "." +
      digits.view(start_offset=exponent + 1).to_owned()
    } else {
      "0." + "0".repeat(-exponent - 1) + digits
    }
  } else {
    let mantissa = if count == 1 {
      digits
    } else {
      digits.view(end_offset=1).to_owned() +
      "." +
      digits.view(start_offset=1).to_owned()
    }
    mantissa +
    "e" +
    (if exponent < 0 { "-" } else { "+" }) +
    exponent.abs().to_string()
  }
  sign + body
}

///|
/// Shortest round-trip form at the value's own precision with an unbounded
/// exponent range: `from_string(text, precision=self.precision())` returns
/// this value. See `to_shortest_string_ctx` for IEEE formats with subnormals.
pub fn BinFloat::to_shortest_string(self : BinFloat) -> String {
  self.to_shortest_string_ctx(BinaryContext::unbounded(self.precision_))
}
