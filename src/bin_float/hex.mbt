///|
/// Largest decimal exponent magnitude read before giving up; it keeps the arithmetic below in
/// `Int64` and is far outside every exponent a `BinFloat` can hold.
const BINARY_HEX_EXPONENT_LIMIT : Int64 = 1_000_000_000_000L

///|
/// IEEE 754-2019 §5.12.3 hexSequence, plus the §5.12.1 sequences for infinities and NaNs.
///
/// Accepted, after trimming surrounding whitespace and an optional `+` or `-` sign:
/// `inf`, `infinity`, `nan` and `snan` in any case, and
/// `0x` or `0X`, a hexSignificand (`h.h`, `.h`, `h.` or `h` with one or more hex digits),
/// `p` or `P`, and a decimal exponent with an optional sign and one or more digits.
/// The value is rounded once to `precision` bits, ties to even.
pub fn BinFloat::from_hex(
  source : String,
  precision : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  let trimmed = source.trim().to_owned()
  let negative = trimmed.has_prefix("-")
  let unsigned = if negative || trimmed.has_prefix("+") {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
  match unsigned.to_lower() {
    "inf" | "infinity" =>
      return Ok(
        BinFloat::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision~,
        ),
      )
    "nan" => return Ok(BinFloat::quiet_nan(negative~, precision~))
    "snan" => return Ok(BinFloat::signaling_nan(negative~, precision~))
    _ => ()
  }
  let chars : Array[Char] = unsigned.iter().collect()
  guard chars.length() >= 2 &&
    chars[0] == '0' &&
    (chars[1] == 'x' || chars[1] == 'X') else {
    return Err(@def.ArithmeticError::parse_error("binary hex literal needs 0x"))
  }
  let digits = StringBuilder()
  let mut index = 2
  let mut digit_count = 0
  let mut fraction_digits = 0
  let mut seen_point = false
  while index < chars.length() && chars[index] != 'p' && chars[index] != 'P' {
    let character = chars[index]
    if character == '.' {
      guard !seen_point else {
        return Err(
          @def.ArithmeticError::parse_error("binary hex literal has two points"),
        )
      }
      seen_point = true
    } else {
      guard character.is_ascii_hexdigit() else {
        return Err(
          @def.ArithmeticError::parse_error("invalid binary hex digit"),
        )
      }
      digits.write_char(character)
      digit_count = digit_count + 1
      if seen_point {
        fraction_digits = fraction_digits + 1
      }
    }
    index = index + 1
  }
  guard digit_count > 0 else {
    return Err(
      @def.ArithmeticError::parse_error("binary hex literal needs a hex digit"),
    )
  }
  guard index < chars.length() else {
    return Err(
      @def.ArithmeticError::parse_error("binary hex literal needs p exponent"),
    )
  }
  index = index + 1
  let mut exponent_negative = false
  if index < chars.length() && (chars[index] == '+' || chars[index] == '-') {
    exponent_negative = chars[index] == '-'
    index = index + 1
  }
  guard index < chars.length() else {
    return Err(@def.ArithmeticError::parse_error("invalid binary exponent"))
  }
  let mut exponent = 0L
  while index < chars.length() {
    let character = chars[index]
    guard character >= '0' && character <= '9' else {
      return Err(@def.ArithmeticError::parse_error("invalid binary exponent"))
    }
    exponent = exponent * 10L + (character.to_int() - '0'.to_int()).to_int64()
    guard exponent <= BINARY_HEX_EXPONENT_LIMIT else {
      return Err(
        @def.ArithmeticError::parse_error("binary exponent out of range"),
      )
    }
    index = index + 1
  }
  let scaled = (if exponent_negative { -exponent } else { exponent }) -
    4L * fraction_digits.to_int64()
  guard BinCoeff::parse(digits.to_string(), radix=16) is Ok(magnitude) else {
    return Err(@def.ArithmeticError::parse_error("invalid binary hex digit"))
  }
  if magnitude.is_zero() {
    return Ok(
      if negative {
        BinFloat::negative_zero(precision~)
      } else {
        BinFloat::zero(precision~)
      },
    )
  }
  guard scaled >= -2147483648L && scaled <= 2147483647L else {
    return Err(
      @def.ArithmeticError::parse_error("binary exponent out of range"),
    )
  }
  Ok(BinFloat::make(magnitude, scaled.to_int(), precision, negative~))
}

///|
pub fn BinFloat::to_hex(self : BinFloat) -> String {
  match self.class {
    FpClass::NaN => if self.negative { "-nan" } else { "nan" }
    FpClass::Infinity => if self.negative { "-inf" } else { "inf" }
    FpClass::Finite if self.is_zero() =>
      if self.negative {
        "-0x0p0"
      } else {
        "0x0p0"
      }
    FpClass::Finite =>
      (if self.negative { "-" } else { "" }) +
      "0x" +
      self.coefficient_.to_radix_string(16) +
      "p" +
      self.exponent2.to_string()
  }
}
