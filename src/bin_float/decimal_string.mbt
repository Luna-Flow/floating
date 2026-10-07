///|
/// A finite decimal `(-1)^negative * digits * 10^exponent`, with `digits`
/// free of leading and trailing zeros (empty for zero).
priv struct DecimalLiteral {
  negative : Bool
  digits : String
  exponent : Int64
}

///|
priv enum ParsedDecimal {
  Finite(DecimalLiteral)
  Infinite(Bool)
  QuietNaN(Bool)
  SignalingNaN(Bool)
}

///|
/// Exponents beyond this magnitude are clamped; any nonzero value that far
/// out overflows or underflows every context.
let decimal_exponent_clamp : Int64 = 1L << 60

///|
fn parse_decimal_literal(
  source : String,
) -> Result[ParsedDecimal, @def.ArithmeticError] {
  let text = source.trim().to_owned()
  let error = fn(reason : String) {
    Err(@def.ArithmeticError::parse_error("invalid decimal number: " + reason))
  }
  if text.length() == 0 {
    return error("empty input")
  }
  let first = text.unsafe_get(0)
  let negative = first == '-'
  let start = if first == '-' || first == '+' { 1 } else { 0 }
  let body = text.view(start_offset=start).to_owned().to_lower()
  match body {
    "inf" | "infinity" => return Ok(Infinite(negative))
    "nan" | "qnan" => return Ok(QuietNaN(negative))
    "snan" => return Ok(SignalingNaN(negative))
    _ => ()
  }
  let digits = StringBuilder()
  let mut fraction_digits = 0L
  let mut seen_digit = false
  let mut seen_point = false
  let mut index = 0
  while index < body.length() {
    let c = body.unsafe_get(index)
    if c >= '0' && c <= '9' {
      seen_digit = true
      // Leading zeros carry no value; fraction digits still shift the scale.
      if digits.is_empty() && c == '0' {
        if seen_point {
          fraction_digits += 1L
        }
      } else {
        digits.write_char(c.to_int().unsafe_to_char())
        if seen_point {
          fraction_digits += 1L
        }
      }
    } else if c == '.' && !seen_point {
      seen_point = true
    } else {
      break
    }
    index += 1
  }
  if !seen_digit {
    return error("no digits in '" + source + "'")
  }
  let mut exponent = 0L
  if index < body.length() {
    guard body.unsafe_get(index) == 'e' else {
      return error("unexpected character in '" + source + "'")
    }
    index += 1
    let exponent_negative = index < body.length() &&
      body.unsafe_get(index) == '-'
    if index < body.length() &&
      (body.unsafe_get(index) == '-' || body.unsafe_get(index) == '+') {
      index += 1
    }
    guard index < body.length() else { return error("empty exponent") }
    while index < body.length() {
      let c = body.unsafe_get(index)
      guard c >= '0' && c <= '9' else {
        return error("unexpected character in '" + source + "'")
      }
      if exponent < decimal_exponent_clamp {
        exponent = exponent * 10L + (c.to_int() - '0'.to_int()).to_int64()
      }
      index += 1
    }
    if exponent > decimal_exponent_clamp {
      exponent = decimal_exponent_clamp
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  // Fold trailing zeros into the exponent.
  let raw = digits.to_string()
  let mut end = raw.length()
  while end > 0 && raw.unsafe_get(end - 1) == '0' {
    end -= 1
  }
  Ok(
    Finite({
      negative,
      digits: raw.view(end_offset=end).to_owned(),
      exponent: exponent - fraction_digits + (raw.length() - end).to_int64(),
    }),
  )
}

///|
/// Above these decimal exponents no tie or exactly representable value is
/// possible (see `binary_round_decimal`), so the Ziv path always terminates.
fn decimal_exact_limit(digit_count : Int, precision : Int) -> Int64 {
  Int64::max(
    400L,
    (digit_count.to_int64() * 3L + precision.to_int64()) / 2L + 64L,
  )
}

///|
fn binary_round_decimal(
  literal : DecimalLiteral,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let negative = literal.negative
  if literal.digits.is_empty() {
    return (finite_zero(negative, context.precision), BinaryFlags::new())
  }
  // log2 |value| lies in [(n - 1 + e) log2 10, (n + e) log2 10).
  let count = literal.digits.length().to_int64()
  let low_decimal = (count - 1L + literal.exponent).to_double()
  let high_decimal = (count + literal.exponent).to_double()
  let margin = 4.0 + (low_decimal.abs() + high_decimal.abs()) * 1.0e-12
  let log2_10 = 3.321928094887362
  let log2_low = low_decimal * log2_10 - margin
  let log2_high = high_decimal * log2_10 + margin
  if log2_low >= (context.range_e_max() + 1).to_double() {
    return binary_overflow_result(negative, context)
  }
  if log2_high < (context.range_e_min() - context.precision).to_double() {
    return binary_tiny_nonzero_result(negative, context)
  }
  let digits = BinCoeff::parse(literal.digits).unwrap()
  let scale = if literal.exponent < 0L {
    -literal.exponent
  } else {
    literal.exponent
  }
  // Within the range check |exponent| is far below Int's limit.
  let scale_int = scale.to_int()
  if scale <= decimal_exact_limit(literal.digits.length(), context.precision) {
    let five_power = BinCoeff::from_uint64(5UL).pow_nat(
      scale_int.reinterpret_as_uint(),
    )
    return if literal.exponent >= 0L {
      binary_round_dyadic(negative, digits.mul(five_power), scale_int, context)
    } else {
      binary_round_rational(negative, digits, five_power, -scale_int, context)
    }
  }
  // Large exponents: D * 5^k with 5^k > 2^(p + 2) is neither representable
  // nor a midpoint, and D / 10^k with 5^k > D is not dyadic, so directed
  // enclosures eventually round to one value.
  let mut work = context.precision + 64
  while true {
    let down = BinaryContext::unbounded(work, rounding=RoundTowardNegative)
    let up = BinaryContext::unbounded(work, rounding=RoundTowardPositive)
    let ten = BinFloat::from_int(10, precision=work)
    let power_low = ten.pow_int_ctx(scale_int, down).0
    let power_high = ten.pow_int_ctx(scale_int, up).0
    let digits_low = BinFloat::make(
      digits,
      0,
      work,
      mode=RoundingMode::TowardNegative,
    )
    let digits_high = BinFloat::make(
      digits,
      0,
      work,
      mode=RoundingMode::TowardPositive,
    )
    let (low, high) = if literal.exponent >= 0L {
      (
        digits_low.mul_ctx(power_low, down).0,
        digits_high.mul_ctx(power_high, up).0,
      )
    } else {
      (
        digits_low.div_ctx(power_high, down).0,
        digits_high.div_ctx(power_low, up).0,
      )
    }
    let (lower, upper) = if negative {
      (high.neg(), low.neg())
    } else {
      (low, high)
    }
    let (result, unique, flags) = binary_certified_target_rounding(
      lower, upper, context,
    )
    if unique {
      return (result, flags)
    }
    work = work * 2
  }
  panic()
}

///|
/// IEEE 754 convertFromDecimalCharacter: parses `[+-]digits[.digits][e[+-]digits]`,
/// `inf`, `infinity`, `nan`, and `snan` (case-insensitive, surrounding
/// whitespace ignored) and rounds the exact decimal value once under
/// `context`, for any precision and exponent.
pub fn BinFloat::from_string_ctx(
  source : String,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  parse_decimal_literal(source).map(fn(parsed) {
    match parsed {
      Finite(literal) => binary_round_decimal(literal, context)
      Infinite(negative) =>
        (
          BinFloat::inf(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          BinaryFlags::new(),
        )
      QuietNaN(negative) =>
        (
          BinFloat::quiet_nan(negative~, precision=context.precision),
          BinaryFlags::new(),
        )
      SignalingNaN(negative) =>
        (
          BinFloat::signaling_nan(negative~, precision=context.precision),
          BinaryFlags::new(),
        )
    }
  })
}

///|
/// `from_string_ctx` in an unbounded round-to-nearest-even context.
pub fn BinFloat::from_string(
  source : String,
  precision? : Int = 53,
) -> Result[BinFloat, @def.ArithmeticError] {
  BinFloat::from_string_ctx(source, BinaryContext::unbounded(precision)).map(fn(
    result,
  ) {
    result.0
  })
}
