///|
pub(all) enum TestFloatOperation {
  Add
  Subtract
  Multiply
  Divide
  SquareRoot
} derive(Eq, Debug)

///|
pub struct TestFloatSpec {
  priv function_name : String
  priv format : @bin_float.BinaryInterchangeFormat
  priv operation : TestFloatOperation
  priv rounding : @bin_float.BinaryRoundingMode
  priv tininess : @bin_float.TininessDetection
} derive(Eq, Debug)

///|
pub struct TestFloatCase {
  priv id : String
  priv line : Int
  priv operands : Array[@bin_float.BinaryInterchange]
  priv expected : @bin_float.BinaryInterchange
  priv expected_flags : Int
}

///|
pub struct TestFloatDocument {
  priv source : String
  priv spec : TestFloatSpec
  priv cases : Array[TestFloatCase]
}

///|
pub struct ParseDiagnostic {
  priv location : @conformance.SourceLocation
  priv message : String
} derive(Eq, Debug)

///|
pub struct CaseResult {
  priv inner : @conformance.CaseResult
}

///|
pub struct RunOptions {
  priv shard : @conformance.ShardSpec
}

///|
pub struct RunSummary {
  priv inner : @conformance.RunSummary
}

///|
fn normalized_word(source : String) -> String {
  let builder = StringBuilder::new()
  for character in source {
    if character >= 'A' && character <= 'Z' {
      builder.write_char(
        Int::unsafe_to_char(character.to_int() + ('a'.to_int() - 'A'.to_int())),
      )
    } else if character != '-' && character != '_' && character != ' ' {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn tokenize_line(source : String) -> Array[String] {
  let tokens : Array[String] = []
  let builder = StringBuilder::new()
  let mut has_content = false
  for character in source {
    if character == ' ' ||
      character == '\t' ||
      character == '\r' ||
      character == '\n' {
      if has_content {
        tokens.push(builder.to_string())
        builder.reset()
        has_content = false
      }
    } else {
      builder.write_char(character)
      has_content = true
    }
  }
  if has_content {
    tokens.push(builder.to_string())
  }
  tokens
}

///|
fn parse_format(source : String) -> @bin_float.BinaryInterchangeFormat? {
  match normalized_word(source) {
    "f16" => Some(@bin_float.BinaryInterchangeFormat::Binary16)
    "f32" => Some(@bin_float.BinaryInterchangeFormat::Binary32)
    "f64" => Some(@bin_float.BinaryInterchangeFormat::Binary64)
    "f128" => Some(@bin_float.BinaryInterchangeFormat::Binary128)
    _ => None
  }
}

///|
fn parse_operation(source : String) -> TestFloatOperation? {
  match normalized_word(source) {
    "add" => Some(Add)
    "sub" => Some(Subtract)
    "mul" => Some(Multiply)
    "div" => Some(Divide)
    "sqrt" => Some(SquareRoot)
    _ => None
  }
}

///|
fn parse_rounding(source : String) -> @bin_float.BinaryRoundingMode? {
  match normalized_word(source) {
    "rneareven" | "neareven" | "roundtiestoeven" =>
      Some(@bin_float.BinaryRoundingMode::RoundTiesToEven)
    "rnearmaxmag" | "nearmaxmag" | "roundtiestoaway" =>
      Some(@bin_float.BinaryRoundingMode::RoundTiesToAway)
    "rminmag" | "minmag" | "roundtowardzero" =>
      Some(@bin_float.BinaryRoundingMode::RoundTowardZero)
    "rmin" | "min" | "roundtowardnegative" =>
      Some(@bin_float.BinaryRoundingMode::RoundTowardNegative)
    "rmax" | "max" | "roundtowardpositive" =>
      Some(@bin_float.BinaryRoundingMode::RoundTowardPositive)
    _ => None
  }
}

///|
fn parse_tininess(source : String) -> @bin_float.TininessDetection? {
  match normalized_word(source) {
    "before" | "tininessbefore" =>
      Some(@bin_float.TininessDetection::BeforeRounding)
    "after" | "tininessafter" =>
      Some(@bin_float.TininessDetection::AfterRounding)
    _ => None
  }
}

///|
pub fn TestFloatSpec::parse(
  function_name : String,
  rounding : String,
  tininess? : String = "after",
) -> Result[TestFloatSpec, String] {
  let parts = function_name.split("_").to_array()
  guard parts.length() == 2 else {
    return Err("unsupported TestFloat function name " + function_name)
  }
  guard parse_format(parts[0].to_owned()) is Some(format) else {
    return Err("unsupported TestFloat format " + parts[0].to_owned())
  }
  guard parse_operation(parts[1].to_owned()) is Some(operation) else {
    return Err("unsupported TestFloat operation " + parts[1].to_owned())
  }
  guard parse_rounding(rounding) is Some(rounding) else {
    return Err("unsupported TestFloat rounding mode " + rounding)
  }
  guard parse_tininess(tininess) is Some(tininess) else {
    return Err("unsupported TestFloat tininess mode " + tininess)
  }
  Ok({ function_name, format, operation, rounding, tininess })
}

///|
pub fn TestFloatSpec::function_name(self : TestFloatSpec) -> String {
  self.function_name
}

///|
pub fn TestFloatSpec::format(
  self : TestFloatSpec,
) -> @bin_float.BinaryInterchangeFormat {
  self.format
}

///|
pub fn TestFloatSpec::operation(self : TestFloatSpec) -> TestFloatOperation {
  self.operation
}

///|
pub fn TestFloatSpec::rounding(
  self : TestFloatSpec,
) -> @bin_float.BinaryRoundingMode {
  self.rounding
}

///|
pub fn TestFloatSpec::tininess(
  self : TestFloatSpec,
) -> @bin_float.TininessDetection {
  self.tininess
}

///|
pub fn TestFloatCase::id(self : TestFloatCase) -> String {
  self.id
}

///|
pub fn TestFloatCase::line(self : TestFloatCase) -> Int {
  self.line
}

///|
pub fn TestFloatDocument::source(self : TestFloatDocument) -> String {
  self.source
}

///|
pub fn TestFloatDocument::spec(self : TestFloatDocument) -> TestFloatSpec {
  self.spec
}

///|
pub fn TestFloatDocument::cases(
  self : TestFloatDocument,
) -> Array[TestFloatCase] {
  self.cases.copy()
}

///|
pub fn TestFloatDocument::case_count(self : TestFloatDocument) -> Int {
  self.cases.length()
}

///|
pub fn ParseDiagnostic::source(self : ParseDiagnostic) -> String {
  self.location.source()
}

///|
pub fn ParseDiagnostic::line(self : ParseDiagnostic) -> Int {
  self.location.line()
}

///|
pub fn ParseDiagnostic::message(self : ParseDiagnostic) -> String {
  self.message
}

///|
fn parse_flags(source : String) -> Int? {
  guard source.length() == 2 else { return None }
  for character in source {
    guard character.is_ascii_hexdigit() else { return None }
  }
  Some(@bigint.BigInt::from_string(source, radix=16).to_int())
}

///|
pub fn parse_testfloat(
  source : String,
  text : String,
  spec : TestFloatSpec,
) -> Result[TestFloatDocument, Array[ParseDiagnostic]] {
  let cases : Array[TestFloatCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let expected_operands = match spec.operation {
    SquareRoot => 1
    _ => 2
  }
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize_line(line)
    if tokens.length() != expected_operands + 2 {
      diagnostics.push({
        location: @conformance.SourceLocation::new(source, line_number),
        message: "unexpected TestFloat field count",
      })
      continue
    }
    let operands : Array[@bin_float.BinaryInterchange] = []
    let mut valid = true
    for index in 0..<expected_operands {
      match @bin_float.BinaryInterchange::from_hex(tokens[index], spec.format) {
        Some(value) => operands.push(value)
        None => valid = false
      }
    }
    let expected = @bin_float.BinaryInterchange::from_hex(
      tokens[expected_operands],
      spec.format,
    )
    let flags = parse_flags(tokens[expected_operands + 1])
    match (valid, expected, flags) {
      (true, Some(expected), Some(expected_flags)) =>
        cases.push({
          id: spec.function_name + ":" + line_number.to_string(),
          line: line_number,
          operands,
          expected,
          expected_flags,
        })
      _ =>
        diagnostics.push({
          location: @conformance.SourceLocation::new(source, line_number),
          message: "invalid TestFloat hexadecimal field",
        })
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, spec, cases })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn RunOptions::new(
  shard_count? : Int = 1,
  shard_index? : Int = 0,
) -> RunOptions {
  { shard: @conformance.ShardSpec::new(shard_count, shard_index) }
}

///|
pub fn RunOptions::shard_count(self : RunOptions) -> Int {
  self.shard.count()
}

///|
pub fn RunOptions::shard_index(self : RunOptions) -> Int {
  self.shard.index()
}

///|
pub fn CaseResult::id(self : CaseResult) -> String {
  self.inner.id()
}

///|
pub fn CaseResult::passed(self : CaseResult) -> Bool {
  self.inner.passed()
}

///|
pub fn CaseResult::message(self : CaseResult) -> String {
  self.inner.message()
}

///|
fn executable_result(
  id : String,
  passed : Bool,
  message? : String = "",
) -> CaseResult {
  { inner: @conformance.CaseResult::executable(id, passed, message~) }
}

///|
fn execute_case(case : TestFloatCase, spec : TestFloatSpec) -> CaseResult {
  let context = spec.format.context(
    rounding=spec.rounding,
    tininess=spec.tininess,
  )
  let operands = case.operands.map(fn(value) { value.to_bin_float() })
  let (actual, flags) = match (spec.operation, operands) {
    (Add, [left, right]) => left.add_ctx(right, context)
    (Subtract, [left, right]) => left.sub_ctx(right, context)
    (Multiply, [left, right]) => left.mul_ctx(right, context)
    (Divide, [left, right]) => left.div_ctx(right, context)
    (SquareRoot, [operand]) => operand.sqrt_ctx(context)
    _ => abort("invalid parsed TestFloat operand arity")
  }
  let (encoded, encoding_flags) = @bin_float.BinaryInterchange::from_bin_float(
    actual,
    spec.format,
    rounding=spec.rounding,
    tininess=spec.tininess,
  )
  let actual_flags = flags.combine(encoding_flags).to_testfloat_bits()
  let expected_value = case.expected.to_bin_float()
  let expected_is_nan = expected_value.is_quiet_nan() ||
    expected_value.is_signaling_nan()
  let value_matches = if expected_is_nan {
    actual.is_quiet_nan()
  } else {
    encoded.to_hex() == case.expected.to_hex()
  }
  if !value_matches {
    return executable_result(
      case.id,
      false,
      message="value mismatch: expected " +
        case.expected.to_hex() +
        ", actual " +
        encoded.to_hex(),
    )
  }
  if actual_flags != case.expected_flags {
    return executable_result(
      case.id,
      false,
      message="flags mismatch: expected " +
        case.expected_flags.to_string() +
        ", actual " +
        actual_flags.to_string(),
    )
  }
  executable_result(case.id, true)
}

///|
pub fn execute_document(
  document : TestFloatDocument,
  options? : RunOptions = RunOptions::new(),
) -> RunSummary {
  let results : Array[CaseResult] = []
  for index, case in document.cases {
    if !options.shard.selects(index) {
      continue
    }
    let result = execute_case(case, document.spec)
    results.push(result)
  }
  {
    inner: @conformance.RunSummary::from_results(
      document.cases.length(),
      results.map(fn(result) { result.inner }),
    ),
  }
}

///|
pub fn RunSummary::total_cases(self : RunSummary) -> Int {
  self.inner.total_cases()
}

///|
pub fn RunSummary::selected_cases(self : RunSummary) -> Int {
  self.inner.selected_cases()
}

///|
pub fn RunSummary::passed_cases(self : RunSummary) -> Int {
  self.inner.passed_cases()
}

///|
pub fn RunSummary::failed_cases(self : RunSummary) -> Int {
  self.inner.failed_cases()
}

///|
pub fn RunSummary::results(self : RunSummary) -> Array[CaseResult] {
  self.inner.results().map(fn(inner) { { inner, } })
}

///|
pub fn RunSummary::success(self : RunSummary) -> Bool {
  self.inner.success()
}
