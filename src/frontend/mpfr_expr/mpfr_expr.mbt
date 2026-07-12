///|
pub struct MpfrCase {
  priv id : String
  priv input : @bin_float.BinFloat
  priv expected : @bin_float.BinFloat
  priv output_precision : Int
  priv rounding : @bin_float.BinaryRoundingMode
}

///|
pub struct MpfrDocument {
  priv source : String
  priv cases : Array[MpfrCase]
}

///|
pub struct MpfrPowCase {
  priv id : String
  priv input : @bin_float.BinFloat
  priv exponent : Int
  priv expected : @bin_float.BinFloat
  priv output_precision : Int
  priv rounding : @bin_float.BinaryRoundingMode
  priv inexact : Bool
}

///|
pub struct MpfrPowDocument {
  priv source : String
  priv cases : Array[MpfrPowCase]
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
pub struct RunSummary {
  priv inner : @conformance.RunSummary
}

///|
fn tokenize(source : String) -> Array[String] {
  let tokens : Array[String] = []
  let builder = StringBuilder::new()
  let mut has_content = false
  for character in source {
    if character == ' ' || character == '\t' || character == '\r' {
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
fn parse_int(source : String) -> Int? {
  try @string.parse_int(source) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn parse_rounding(source : String) -> @bin_float.BinaryRoundingMode? {
  match source {
    "n" => Some(@bin_float.BinaryRoundingMode::RoundTiesToEven)
    "na" => Some(@bin_float.BinaryRoundingMode::RoundTiesToAway)
    "z" => Some(@bin_float.BinaryRoundingMode::RoundTowardZero)
    "u" => Some(@bin_float.BinaryRoundingMode::RoundTowardPositive)
    "d" => Some(@bin_float.BinaryRoundingMode::RoundTowardNegative)
    "a" => Some(@bin_float.BinaryRoundingMode::RoundAwayFromZero)
    _ => None
  }
}

///|
fn parse_bool_digit(source : String) -> Bool? {
  match source {
    "0" => Some(false)
    "1" => Some(true)
    _ => None
  }
}

///|
fn mpfr_pow_hex(coefficient : String, exponent2 : String) -> String {
  "0x" + coefficient + "p" + exponent2
}

///|
pub fn parse_pow_data(
  source : String,
  text : String,
) -> Result[MpfrPowDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrPowCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize(line)
    if tokens.length() != 10 {
      diagnostics.push({
        location: @conformance.SourceLocation::new(source, line_number),
        message: "MPFR pow row must contain ten fields",
      })
      continue
    }
    let precision = parse_int(tokens[0])
    let rounding = parse_rounding(tokens[1])
    let input_exponent = parse_int(tokens[3])
    let input_negative = parse_bool_digit(tokens[4])
    let exponent = parse_int(tokens[5])
    let output_exponent = parse_int(tokens[7])
    let output_negative = parse_bool_digit(tokens[8])
    let inexact = parse_bool_digit(tokens[9])
    match
      (
        precision, rounding, input_exponent, input_negative, exponent, output_exponent,
        output_negative, inexact,
      ) {
      (
        Some(precision),
        Some(rounding),
        Some(input_exponent),
        Some(input_negative),
        Some(exponent),
        Some(output_exponent),
        Some(output_negative),
        Some(inexact),
      ) => {
        let input_text = mpfr_pow_hex(tokens[2], input_exponent.to_string())
        let output_text = mpfr_pow_hex(tokens[6], output_exponent.to_string())
        let input = @bin_float.BinFloat::from_hex(input_text, 512)
        let expected = @bin_float.BinFloat::from_hex(output_text, precision)
        match (input, expected) {
          (Ok(input), Ok(expected)) =>
            cases.push({
              id: "pow:" + line_number.to_string(),
              input: if input_negative {
                input.neg()
              } else {
                input
              },
              exponent,
              expected: if output_negative {
                expected.neg()
              } else {
                expected
              },
              output_precision: precision,
              rounding,
              inexact,
            })
          _ =>
            diagnostics.push({
              location: @conformance.SourceLocation::new(source, line_number),
              message: "invalid MPFR pow hexadecimal operand",
            })
        }
      }
      _ =>
        diagnostics.push({
          location: @conformance.SourceLocation::new(source, line_number),
          message: "invalid MPFR pow field",
        })
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn parse_sqrt_data(
  source : String,
  text : String,
) -> Result[MpfrDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize(line)
    if tokens.length() != 5 {
      diagnostics.push({
        location: @conformance.SourceLocation::new(source, line_number),
        message: "MPFR data_check row must contain five fields",
      })
      continue
    }
    let input_precision = parse_int(tokens[0])
    let output_precision = parse_int(tokens[1])
    let rounding = parse_rounding(tokens[2])
    match (input_precision, output_precision, rounding) {
      (Some(input_precision), Some(output_precision), Some(rounding)) => {
        let input = @bin_float.BinFloat::from_hex(tokens[3], input_precision)
        let expected = @bin_float.BinFloat::from_hex(
          tokens[4],
          output_precision,
        )
        match (input, expected) {
          (Ok(input), Ok(expected)) =>
            cases.push({
              id: "sqrt:" + line_number.to_string(),
              input,
              expected,
              output_precision,
              rounding,
            })
          _ =>
            diagnostics.push({
              location: @conformance.SourceLocation::new(source, line_number),
              message: "invalid MPFR hexadecimal operand",
            })
        }
      }
      _ =>
        diagnostics.push({
          location: @conformance.SourceLocation::new(source, line_number),
          message: "invalid or unsupported MPFR data_check directive",
        })
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn ParseDiagnostic::source(self : ParseDiagnostic) -> String {
  self.location.source()
}

///|
pub fn MpfrDocument::source(self : MpfrDocument) -> String {
  self.source
}

///|
pub fn MpfrDocument::case_count(self : MpfrDocument) -> Int {
  self.cases.length()
}

///|
pub fn MpfrPowDocument::source(self : MpfrPowDocument) -> String {
  self.source
}

///|
pub fn MpfrPowDocument::case_count(self : MpfrPowDocument) -> Int {
  self.cases.length()
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
pub fn execute_sqrt_data(document : MpfrDocument) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let actual = case.input.sqrt_ctx(
        @bin_float.BinaryContext::unbounded(
          case.output_precision,
          rounding=case.rounding,
        ),
      ).0
    let passed = actual == case.expected
    let result : CaseResult = {
      inner: @conformance.CaseResult::executable(
        case.id,
        passed,
        message=if passed {
          ""
        } else {
          "value mismatch: expected " +
          case.expected.to_hex() +
          ", actual " +
          actual.to_hex()
        },
      ),
    }
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
pub fn execute_pow_data(document : MpfrPowDocument) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let actual = case.input.pow_int_ctx(
      case.exponent,
      @bin_float.BinaryContext::unbounded(
        case.output_precision,
        rounding=case.rounding,
      ),
    )
    let passed = actual.0 == case.expected &&
      actual.1.inexact() == case.inexact &&
      !actual.1.underflow() &&
      !actual.1.overflow() &&
      !actual.1.division_by_zero() &&
      !actual.1.invalid_operation()
    results.push({
      inner: @conformance.CaseResult::executable(
        case.id,
        passed,
        message=if passed {
          ""
        } else {
          "pow mismatch: expected " +
          case.expected.to_hex() +
          " inexact=" +
          case.inexact.to_string() +
          ", actual " +
          actual.0.to_hex() +
          " inexact=" +
          actual.1.inexact().to_string()
        },
      ),
    })
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
