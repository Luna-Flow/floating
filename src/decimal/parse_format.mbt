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
fn signed_exponent10(exponent : Int) -> String {
  if exponent >= 0 {
    "E+" + exponent.to_string()
  } else {
    "E" + exponent.to_string()
  }
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
  let prefix = if value.negative { "-" } else { "" }
  if value.coefficient.is_zero() {
    if value.exponent10 < 0 {
      return prefix + "0." + zeros(-value.exponent10)
    }
    return prefix + "0" + zeros(value.exponent10)
  }
  let digits = value.coefficient.to_string()
  if value.exponent10 >= 0 {
    prefix + digits + zeros(value.exponent10)
  } else {
    let split = digits.length() + value.exponent10
    if split > 0 {
      prefix + digits[:split].to_owned() + "." + digits[split:].to_owned()
    } else {
      prefix + "0." + zeros(-split) + digits
    }
  }
}

///|
fn format_sci_finite(value : Decimal) -> String {
  let prefix = if value.negative { "-" } else { "" }
  if value.coefficient.is_zero() {
    if value.exponent10 <= 0 && value.exponent10 >= -6 {
      return format_plain_finite(value)
    }
    return prefix + "0" + signed_exponent10(value.exponent10)
  }
  let adjusted = adjusted_exponent(value)
  if value.exponent10 <= 0 && adjusted >= -6 {
    return format_plain_finite(value)
  }
  let digits = value.coefficient.to_string()
  let significand = if digits.length() == 1 {
    digits
  } else {
    digits[:1].to_owned() + "." + digits[1:].to_owned()
  }
  prefix + significand + signed_exponent10(adjusted)
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
    let prefix = if value.negative { "-" } else { "" }
    if zero_count == 0 {
      prefix + "0" + signed_exponent10(eng_exp)
    } else {
      prefix + "0." + zeros(zero_count) + signed_exponent10(eng_exp)
    }
  } else {
    let adjusted = adjusted_exponent(value)
    let eng_exp = floor_multiple3(adjusted)
    if adjusted >= -6 && (value.exponent10 <= 0 || eng_exp == 0) {
      return format_plain_finite(value)
    }
    let int_digits = adjusted - eng_exp + 1
    let prefix = if value.negative { "-" } else { "" }
    let digits = value.coefficient.to_string()
    let significand = if int_digits >= digits.length() {
      digits + zeros(int_digits - digits.length())
    } else if int_digits <= 0 {
      "0." + zeros(-int_digits) + digits
    } else if int_digits == digits.length() {
      digits
    } else {
      digits[:int_digits].to_owned() + "." + digits[int_digits:].to_owned()
    }
    prefix + significand + signed_exponent10(eng_exp)
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
  (
    Decimal::nan(precision=finite_precision_for(bigint_zero(), ctx)),
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
  let precision = finite_precision_for(bigint_one(), ctx)
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
      finite_with_exponent(
        negative,
        pow10(precision) - bigint_one(),
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
  let precision = finite_precision_for(bigint_zero(), ctx)
  if !ctx.extended {
    return (
      finite_with_exponent(false, bigint_zero(), 0, precision),
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
    finite_with_exponent(negative, bigint_zero(), clamped_exponent, precision),
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
  magnitude : BigInt,
  original_digits : Int,
  exponent10 : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 && !magnitude.is_zero() else { return None }
  let tiny = etiny(ctx)
  guard exponent10 < tiny else { return None }
  let shift_big = BigInt::from_int(tiny) - BigInt::from_int(exponent10)
  guard shift_big > BigInt::from_int(original_digits + 2) else { return None }
  let precision = finite_precision_for(magnitude, ctx)
  let rounded_magnitude = huge_shift_rounded_unit(
    magnitude,
    negative,
    ctx.decimal_rounding,
  )
  let adjusted = BigInt::from_int(exponent10) +
    BigInt::from_int(original_digits - 1)
  let subnormal = adjusted < BigInt::from_int(ctx.e_min)
  Some(
    (
      finite_with_exponent(negative, rounded_magnitude, tiny, precision),
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
  let body = src[start:].to_owned()
  let lower = ascii_lower(body)
  let precision = finite_precision_for(bigint_zero(), ctx)
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
    bigint_zero()
  } else {
    BigInt::from_string(payload_digits)
  }
  Some(
    (
      make_special(FpClass::NaN, negative, payload, precision, signaling),
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
          let magnitude = BigInt::from_string(significant_digits)
          match
            decimal_extreme_tiny_conversion_result(
              negative, magnitude, original_digits, exponent10, ctx,
            ) {
            Some(result) => return result
            None => ()
          }
          let (value, flags) = normalize_decimal_parts_ctx(
            negative, magnitude, exponent10, ctx,
          )
          if ctx.precision > 0 &&
            !magnitude.is_zero() &&
            original_digits > finite_precision_for(magnitude, ctx) {
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
        Ok(finite_with_exponent(negative, bigint_zero(), exponent10, precision))
      } else {
        let coeff = BigInt::from_string(significant_digits)
        if significant_digits.length() <= precision {
          Ok(finite_with_exponent(negative, coeff, exponent10, precision))
        } else {
          Ok(
            normalize_decimal_parts(
              negative,
              coeff,
              exponent10,
              precision,
              RoundingMode::ToNearestEven,
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
