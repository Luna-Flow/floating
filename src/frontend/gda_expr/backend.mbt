///|
priv enum RuntimeValue {
  DecimalValue(@decimal_gda.Decimal)
  IntValue(Int)
  BoolValue(Bool)
  TextValue(String)
}

///|
priv struct RuntimeFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
}

///|
priv struct EvaluatedValue {
  value : RuntimeValue
  flags : RuntimeFlags
}

///|
priv struct ResolvedContext {
  decimal : @decimal_gda.DecimalContext
  gda : @decimal_gda.GdaContext
}

///|
fn evaluated_decimal(
  value : @decimal_gda.Decimal,
  flags? : @decimal_gda.DecimalFlags = @decimal_gda.DecimalFlags::new(),
) -> EvaluatedValue {
  { value: DecimalValue(value), flags: runtime_flags_from_decimal(flags) }
}

///|
fn RuntimeFlags::none() -> RuntimeFlags {
  {
    inexact: false,
    rounded: false,
    lost_digits: false,
    invalid_operation: false,
    division_by_zero: false,
    overflow: false,
    underflow: false,
    subnormal: false,
    clamped: false,
    conversion_syntax: false,
    division_impossible: false,
    division_undefined: false,
    invalid_context: false,
  }
}

///|
fn RuntimeFlags::combine(
  self : RuntimeFlags,
  other : RuntimeFlags,
) -> RuntimeFlags {
  {
    inexact: self.inexact || other.inexact,
    rounded: self.rounded || other.rounded,
    lost_digits: self.lost_digits || other.lost_digits,
    invalid_operation: self.invalid_operation || other.invalid_operation,
    division_by_zero: self.division_by_zero || other.division_by_zero,
    overflow: self.overflow || other.overflow,
    underflow: self.underflow || other.underflow,
    subnormal: self.subnormal || other.subnormal,
    clamped: self.clamped || other.clamped,
    conversion_syntax: self.conversion_syntax || other.conversion_syntax,
    division_impossible: self.division_impossible || other.division_impossible,
    division_undefined: self.division_undefined || other.division_undefined,
    invalid_context: self.invalid_context || other.invalid_context,
  }
}

///|
fn runtime_flags_from_decimal(
  flags : @decimal_gda.DecimalFlags,
) -> RuntimeFlags {
  {
    inexact: flags.inexact,
    rounded: flags.rounded,
    lost_digits: flags.lost_digits,
    invalid_operation: flags.invalid_operation,
    division_by_zero: flags.division_by_zero,
    overflow: flags.overflow,
    underflow: flags.underflow,
    subnormal: flags.subnormal,
    clamped: flags.clamped,
    conversion_syntax: flags.conversion_syntax,
    division_impossible: flags.division_impossible,
    division_undefined: flags.division_undefined,
    invalid_context: flags.invalid_context,
  }
}

///|
fn runtime_flags_from_gda(flags : @decimal_gda.GdaFlags) -> RuntimeFlags {
  {
    inexact: flags.inexact,
    rounded: flags.rounded,
    lost_digits: flags.lost_digits,
    invalid_operation: flags.invalid_operation,
    division_by_zero: flags.division_by_zero,
    overflow: flags.overflow,
    underflow: flags.underflow,
    subnormal: flags.subnormal,
    clamped: flags.clamped,
    conversion_syntax: flags.conversion_syntax,
    division_impossible: flags.division_impossible,
    division_undefined: flags.division_undefined,
    invalid_context: flags.invalid_context,
  }
}

///|
fn evaluated_gda_decimal(
  outcome : @decimal_gda.GdaOutcome[@decimal_gda.Decimal],
) -> EvaluatedValue {
  {
    value: DecimalValue(outcome.value()),
    flags: runtime_flags_from_gda(outcome.raised()),
  }
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
) -> @decimal_gda.GdaInterchangeFormat? {
  match (context.precision(), context.min_exponent(), context.max_exponent()) {
    (7, -95, 96) => Some(@decimal_gda.Decimal32)
    (16, -383, 384) => Some(@decimal_gda.Decimal64)
    (34, -6143, 6144) => Some(@decimal_gda.Decimal128)
    _ => None
  }
}

///|
fn resolve_context(context : GdaContext) -> ResolvedContext? {
  let normalized = normalized_word(context.rounding())
  let (rounding, decimal_rounding, gda_rounding) = match normalized {
    "halfeven" =>
      (
        @lf_arith.RoundingMode::ToNearestEven,
        @decimal_gda.DecimalRoundingMode::HalfEven,
        @decimal_gda.GdaRoundingMode::HalfEven,
      )
    "halfup" =>
      (
        @lf_arith.RoundingMode::ToNearestEven,
        @decimal_gda.DecimalRoundingMode::HalfUp,
        @decimal_gda.GdaRoundingMode::HalfUp,
      )
    "halfdown" =>
      (
        @lf_arith.RoundingMode::ToNearestEven,
        @decimal_gda.DecimalRoundingMode::HalfDown,
        @decimal_gda.GdaRoundingMode::HalfDown,
      )
    "down" | "towardzero" =>
      (
        @lf_arith.RoundingMode::TowardZero,
        @decimal_gda.DecimalRoundingMode::Down,
        @decimal_gda.GdaRoundingMode::Down,
      )
    "ceiling" | "towardpositive" =>
      (
        @lf_arith.RoundingMode::TowardPositive,
        @decimal_gda.DecimalRoundingMode::Ceiling,
        @decimal_gda.GdaRoundingMode::Ceiling,
      )
    "floor" | "towardnegative" =>
      (
        @lf_arith.RoundingMode::TowardNegative,
        @decimal_gda.DecimalRoundingMode::Floor,
        @decimal_gda.GdaRoundingMode::Floor,
      )
    "up" | "awayfromzero" =>
      (
        @lf_arith.RoundingMode::AwayFromZero,
        @decimal_gda.DecimalRoundingMode::Up,
        @decimal_gda.GdaRoundingMode::Up,
      )
    "05up" | "zerofiveup" =>
      (
        @lf_arith.RoundingMode::TowardZero,
        @decimal_gda.DecimalRoundingMode::ZeroFiveUp,
        @decimal_gda.GdaRoundingMode::ZeroFiveUp,
      )
    _ => return None
  }
  Some({
    decimal: @decimal_gda.DecimalContext::new(
      precision=context.precision(),
      rounding~,
      decimal_rounding~,
      e_min=context.min_exponent(),
      e_max=context.max_exponent(),
      clamp=context.clamp(),
      extended=context.extended(),
    ),
    gda: @decimal_gda.GdaContext::new(
      precision=context.precision(),
      rounding=gda_rounding,
      e_min=context.min_exponent(),
      e_max=context.max_exponent(),
      clamp=context.clamp(),
      extended=context.extended(),
      traps=@decimal_gda.GdaTrapSet::none(),
    ),
  })
}

///|
let decimal32_gda_context : @decimal_gda.DecimalContext = @decimal_gda.DecimalContext::decimal32()

///|
let decimal64_gda_context : @decimal_gda.DecimalContext = @decimal_gda.DecimalContext::decimal64()

///|
let decimal128_gda_context : @decimal_gda.DecimalContext = @decimal_gda.DecimalContext::decimal128()

///|
fn decode_decimal(
  token : String,
  context : GdaContext,
) -> @decimal_gda.Decimal? {
  let normalized = normalize_token(token)
  if normalized.has_prefix("32#") {
    Some(
      @decimal_gda.Decimal::from_string_ctx(
        normalized[3:].to_owned(),
        decimal32_gda_context,
      ).0,
    )
  } else if normalized.has_prefix("64#") {
    Some(
      @decimal_gda.Decimal::from_string_ctx(
        normalized[3:].to_owned(),
        decimal64_gda_context,
      ).0,
    )
  } else if normalized.has_prefix("128#") {
    Some(
      @decimal_gda.Decimal::from_string_ctx(
        normalized[4:].to_owned(),
        decimal128_gda_context,
      ).0,
    )
  } else if normalized.has_prefix("#") {
    match interchange_format(context) {
      Some(format) =>
        @decimal_gda.Decimal::from_interchange_hex(normalized, format)
      None => None
    }
  } else {
    @decimal_gda.Decimal::from_string(
      normalized,
      precision=Int::max(64, context.precision()),
    )
  }
}

///|
fn decimal_argument(
  values : Array[EvaluatedValue],
  index : Int,
) -> @decimal_gda.Decimal? {
  guard index >= 0 && index < values.length() else { return None }
  match values[index].value {
    DecimalValue(value) => Some(value)
    _ => None
  }
}

///|
fn unary_gda_decimal(
  values : Array[EvaluatedValue],
  call : (@decimal_gda.Decimal) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal],
) -> Result[EvaluatedValue, String] {
  guard decimal_argument(values, 0) is Some(value) else {
    return Err("operation expects one decimal operand")
  }
  Ok(evaluated_gda_decimal(call(value)))
}

///|
fn binary_gda_decimal(
  values : Array[EvaluatedValue],
  call : (@decimal_gda.Decimal, @decimal_gda.Decimal) -> @decimal_gda.GdaOutcome[
    @decimal_gda.Decimal,
  ],
) -> Result[EvaluatedValue, String] {
  guard decimal_argument(values, 0) is Some(left) &&
    decimal_argument(values, 1) is Some(right) else {
    return Err("operation expects two decimal operands")
  }
  Ok(evaluated_gda_decimal(call(left, right)))
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
fn case_disposition(
  case : GdaCase,
  context : ResolvedContext?,
) -> CaseDisposition {
  for token in case.operands() {
    if token == "#" {
      return Diagnostic("diagnostic interchange/non-scalar row")
    }
    if token == "?" {
      return Diagnostic("diagnostic legacy non-decimal operand ?")
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
  } else if context is None {
    Unsupported("unsupported rounding " + case.context().rounding())
  } else {
    Executable
  }
}

///|
fn flags_match(actual : RuntimeFlags, conditions : Array[String]) -> Bool {
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
fn decimal_flags_text(flags : RuntimeFlags) -> String {
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
  context : ResolvedContext,
  operation : @numeric_expr.Operation,
  values : Array[EvaluatedValue],
) -> Result[EvaluatedValue, String] {
  let op = operation.name()
  let raws = case.operands()
  if op == "apply" && raws.length() >= 1 {
    let raw = raws[0]
    if case.expected().has_prefix("#") {
      guard interchange_format(case.context()) is Some(format) else {
        return Err("interchange apply requires a concrete format")
      }
      let encoded = if raw.has_prefix("#") {
        match @decimal_gda.GdaInterchange::from_hex(raw, format) {
          Some(value) =>
            Some((value.canonical().to_hex(), RuntimeFlags::none()))
          None => None
        }
      } else {
        match decode_decimal(raw, case.context()) {
          Some(value) => {
            let encoded = value.to_interchange_hex(format)
            Some((encoded.0, runtime_flags_from_decimal(encoded.1)))
          }
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
        @decimal_gda.GdaInterchange::from_hex(raw, format) is Some(value) else {
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
      @decimal_gda.GdaInterchange::from_hex(raws[0], format) is Some(raw) else {
      return Err("invalid interchange copy operand")
    }
    let copied = match op {
      "copy" => raw.copy()
      "copyabs" => raw.copy_abs()
      _ => raw.copy_negate()
    }
    return Ok({ value: TextValue(copied.to_hex()), flags: RuntimeFlags::none() })
  }
  if op == "copysign" &&
    raws.length() >= 2 &&
    raws[0].has_prefix("#") &&
    case.expected().has_prefix("#") {
    guard interchange_format(case.context()) is Some(format) &&
      @decimal_gda.GdaInterchange::from_hex(raws[0], format) is Some(left) else {
      return Err("invalid interchange copysign operand")
    }
    let right = if raws[1].has_prefix("#") {
      @decimal_gda.GdaInterchange::from_hex(raws[1], format)
    } else {
      match decimal_argument(values, 1) {
        Some(decimal) =>
          Some(@decimal_gda.GdaInterchange::from_decimal(decimal, format).0)
        None => None
      }
    }
    guard right is Some(right) else {
      return Err("invalid interchange copysign sign operand")
    }
    return Ok({
      value: TextValue(left.copy_sign(right).to_hex()),
      flags: RuntimeFlags::none(),
    })
  }
  match op {
    "add" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.add(a, b, context.gda)
      })
    "subtract" | "sub" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.subtract(a, b, context.gda)
      })
    "multiply" | "mul" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.multiply(a, b, context.gda)
      })
    "divide" | "div" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.divide(a, b, context.gda)
      })
    "power" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.power(a, b, context.gda)
      })
    "divideint" | "divideinteger" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.divide_integer(a, b, context.gda)
      })
    "remainder" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.remainder(a, b, context.gda)
      })
    "remaindernear" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.remainder_near(a, b, context.gda)
      })
    "quantize" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.quantize(a, b, context.gda)
      })
    "rescale" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.rescale(a, b, context.gda)
      })
    "compare" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.compare(a, b, context.gda)
      })
    "comparesig" | "comparesignal" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.compare_signal(a, b, context.gda)
      })
    "min" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.min(a, b, context.gda)
      })
    "max" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.max(a, b, context.gda)
      })
    "minmag" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.min_mag(a, b, context.gda)
      })
    "maxmag" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.max_mag(a, b, context.gda)
      })
    "nexttoward" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.next_toward(a, b, context.gda)
      })
    "scaleb" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.scaleb(a, b, context.gda)
      })
    "shift" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.shift(a, b, context.gda)
      })
    "rotate" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.rotate(a, b, context.gda)
      })
    "and" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.logical_and(a, b, context.gda)
      })
    "or" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.logical_or(a, b, context.gda)
      })
    "xor" =>
      binary_gda_decimal(values, fn(a, b) {
        @decimal_gda.logical_xor(a, b, context.gda)
      })
    "apply" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.apply(a, context.gda) })
    "plus" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.plus(a, context.gda) })
    "minus" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.minus(a, context.gda) })
    "abs" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.abs(a, context.gda) })
    "reduce" | "normalize" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.reduce(a, context.gda) })
    "nextplus" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.next_plus(a, context.gda) })
    "nextminus" =>
      unary_gda_decimal(values, fn(a) {
        @decimal_gda.next_minus(a, context.gda)
      })
    "exp" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.exp(a, context.gda) })
    "ln" => unary_gda_decimal(values, fn(a) { @decimal_gda.ln(a, context.gda) })
    "log10" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.log10(a, context.gda) })
    "logb" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.logb(a, context.gda) })
    "invert" =>
      unary_gda_decimal(values, fn(a) {
        @decimal_gda.logical_invert(a, context.gda)
      })
    "sqrt" | "squareroot" =>
      unary_gda_decimal(values, fn(a) { @decimal_gda.sqrt(a, context.gda) })
    "tointegralx" | "tointegralexact" =>
      unary_gda_decimal(values, fn(a) {
        @decimal_gda.to_integral_exact(a, context.gda)
      })
    "tointegral" | "tointegralvalue" =>
      unary_gda_decimal(values, fn(a) {
        @decimal_gda.to_integral_value(a, context.gda)
      })
    "fma" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) &&
        decimal_argument(values, 2) is Some(c) else {
        return Err("fma expects three decimal operands")
      }
      Ok(evaluated_gda_decimal(@decimal_gda.fma(a, b, c, context.gda)))
    }
    "comparetotal" | "comparetot" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("comparetotal expects two operands")
      }
      let outcome = @decimal_gda.compare_total(a, b, context.gda)
      Ok({
        value: IntValue(outcome.value()),
        flags: runtime_flags_from_gda(outcome.raised()),
      })
    }
    "comparetotalmag" | "comparetotmag" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("comparetotalmag expects two operands")
      }
      let outcome = @decimal_gda.compare_total_magnitude(a, b, context.gda)
      Ok({
        value: IntValue(outcome.value()),
        flags: runtime_flags_from_gda(outcome.raised()),
      })
    }
    "samequantum" => {
      guard decimal_argument(values, 0) is Some(a) &&
        decimal_argument(values, 1) is Some(b) else {
        return Err("samequantum expects two operands")
      }
      let outcome = @decimal_gda.same_quantum(a, b, context.gda)
      Ok({
        value: BoolValue(outcome.value()),
        flags: runtime_flags_from_gda(outcome.raised()),
      })
    }
    "trim" | "copy" | "copyabs" | "copynegate" | "copyneg" => {
      guard decimal_argument(values, 0) is Some(value) else {
        return Err("copy operation expects one operand")
      }
      let result = match op {
        "trim" =>
          if !context.decimal.extended() && value.is_zero() {
            @decimal_gda.Decimal::zero(precision=context.decimal.precision())
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
      let outcome = @decimal_gda.class_name(value, context.gda)
      Ok({
        value: TextValue(outcome.value()),
        flags: runtime_flags_from_gda(outcome.raised()),
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
      if op == "isnormal" {
        let outcome = @decimal_gda.is_normal(value, context.gda)
        return Ok({
          value: BoolValue(outcome.value()),
          flags: runtime_flags_from_gda(outcome.raised()),
        })
      }
      if op == "issubnormal" {
        let outcome = @decimal_gda.is_subnormal(value, context.gda)
        return Ok({
          value: BoolValue(outcome.value()),
          flags: runtime_flags_from_gda(outcome.raised()),
        })
      }
      let result = match op {
        "iscanonical" => value.is_canonical()
        "isfinite" => value.is_finite()
        "isinfinite" => value.is_infinite()
        "isnan" => value.is_nan()
        "isqnan" => value.is_qnan()
        "issnan" => value.is_snan()
        "isnegative" => value.is_negative()
        "issigned" => value.is_signed()
        _ => value.is_zero()
      }
      Ok({ value: BoolValue(result), flags: RuntimeFlags::none() })
    }
    "tosci" | "toeng" => {
      guard raws is [raw, ..] else {
        return Err("string conversion expects one operand")
      }
      let (text, flags) = if op == "tosci" {
        @decimal_gda.Decimal::to_sci_string(raw, context.decimal)
      } else {
        @decimal_gda.Decimal::to_eng_string(raw, context.decimal)
      }
      Ok({ value: TextValue(text), flags: runtime_flags_from_decimal(flags) })
    }
    "canonical" => {
      guard raws is [raw, ..] &&
        interchange_format(case.context()) is Some(format) else {
        return Err("canonical requires an interchange operand and context")
      }
      let value = if raw.has_prefix("#") {
        @decimal_gda.GdaInterchange::from_hex(raw, format)
      } else {
        match decode_decimal(raw, case.context()) {
          Some(decimal) =>
            Some(@decimal_gda.GdaInterchange::from_decimal(decimal, format).0)
          None => None
        }
      }
      guard value is Some(value) else {
        return Err("invalid interchange encoding")
      }
      Ok({
        value: TextValue(value.canonical().to_hex()),
        flags: RuntimeFlags::none(),
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
      actual.flags.combine(
        runtime_flags_from_decimal(
          value.to_interchange_hex(@decimal_gda.Decimal32).1,
        ),
      )
    DecimalValue(value) if expected.has_prefix("64#") =>
      actual.flags.combine(
        runtime_flags_from_decimal(
          value.to_interchange_hex(@decimal_gda.Decimal64).1,
        ),
      )
    DecimalValue(value) if expected.has_prefix("128#") =>
      actual.flags.combine(
        runtime_flags_from_decimal(
          value.to_interchange_hex(@decimal_gda.Decimal128).1,
        ),
      )
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
fn execute_case(
  case : GdaCase,
  resolved_context : ResolvedContext?,
) -> CaseResult {
  let disposition = case_disposition(case, resolved_context)
  match disposition {
    Executable => ()
    _ => return case_result(case.id(), disposition, false, message="skipped")
  }
  let context = match resolved_context {
    Some(value) => value
    None => return case_result(case.id(), disposition, false, message="skipped")
  }
  let result = @numeric_expr.evaluate(
    case.expression(),
    fn(literal) {
      if case.normalized_operation() == "tosci" ||
        case.normalized_operation() == "toeng" {
        Ok(evaluated_decimal(@decimal_gda.Decimal::zero()))
      } else {
        match decode_decimal(literal.raw(), case.context()) {
          Some(value) => Ok(evaluated_decimal(value))
          None => Err("invalid decimal operand " + literal.raw())
        }
      }
    },
    fn(operation, arguments) {
      invoke_decimal_operation(case, context, operation, arguments)
    },
  )
  match result {
    Ok(actual) =>
      match compare_evaluated(case, actual) {
        Ok(_) => case_result(case.id(), disposition, true)
        Err(message) => case_result(case.id(), disposition, false, message~)
      }
    Err(_) =>
      case_result(case.id(), disposition, false, message="evaluation failed")
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
  let mut ordinal = 0
  let mut cached_model_context : GdaContext? = None
  let mut cached_resolved_context : ResolvedContext? = None
  for document in documents {
    for case in document.cases() {
      if !case_filter_matches(case.id(), options.case_filter()) {
        continue
      }
      total_cases += 1
      let selected = options.shard.selects(ordinal)
      ordinal += 1
      if !selected {
        continue
      }
      let model_context = case.context()
      let resolved_context = match cached_model_context {
        Some(previous) if previous == model_context => cached_resolved_context
        _ => {
          let resolved = resolve_context(model_context)
          cached_model_context = Some(model_context)
          cached_resolved_context = resolved
          resolved
        }
      }
      let result = execute_case(case, resolved_context)
      results.push(result)
    }
  }
  {
    inner: @conformance.RunSummary::from_results(
      total_cases,
      results.map(fn(result) { result.inner }),
    ),
  }
}
