///|
priv enum RuntimeValue {
  DecimalValue(@decimal.Decimal)
  IntValue(Int)
  BoolValue(Bool)
  TextValue(String)
}

///|
priv struct EvaluatedValue {
  value : RuntimeValue
  flags : @decimal.DecimalFlags
}

///|
fn evaluated_decimal(
  value : @decimal.Decimal,
  flags? : @decimal.DecimalFlags = @decimal.DecimalFlags::new(),
) -> EvaluatedValue {
  { value: DecimalValue(value), flags }
}

///|
fn normalize_token(src : String) -> String {
  let trimmed = src.trim().to_owned()
  if trimmed.has_prefix("+") {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
}

///|
fn uppercase_ascii(src : String) -> String {
  let builder = StringBuilder::new()
  for index in 0..<src.length() {
    let ch = src[index]
    if ch >= 'a' && ch <= 'z' {
      builder.write_char(Int::unsafe_to_char(ch.to_int() - 32))
    } else {
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    }
  }
  builder.to_string()
}

///|
fn interchange_format(
  context : GdaContext,
) -> @decimal.DecimalInterchangeFormat? {
  match (context.precision(), context.min_exponent(), context.max_exponent()) {
    (7, -95, 96) => Some(@decimal.Decimal32)
    (16, -383, 384) => Some(@decimal.Decimal64)
    (34, -6143, 6144) => Some(@decimal.Decimal128)
    _ => None
  }
}

///|
fn decimal_context(context : GdaContext) -> @decimal.DecimalContext? {
  let normalized = normalized_word(context.rounding())
  let (rounding, decimal_rounding) = match normalized {
    "halfeven" => (@lf_arith.RoundingMode::ToNearestEven, @decimal.HalfEven)
    "halfup" => (@lf_arith.RoundingMode::ToNearestEven, @decimal.HalfUp)
    "halfdown" => (@lf_arith.RoundingMode::ToNearestEven, @decimal.HalfDown)
    "down" | "towardzero" => (@lf_arith.RoundingMode::TowardZero, @decimal.Down)
    "ceiling" | "towardpositive" =>
      (@lf_arith.RoundingMode::TowardPositive, @decimal.Ceiling)
    "floor" | "towardnegative" =>
      (@lf_arith.RoundingMode::TowardNegative, @decimal.Floor)
    "up" | "awayfromzero" => (@lf_arith.RoundingMode::AwayFromZero, @decimal.Up)
    "05up" | "zerofiveup" =>
      (@lf_arith.RoundingMode::TowardZero, @decimal.ZeroFiveUp)
    _ => return None
  }
  Some(
    @decimal.DecimalContext::new(
      precision=context.precision(),
      rounding~,
      decimal_rounding~,
      e_min=context.min_exponent(),
      e_max=context.max_exponent(),
      clamp=context.clamp(),
      extended=context.extended(),
    ),
  )
}

///|
fn decode_decimal(token : String, context : GdaContext) -> @decimal.Decimal? {
  let normalized = normalize_token(token)
  if normalized.has_prefix("32#") {
    Some(
      @decimal.Decimal::from_string_ctx(
        normalized[3:].to_owned(),
        @decimal.DecimalContext::decimal32(),
      ).0,
    )
  } else if normalized.has_prefix("64#") {
    Some(
      @decimal.Decimal::from_string_ctx(
        normalized[3:].to_owned(),
        @decimal.DecimalContext::decimal64(),
      ).0,
    )
  } else if normalized.has_prefix("128#") {
    Some(
      @decimal.Decimal::from_string_ctx(
        normalized[4:].to_owned(),
        @decimal.DecimalContext::decimal128(),
      ).0,
    )
  } else if normalized.has_prefix("#") {
    match interchange_format(context) {
      Some(format) => @decimal.Decimal::from_interchange_hex(normalized, format)
      None => None
    }
  } else {
    @decimal.Decimal::from_string(
      normalized,
      precision=Int::max(64, context.precision()),
    )
  }
}

///|
fn decimal_argument(
  values : Array[EvaluatedValue],
  index : Int,
) -> @decimal.Decimal? {
  guard index >= 0 && index < values.length() else { return None }
  match values[index].value {
    DecimalValue(value) => Some(value)
    _ => None
  }
}

///|
fn unary_decimal(
  values : Array[EvaluatedValue],
  call : (@decimal.Decimal) -> (@decimal.Decimal, @decimal.DecimalFlags),
) -> Result[EvaluatedValue, String] {
  guard decimal_argument(values, 0) is Some(value) else {
    return Err("operation expects one decimal operand")
  }
  let (result, flags) = call(value)
  Ok(evaluated_decimal(result, flags~))
}

///|
fn binary_decimal(
  values : Array[EvaluatedValue],
  call : (@decimal.Decimal, @decimal.Decimal) -> (
    @decimal.Decimal,
    @decimal.DecimalFlags,
  ),
) -> Result[EvaluatedValue, String] {
  guard decimal_argument(values, 0) is Some(left) &&
    decimal_argument(values, 1) is Some(right) else {
    return Err("operation expects two decimal operands")
  }
  let (result, flags) = call(left, right)
  Ok(evaluated_decimal(result, flags~))
}

///|
fn operation_supported(operation : String) -> Bool {
  match operation {
    "apply"
    | "canonical"
    | "add"
    | "subtract"
    | "sub"
    | "multiply"
    | "mul"
    | "power"
    | "divide"
    | "div"
    | "divideint"
    | "divideinteger"
    | "exp"
    | "remainder"
    | "remaindernear"
    | "fma"
    | "quantize"
    | "rescale"
    | "tointegralx"
    | "tointegralexact"
    | "tointegral"
    | "tointegralvalue"
    | "compare"
    | "comparesig"
    | "comparesignal"
    | "comparetotal"
    | "comparetot"
    | "comparetotalmag"
    | "comparetotmag"
    | "samequantum"
    | "sqrt"
    | "squareroot"
    | "plus"
    | "minus"
    | "abs"
    | "reduce"
    | "normalize"
    | "trim"
    | "nextplus"
    | "nextminus"
    | "nexttoward"
    | "ln"
    | "log10"
    | "logb"
    | "scaleb"
    | "shift"
    | "rotate"
    | "tosci"
    | "toeng"
    | "copy"
    | "copyabs"
    | "copynegate"
    | "copyneg"
    | "copysign"
    | "class"
    | "iscanonical"
    | "isfinite"
    | "isinfinite"
    | "isnan"
    | "isqnan"
    | "issnan"
    | "isnegative"
    | "isnormal"
    | "issubnormal"
    | "issigned"
    | "iszero"
    | "min"
    | "max"
    | "minmag"
    | "maxmag"
    | "and"
    | "or"
    | "xor"
    | "invert" => true
    _ => false
  }
}

///|
fn case_disposition(case : GdaCase) -> CaseDisposition {
  for token in case.operands() {
    if token == "#" {
      return Diagnostic("diagnostic interchange/non-scalar row")
    }
    if token == "?" {
      return Legacy("legacy subset non-decimal operand ?")
    }
  }
  if case.expected() == "#" {
    return Diagnostic("diagnostic interchange/non-scalar row")
  }
  for condition in case.conditions() {
    let normalized = normalized_word(condition)
    match normalized {
      "inexact"
      | "rounded"
      | "lostdigits"
      | "invalidoperation"
      | "divisionbyzero"
      | "overflow"
      | "underflow"
      | "subnormal"
      | "clamped"
      | "conversionsyntax"
      | "divisionimpossible"
      | "divisionundefined"
      | "invalidcontext" => ()
      _ => return Unsupported("unsupported condition " + condition)
    }
  }
  if !operation_supported(case.normalized_operation()) {
    Unsupported("unsupported operation " + case.operation())
  } else if decimal_context(case.context()) is None {
    Unsupported("unsupported rounding " + case.context().rounding())
  } else {
    Executable
  }
}

///|
fn flags_match(
  actual : @decimal.DecimalFlags,
  conditions : Array[String],
) -> Bool {
  let mut inexact = false
  let mut rounded = false
  let mut lost_digits = false
  let mut invalid_operation = false
  let mut division_by_zero = false
  let mut overflow = false
  let mut underflow = false
  let mut subnormal = false
  let mut clamped = false
  let mut conversion_syntax = false
  let mut division_impossible = false
  let mut division_undefined = false
  let mut invalid_context = false
  for condition in conditions {
    match normalized_word(condition) {
      "inexact" => inexact = true
      "rounded" => rounded = true
      "lostdigits" => lost_digits = true
      "invalidoperation" => invalid_operation = true
      "divisionbyzero" => division_by_zero = true
      "overflow" => overflow = true
      "underflow" => underflow = true
      "subnormal" => subnormal = true
      "clamped" => clamped = true
      "conversionsyntax" => conversion_syntax = true
      "divisionimpossible" => {
        division_impossible = true
        invalid_operation = true
      }
      "divisionundefined" => {
        division_undefined = true
        invalid_operation = true
      }
      "invalidcontext" => invalid_context = true
      _ => ()
    }
  }
  actual.inexact == inexact &&
  actual.rounded == rounded &&
  actual.lost_digits == lost_digits &&
  actual.invalid_operation == invalid_operation &&
  actual.division_by_zero == division_by_zero &&
  actual.overflow == overflow &&
  actual.underflow == underflow &&
  actual.subnormal == subnormal &&
  actual.clamped == clamped &&
  actual.conversion_syntax == conversion_syntax &&
  actual.division_impossible == division_impossible &&
  actual.division_undefined == division_undefined &&
  actual.invalid_context == invalid_context
}

///|
fn decimal_flags_text(flags : @decimal.DecimalFlags) -> String {
  let mut text = ""
  if flags.inexact {
    text = text + " Inexact"
  }
  if flags.rounded {
    text = text + " Rounded"
  }
  if flags.lost_digits {
    text = text + " Lost_digits"
  }
  if flags.invalid_operation {
    text = text + " Invalid_operation"
  }
  if flags.division_by_zero {
    text = text + " Division_by_zero"
  }
  if flags.overflow {
    text = text + " Overflow"
  }
  if flags.underflow {
    text = text + " Underflow"
  }
  if flags.subnormal {
    text = text + " Subnormal"
  }
  if flags.clamped {
    text = text + " Clamped"
  }
  if flags.conversion_syntax {
    text = text + " Conversion_syntax"
  }
  if flags.division_impossible {
    text = text + " Division_impossible"
  }
  if flags.division_undefined {
    text = text + " Division_undefined"
  }
  if flags.invalid_context {
    text = text + " Invalid_context"
  }
  if text.length() == 0 {
    "none"
  } else {
    text[1:].to_owned()
  }
}

///|
fn invoke_decimal_operation(
  case : GdaCase,
  operation : @numeric_expr.Operation,
  values : Array[EvaluatedValue],
) -> Result[EvaluatedValue, String] {
  guard decimal_context(case.context()) is Some(context) else {
    return Err("unsupported decimal context")
  }
  let op = operation.name()
  let raws = case.operands()
  if op == "apply" && raws.length() >= 1 {
    let raw = raws[0]
    if case.expected().has_prefix("#") {
      guard interchange_format(case.context()) is Some(format) else {
        return Err("interchange apply requires a concrete format")
      }
      let encoded = if raw.has_prefix("#") {
        match @decimal.DecimalInterchange::from_hex(raw, format) {
          Some(value) =>
            Some((value.canonical().to_hex(), @decimal.DecimalFlags::new()))
          None => None
        }
      } else {
        match decode_decimal(raw, case.context()) {
          Some(value) => Some(value.to_interchange_hex(format))
          None => None
        }
      }
      guard encoded is Some(encoded) else {
        return Err("invalid interchange apply operand")
      }
      return Ok({ value: TextValue(encoded.0), flags: encoded.1 })
    }
    if raw.has_prefix("#") {
      guard interchange_format(case.context()) is Some(format) &&
        @decimal.DecimalInterchange::from_hex(raw, format) is Some(value) else {
        return Err("invalid interchange apply operand")
      }
      let (decimal, flags) = value.to_decimal_ctx()
      return Ok(evaluated_decimal(decimal, flags~))
    }
  }
  if (op == "copy" || op == "copyabs" || op == "copynegate" || op == "copyneg") &&
    raws.length() >= 1 &&
    raws[0].has_prefix("#") &&
    case.expected().has_prefix("#") {
    guard interchange_format(case.context()) is Some(format) &&
      @decimal.DecimalInterchange::from_hex(raws[0], format) is Some(raw) else {
      return Err("invalid interchange copy operand")
    }
    let copied = match op {
      "copy" => raw.copy()
      "copyabs" => raw.copy_abs()
      _ => raw.copy_negate()
    }
    return Ok({
      value: TextValue(copied.to_hex()),
      flags: @decimal.DecimalFlags::new(),
    })
  }
  if op == "copysign" &&
    raws.length() >= 2 &&
    raws[0].has_prefix("#") &&
    case.expected().has_prefix("#") {
    guard interchange_format(case.context()) is Some(format) &&
      @decimal.DecimalInterchange::from_hex(raws[0], format) is Some(left) else {
      return Err("invalid interchange copysign operand")
    }
    let right = if raws[1].has_prefix("#") {
      @decimal.DecimalInterchange::from_hex(raws[1], format)
    } else {
      match decimal_argument(values, 1) {
        Some(decimal) =>
          Some(@decimal.DecimalInterchange::from_decimal(decimal, format).0)
        None => None
      }
    }
    guard right is Some(right) else {
      return Err("invalid interchange copysign sign operand")
    }
    return Ok({
      value: TextValue(left.copy_sign(right).to_hex()),
      flags: @decimal.DecimalFlags::new(),
    })
  }
  match op {
    "add" => binary_decimal(values, fn(a, b) { a.add_ctx(b, context) })
    "subtract" | "sub" =>
      binary_decimal(values, fn(a, b) { a.sub_ctx(b, context) })
    "multiply" | "mul" =>
      binary_decimal(values, fn(a, b) { a.mul_ctx(b, context) })
    "divide" | "div" =>
      binary_decimal(values, fn(a, b) { a.div_ctx(b, context) })
    "power" => binary_decimal(values, fn(a, b) { a.power_ctx(b, context) })
    "divideint" | "divideinteger" =>
      binary_decimal(values, fn(a, b) { a.divide_integer(b, context) })
    "remainder" => binary_decimal(values, fn(a, b) { a.remainder(b, context) })
    "remaindernear" =>
      binary_decimal(values, fn(a, b) { a.remainder_near(b, context) })
    "quantize" => binary_decimal(values, fn(a, b) { a.quantize(b, context) })
    "rescale" => binary_decimal(values, fn(a, b) { a.rescale(b, context) })
    "compare" => binary_decimal(values, fn(a, b) { a.compare_ctx(b, context) })
    "comparesig" | "comparesignal" =>
      binary_decimal(values, fn(a, b) { a.compare_signal_ctx(b, context) })
    "min" => binary_decimal(values, fn(a, b) { a.min_ctx(b, context) })
    "max" => binary_decimal(values, fn(a, b) { a.max_ctx(b, context) })
    "minmag" => binary_decimal(values, fn(a, b) { a.min_mag_ctx(b, context) })
    "maxmag" => binary_decimal(values, fn(a, b) { a.max_mag_ctx(b, context) })
    "nexttoward" =>
      binary_decimal(values, fn(a, b) { a.next_toward(b, context) })
    "scaleb" => binary_decimal(values, fn(a, b) { a.scaleb_ctx(b, context) })
    "shift" => binary_decimal(values, fn(a, b) { a.shift_ctx(b, context) })
    "rotate" => binary_decimal(values, fn(a, b) { a.rotate_ctx(b, context) })
    "and" => binary_decimal(values, fn(a, b) { a.logical_and(b, context) })
    "or" => binary_decimal(values, fn(a, b) { a.logical_or(b, context) })
    "xor" => binary_decimal(values, fn(a, b) { a.logical_xor(b, context) })
    "apply" => unary_decimal(values, fn(a) { a.apply_ctx(context) })
    "plus" => unary_decimal(values, fn(a) { a.plus_ctx(context) })
    "minus" => unary_decimal(values, fn(a) { a.minus_ctx(context) })
    "abs" => unary_decimal(values, fn(a) { a.abs_ctx(context) })
    "reduce" => unary_decimal(values, fn(a) { a.reduce_ctx(context) })
    "normalize" => unary_decimal(values, fn(a) { a.normalize_ctx(context) })
    "nextplus" => unary_decimal(values, fn(a) { a.next_plus(context) })
    "nextminus" => unary_decimal(values, fn(a) { a.next_minus(context) })
    "exp" => unary_decimal(values, fn(a) { a.exp_ctx(context) })
    "ln" => unary_decimal(values, fn(a) { a.ln_ctx(context) })
    "log10" => unary_decimal(values, fn(a) { a.log10_ctx(context) })
    "logb" => unary_decimal(values, fn(a) { a.logb_ctx(context) })
    "invert" => unary_decimal(values, fn(a) { a.logical_invert(context) })
    "sqrt" | "squareroot" =>
      unary_decimal(values, fn(a) { a.sqrt_ctx(context) })
    "tointegralx" | "tointegralexact" =>
      unary_decimal(values, fn(a) { a.to_integral_exact(context) })
    "tointegral" | "tointegralvalue" =>
      unary_decimal(values, fn(a) { a.to_integral_value(context) })
    "fma" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) &&
        decimal_argument(values, 2) is Some(c) else {
        return Err("fma expects three decimal operands")
      }
      let (result, flags) = a.fma_ctx(b, c, context)
      Ok(evaluated_decimal(result, flags~))
    }
    "comparetotal" | "comparetot" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("comparetotal expects two operands")
      }
      let (result, flags) = a.compare_total_ctx(b, context)
      Ok({ value: IntValue(result), flags })
    }
    "comparetotalmag" | "comparetotmag" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("comparetotalmag expects two operands")
      }
      let (result, flags) = a.compare_total_magnitude_ctx(b, context)
      Ok({ value: IntValue(result), flags })
    }
    "samequantum" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("samequantum expects two operands")
      }
      Ok({
        value: BoolValue(a.same_quantum(b)),
        flags: @decimal.DecimalFlags::new(),
      })
    }
    "trim" | "copy" | "copyabs" | "copynegate" | "copyneg" => {
      guard decimal_argument(values, 0) is Some(value) else {
        return Err("copy operation expects one operand")
      }
      let result = match op {
        "trim" =>
          if !context.extended && value.is_zero() {
            @decimal.Decimal::zero(precision=context.precision)
          } else {
            value.trim()
          }
        "copy" => value.copy()
        "copyabs" => value.copy_abs()
        _ => value.copy_negate()
      }
      Ok(evaluated_decimal(result))
    }
    "copysign" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("copysign expects two operands")
      }
      Ok(evaluated_decimal(a.copy_sign(b)))
    }
    "class" => {
      guard decimal_argument(values, 0) is Some(value) else {
        return Err("class expects one operand")
      }
      Ok({
        value: TextValue(value.class_name(context)),
        flags: @decimal.DecimalFlags::new(),
      })
    }
    "iscanonical"
    | "isfinite"
    | "isinfinite"
    | "isnan"
    | "isqnan"
    | "issnan"
    | "isnegative"
    | "isnormal"
    | "issubnormal"
    | "issigned"
    | "iszero" => {
      guard decimal_argument(values, 0) is Some(value) else {
        return Err("predicate expects one operand")
      }
      let result = match op {
        "iscanonical" => value.is_canonical()
        "isfinite" => value.is_finite()
        "isinfinite" => value.is_infinite()
        "isnan" => value.is_nan()
        "isqnan" => value.is_qnan()
        "issnan" => value.is_snan()
        "isnegative" => value.is_negative()
        "isnormal" => value.is_normal(context)
        "issubnormal" => value.is_subnormal(context)
        "issigned" => value.is_signed()
        _ => value.is_zero()
      }
      Ok({ value: BoolValue(result), flags: @decimal.DecimalFlags::new() })
    }
    "tosci" | "toeng" => {
      guard raws is [raw, ..] else {
        return Err("string conversion expects one operand")
      }
      let (text, flags) = if op == "tosci" {
        @decimal.Decimal::to_sci_string(raw, context)
      } else {
        @decimal.Decimal::to_eng_string(raw, context)
      }
      Ok({ value: TextValue(text), flags })
    }
    "canonical" => {
      guard raws is [raw, ..] &&
        interchange_format(case.context()) is Some(format) else {
        return Err("canonical requires an interchange operand and context")
      }
      let value = if raw.has_prefix("#") {
        @decimal.DecimalInterchange::from_hex(raw, format)
      } else {
        match decode_decimal(raw, case.context()) {
          Some(decimal) =>
            Some(@decimal.DecimalInterchange::from_decimal(decimal, format).0)
          None => None
        }
      }
      guard value is Some(value) else {
        return Err("invalid interchange encoding")
      }
      Ok({
        value: TextValue(value.canonical().to_hex()),
        flags: @decimal.DecimalFlags::new(),
      })
    }
    _ => Err("unsupported operation " + op)
  }
}

///|
fn compare_evaluated(
  case : GdaCase,
  actual : EvaluatedValue,
) -> Result[Unit, String] {
  let expected = case.expected()
  let actual_flags = match actual.value {
    DecimalValue(value) if expected.has_prefix("32#") =>
      actual.flags.combine(value.to_interchange_hex(@decimal.Decimal32).1)
    DecimalValue(value) if expected.has_prefix("64#") =>
      actual.flags.combine(value.to_interchange_hex(@decimal.Decimal64).1)
    DecimalValue(value) if expected.has_prefix("128#") =>
      actual.flags.combine(value.to_interchange_hex(@decimal.Decimal128).1)
    _ => actual.flags
  }
  if expected != "?" {
    let value_matches = match actual.value {
      DecimalValue(value) =>
        if expected.has_prefix("#") {
          match interchange_format(case.context()) {
            Some(format) =>
              value.to_interchange_hex(format).0 == uppercase_ascii(expected)
            None => false
          }
        } else {
          match decode_decimal(expected, case.context()) {
            Some(target) =>
              if expected.has_prefix("32#") ||
                expected.has_prefix("64#") ||
                expected.has_prefix("128#") {
                value.compare(target) == 0
              } else {
                value.to_string() == expected ||
                value.compare_total(target) == 0
              }
            None => false
          }
        }
      IntValue(value) => value.to_string() == expected
      BoolValue(value) => {
        let normalized = ascii_lower(expected)
        value.to_string() == normalized ||
        (value && normalized == "1") ||
        (!value && normalized == "0")
      }
      TextValue(value) =>
        if expected.has_prefix("#") {
          uppercase_ascii(value) == uppercase_ascii(expected)
        } else {
          value == expected
        }
    }
    guard value_matches else {
      let actual_text = match actual.value {
        DecimalValue(value) => value.to_string()
        IntValue(value) => value.to_string()
        BoolValue(value) => value.to_string()
        TextValue(value) => value
      }
      return Err(
        "result mismatch: expected " + expected + ", actual " + actual_text,
      )
    }
  }
  guard flags_match(actual_flags, case.conditions()) else {
    return Err(
      "status flags mismatch: expected " +
      case.conditions().join(" ") +
      ", actual " +
      decimal_flags_text(actual_flags),
    )
  }
  Ok(())
}

///|
fn execute_case(case : GdaCase) -> CaseResult {
  let disposition = case_disposition(case)
  match disposition {
    Executable => ()
    _ =>
      return { id: case.id(), disposition, passed: false, message: "skipped" }
  }
  let result = @numeric_expr.evaluate(
    case.expression(),
    fn(literal) {
      if case.normalized_operation() == "tosci" ||
        case.normalized_operation() == "toeng" {
        Ok(evaluated_decimal(@decimal.Decimal::zero()))
      } else {
        match decode_decimal(literal.raw(), case.context()) {
          Some(value) => Ok(evaluated_decimal(value))
          None => Err("invalid decimal operand " + literal.raw())
        }
      }
    },
    fn(operation, arguments) {
      invoke_decimal_operation(case, operation, arguments)
    },
  )
  match result {
    Ok(actual) =>
      match compare_evaluated(case, actual) {
        Ok(_) => { id: case.id(), disposition, passed: true, message: "" }
        Err(message) => { id: case.id(), disposition, passed: false, message }
      }
    Err(_) =>
      {
        id: case.id(),
        disposition,
        passed: false,
        message: "evaluation failed",
      }
  }
}

///|
fn case_filter_matches(id : String, filter : String) -> Bool {
  if filter.length() == 0 {
    return true
  }
  for selector_view in filter.split(",") {
    let selector = selector_view.to_owned().trim().to_owned()
    let range = selector.split("..").to_array()
    if range.length() == 1 && id == selector {
      return true
    }
    if range.length() == 2 {
      let start = range[0].to_owned()
      let finish = range[1].to_owned()
      if id.length() == start.length() &&
        id.length() == finish.length() &&
        id >= start &&
        id <= finish {
        return true
      }
    }
  }
  false
}

///|
pub fn execute_documents(
  documents : Array[GdaDocument],
  options? : RunOptions = RunOptions::new(),
) -> RunSummary {
  let results : Array[CaseResult] = []
  let mut total_cases = 0
  let mut selected_cases = 0
  let mut executable_cases = 0
  let mut passed_cases = 0
  let mut failed_cases = 0
  let mut skipped_cases = 0
  let mut diagnostic_cases = 0
  let mut legacy_cases = 0
  let mut unsupported_cases = 0
  let mut ordinal = 0
  for document in documents {
    for case in document.cases() {
      if !case_filter_matches(case.id(), options.case_filter()) {
        continue
      }
      total_cases += 1
      let selected = ordinal % options.shard_count() == options.shard_index()
      ordinal += 1
      if !selected {
        continue
      }
      selected_cases += 1
      let result = execute_case(case)
      results.push(result)
      match result.disposition() {
        Executable => {
          executable_cases += 1
          if result.passed() {
            passed_cases += 1
          } else {
            failed_cases += 1
          }
        }
        Diagnostic(_) => {
          skipped_cases += 1
          diagnostic_cases += 1
        }
        Legacy(_) => {
          skipped_cases += 1
          legacy_cases += 1
        }
        Unsupported(_) => {
          skipped_cases += 1
          unsupported_cases += 1
        }
      }
    }
  }
  {
    total_cases,
    selected_cases,
    executable_cases,
    passed_cases,
    failed_cases,
    skipped_cases,
    diagnostic_cases,
    legacy_cases,
    unsupported_cases,
    results,
  }
}
