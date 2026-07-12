///|
pub struct BinaryInterchange {
  priv format : BinaryInterchangeFormat
  priv bits : BinCoeff
} derive(Eq)

///|
pub fn BinaryInterchangeFormat::total_bits(
  self : BinaryInterchangeFormat,
) -> Int {
  match self {
    Binary16 => 16
    Binary32 => 32
    Binary64 => 64
    Binary128 => 128
  }
}

///|
pub fn BinaryInterchangeFormat::exponent_bits(
  self : BinaryInterchangeFormat,
) -> Int {
  match self {
    Binary16 => 5
    Binary32 => 8
    Binary64 => 11
    Binary128 => 15
  }
}

///|
pub fn BinaryInterchangeFormat::fraction_bits(
  self : BinaryInterchangeFormat,
) -> Int {
  self.precision() - 1
}

///|
pub fn BinaryInterchangeFormat::bias(self : BinaryInterchangeFormat) -> Int {
  self.e_max()
}

///|
fn binary_interchange_mask(format : BinaryInterchangeFormat) -> BinCoeff {
  BinCoeff::one()
  .shift_left(format.total_bits())
  .sub_checked(BinCoeff::one())
  .unwrap()
}

///|
fn binary_fraction_mask(format : BinaryInterchangeFormat) -> BinCoeff {
  BinCoeff::one()
  .shift_left(format.fraction_bits())
  .sub_checked(BinCoeff::one())
  .unwrap()
}

///|
fn binary_exponent_mask(format : BinaryInterchangeFormat) -> BinCoeff {
  BinCoeff::one()
  .shift_left(format.exponent_bits())
  .sub_checked(BinCoeff::one())
  .unwrap()
}

///|
fn binary_sign_mask(format : BinaryInterchangeFormat) -> BinCoeff {
  BinCoeff::one().shift_left(format.total_bits() - 1)
}

///|
fn binary_uppercase_ascii(source : String) -> String {
  let builder = StringBuilder::new()
  for character in source {
    if character >= 'a' && character <= 'f' {
      builder.write_char(
        Int::unsafe_to_char(character.to_int() + ('A'.to_int() - 'a'.to_int())),
      )
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn binary_zero_digits(count : Int) -> String {
  let builder = StringBuilder::new()
  for _ in 0..<count {
    builder.write_char('0')
  }
  builder.to_string()
}

///|
fn binary_normalize_hex(source : String, digits : Int) -> BinCoeff? {
  let trimmed = source.trim()
  let body = if trimmed.has_prefix("#") {
    trimmed[1:].to_owned()
  } else if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    trimmed[2:].to_owned()
  } else {
    trimmed.to_owned()
  }
  guard body.length() == digits else { return None }
  for character in body {
    guard character.is_ascii_hexdigit() else { return None }
  }
  match BinCoeff::parse(body, radix=16) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn binary_interchange_hex(
  bits : BinCoeff,
  format : BinaryInterchangeFormat,
) -> String {
  let digits = format.total_bits() / 4
  let body = binary_uppercase_ascii(bits.to_string(radix=16))
  if body.length() < digits {
    binary_zero_digits(digits - body.length()) + body
  } else {
    body
  }
}

///|
pub fn BinaryInterchange::from_hex(
  source : String,
  format : BinaryInterchangeFormat,
) -> BinaryInterchange? {
  match binary_normalize_hex(source, format.total_bits() / 4) {
    Some(bits) =>
      Some({ format, bits: bits.bit_and(binary_interchange_mask(format)) })
    None => None
  }
}

///|
pub fn BinaryInterchange::format(
  self : BinaryInterchange,
) -> BinaryInterchangeFormat {
  self.format
}

///|
pub fn BinaryInterchange::bits(self : BinaryInterchange) -> BinCoeff {
  self.bits
}

///|
pub fn BinaryInterchange::from_bits(
  bits : BinCoeff,
  format : BinaryInterchangeFormat,
) -> BinaryInterchange {
  { format, bits: bits.bit_and(binary_interchange_mask(format)) }
}

///|
pub fn BinaryInterchange::to_hex(self : BinaryInterchange) -> String {
  binary_interchange_hex(self.bits, self.format)
}

///|
pub fn BinaryInterchange::to_bin_float(self : BinaryInterchange) -> BinFloat {
  let format = self.format
  let fraction_bits = format.fraction_bits()
  let exponent_field = self.bits
    .shift_right(fraction_bits)
    .bit_and(binary_exponent_mask(format))
    .to_uint64()
    .unwrap()
    .to_int()
  let fraction = self.bits.bit_and(binary_fraction_mask(format))
  let negative = !self.bits.bit_and(binary_sign_mask(format)).is_zero()
  let max_exponent_field = (1 << format.exponent_bits()) - 1
  if exponent_field == max_exponent_field {
    if fraction.is_zero() {
      return BinFloat::inf(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=format.precision(),
      )
    }
    let quiet_bit = BinCoeff::one().shift_left(fraction_bits - 1)
    let payload = fraction.bit_and(
      quiet_bit.sub_checked(BinCoeff::one()).unwrap(),
    )
    return if fraction.bit_and(quiet_bit).is_zero() {
      BinFloat::signaling_nan(
        payload=if payload.is_zero() { BinCoeff::one() } else { payload },
        negative~,
        precision=format.precision(),
      )
    } else {
      BinFloat::quiet_nan(payload~, negative~, precision=format.precision())
    }
  }
  if exponent_field == 0 {
    if fraction.is_zero() {
      return if negative {
        BinFloat::negative_zero(precision=format.precision())
      } else {
        BinFloat::zero(precision=format.precision())
      }
    }
    return finite_from_parts(
      negative,
      fraction,
      format.e_min() - fraction_bits,
      format.precision(),
    )
  }
  finite_from_parts(
    negative,
    BinCoeff::one().shift_left(fraction_bits).add(fraction),
    exponent_field - format.bias() - fraction_bits,
    format.precision(),
  )
}

///|
fn binary_encode_rounded(
  value : BinFloat,
  format : BinaryInterchangeFormat,
) -> BinCoeff {
  let sign = if value.negative {
    binary_sign_mask(format)
  } else {
    BinCoeff::zero()
  }
  match value.class {
    FpClass::Infinity =>
      sign.bit_or(
        binary_exponent_mask(format).shift_left(format.fraction_bits()),
      )
    FpClass::NaN => {
      let quiet_bit = BinCoeff::one().shift_left(format.fraction_bits() - 1)
      let payload_mask = quiet_bit.sub_checked(BinCoeff::one()).unwrap()
      let payload = value.nan_payload.bit_and(payload_mask)
      sign
      .bit_or(binary_exponent_mask(format).shift_left(format.fraction_bits()))
      .bit_or(quiet_bit)
      .bit_or(payload)
    }
    FpClass::Finite if value.is_zero() => sign
    FpClass::Finite => {
      let magnitude = value.coefficient_
      let top = binary_exact_top(magnitude, value.exponent2)
      if top < format.e_min() {
        let quantum = format.e_min() - format.fraction_bits()
        sign.bit_or(magnitude.shift_left(value.exponent2 - quantum))
      } else {
        let coefficient = magnitude.shift_left(
          format.precision() - magnitude.bit_length(),
        )
        let exponent_field = BinCoeff::from_uint64(
          (top + format.bias()).to_uint64(),
        )
        let fraction = coefficient
          .sub_checked(BinCoeff::one().shift_left(format.fraction_bits()))
          .unwrap()
        sign
        .bit_or(exponent_field.shift_left(format.fraction_bits()))
        .bit_or(fraction)
      }
    }
  }
}

///|
pub fn BinaryInterchange::from_bin_float(
  value : BinFloat,
  format : BinaryInterchangeFormat,
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> (BinaryInterchange, BinaryFlags) {
  let (rounded, flags) = value.round_ctx(format.context(rounding~, tininess~))
  ({ format, bits: binary_encode_rounded(rounded, format) }, flags)
}

///|
pub fn BinFloat::to_interchange(
  self : BinFloat,
  format : BinaryInterchangeFormat,
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> (BinaryInterchange, BinaryFlags) {
  BinaryInterchange::from_bin_float(self, format, rounding~, tininess~)
}
