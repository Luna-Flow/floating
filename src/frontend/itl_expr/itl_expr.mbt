///|
pub struct ItlCase {
  priv id_ : String
  priv operation_ : String
  priv operands_ : Array[String]
  priv expected_ : String
} derive(Eq, Debug)

///|
pub fn ItlCase::id(self : ItlCase) -> String {
  self.id_
}

///|
pub fn ItlCase::operation(self : ItlCase) -> String {
  self.operation_
}

///|
pub fn ItlCase::operands(self : ItlCase) -> Array[String] {
  self.operands_.copy()
}

///|
pub fn ItlCase::expected(self : ItlCase) -> String {
  self.expected_
}

///|
pub(all) enum ItlDisposition {
  Executable
  Unsupported(String)
  Diagnostic(String)
}

///|
pub struct ItlResult {
  priv id_ : String
  priv disposition_ : ItlDisposition
  priv passed_ : Bool
  priv message_ : String
}

///|
pub fn ItlResult::id(self : ItlResult) -> String {
  self.id_
}

///|
pub fn ItlResult::disposition(self : ItlResult) -> ItlDisposition {
  self.disposition_
}

///|
pub fn ItlResult::passed(self : ItlResult) -> Bool {
  self.passed_
}

///|
pub fn ItlResult::message(self : ItlResult) -> String {
  self.message_
}

///|
fn ItlResult::to_conformance(self : ItlResult) -> @conformance.CaseResult {
  let disposition = match self.disposition_ {
    Executable => @conformance.CaseDisposition::Executable
    Unsupported(message) => @conformance.CaseDisposition::Unsupported(message)
    Diagnostic(message) => @conformance.CaseDisposition::Diagnostic(message)
  }
  @conformance.CaseResult::new(
    self.id_,
    disposition,
    self.passed_,
    message=self.message_,
  )
}

///|
pub struct RunSummary {
  priv inner : @conformance.RunSummary
  priv results_ : Array[ItlResult]
}

///|
pub fn summarize_results(results : Array[ItlResult]) -> RunSummary {
  {
    inner: @conformance.RunSummary::from_results(
      results.length(),
      results.map(fn(result) { result.to_conformance() }),
    ),
    results_: results.copy(),
  }
}

///|
pub fn RunSummary::total_cases(self : RunSummary) -> Int {
  self.inner.total_cases()
}

///|
pub fn RunSummary::executable_cases(self : RunSummary) -> Int {
  self.inner.executable_cases()
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
pub fn RunSummary::diagnostic_cases(self : RunSummary) -> Int {
  self.inner.diagnostic_cases()
}

///|
pub fn RunSummary::unsupported_cases(self : RunSummary) -> Int {
  self.inner.unsupported_cases()
}

///|
pub fn RunSummary::results(self : RunSummary) -> Array[ItlResult] {
  self.results_.copy()
}

///|
pub fn RunSummary::success(self : RunSummary) -> Bool {
  self.inner.success() && self.inner.diagnostic_cases() == 0
}

///|
fn find_char(src : String, target : UInt16) -> Int? {
  for index in 0..<src.length() {
    if src[index] == target {
      return Some(index)
    }
  }
  None
}

///|
fn split_words_preserving_intervals(src : String) -> Array[String] {
  let words : Array[String] = []
  let builder = StringBuilder::new()
  let mut bracket_depth = 0
  for index in 0..<src.length() {
    let ch = src[index]
    if ch == '[' {
      bracket_depth += 1
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    } else if ch == ']' {
      bracket_depth -= 1
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    } else if (ch == ' ' || ch == '\t') && bracket_depth == 0 {
      let word = builder.to_string()
      if word.length() > 0 {
        words.push(word)
        builder.reset()
      }
    } else {
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    }
  }
  let word = builder.to_string()
  if word.length() > 0 {
    words.push(word)
  }
  words
}

///|
fn parse_statement(
  testcase : String,
  index : Int,
  statement : String,
) -> Result[ItlCase, String] {
  guard find_char(statement, '=') is Some(equals) else {
    return Err("missing '='")
  }
  let left = statement[0:equals].trim().to_owned()
  let expected = statement[equals + 1:].trim().to_owned()
  let words = split_words_preserving_intervals(left)
  guard words.length() > 0 else { return Err("missing operation") }
  let operands : Array[String] = []
  for operand_index in 1..<words.length() {
    operands.push(words[operand_index])
  }
  Ok({
    id_: testcase + ":" + index.to_string(),
    operation_: words[0],
    operands_: operands,
    expected_: expected,
  })
}

///|
pub fn parse_itl(source : String) -> Result[Array[ItlCase], Array[String]] {
  let cases : Array[ItlCase] = []
  let diagnostics : Array[String] = []
  let mut testcase = "anonymous"
  let mut case_index = 0
  let mut in_comment = false
  let statement = StringBuilder::new()
  for raw_line in source.split("\n") {
    let line = raw_line.trim().to_owned()
    if in_comment {
      if line.contains("*/") {
        in_comment = false
      }
      continue
    }
    if line.has_prefix("/*") {
      if !line.contains("*/") {
        in_comment = true
      }
      continue
    }
    if line.length() == 0 || line.has_prefix("//") {
      continue
    }
    if line.has_prefix("testcase ") {
      let suffix = line[9:].trim().to_owned()
      guard find_char(suffix, ' ') is Some(space) else {
        diagnostics.push("invalid testcase declaration")
        continue
      }
      testcase = suffix[0:space].to_owned()
      case_index = 0
      continue
    }
    if line == "}" {
      continue
    }
    if statement.to_string().length() > 0 {
      statement.write_char(' ')
    }
    statement.write_string(line)
    if line.has_suffix(";") {
      let complete = statement.to_string()
      statement.reset()
      case_index += 1
      match
        parse_statement(
          testcase,
          case_index,
          complete[0:complete.length() - 1].to_owned(),
        ) {
        Ok(case) => cases.push(case)
        Err(message) =>
          diagnostics.push(
            testcase + ":" + case_index.to_string() + ": " + message,
          )
      }
    }
  }
  if statement.to_string().length() > 0 {
    diagnostics.push("unterminated ITL statement")
  }
  if diagnostics.length() > 0 {
    Err(diagnostics)
  } else {
    Ok(cases)
  }
}

///|
fn parse_decoration(src : String) -> @ball_float.Decoration? {
  match src {
    "ill" => Some(Ill)
    "trv" => Some(Trv)
    "def" => Some(Def)
    "dac" => Some(Dac)
    "com" => Some(Com)
    _ => None
  }
}

///|
fn split_literal_decoration(src : String) -> (String, String?) {
  guard find_char(src, '_') is Some(separator) else { return (src, None) }
  (src[0:separator].to_owned(), Some(src[separator + 1:].to_owned()))
}

///|
fn parse_bound(
  src : String,
  precision : Int,
  mode : @lf_arith.RoundingMode,
) -> @bin_float.BinFloat? {
  let normalized = src.trim().to_owned()
  if normalized == "-inf" || normalized == "-infinity" {
    Some(@bin_float.BinFloat::inf(@def.Sign::Negative, precision~))
  } else if normalized == "+inf" ||
    normalized == "inf" ||
    normalized == "+infinity" ||
    normalized == "infinity" {
    Some(@bin_float.BinFloat::inf(@def.Sign::Positive, precision~))
  } else {
    if normalized.has_prefix("0x") ||
      normalized.has_prefix("0X") ||
      normalized.has_prefix("-0x") ||
      normalized.has_prefix("-0X") ||
      normalized.has_prefix("+0x") ||
      normalized.has_prefix("+0X") {
      return parse_hex_bound(normalized, precision, mode)
    }
    match
      @decimal.Decimal::from_string(normalized, precision=precision * 2 + 16) {
      Some(value) => Some(value.to_bin_float(precision~, mode~))
      None => None
    }
  }
}

///|
fn parse_int_option(src : String) -> Int? {
  try @string.parse_int(src) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn parse_hex_bound(
  src : String,
  precision : Int,
  mode : @lf_arith.RoundingMode,
) -> @bin_float.BinFloat? {
  let negative = src.has_prefix("-")
  let unsigned = if negative || src.has_prefix("+") {
    src[1:].to_owned()
  } else {
    src
  }
  guard unsigned.has_prefix("0x") || unsigned.has_prefix("0X") else {
    return None
  }
  let exponent_index = match find_char(unsigned, 'p') {
    Some(index) => index
    None =>
      match find_char(unsigned, 'P') {
        Some(index) => index
        None => return None
      }
  }
  let mantissa = unsigned[2:exponent_index].to_owned()
  let exponent_src = unsigned[exponent_index + 1:].to_owned()
  guard parse_int_option(exponent_src) is Some(exponent) else { return None }
  let digits = StringBuilder::new()
  let mut fractional_digits = 0
  let mut after_point = false
  for index in 0..<mantissa.length() {
    let ch = mantissa[index]
    if ch == '.' {
      after_point = true
    } else {
      digits.write_char(Int::unsafe_to_char(ch.to_int()))
      if after_point {
        fractional_digits += 1
      }
    }
  }
  guard @bin_float.BinCoeff::parse(digits.to_string(), radix=16)
    is Ok(magnitude) else {
    return None
  }
  Some(
    @bin_float.BinFloat::make(
      magnitude,
      exponent - 4 * fractional_digits,
      Int::max(precision, magnitude.bit_length()),
      negative~,
    ).with_precision(precision, mode),
  )
}

///|
fn parse_interval(
  src : String,
  precision : Int,
) -> @ball_float.BallFloatDecorated? {
  let (literal, decoration_src) = split_literal_decoration(
    src.trim().to_owned(),
  )
  let decoration = match decoration_src {
    Some(value) =>
      match parse_decoration(value) {
        Some(dec) => dec
        None => return None
      }
    None => Com
  }
  if literal == "[nai]" {
    return Some(@ball_float.BallFloatDecorated::nai(precision~))
  }
  if literal == "[empty]" {
    return Some(
      @ball_float.BallFloatDecorated::new(
        @ball_float.BallFloat::empty(precision~),
        decoration~,
      ),
    )
  }
  if literal == "[entire]" {
    return Some(
      @ball_float.BallFloatDecorated::new(
        @ball_float.BallFloat::whole(precision~),
        decoration~,
      ),
    )
  }
  guard literal.has_prefix("[") && literal.has_suffix("]") else { return None }
  let content = literal[1:literal.length() - 1].to_owned()
  guard find_char(content, ',') is Some(comma) else { return None }
  let lower_src = content[0:comma].trim().to_owned()
  let upper_src = content[comma + 1:].trim().to_owned()
  guard parse_bound(lower_src, precision, @lf_arith.RoundingMode::ToNearestEven)
    is Some(lo) &&
    parse_bound(upper_src, precision, @lf_arith.RoundingMode::ToNearestEven)
    is Some(hi) else {
    return None
  }
  Some(
    @ball_float.BallFloatDecorated::new(
      @ball_float.BallFloat::from_bounds(lo, hi, precision~),
      decoration~,
    ),
  )
}

///|
fn intervals_equal(
  actual : @ball_float.BallFloatDecorated,
  expected : @ball_float.BallFloatDecorated,
  compare_decoration : Bool,
) -> Bool {
  if actual.is_nai() || expected.is_nai() {
    return actual.is_nai() && expected.is_nai()
  }
  let left = actual.interval()
  let right = expected.interval()
  let intervals_match = if left.is_empty() || right.is_empty() {
    left.is_empty() && right.is_empty()
  } else {
    left.lower_bound().compare(right.lower_bound()) == 0 &&
    left.upper_bound().compare(right.upper_bound()) == 0
  }
  intervals_match &&
  (!compare_decoration || actual.decoration() == expected.decoration())
}

///|
pub fn execute_case(case : ItlCase, precision? : Int = 53) -> ItlResult {
  if case.expected_ == "true" || case.expected_ == "false" {
    return execute_boolean_case(case, precision)
  }
  if case.operation_ == "overlap" {
    return execute_overlap_case(case, precision)
  }
  if case.operation_ == "inf" ||
    case.operation_ == "sup" ||
    case.operation_ == "mid" ||
    case.operation_ == "rad" ||
    case.operation_ == "wid" ||
    case.operation_ == "mag" ||
    case.operation_ == "mig" {
    return execute_numeric_case(case, precision)
  }
  if case.operation_ == "pos" ||
    case.operation_ == "neg" ||
    case.operation_ == "abs" ||
    case.operation_ == "recip" ||
    case.operation_ == "sqr" ||
    case.operation_ == "sqrt" ||
    case.operation_ == "exp" ||
    case.operation_ == "exp2" ||
    case.operation_ == "exp10" ||
    case.operation_ == "log" ||
    case.operation_ == "log2" ||
    case.operation_ == "log10" ||
    case.operation_ == "sin" ||
    case.operation_ == "cos" ||
    case.operation_ == "tan" {
    return execute_interval_unary_case(case, precision)
  }
  if case.operation_ == "fma" {
    return execute_fma_case(case, precision)
  }
  if case.operation_ == "pown" {
    return execute_pown_case(case, precision)
  }
  let operands : Array[@ball_float.BallFloatDecorated] = []
  for src in case.operands_ {
    match parse_interval(src, precision) {
      Some(value) => operands.push(value)
      None =>
        return {
          id_: case.id_,
          disposition_: Diagnostic("invalid interval operand"),
          passed_: false,
          message_: src,
        }
    }
  }
  guard parse_interval(case.expected_, precision) is Some(expected) else {
    return {
      id_: case.id_,
      disposition_: Unsupported("non-interval expected value"),
      passed_: false,
      message_: case.expected_,
    }
  }
  guard operands.length() == 2 else {
    return {
      id_: case.id_,
      disposition_: Unsupported("operation arity"),
      passed_: false,
      message_: case.operation_,
    }
  }
  let binary64 = @ball_float.BallContext::binary64()
  let actual = match case.operation_ {
    "intersection" => operands[0].intersection(operands[1])
    "convexHull" => operands[0].convex_hull(operands[1])
    "cancelPlus" => operands[0].cancel_plus(operands[1]).apply_ctx(binary64).0
    "cancelMinus" => operands[0].cancel_minus(operands[1]).apply_ctx(binary64).0
    "add" => (operands[0] + operands[1]).apply_ctx(binary64).0
    "sub" => (operands[0] - operands[1]).apply_ctx(binary64).0
    "mul" => (operands[0] * operands[1]).apply_ctx(binary64).0
    "div" => (operands[0] / operands[1]).apply_ctx(binary64).0
    "pow" => operands[0].pow_interval(operands[1])
    "min" => operands[0].minimum(operands[1]).apply_ctx(binary64).0
    "max" => operands[0].maximum(operands[1]).apply_ctx(binary64).0
    _ =>
      return {
        id_: case.id_,
        disposition_: Unsupported(case.operation_),
        passed_: false,
        message_: "unsupported operation",
      }
  }
  let passed = intervals_equal(
    actual,
    expected,
    find_char(case.expected_, '_') is Some(_),
  )
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + expected.to_string() + ", got " + actual.to_string()
    },
  }
}

///|
fn execute_pown_case(case : ItlCase, precision : Int) -> ItlResult {
  guard case.operands_.length() == 2 &&
    parse_interval(case.operands_[0], precision) is Some(base) &&
    parse_int_option(case.operands_[1]) is Some(exponent) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid pown operands"),
      passed_: false,
      message_: case.operation_,
    }
  }
  guard parse_interval(case.expected_, precision) is Some(expected) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid pown expected value"),
      passed_: false,
      message_: case.expected_,
    }
  }
  let actual = base
    .pown(exponent)
    .apply_ctx(@ball_float.BallContext::binary64()).0
  let passed = intervals_equal(
    actual,
    expected,
    find_char(case.expected_, '_') is Some(_),
  )
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + expected.to_string() + ", got " + actual.to_string()
    },
  }
}

///|
fn execute_fma_case(case : ItlCase, precision : Int) -> ItlResult {
  guard case.operands_.length() == 3 &&
    parse_interval(case.operands_[0], precision) is Some(left) &&
    parse_interval(case.operands_[1], precision) is Some(multiplier) &&
    parse_interval(case.operands_[2], precision) is Some(addend) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid fma operands"),
      passed_: false,
      message_: case.operation_,
    }
  }
  guard parse_interval(case.expected_, precision) is Some(expected) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid fma expected value"),
      passed_: false,
      message_: case.expected_,
    }
  }
  let actual = left
    .fma(multiplier, addend)
    .apply_ctx(@ball_float.BallContext::binary64()).0
  let passed = intervals_equal(
    actual,
    expected,
    find_char(case.expected_, '_') is Some(_),
  )
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + expected.to_string() + ", got " + actual.to_string()
    },
  }
}

///|
fn execute_interval_unary_case(case : ItlCase, precision : Int) -> ItlResult {
  guard case.operands_.length() == 1 &&
    parse_interval(case.operands_[0], precision) is Some(operand) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid unary interval operand"),
      passed_: false,
      message_: case.operation_,
    }
  }
  guard parse_interval(case.expected_, precision) is Some(expected) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid unary interval expected value"),
      passed_: false,
      message_: case.expected_,
    }
  }
  let unbounded = match case.operation_ {
    "pos" => operand.pos()
    "neg" => operand.neg()
    "abs" => operand.abs()
    "recip" => operand.reciprocal()
    "sqr" => operand.square()
    "sqrt" => operand.sqrt_interval()
    "exp" => operand.exp_interval()
    "exp2" => operand.exp2_interval()
    "exp10" => operand.exp10_interval()
    "log" => operand.ln_interval()
    "log2" => operand.log2_interval()
    "log10" => operand.log10_interval()
    "sin" => operand.sin_interval()
    "cos" => operand.cos_interval()
    "tan" => operand.tan_interval()
    _ => abort("unreachable unary interval operation")
  }
  let actual = unbounded.apply_ctx(@ball_float.BallContext::binary64()).0
  let passed = intervals_equal(
    actual,
    expected,
    find_char(case.expected_, '_') is Some(_),
  )
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + expected.to_string() + ", got " + actual.to_string()
    },
  }
}

///|
fn execute_numeric_case(case : ItlCase, precision : Int) -> ItlResult {
  guard case.operands_.length() == 1 &&
    parse_interval(case.operands_[0], precision) is Some(operand) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid numeric operand"),
      passed_: false,
      message_: case.operation_,
    }
  }
  guard parse_bound(
      case.expected_,
      precision,
      @lf_arith.RoundingMode::ToNearestEven,
    )
    is Some(expected) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid numeric expected value"),
      passed_: false,
      message_: case.expected_,
    }
  }
  let interval = operand.interval()
  let actual = match case.operation_ {
    "inf" => interval.lower_bound()
    "sup" => interval.upper_bound()
    "mid" => interval.midpoint_ctx(@ball_float.BallContext::binary64()).0
    "rad" => interval.radius_extended()
    "wid" => interval.width()
    "mag" => interval.magnitude()
    "mig" => interval.mignitude()
    _ => abort("unreachable numeric operation")
  }
  let passed = actual.compare(expected) == 0
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + expected.to_string() + ", got " + actual.to_string()
    },
  }
}

///|
fn overlap_name(state : @ball_float.OverlapState) -> String {
  match state {
    Undefined => "undefined"
    BothEmpty => "bothEmpty"
    FirstEmpty => "firstEmpty"
    SecondEmpty => "secondEmpty"
    Before => "before"
    Meets => "meets"
    OverlapsState => "overlaps"
    Starts => "starts"
    ContainedBy => "containedBy"
    Finishes => "finishes"
    EqualIntervals => "equals"
    After => "after"
    MetBy => "metBy"
    OverlappedBy => "overlappedBy"
    StartedBy => "startedBy"
    ContainsInterval => "contains"
    FinishedBy => "finishedBy"
  }
}

///|
fn execute_overlap_case(case : ItlCase, precision : Int) -> ItlResult {
  guard case.operands_.length() == 2 &&
    parse_interval(case.operands_[0], precision) is Some(left) &&
    parse_interval(case.operands_[1], precision) is Some(right) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid overlap operands"),
      passed_: false,
      message_: "",
    }
  }
  let actual = overlap_name(left.overlap_state(right))
  let passed = actual == case.expected_
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + case.expected_ + ", got " + actual
    },
  }
}

///|
fn parse_boolean_interval(
  src : String,
  precision : Int,
) -> @ball_float.BallFloatDecorated? {
  parse_interval(src, precision)
}

///|
fn boolean_result(case : ItlCase, actual : Bool) -> ItlResult {
  let expected = case.expected_ == "true"
  let passed = actual == expected
  {
    id_: case.id_,
    disposition_: Executable,
    passed_: passed,
    message_: if passed {
      ""
    } else {
      "expected " + case.expected_ + ", got " + actual.to_string()
    },
  }
}

///|
fn execute_boolean_case(case : ItlCase, precision : Int) -> ItlResult {
  if case.operation_ == "isMember" {
    guard case.operands_.length() == 2 &&
      parse_bound(
        case.operands_[0],
        precision,
        @lf_arith.RoundingMode::ToNearestEven,
      )
      is Some(candidate) &&
      parse_boolean_interval(case.operands_[1], precision) is Some(container) else {
      return {
        id_: case.id_,
        disposition_: Diagnostic("invalid isMember operands"),
        passed_: false,
        message_: "",
      }
    }
    return boolean_result(case, container.contains(candidate))
  }
  guard case.operands_.length() >= 1 &&
    parse_boolean_interval(case.operands_[0], precision) is Some(left) else {
    return {
      id_: case.id_,
      disposition_: Diagnostic("invalid interval operand"),
      passed_: false,
      message_: case.operation_,
    }
  }
  let unary = match case.operation_ {
    "isEmpty" => Some(left.is_empty())
    "isEntire" => Some(left.is_entire())
    "isNaI" => Some(left.is_nai())
    "isCommonInterval" => Some(left.is_common_interval())
    "isSingleton" => Some(left.is_singleton())
    _ => None
  }
  match unary {
    Some(actual) => return boolean_result(case, actual)
    None => ()
  }
  guard case.operands_.length() == 2 &&
    parse_boolean_interval(case.operands_[1], precision) is Some(right) else {
    return {
      id_: case.id_,
      disposition_: Unsupported(case.operation_),
      passed_: false,
      message_: "unsupported boolean operation",
    }
  }
  let actual = match case.operation_ {
    "equal" => left.set_equal(right)
    "subset" => left.subset(right)
    "interior" => left.interior(right)
    "disjoint" => left.disjoint(right)
    "precedes" => left.precedes(right)
    "strictPrecedes" => left.strictly_precedes(right)
    "less" => left.less(right)
    "strictLess" => left.strictly_less(right)
    _ =>
      return {
        id_: case.id_,
        disposition_: Unsupported(case.operation_),
        passed_: false,
        message_: "unsupported boolean operation",
      }
  }
  boolean_result(case, actual)
}
