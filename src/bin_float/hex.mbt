///|
fn binary_hex_exponent(source : String) -> Int? {
  try @string.parse_int(source) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
pub fn BinFloat::from_hex(
  source : String,
  precision : Int,
) -> Result[BinFloat, @def.ArithmeticError] {
  let trimmed = source.trim().to_owned()
  let lower = trimmed.to_lower()
  if lower == "nan" || lower == "+nan" || lower == "-nan" {
    return Ok(BinFloat::quiet_nan(negative=lower.has_prefix("-"), precision~))
  }
  if lower == "inf" ||
    lower == "+inf" ||
    lower == "-inf" ||
    lower == "infinity" ||
    lower == "+infinity" ||
    lower == "-infinity" {
    return Ok(
      BinFloat::inf(
        if lower.has_prefix("-") {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      ),
    )
  }
  let negative = trimmed.has_prefix("-")
  let unsigned = if negative || trimmed.has_prefix("+") {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
  guard unsigned.has_prefix("0x") || unsigned.has_prefix("0X") else {
    return Err(@def.ArithmeticError::parse_error("binary hex literal needs 0x"))
  }
  let mut separator = -1
  for index in 2..<unsigned.length() {
    if unsigned[index] == 'p' || unsigned[index] == 'P' {
      separator = index
      break
    }
  }
  guard separator > 2 && separator + 1 < unsigned.length() else {
    return Err(
      @def.ArithmeticError::parse_error("binary hex literal needs p exponent"),
    )
  }
  let digits = unsigned[2:separator].to_owned()
  for character in digits {
    guard character.is_ascii_hexdigit() else {
      return Err(@def.ArithmeticError::parse_error("invalid binary hex digit"))
    }
  }
  guard binary_hex_exponent(unsigned[separator + 1:].to_owned())
    is Some(exponent) else {
    return Err(@def.ArithmeticError::parse_error("invalid binary exponent"))
  }
  guard BinCoeff::parse(digits, radix=16) is Ok(magnitude) else {
    return Err(@def.ArithmeticError::parse_error("invalid binary hex digit"))
  }
  if magnitude.is_zero() {
    Ok(
      if negative {
        BinFloat::negative_zero(precision~)
      } else {
        BinFloat::zero(precision~)
      },
    )
  } else {
    Ok(BinFloat::make(magnitude, exponent, precision, negative~))
  }
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
      self.coefficient_.to_string(radix=16) +
      "p" +
      self.exponent2.to_string()
  }
}
