///|
/// Largest decimal exponent magnitude read before giving up; it keeps the arithmetic below in
/// `Int64` and is far outside every exponent a `BinFloat` can hold.
const BINARY_HEX_EXPONENT_LIMIT : Int64 = 1_000_000_000_000L

///|
/// A parsed hexSequence (§5.12.3) or special sequence (§5.12.1): the value is
/// `magnitude * 2^exponent2`, exactly, with the sign `negative`.
priv enum BinaryHexLiteral {
  Finite(negative~ : Bool, magnitude~ : Coeff, exponent2~ : Int64)
  Infinite(negative~ : Bool)
  QuietNaN(negative~ : Bool)
  SignalingNaN(negative~ : Bool)
}

///|
/// The grammar of `from_hex`: after trimming surrounding whitespace and an
/// optional `+` or `-` sign, `inf`, `infinity`, `nan` and `snan` in any case, and
/// `0x` or `0X`, a hexSignificand (`h.h`, `.h`, `h.` or `h` with one or more hex
/// digits), `p` or `P`, and a decimal exponent with an optional sign and one or
/// more digits. The exponent is read up to `BINARY_HEX_EXPONENT_LIMIT`.
fn binary_parse_hex(
  source : String,
) -> Result[BinaryHexLiteral, @def.ArithmeticError] {
  let trimmed = source.trim().to_owned()
  let negative = trimmed.has_prefix("-")
  let unsigned = if negative || trimmed.has_prefix("+") {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
  match unsigned.to_lower() {
    "inf" | "infinity" => return Ok(Infinite(negative~))
    "nan" => return Ok(QuietNaN(negative~))
    "snan" => return Ok(SignalingNaN(negative~))
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
  guard Coeff::parse(digits.to_string(), radix=16) is Ok(magnitude) else {
    return Err(@def.ArithmeticError::parse_error("invalid binary hex digit"))
  }
  Ok(Finite(negative~, magnitude~, exponent2=scaled))
}

///|
/// IEEE 754-2019 §5.12.3 hexSequence, plus the §5.12.1 sequences for infinities and NaNs.
///
/// Accepted, after trimming surrounding whitespace and an optional `+` or `-` sign:
/// `inf`, `infinity`, `nan` and `snan` in any case, and
/// `0x` or `0X`, a hexSignificand (`h.h`, `.h`, `h.` or `h` with one or more hex digits),
/// `p` or `P`, and a decimal exponent with an optional sign and one or more digits.
/// The value is rounded once to `precision` bits, ties to even, in an unbounded
/// context and without flags (`from_hex_ctx` takes a rounding direction and
/// reports the flags). A binary exponent outside the 32-bit range is a parse
/// error here.
pub fn BinFloat::from_hex(
  source : String,
  precision : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  if precision < 1 || precision > binary_precision_max {
    return Err(binary_precision_error("BinFloat::from_hex", precision))
  }
  binary_parse_hex(source).bind(fn(parsed) {
    match parsed {
      Infinite(negative~) =>
        Ok(
          BinFloat::inf_raw(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision~,
          ),
        )
      QuietNaN(negative~) =>
        Ok(binary_convert_nan(negative, false, Coeff::zero(), precision))
      SignalingNaN(negative~) =>
        Ok(binary_convert_nan(negative, true, Coeff::one(), precision))
      Finite(negative~, magnitude~, exponent2~) => {
        if magnitude.is_zero() {
          return Ok(
            if negative {
              BinFloat::negative_zero_raw(precision~)
            } else {
              BinFloat::zero_raw(precision~)
            },
          )
        }
        guard exponent2 >= -2147483648L && exponent2 <= 2147483647L else {
          return Err(
            @def.ArithmeticError::parse_error("binary exponent out of range"),
          )
        }
        Ok(
          BinFloat::make_coeff(
            magnitude,
            exponent2.to_int(),
            precision,
            negative~,
          ),
        )
      }
    }
  })
}

///|
/// IEEE 754-2019 §5.12.3 convertFromHexCharacter: reads the grammar of
/// `from_hex` and rounds the exact value once under `context`: the result is
/// correctly rounded in the context's rounding direction, and the flags
/// `inexact`, `overflow` and `underflow` are signaled as for every other
/// operation of the context (a bounded context has subnormals and a tininess
/// rule). `+-inf`, `nan` and `snan` give the special values without flags, as
/// `from_string_ctx` does. A binary exponent far outside the 32-bit range is not
/// an error here: the value overflows or underflows like any other.
pub fn BinFloat::from_hex_ctx(
  source : String,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  binary_parse_hex(source).map(fn(parsed) {
    match parsed {
      Infinite(negative~) =>
        (
          BinFloat::inf_raw(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          BinaryFlags::new(),
        )
      QuietNaN(negative~) =>
        (
          BinFloat::quiet_nan(negative~, precision=context.precision),
          BinaryFlags::new(),
        )
      SignalingNaN(negative~) =>
        (
          binary_convert_nan(negative, true, Coeff::one(), context.precision),
          BinaryFlags::new(),
        )
      Finite(negative~, magnitude~, exponent2~) => {
        // The exponent saturates at the 32-bit range: |value| is then at least
        // 2^(2^31 - 1) or at most 2^(-2^31 + bits), far outside every range.
        let clamped = if exponent2 > 2147483647L {
          2147483647
        } else if exponent2 < -2147483648L {
          -2147483648
        } else {
          exponent2.to_int()
        }
        binary_round_dyadic(negative, magnitude, clamped, context)
      }
    }
  })
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
