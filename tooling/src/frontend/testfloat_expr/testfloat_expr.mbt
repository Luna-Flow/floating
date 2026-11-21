///|
/// The five flags as the TestFloat bit mask: inexact 0x01, underflow 0x02,
/// overflow 0x04, divideByZero 0x08, invalid 0x10.
fn testfloat_flag_bits(flags : @bin_float.BinaryFlags) -> Int32 {
  (if flags.inexact() { 0x01 } else { 0 }) |
  (if flags.underflow() { 0x02 } else { 0 }) |
  (if flags.overflow() { 0x04 } else { 0 }) |
  (if flags.division_by_zero() { 0x08 } else { 0 }) |
  (if flags.invalid_operation() { 0x10 } else { 0 })
}

///|
#derive(Eq, Debug)
pub(all) enum TestFloatOperation {
  Add
  Subtract
  Multiply
  Divide
  SquareRoot
  MulAdd
  Remainder
  RoundToInt
  ToInt32
  ToInt64
  ToUInt32
  ToUInt64
  /// `f64_to_f32` and the other format conversions: the operand is in the format of
  /// the function name's prefix, the result in this format.
  ConvertFormat(@bin_float.BinaryInterchangeFormat)
  Equal
  LessEqual
  Less
  EqualSignaling
  LessEqualQuiet
  LessQuiet
}

///|
#derive(Eq, Debug)
pub struct TestFloatSpec {
  priv function_name : String
  priv format : @bin_float.BinaryInterchangeFormat
  priv operation : TestFloatOperation
  priv rounding : @bin_float.BinaryRoundingMode
  priv tininess : @bin_float.TininessDetection
  priv exact : Bool
}

///|
/// Result column of a TestFloat vector: an interchange encoding, an integer
/// in hexadecimal, or a 0/1 comparison result.
priv enum TestFloatExpected {
  /// The text of the column as written in the vector (the number of digits is
  /// checked when the vector is read).
  Encoded(String)
  Integer(UInt64)
  Boolean(Bool)
}

///|
pub struct TestFloatCase {
  priv id : String
  priv line : Int32
  priv operands : Array[@bin_float.BinaryInterchange]
  priv expected : TestFloatExpected
  priv expected_flags : Int32
}

///|
pub struct TestFloatDocument {
  priv source : String
  priv spec : TestFloatSpec
  priv cases : Array[TestFloatCase]
}

///|
#derive(Eq, Debug)
pub struct ParseDiagnostic {
  priv location : @conformance.SourceLocation
  priv message : String
}

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
  let builder = StringBuilder()
  for character in source {
    if character >= 'A' && character <= 'Z' {
      builder.write_char(
        Int32::unsafe_to_char(
          character.to_int() + ('a'.to_int() - 'A'.to_int()),
        ),
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
  let builder = StringBuilder()
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
    "muladd" => Some(MulAdd)
    "rem" => Some(Remainder)
    "roundtoint" => Some(RoundToInt)
    "toi32" => Some(ToInt32)
    "toi64" => Some(ToInt64)
    "toui32" => Some(ToUInt32)
    "toui64" => Some(ToUInt64)
    "tof16" => Some(ConvertFormat(@bin_float.BinaryInterchangeFormat::Binary16))
    "tof32" => Some(ConvertFormat(@bin_float.BinaryInterchangeFormat::Binary32))
    "tof64" => Some(ConvertFormat(@bin_float.BinaryInterchangeFormat::Binary64))
    "tof128" =>
      Some(ConvertFormat(@bin_float.BinaryInterchangeFormat::Binary128))
    "eq" => Some(Equal)
    "le" => Some(LessEqual)
    "lt" => Some(Less)
    "eqsignaling" => Some(EqualSignaling)
    "lequiet" => Some(LessEqualQuiet)
    "ltquiet" => Some(LessQuiet)
    _ => None
  }
}

///|
fn operand_count(operation : TestFloatOperation) -> Int32 {
  match operation {
    SquareRoot
    | RoundToInt
    | ToInt32
    | ToInt64
    | ToUInt32
    | ToUInt64
    | ConvertFormat(_) => 1
    MulAdd => 3
    _ => 2
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
/// Parses a TestFloat function name such as `f64_mulAdd`, `f32_to_ui64`, or
/// `f16_le_quiet`. `exact` selects the `-exact` variants of `roundToInt` and
/// the integer conversions.
pub fn TestFloatSpec::parse(
  function_name : String,
  rounding : String,
  tininess~ : String = "after",
  exact~ : Bool = false,
) -> Result[TestFloatSpec, String] {
  let parts = function_name.split("_").to_array()
  guard parts.length() >= 2 else {
    return Err("unsupported TestFloat function name " + function_name)
  }
  guard parse_format(parts[0].to_owned()) is Some(format) else {
    return Err("unsupported TestFloat format " + parts[0].to_owned())
  }
  let operation_name = parts[1:].map(fn(part) { part.to_owned() }).join("_")
  guard parse_operation(operation_name) is Some(operation) else {
    return Err("unsupported TestFloat operation " + operation_name)
  }
  guard parse_rounding(rounding) is Some(rounding) else {
    return Err("unsupported TestFloat rounding mode " + rounding)
  }
  guard parse_tininess(tininess) is Some(tininess) else {
    return Err("unsupported TestFloat tininess mode " + tininess)
  }
  Ok({ function_name, format, operation, rounding, tininess, exact, })
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
pub fn TestFloatSpec::exact(self : TestFloatSpec) -> Bool {
  self.exact
}

///|
pub fn TestFloatCase::id(self : TestFloatCase) -> String {
  self.id
}

///|
pub fn TestFloatCase::line(self : TestFloatCase) -> Int32 {
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
pub fn TestFloatDocument::case_count(self : TestFloatDocument) -> Int32 {
  self.cases.length()
}

///|
pub fn ParseDiagnostic::source(self : ParseDiagnostic) -> String {
  self.location.source()
}

///|
pub fn ParseDiagnostic::line(self : ParseDiagnostic) -> Int32 {
  self.location.line()
}

///|
pub fn ParseDiagnostic::message(self : ParseDiagnostic) -> String {
  self.message
}

///|
fn parse_flags(source : String) -> Int32? {
  guard source.length() == 2 else { return None }
  for character in source {
    guard character.is_ascii_hexdigit() else { return None }
  }
  Some(bigint_from_text(source, radix=16).to_int())
}

///|
fn parse_expected(source : String, spec : TestFloatSpec) -> TestFloatExpected? {
  match spec.operation {
    ToInt32 | ToInt64 | ToUInt32 | ToUInt64 => {
      guard source.length() > 0 && source.length() <= 16 else { return None }
      let mut value = 0UL
      for character in source {
        let digit = if character >= '0' && character <= '9' {
          character.to_int() - '0'.to_int()
        } else if character >= 'A' && character <= 'F' {
          character.to_int() - 'A'.to_int() + 10
        } else if character >= 'a' && character <= 'f' {
          character.to_int() - 'a'.to_int() + 10
        } else {
          return None
        }
        value = (value << 4) | digit.to_uint64()
      }
      Some(Integer(value))
    }
    Equal | LessEqual | Less | EqualSignaling | LessEqualQuiet | LessQuiet =>
      match source {
        "0" => Some(Boolean(false))
        "1" => Some(Boolean(true))
        _ => None
      }
    ConvertFormat(target) =>
      @bin_float.BinaryInterchange::from_hex(source, target).map(fn(_) {
        Encoded(source)
      })
    _ =>
      @bin_float.BinaryInterchange::from_hex(source, spec.format).map(fn(_) {
        Encoded(source)
      })
  }
}

///|
pub fn parse_testfloat(
  source : String,
  text : String,
  spec : TestFloatSpec,
) -> Result[TestFloatDocument, Array[ParseDiagnostic]] {
  let cases : Array[TestFloatCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let expected_operands = operand_count(spec.operation)
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
    let expected = parse_expected(tokens[expected_operands], spec)
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
    Ok({ source, spec, cases, })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn RunOptions::new(
  shard_count~ : Int32 = 1,
  shard_index~ : Int32 = 0,
) -> RunOptions {
  { shard: @conformance.ShardSpec::new(shard_count, shard_index), }
}

///|
pub fn RunOptions::shard_count(self : RunOptions) -> Int32 {
  self.shard.count()
}

///|
pub fn RunOptions::shard_index(self : RunOptions) -> Int32 {
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
  message~ : String = "",
) -> CaseResult {
  { inner: @conformance.CaseResult::executable(id, passed, message~), }
}

///|
fn execute_case(case : TestFloatCase, spec : TestFloatSpec) -> CaseResult {
  let context = spec.format.context(
    rounding=spec.rounding,
    tininess=spec.tininess,
  )
  let operands = case.operands.map(fn(value) { value.to_bin_float() })
  match case.expected {
    Encoded(_) => execute_float_case(case, spec, context, operands)
    Integer(expected) =>
      execute_integer_case(case, spec, context, operands[0], expected)
    Boolean(expected) => execute_boolean_case(case, spec, operands, expected)
  }
}

///|
fn flags_result(case : TestFloatCase, actual_flags : Int32) -> CaseResult {
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
fn execute_float_case(
  case : TestFloatCase,
  spec : TestFloatSpec,
  context : @bin_float.BinaryContext,
  operands : Array[@bin_float.BinFloat],
) -> CaseResult {
  // The result format: the destination of a format conversion, else the format
  // of the operands.
  let result_format = match spec.operation {
    ConvertFormat(target) => target
    _ => spec.format
  }
  let (actual, flags) = match (spec.operation, operands) {
    (ConvertFormat(target), [operand]) =>
      operand.convert_format(
        target,
        rounding=spec.rounding,
        tininess=spec.tininess,
      )
    (Add, [left, right]) => left.add_ctx(right, context)
    (Subtract, [left, right]) => left.sub_ctx(right, context)
    (Multiply, [left, right]) => left.mul_ctx(right, context)
    (Divide, [left, right]) => left.div_ctx(right, context)
    (SquareRoot, [operand]) => operand.sqrt_ctx(context)
    (MulAdd, [left, right, addend]) => left.fma_ctx(right, addend, context)
    (Remainder, [left, right]) => left.remainder_ctx(right, context)
    (RoundToInt, [operand]) =>
      if spec.exact {
        operand.to_integral_exact_ctx(context)
      } else {
        operand.to_integral_value_ctx(context)
      }
    _ => abort("invalid parsed TestFloat operand arity")
  }
  judge_float_result(case, result_format, actual, flags)
}

///|
/// Judges the result of a contextual operation against the vector. The result
/// is taken as the operation returns it: it must already be a number of the
/// result format, and it is packed into the bit fields of the format by the code
/// of this file (`pack_exact`), without a rounding. The flags compared are the
/// operation's own.
///
/// Shared with the code under test: the decoding of the operands
/// (`BinaryInterchange::from_hex` and `to_bin_float`; a wrong decoding changes the
/// result and is seen as a mismatch with the vector, it cannot be compensated by
/// the packing) and `BinFloat::to_hex` in the failure message only. The expected
/// column is compared as the text of the vector. NaN: a NaN result is compared
/// as a quiet NaN against a NaN column; the payload and the sign of a NaN are not
/// compared.
fn judge_float_result(
  case : TestFloatCase,
  result_format : @bin_float.BinaryInterchangeFormat,
  actual : @bin_float.BinFloat,
  flags : @bin_float.BinaryFlags,
) -> CaseResult {
  let expected_text = match case.expected {
    Encoded(text) => normalized_bits_text(text, result_format)
    _ => abort("a float case has an encoded expected value")
  }
  if bits_text_is_nan(expected_text, result_format) {
    if !actual.is_quiet_nan() {
      return executable_result(
        case.id,
        false,
        message="value mismatch: expected a NaN, actual " + actual.to_hex(),
      )
    }
  } else {
    match pack_exact(actual, result_format) {
      None =>
        return executable_result(
          case.id,
          false,
          message="result not in the format: expected " +
            expected_text +
            ", actual " +
            actual.to_hex() +
            " (a NaN, or a value that is not a number of the format)",
        )
      Some(packed) =>
        if packed != expected_text {
          return executable_result(
            case.id,
            false,
            message="value mismatch: expected " +
              expected_text +
              ", actual " +
              packed,
          )
        }
    }
  }
  flags_result(case, testfloat_flag_bits(flags))
}

///|
/// The layout of an interchange format, written out here and not read from the
/// library: precision, width in bits, largest exponent (the bias).
fn format_layout(
  format : @bin_float.BinaryInterchangeFormat,
) -> (Int32, Int32, Int32) {
  match format {
    Binary16 => (11, 16, 15)
    Binary32 => (24, 32, 127)
    Binary64 => (53, 64, 1023)
    Binary128 => (113, 128, 16383)
  }
}

///|
fn bits_text_digits(text : String, digits : Int32) -> String {
  let builder = StringBuilder()
  for _ in text.length()..<digits {
    builder.write_char('0')
  }
  builder.write_string(text)
  builder.to_string()
}

///|
/// The hexadecimal text of a vector column in one form: no prefix, lower case,
/// as many digits as the format has.
fn normalized_bits_text(
  text : String,
  format : @bin_float.BinaryInterchangeFormat,
) -> String {
  let (_, width, _) = format_layout(format)
  let lower = normalized_word(text)
  let digits = if lower.has_prefix("0x") { lower[2:].to_owned() } else { lower }
  bits_text_digits(digits, width / 4)
}

///|
fn bits_text_is_nan(
  normalized : String,
  format : @bin_float.BinaryInterchangeFormat,
) -> Bool {
  let (precision, width, _) = format_layout(format)
  let fraction_bits = precision - 1
  let bits = bigint_from_text(normalized, radix=16)
  let ones = (@bigint.BigInt::from_int(1) << (width - precision)) -
    @bigint.BigInt::from_int(1)
  let exponent = (bits >> fraction_bits) & ones
  let fraction = bits &
    (
      (@bigint.BigInt::from_int(1) << fraction_bits) -
      @bigint.BigInt::from_int(1)
    )
  exponent == ones && !fraction.is_zero()
}

///|
/// The bit fields of `value` in `format`, as lower-case hexadecimal of the full
/// width, packed from the sign, the coefficient and the exponent with the layout
/// of `format_layout`: no rounding, no flag. `None` for a NaN and for a finite
/// value that is not a number of the format (more significant bits than the
/// precision, a bit below the last place of the smallest subnormal, or a leading
/// bit above the largest exponent).
fn pack_exact(
  value : @bin_float.BinFloat,
  format : @bin_float.BinaryInterchangeFormat,
) -> String? {
  if value.is_nan() {
    return None
  }
  let (precision, width, emax) = format_layout(format)
  let fraction_bits = precision - 1
  let one = @bigint.BigInt::from_int(1)
  let sign = if value.is_negative() || value.is_negative_zero() {
    one << (width - 1)
  } else {
    @bigint.BigInt::from_int(0)
  }
  let bits = if value.is_infinite() {
    sign | (((one << (width - precision)) - one) << fraction_bits)
  } else if value.is_zero() {
    sign
  } else {
    let coefficient = @bigint.BigInt::from_octets(
      value.coefficient().to_bytes_be()[:],
    )
    let exponent = value.exponent2()
    let length = coefficient.bit_length()
    guard length <= precision else { return None }
    let emin = 1 - emax
    // the exponent of the leading bit
    let leading = exponent + length - 1
    guard leading <= emax else { return None }
    if leading >= emin {
      let fraction = (coefficient << (precision - length)) -
        (one << fraction_bits)
      sign |
      (@bigint.BigInt::from_int(leading + emax) << fraction_bits) |
      fraction
    } else {
      // subnormal: the coefficient counts units of the last place of the
      // smallest subnormal
      let lowest = emin - fraction_bits
      guard exponent >= lowest else { return None }
      sign | (coefficient << (exponent - lowest))
    }
  }
  Some(bits_text_digits(bits.to_string(radix=16), width / 4))
}

///|
/// SoftFloat returns platform-specific sentinels for invalid conversions;
/// those cases require no value and identical flags, as NaN results do.
fn execute_integer_case(
  case : TestFloatCase,
  spec : TestFloatSpec,
  context : @bin_float.BinaryContext,
  operand : @bin_float.BinFloat,
  expected : UInt64,
) -> CaseResult {
  let exact = spec.exact
  let (actual, flags) = match spec.operation {
    ToInt32 => {
      let (value, flags) = operand.to_int_ctx(context, exact~)
      (value.map(fn(value) { value.reinterpret_as_uint().to_uint64() }), flags)
    }
    ToInt64 => {
      let (value, flags) = operand.to_int64_ctx(context, exact~)
      (value.map(fn(value) { value.reinterpret_as_uint64() }), flags)
    }
    ToUInt32 => {
      let (value, flags) = operand.to_uint_ctx(context, exact~)
      (value.map(fn(value) { value.to_uint64() }), flags)
    }
    ToUInt64 => operand.to_uint64_ctx(context, exact~)
    _ => abort("invalid parsed TestFloat conversion")
  }
  let invalid_expected = (case.expected_flags & 0x10) != 0
  let value_matches = match actual {
    None => invalid_expected
    Some(value) => !invalid_expected && value == expected
  }
  if !value_matches {
    return executable_result(
      case.id,
      false,
      message="integer mismatch: expected " +
        expected.to_string() +
        (if invalid_expected { " (invalid)" } else { "" }) +
        ", actual " +
        (match actual {
          Some(value) => value.to_string()
          None => "invalid"
        }),
    )
  }
  flags_result(case, testfloat_flag_bits(flags))
}

///|
fn execute_boolean_case(
  case : TestFloatCase,
  spec : TestFloatSpec,
  operands : Array[@bin_float.BinFloat],
  expected : Bool,
) -> CaseResult {
  let left = operands[0]
  let right = operands[1]
  let (actual, flags) = match spec.operation {
    Equal => left.compare_quiet_equal(right)
    LessEqual => left.compare_signaling_less_equal(right)
    Less => left.compare_signaling_less(right)
    EqualSignaling => left.compare_signaling_equal(right)
    LessEqualQuiet => left.compare_quiet_less_equal(right)
    LessQuiet => left.compare_quiet_less(right)
    _ => abort("invalid parsed TestFloat comparison")
  }
  if actual != expected {
    return executable_result(
      case.id,
      false,
      message="comparison mismatch: expected " +
        expected.to_string() +
        ", actual " +
        actual.to_string(),
    )
  }
  flags_result(case, testfloat_flag_bits(flags))
}

///|
pub fn execute_document(
  document : TestFloatDocument,
  options~ : RunOptions = RunOptions::new(),
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
pub fn RunSummary::total_cases(self : RunSummary) -> Int32 {
  self.inner.total_cases()
}

///|
pub fn RunSummary::selected_cases(self : RunSummary) -> Int32 {
  self.inner.selected_cases()
}

///|
pub fn RunSummary::passed_cases(self : RunSummary) -> Int32 {
  self.inner.passed_cases()
}

///|
pub fn RunSummary::failed_cases(self : RunSummary) -> Int32 {
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

///|
pub extend TestFloatOperation with Eq::{not_equal, equal}

///|
pub extend TestFloatOperation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TestFloatSpec with Eq::{not_equal, equal}

///|
pub extend TestFloatSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParseDiagnostic with Eq::{not_equal, equal}

///|
pub extend ParseDiagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parses `text` as a BigInt; malformed text aborts, as the deprecated
/// `BigInt::from_string` did.
fn bigint_from_text(text : StringView, radix~ : Int32 = 10) -> @bigint.BigInt {
  @string.parse_bigint(text, radix~) catch {
    _ => abort("invalid BigInt text")
  }
}
