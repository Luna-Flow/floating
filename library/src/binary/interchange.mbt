///|
/// An encoded value: a `BinaryInterchangeFormat` and its bit pattern (IEEE 754-2019
/// 3.4). `==` compares the format and the bits, so two NaNs with different payloads
/// differ, and `+0` differs from `-0`. Build one with `from_bits`, `from_hex` or
/// `Binary::to_interchange`; decode it exactly with `to_binary`.
#derive(Eq)
pub struct BinaryInterchange {
  priv format : BinaryInterchangeFormat
  priv bits : Coeff
}

///|
pub fn BinaryInterchangeFormat::storage_width(
  self : BinaryInterchangeFormat,
) -> Int32 {
  match self {
    Binary16 => 16
    Binary32 => 32
    Binary64 => 64
    Binary128 => 128
  }
}

///|
pub fn BinaryInterchangeFormat::exponent_field_width(
  self : BinaryInterchangeFormat,
) -> Int32 {
  match self {
    Binary16 => 5
    Binary32 => 8
    Binary64 => 11
    Binary128 => 15
  }
}

///|
pub fn BinaryInterchangeFormat::trailing_significand_field_width(
  self : BinaryInterchangeFormat,
) -> Int32 {
  self.precision() - 1
}

///|
pub fn BinaryInterchangeFormat::bias(self : BinaryInterchangeFormat) -> Int32 {
  self.e_max()
}

///|
fn binary_interchange_mask(format : BinaryInterchangeFormat) -> Coeff {
  Coeff::one()
  .shift_left(format.storage_width())
  .sub_checked(Coeff::one())
  .unwrap()
}

///|
fn binary_fraction_mask(format : BinaryInterchangeFormat) -> Coeff {
  Coeff::one()
  .shift_left(format.trailing_significand_field_width())
  .sub_checked(Coeff::one())
  .unwrap()
}

///|
fn binary_exponent_mask(format : BinaryInterchangeFormat) -> Coeff {
  Coeff::one()
  .shift_left(format.exponent_field_width())
  .sub_checked(Coeff::one())
  .unwrap()
}

///|
fn binary_sign_mask(format : BinaryInterchangeFormat) -> Coeff {
  Coeff::one().shift_left(format.storage_width() - 1)
}

///|
fn binary_uppercase_ascii(source : String) -> String {
  let builder = StringBuilder()
  for character in source {
    if character >= 'a' && character <= 'f' {
      builder.write_char(
        Int32::unsafe_to_char(
          character.to_int() + ('A'.to_int() - 'a'.to_int()),
        ),
      )
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn binary_zero_digits(count : Int32) -> String {
  let builder = StringBuilder()
  for _ in 0..<count {
    builder.write_char('0')
  }
  builder.to_string()
}

///|
fn binary_normalize_hex(source : String, digits : Int32) -> Coeff? {
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
  match Coeff::parse(body, radix=16) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn binary_interchange_hex(
  bits : Coeff,
  format : BinaryInterchangeFormat,
) -> String {
  let digits = format.storage_width() / 4
  let body = binary_uppercase_ascii(bits.to_radix_string(16))
  if body.length() < digits {
    binary_zero_digits(digits - body.length()) + body
  } else {
    body
  }
}

///|
/// Parses the bit pattern of `format` from hexadecimal text. Surrounding
/// whitespace is ignored; the text is `storage_width / 4` hexadecimal digits (either
/// case), optionally prefixed with `0x`, `0X` or `#`. Returns `None` for text of
/// another length or with another character.
pub fn BinaryInterchange::from_hex(
  source : String,
  format : BinaryInterchangeFormat,
) -> BinaryInterchange? {
  match binary_normalize_hex(source, format.storage_width() / 4) {
    Some(bits) =>
      Some({ format, bits: bits.bit_and(binary_interchange_mask(format)), })
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
  BinCoeff(self.bits)
}

///|
pub fn BinaryInterchange::from_bits(
  bits : BinCoeff,
  format : BinaryInterchangeFormat,
) -> BinaryInterchange {
  { format, bits: bits.0.bit_and(binary_interchange_mask(format)), }
}

///|
/// Prints the bit pattern as upper-case hexadecimal digits, padded to
/// `storage_width / 4` digits.
pub fn BinaryInterchange::to_hex(self : BinaryInterchange) -> String {
  binary_interchange_hex(self.bits, self.format)
}

///|
/// Decodes the encoding exactly into a `Binary` with the precision of the format.
/// Zeros, infinities and finite numbers decode to themselves; a NaN keeps its sign,
/// payload and quiet or signaling kind.
pub fn BinaryInterchange::to_binary(self : BinaryInterchange) -> Binary {
  let format = self.format
  let fraction_bits = format.trailing_significand_field_width()
  let exponent_field = self.bits
    .shift_right(fraction_bits)
    .bit_and(binary_exponent_mask(format))
    .to_uint64()
    .unwrap()
    .to_int()
  let fraction = self.bits.bit_and(binary_fraction_mask(format))
  let negative = !self.bits.bit_and(binary_sign_mask(format)).is_zero()
  let max_exponent_field = (1 << format.exponent_field_width()) - 1
  if exponent_field == max_exponent_field {
    if fraction.is_zero() {
      return Binary::inf_raw(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=format.precision(),
      )
    }
    let quiet_bit = Coeff::one().shift_left(fraction_bits - 1)
    let payload = fraction.bit_and(quiet_bit.sub_checked(Coeff::one()).unwrap())
    return if fraction.bit_and(quiet_bit).is_zero() {
      Binary::signaling_nan(
        payload=if payload.is_zero() { Coeff::one() } else { payload },
        negative~,
        precision=format.precision(),
      )
    } else {
      Binary::quiet_nan(payload~, negative~, precision=format.precision())
    }
  }
  if exponent_field == 0 {
    if fraction.is_zero() {
      return if negative {
        Binary::negative_zero_raw(precision=format.precision())
      } else {
        Binary::zero_raw(precision=format.precision())
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
    Coeff::one().shift_left(fraction_bits).add(fraction),
    exponent_field - format.bias() - fraction_bits,
    format.precision(),
  )
}

///|
fn binary_encode_rounded(
  value : Binary,
  format : BinaryInterchangeFormat,
) -> Coeff {
  let sign = if value.negative() {
    binary_sign_mask(format)
  } else {
    Coeff::zero()
  }
  match value.class() {
    FpClass::Infinity =>
      sign.bit_or(
        binary_exponent_mask(format).shift_left(
          format.trailing_significand_field_width(),
        ),
      )
    FpClass::NaN => {
      let quiet_bit = Coeff::one().shift_left(
        format.trailing_significand_field_width() - 1,
      )
      let payload_mask = quiet_bit.sub_checked(Coeff::one()).unwrap()
      let payload = value.payload_().bit_and(payload_mask)
      sign
      .bit_or(
        binary_exponent_mask(format).shift_left(
          format.trailing_significand_field_width(),
        ),
      )
      .bit_or(quiet_bit)
      .bit_or(payload)
    }
    FpClass::Finite if value.is_zero() => sign
    FpClass::Finite => {
      let magnitude = value.coefficient_()
      let top = binary_exact_top(magnitude, value.exponent2_())
      if top < format.e_min() {
        let quantum = format.e_min() - format.trailing_significand_field_width()
        sign.bit_or(magnitude.shift_left(value.exponent2_() - quantum))
      } else {
        let coefficient = magnitude.shift_left(
          format.precision() - magnitude.bit_length(),
        )
        let exponent_field = Coeff::from_uint64(
          (top + format.bias()).to_uint64(),
        )
        let fraction = coefficient
          .sub_checked(
            Coeff::one().shift_left(format.trailing_significand_field_width()),
          )
          .unwrap()
        sign
        .bit_or(
          exponent_field.shift_left(format.trailing_significand_field_width()),
        )
        .bit_or(fraction)
      }
    }
  }
}

///|
pub fn BinaryInterchange::from_binary(
  value : Binary,
  format : BinaryInterchangeFormat,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> (BinaryInterchange, BinaryFlags) {
  let (rounded, flags) = value.apply_ctx(format.context(rounding~, tininess~))
  ({ format, bits: binary_encode_rounded(rounded, format), }, flags)
}

///|
/// Rounds `self` into `format` (under `rounding` and `tininess`, nearest-even and
/// after-rounding by default) and encodes it. Returns the encoding and the flags of
/// the rounding. A signaling NaN is encoded as a quiet NaN with
/// `invalid_operation`; a NaN payload is cut to the payload field of the format.
///
/// ```mbt check
/// test {
///   let tenth = @binary.Binary::from_string("0.1", precision=200).unwrap()
///   let (bits, flags) = tenth.to_interchange(
///     @binary.BinaryInterchangeFormat::Binary32,
///   )
///   inspect(bits.to_hex(), content="3DCCCCCD")
///   inspect(flags.inexact(), content="true")
/// }
/// ```
pub fn Binary::to_interchange(
  self : Binary,
  format : BinaryInterchangeFormat,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> (BinaryInterchange, BinaryFlags) {
  BinaryInterchange::from_binary(self, format, rounding~, tininess~)
}

///|
/// IEEE 754-2019 5.4.2 formatOf-convertFormat: the value rounded to `format`
/// under `rounding` and `tininess`, with its flags, as a `Binary` (the
/// parameters of `to_interchange`, which returns the encoding instead).
///
/// A conversion to a wider precision and range is exact; to a narrower one the
/// result is rounded as specified in Clause 4 (`inexact`, `underflow`,
/// `overflow`). A signaling NaN gives a quiet NaN and `invalid` (also when the
/// formats are identical: the canonicalizing conversion of 5.4.2). The payload
/// of a NaN is kept as far as the destination holds it and otherwise truncated
/// to its low bits (6.2.3: a quiet NaN converted to a wider format and back
/// keeps its payload; a payload that does not fit gives "a quiet NaN that
/// should provide some language-defined diagnostic information"): the result is
/// the value that decoding `to_interchange(format)` returns.
pub fn Binary::convert_format(
  self : Binary,
  format : BinaryInterchangeFormat,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> (Binary, BinaryFlags) {
  let (value, flags) = self.apply_ctx(format.context(rounding~, tininess~))
  if value.class() == FpClass::NaN {
    // The payload field of the format has precision - 2 bits below the quiet bit.
    let payload_mask = Coeff::one()
      .shift_left(format.trailing_significand_field_width() - 1)
      .sub_checked(Coeff::one())
      .unwrap()
    return (
      Binary::quiet_nan(
        payload=value.payload_().bit_and(payload_mask),
        negative=value.negative(),
        precision=format.precision(),
      ),
      flags,
    )
  }
  (value, flags)
}

///|
pub extend BinaryInterchange with Eq::{not_equal, equal}
