///|
// Decimal string parsing and formatting APIs.

fn zeros(n : Int) -> String {
  let b = StringBuilder::new()
  for _ in 0..<n {
    b.write_char('0')
  }
  b.to_string()
}

///|
fn write_zeros(builder : StringBuilder, count : Int) -> Unit {
  for _ in 0..<count {
    builder.write_char('0')
  }
}

///|
fn write_chars_range(
  builder : StringBuilder,
  src : String,
  start : Int,
  end : Int,
) -> Unit {
  for index in start..<end {
    builder.write_char(Int::unsafe_to_char(src[index].to_int()))
  }
}

///|
fn write_signed_exponent10(builder : StringBuilder, exponent : Int) -> Unit {
  builder.write_char('E')
  if exponent >= 0 {
    builder.write_char('+')
  }
  builder.write_string(exponent.to_string())
}

///|
fn format_special_gda(value : Decimal) -> String {
  match value.class {
    FpClass::Infinity => if value.negative { "-Infinity" } else { "Infinity" }
    FpClass::NaN => {
      let prefix = if value.negative { "-" } else { "" }
      let kind = if value.signaling_nan { "sNaN" } else { "NaN" }
      if value.coefficient.is_zero() {
        prefix + kind
      } else {
        prefix + kind + value.coefficient.to_string()
      }
    }
    FpClass::Finite => abort("format_special_gda expects a special value")
  }
}

///|
fn format_plain_finite(value : Decimal) -> String {
  let builder = StringBuilder::new()
  if value.negative {
    builder.write_char('-')
  }
  if value.coefficient.is_zero() {
    if value.exponent10 < 0 {
      builder.write_string("0.")
      write_zeros(builder, -value.exponent10)
    } else {
      builder.write_char('0')
      write_zeros(builder, value.exponent10)
    }
    return builder.to_string()
  }
  let digits = value.coefficient.to_string()
  if value.exponent10 >= 0 {
    builder.write_string(digits)
    write_zeros(builder, value.exponent10)
  } else {
    let split = digits.length() + value.exponent10
    if split > 0 {
      write_chars_range(builder, digits, 0, split)
      builder.write_char('.')
      write_chars_range(builder, digits, split, digits.length())
    } else {
      builder.write_string("0.")
      write_zeros(builder, -split)
      builder.write_string(digits)
    }
  }
  builder.to_string()
}

///|
fn format_sci_finite(value : Decimal) -> String {
  if value.coefficient.is_zero() {
    if value.exponent10 <= 0 && value.exponent10 >= -6 {
      return format_plain_finite(value)
    }
    let builder = StringBuilder::new()
    if value.negative {
      builder.write_char('-')
    }
    builder.write_char('0')
    write_signed_exponent10(builder, value.exponent10)
    return builder.to_string()
  }
  let adjusted = adjusted_exponent(value)
  if value.exponent10 <= 0 && adjusted >= -6 {
    return format_plain_finite(value)
  }
  let digits = value.coefficient.to_string()
  let builder = StringBuilder::new()
  if value.negative {
    builder.write_char('-')
  }
  builder.write_char(Int::unsafe_to_char(digits[0].to_int()))
  if digits.length() > 1 {
    builder.write_char('.')
    write_chars_range(builder, digits, 1, digits.length())
  }
  write_signed_exponent10(builder, adjusted)
  builder.to_string()
}

///|
fn floor_multiple3(n : Int) -> Int {
  if n >= 0 {
    n - n % 3
  } else {
    n - (n % 3 + 3) % 3
  }
}

///|
fn ceil_multiple3(n : Int) -> Int {
  let floor = floor_multiple3(n)
  if floor == n {
    floor
  } else {
    floor + 3
  }
}

///|
fn format_eng_finite(value : Decimal) -> String {
  if value.coefficient.is_zero() {
    if value.exponent10 <= 0 && value.exponent10 >= -6 {
      return format_plain_finite(value)
    }
    let eng_exp = ceil_multiple3(value.exponent10)
    let zero_count = eng_exp - value.exponent10
    let builder = StringBuilder::new()
    if value.negative {
      builder.write_char('-')
    }
    builder.write_char('0')
    if zero_count > 0 {
      builder.write_char('.')
      write_zeros(builder, zero_count)
    }
    write_signed_exponent10(builder, eng_exp)
    builder.to_string()
  } else {
    let adjusted = adjusted_exponent(value)
    let eng_exp = floor_multiple3(adjusted)
    if adjusted >= -6 && (value.exponent10 <= 0 || eng_exp == 0) {
      return format_plain_finite(value)
    }
    let int_digits = adjusted - eng_exp + 1
    let digits = value.coefficient.to_string()
    let builder = StringBuilder::new()
    if value.negative {
      builder.write_char('-')
    }
    if int_digits >= digits.length() {
      builder.write_string(digits)
      write_zeros(builder, int_digits - digits.length())
    } else if int_digits <= 0 {
      builder.write_string("0.")
      write_zeros(builder, -int_digits)
      builder.write_string(digits)
    } else {
      write_chars_range(builder, digits, 0, int_digits)
      builder.write_char('.')
      write_chars_range(builder, digits, int_digits, digits.length())
    }
    write_signed_exponent10(builder, eng_exp)
    builder.to_string()
  }
}

///|
fn format_sci_gda(value : Decimal) -> String {
  match value.class {
    FpClass::Finite => format_sci_finite(value)
    _ => format_special_gda(value)
  }
}

///|
fn format_eng_gda(value : Decimal) -> String {
  match value.class {
    FpClass::Finite => format_eng_finite(value)
    _ => format_special_gda(value)
  }
}

///|
fn ascii_lower(src : String) -> String {
  let b = StringBuilder::new()
  for i in 0..<src.length() {
    let ch = src[i]
    if ch >= 'A' && ch <= 'Z' {
      b.write_char(
        Int::unsafe_to_char(ch.to_int() + ('a'.to_int() - 'A'.to_int())),
      )
    } else {
      b.write_char(Int::unsafe_to_char(ch.to_int()))
    }
  }
  b.to_string()
}

///|
fn strip_leading_zero_digits(src : String) -> String {
  let mut i = 0
  while i < src.length() && src[i] == '0' {
    i += 1
  }
  if i >= src.length() {
    ""
  } else {
    src[i:].to_owned()
  }
}

///|
fn decimal_conversion_syntax_result(
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  (
    make_special_repr(FpClass::NaN, false, gda_coeff_zero(), precision, false),
    { ..DecimalFlags::new(), conversion_syntax: true },
  )
}

///|
fn overflow_to_infinity(negative : Bool, mode : DecimalRoundingMode) -> Bool {
  match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    ZeroFiveUp => false
    Up | HalfEven | HalfUp | HalfDown => true
  }
}

///|
fn decimal_overflow_result(
  negative : Bool,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_from_int(1), ctx)
  let flags = {
    ..DecimalFlags::new(),
    overflow: true,
    rounded: true,
    inexact: true,
  }
  if overflow_to_infinity(negative, ctx.decimal_rounding) {
    (
      Decimal::inf(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      ),
      flags,
    )
  } else {
    (
      finite_with_exponent_repr(
        negative,
        gda_coeff_magnitude_sub_unit(gda_coeff_power10_repr(precision), 1),
        ctx.e_max - precision + 1,
        precision,
      ),
      flags,
    )
  }
}

///|
fn decimal_zero_conversion_result(
  negative : Bool,
  exponent10 : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  if !ctx.extended {
    return (
      finite_with_exponent_repr(false, gda_coeff_zero(), 0, precision),
      DecimalFlags::new(),
    )
  }
  let upper = if ctx.clamp && ctx.precision > 0 {
    ctx.e_max - precision + 1
  } else {
    ctx.e_max
  }
  let lower = etiny(ctx)
  let clamped_exponent = if exponent10 > upper {
    upper
  } else if exponent10 < lower {
    lower
  } else {
    exponent10
  }
  (
    finite_with_exponent_repr(
      negative,
      gda_coeff_zero(),
      clamped_exponent,
      precision,
    ),
    if clamped_exponent == exponent10 {
      DecimalFlags::new()
    } else {
      { ..DecimalFlags::new(), clamped: true }
    },
  )
}

///|
fn decimal_extreme_tiny_conversion_result(
  negative : Bool,
  original_digits : Int,
  exponent10 : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 else { return None }
  let tiny = etiny(ctx)
  guard exponent10 < tiny else { return None }
  let shift = tiny.to_int64() - exponent10.to_int64()
  guard shift > (original_digits + 2).to_int64() else { return None }
  let precision = finite_precision_for_default(ctx)
  let rounded_magnitude = huge_shift_rounded_unit_repr(
    gda_coeff_from_int(1),
    negative,
    ctx.decimal_rounding,
  )
  let adjusted = exponent10.to_int64() + (original_digits - 1).to_int64()
  let subnormal = adjusted < ctx.e_min.to_int64()
  Some(
    (
      finite_with_exponent_repr(negative, rounded_magnitude, tiny, precision),
      {
        ..DecimalFlags::new(),
        rounded: true,
        inexact: true,
        subnormal,
        underflow: subnormal,
        clamped: ctx.extended && rounded_magnitude.is_zero(),
      },
    ),
  )
}

///|
fn parse_special_decimal_string_ctx(
  src : String,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard src.length() > 0 else { return None }
  let mut negative = false
  let mut start = 0
  if src[0] == '-' {
    negative = true
    start = 1
  } else if src[0] == '+' {
    start = 1
  }
  guard start < src.length() else { return None }
  let first = src[start]
  guard first == 'I' ||
    first == 'i' ||
    first == 'N' ||
    first == 'n' ||
    first == 'S' ||
    first == 's' else {
    return None
  }
  let body = src[start:].to_owned()
  let lower = ascii_lower(body)
  let precision = finite_precision_for_coeff(gda_coeff_zero(), ctx)
  if lower == "inf" || lower == "infinity" {
    if !ctx.extended {
      return Some(decimal_conversion_syntax_result(ctx))
    }
    return Some(
      (
        Decimal::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision~,
        ),
        DecimalFlags::new(),
      ),
    )
  }
  let mut signaling = false
  let mut payload_start = 0
  if lower.length() >= 4 && lower[:4].to_owned() == "snan" {
    signaling = true
    payload_start = 4
  } else if lower.length() >= 3 && lower[:3].to_owned() == "nan" {
    payload_start = 3
  } else {
    return None
  }
  if !ctx.extended {
    return Some(decimal_conversion_syntax_result(ctx))
  }
  let payload_src = body[payload_start:].to_owned()
  for i in 0..<payload_src.length() {
    let ch = payload_src[i]
    guard ch >= '0' && ch <= '9' else {
      return Some(decimal_conversion_syntax_result(ctx))
    }
  }
  let payload_digits = strip_leading_zero_digits(payload_src)
  let payload_limit = if ctx.clamp && ctx.precision > 0 {
    precision - 1
  } else {
    precision
  }
  if payload_digits.length() > payload_limit {
    return Some(decimal_conversion_syntax_result(ctx))
  }
  let payload = if payload_digits.length() == 0 {
    gda_coeff_zero()
  } else {
    match gda_coeff_from_decimal_digits_repr(payload_digits) {
      Some(value) => value
      None => return Some(decimal_conversion_syntax_result(ctx))
    }
  }
  Some(
    (
      make_special_repr(FpClass::NaN, negative, payload, precision, signaling),
      DecimalFlags::new(),
    ),
  )
}

///|
fn parse_decimal_string_ctx(
  src : String,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match parse_special_decimal_string_ctx(src, ctx) {
    Some(result) => result
    None =>
      match split_decimal_string(src) {
        Some((negative, digits, exponent10)) => {
          let significant_digits = strip_leading_zero_digits(digits)
          if significant_digits.length() == 0 {
            return decimal_zero_conversion_result(negative, exponent10, ctx)
          }
          let original_digits = significant_digits.length()
          if exponent10 + original_digits - 1 > ctx.e_max {
            return decimal_overflow_result(negative, ctx)
          }
          match
            decimal_extreme_tiny_conversion_result(
              negative, original_digits, exponent10, ctx,
            ) {
            Some(result) => return result
            None => ()
          }
          let magnitude = match
            gda_coeff_from_decimal_digits_repr(significant_digits) {
            Some(value) => value
            None => return decimal_conversion_syntax_result(ctx)
          }
          let (value, flags) = normalize_decimal_parts_ctx_repr(
            negative, magnitude, exponent10, ctx,
          )
          if ctx.precision > 0 &&
            !magnitude.is_zero() &&
            original_digits > finite_precision_for_coeff(magnitude, ctx) {
            (value, { ..flags, rounded: true })
          } else {
            (value, flags)
          }
        }
        None => decimal_conversion_syntax_result(ctx)
      }
  }
}

///|
pub fn Decimal::parse(
  src : String,
  precision? : Int = 34,
) -> Result[Decimal, @def.ArithmeticError] {
  let precision = Int::max(1, precision)
  match parse_special_decimal_string_ctx(src, DecimalContext::new(precision~)) {
    Some((value, flags)) => {
      if flags.conversion_syntax {
        return Err(
          @def.ArithmeticError::parse_error("invalid decimal literal: " + src),
        )
      }
      return Ok(value)
    }
    None => ()
  }
  match split_decimal_string(src) {
    Some((negative, digits, exponent10)) => {
      let significant_digits = strip_leading_zero_digits(digits)
      if significant_digits.length() == 0 {
        Ok(
          finite_with_exponent_repr(
            negative,
            gda_coeff_zero(),
            exponent10,
            precision,
          ),
        )
      } else {
        let coeff = match
          gda_coeff_from_decimal_digits_repr(significant_digits) {
          Some(value) => value
          None =>
            return Err(
              @def.ArithmeticError::parse_error(
                "invalid decimal literal: " + src,
              ),
            )
        }
        if significant_digits.length() <= precision {
          Ok(finite_with_exponent_repr(negative, coeff, exponent10, precision))
        } else {
          Ok(
            normalize_decimal_parts_gda_repr(
              negative,
              coeff,
              exponent10,
              precision,
              DecimalRoundingMode::HalfEven,
            ),
          )
        }
      }
    }
    None =>
      Err(@def.ArithmeticError::parse_error("invalid decimal literal: " + src))
  }
}

///|
pub fn Decimal::from_string(src : String, precision? : Int = 34) -> Decimal? {
  match Decimal::parse(src, precision~) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
pub fn Decimal::from_string_ctx(
  src : String,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  parse_decimal_string_ctx(src, ctx)
}

///|
pub fn Decimal::to_sci_string(
  src : String,
  ctx : DecimalContext,
) -> (String, DecimalFlags) {
  let (value, flags) = parse_decimal_string_ctx(src, ctx)
  (format_sci_gda(value), flags)
}

///|
pub fn Decimal::to_eng_string(
  src : String,
  ctx : DecimalContext,
) -> (String, DecimalFlags) {
  let (value, flags) = parse_decimal_string_ctx(src, ctx)
  (format_eng_gda(value), flags)
}

///|
pub impl Show for Decimal with fn to_string(self) {
  match self.class {
    FpClass::NaN => {
      let prefix = if self.negative { "-" } else { "" }
      let kind = if self.signaling_nan { "snan" } else { "nan" }
      if self.coefficient.is_zero() {
        prefix + kind
      } else {
        prefix + kind + self.coefficient.to_string()
      }
    }
    FpClass::Infinity =>
      if self.sign() == Sign::Negative {
        "-inf"
      } else {
        "inf"
      }
    FpClass::Finite => {
      let pre = self.coefficient.digits10() + self.exponent10
      if self.exponent10 > 0 || pre < -5 {
        format_sci_finite(self)
      } else {
        format_plain_finite(self)
      }
    }
  }
}
