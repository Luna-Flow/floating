///|
// MPFR differential corpora for decimal character conversion (IEEE 754-2019
// 5.12): `mpfr-strtofr-v1` (decimal text to a binary value) and
// `mpfr-decimal-output-v1` (a binary value to digits).

///|
priv struct MpfrStrtofrCase {
  id : String
  input : String
  expected : @bin_float.BinFloat
  output_precision : Int32
  rounding : @bin_float.BinaryRoundingMode
  inexact : Bool
  overflow : Bool
  underflow : Bool
}

///|
pub struct MpfrStrtofrDocument {
  priv source : String
  priv cases : Array[MpfrStrtofrCase]
}

///|
priv enum MpfrDecimalOutputCase {
  Fixed(
    id~ : String,
    digits~ : Int32,
    value~ : @bin_float.BinFloat,
    rounding~ : @bin_float.BinaryRoundingMode,
    expected_digits~ : String,
    expected_exponent10~ : Int32,
    inexact~ : Bool
  )
  Shortest(
    id~ : String,
    value~ : @bin_float.BinFloat,
    expected_digit_count~ : Int32
  )
}

///|
pub struct MpfrDecimalOutputDocument {
  priv source : String
  priv cases : Array[MpfrDecimalOutputCase]
}

///|
fn row_diagnostic(
  source : String,
  line_number : Int32,
  message : String,
) -> ParseDiagnostic {
  { location: @conformance.SourceLocation::new(source, line_number), message, }
}

///|
pub fn parse_strtofr_data(
  source : String,
  text : String,
) -> Result[MpfrStrtofrDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrStrtofrCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize(line)
    if tokens.length() != 7 {
      diagnostics.push(
        row_diagnostic(
          source, line_number, "MPFR strtofr row must contain seven fields",
        ),
      )
      continue
    }
    match
      (
        parse_int(tokens[0]),
        parse_rounding(tokens[1]),
        parse_bool_digit(tokens[4]),
        parse_bool_digit(tokens[5]),
        parse_bool_digit(tokens[6]),
      ) {
      (
        Some(output_precision),
        Some(rounding),
        Some(inexact),
        Some(overflow),
        Some(underflow),
      ) =>
        match @bin_float.BinFloat::from_hex(tokens[3], output_precision) {
          Ok(expected) =>
            cases.push({
              id: "strtofr:" + line_number.to_string(),
              input: tokens[2],
              expected,
              output_precision,
              rounding,
              inexact,
              overflow,
              underflow,
            })
          Err(_) =>
            diagnostics.push(
              row_diagnostic(
                source, line_number, "invalid MPFR strtofr expected value",
              ),
            )
        }
      _ =>
        diagnostics.push(
          row_diagnostic(source, line_number, "invalid MPFR strtofr field"),
        )
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases, })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn MpfrStrtofrDocument::source(self : MpfrStrtofrDocument) -> String {
  self.source
}

///|
pub fn MpfrStrtofrDocument::case_count(self : MpfrStrtofrDocument) -> Int32 {
  self.cases.length()
}

///|
fn summary_of(results : Array[CaseResult]) -> RunSummary {
  {
    inner: @conformance.RunSummary::from_results(
      results.length(),
      results.map(result => result.inner),
    ),
  }
}

///|
pub fn execute_strtofr_data(document : MpfrStrtofrDocument) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let context = @bin_float.BinaryContext::unbounded(
      case.output_precision,
      rounding=case.rounding,
    )
    let (passed, message) = match
      @bin_float.BinFloat::from_string_ctx(case.input, context) {
      Err(_) => (false, "strtofr rejected " + case.input)
      Ok((actual, flags)) => {
        // `compare` treats -0 and +0 as equal; MPFR results carry the sign.
        let same_value = actual.compare(case.expected) == 0 &&
          actual.is_negative() == case.expected.is_negative() &&
          actual.classify() == case.expected.classify()
        let passed = same_value &&
          flags.inexact() == case.inexact &&
          flags.overflow() == case.overflow &&
          flags.underflow() == case.underflow &&
          !flags.invalid_operation() &&
          !flags.division_by_zero()
        (
          passed,
          if passed {
            ""
          } else {
            "strtofr mismatch for " +
            case.input +
            ": expected " +
            case.expected.to_hex() +
            " flags=" +
            case.inexact.to_string() +
            "/" +
            case.overflow.to_string() +
            "/" +
            case.underflow.to_string() +
            ", actual " +
            actual.to_hex() +
            " flags=" +
            flags.inexact().to_string() +
            "/" +
            flags.overflow().to_string() +
            "/" +
            flags.underflow().to_string()
          },
        )
      }
    }
    results.push({
      inner: @conformance.CaseResult::executable(case.id, passed, message~),
    })
  }
  summary_of(results)
}

///|
pub fn parse_decimal_output_data(
  source : String,
  text : String,
) -> Result[MpfrDecimalOutputDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrDecimalOutputCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize(line)
    if tokens[0] == "fixed" && tokens.length() == 8 {
      match
        (
          parse_int(tokens[1]),
          parse_int(tokens[2]),
          parse_rounding(tokens[3]),
          parse_int(tokens[6]),
          parse_bool_digit(tokens[7]),
        ) {
        (
          Some(digits),
          Some(precision),
          Some(rounding),
          Some(exponent10),
          Some(inexact),
        ) =>
          match @bin_float.BinFloat::from_hex(tokens[4], precision) {
            Ok(value) =>
              cases.push(
                Fixed(
                  id="fixed:" + line_number.to_string(),
                  digits~,
                  value~,
                  rounding~,
                  expected_digits=tokens[5],
                  expected_exponent10=exponent10,
                  inexact~,
                ),
              )
            Err(_) =>
              diagnostics.push(
                row_diagnostic(
                  source, line_number, "invalid MPFR decimal output value",
                ),
              )
          }
        _ =>
          diagnostics.push(
            row_diagnostic(
              source, line_number, "invalid MPFR decimal output field",
            ),
          )
      }
    } else if tokens[0] == "shortest" && tokens.length() == 4 {
      match (parse_int(tokens[1]), parse_int(tokens[3])) {
        (Some(precision), Some(count)) =>
          match @bin_float.BinFloat::from_hex(tokens[2], precision) {
            Ok(value) =>
              cases.push(
                Shortest(
                  id="shortest:" + line_number.to_string(),
                  value~,
                  expected_digit_count=count,
                ),
              )
            Err(_) =>
              diagnostics.push(
                row_diagnostic(
                  source, line_number, "invalid MPFR decimal output value",
                ),
              )
          }
        _ =>
          diagnostics.push(
            row_diagnostic(
              source, line_number, "invalid MPFR decimal output field",
            ),
          )
      }
    } else {
      diagnostics.push(
        row_diagnostic(
          source, line_number, "MPFR decimal output row must be a fixed row of eight fields or a shortest row of four",
        ),
      )
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases, })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn MpfrDecimalOutputDocument::source(
  self : MpfrDecimalOutputDocument,
) -> String {
  self.source
}

///|
pub fn MpfrDecimalOutputDocument::case_count(
  self : MpfrDecimalOutputDocument,
) -> Int32 {
  self.cases.length()
}

///|
/// Splits `[-]d.ddde[+-]x` (as printed by `to_decimal_string_ctx`) into its
/// digit string and the decimal exponent of the first digit.
fn split_scientific(text : String) -> (String, Int32)? {
  let body = if text.has_prefix("-") {
    text.view(start_offset=1).to_owned()
  } else {
    text
  }
  let mut split = -1
  for index = 0; index < body.length(); index = index + 1 {
    if body[index] == 'e' {
      split = index
      break
    }
  }
  guard split > 0 else { return None }
  let mantissa = body.view(end_offset=split).to_owned()
  let exponent_text = body.view(start_offset=split + 1).to_owned()
  let exponent_text = if exponent_text.has_prefix("+") {
    exponent_text.view(start_offset=1).to_owned()
  } else {
    exponent_text
  }
  let digits = StringBuilder()
  for character in mantissa {
    if character != '.' {
      digits.write_char(character)
    }
  }
  match parse_int(exponent_text) {
    Some(exponent) => Some((digits.to_string(), exponent))
    None => None
  }
}

///|
/// Number of significant digits of a shortest-form string, ignoring the sign,
/// leading zeros and the trailing zeros of positional notation (`1500` has two).
fn significant_digit_count(text : String) -> Int32 {
  let digits = StringBuilder()
  let mut in_exponent = false
  for character in text {
    if character == 'e' || character == 'E' {
      in_exponent = true
    }
    if !in_exponent && character >= '0' && character <= '9' {
      digits.write_char(character)
    }
  }
  let all = digits.to_string()
  let mut start = 0
  while start < all.length() && all[start] == '0' {
    start += 1
  }
  let mut end = all.length()
  while end > start && all[end - 1] == '0' {
    end -= 1
  }
  end - start
}

///|
pub fn execute_decimal_output_data(
  document : MpfrDecimalOutputDocument,
) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let (id, passed, message) = match case {
      Fixed(
        id~,
        digits~,
        value~,
        rounding~,
        expected_digits~,
        expected_exponent10~,
        inexact~
      ) => {
        let context = @bin_float.BinaryContext::unbounded(
          value.precision(),
          rounding~,
        )
        let (text, flags) = value.to_decimal_string_ctx(digits, context)
        match split_scientific(text) {
          Some((actual_digits, actual_exponent)) => {
            let passed = actual_digits == expected_digits &&
              actual_exponent == expected_exponent10 &&
              text.has_prefix("-") == value.is_negative() &&
              flags.inexact() == inexact &&
              !flags.overflow() &&
              !flags.underflow()
            (
              id,
              passed,
              if passed {
                ""
              } else {
                "fixed mismatch for " +
                value.to_hex() +
                " with " +
                digits.to_string() +
                " digits: expected " +
                expected_digits +
                "e" +
                expected_exponent10.to_string() +
                " inexact=" +
                inexact.to_string() +
                ", actual " +
                text +
                " inexact=" +
                flags.inexact().to_string()
              },
            )
          }
          None => (id, false, "unparsable decimal output " + text)
        }
      }
      Shortest(id~, value~, expected_digit_count~) => {
        let text = value.to_shortest_string()
        let count = significant_digit_count(text)
        // The text must read back as exactly this value at its own precision
        // and have the fewest digits MPFR finds for it.
        let reads_back = match
          @bin_float.BinFloat::from_string(text, precision=value.precision()) {
          Ok(parsed) =>
            parsed.compare(value) == 0 &&
            parsed.is_negative() == value.is_negative()
          Err(_) => false
        }
        let passed = reads_back && count == expected_digit_count
        (
          id,
          passed,
          if passed {
            ""
          } else {
            "shortest mismatch for " +
            value.to_hex() +
            ": expected " +
            expected_digit_count.to_string() +
            " digits, actual " +
            text +
            " (" +
            count.to_string() +
            " digits, reads back: " +
            reads_back.to_string() +
            ")"
          },
        )
      }
    }
    results.push({
      inner: @conformance.CaseResult::executable(id, passed, message~),
    })
  }
  summary_of(results)
}
