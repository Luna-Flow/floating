///|
// `mpfr-random-v1`: seeded random differential rows produced by
// `tools/generate_mpfr_random_oracle.c`. One row carries the operation, the
// rounding direction, the output precision, an optional exponent range with
// its tininess rule, up to three exact operands and the MPFR result with its
// exception flags:
//
//   id op rounding precision emin emax tininess a b c n expected flags
//
// `-` stands for an absent field. `flags` is `-` or a subset of `xouvz`
// (inexact, overflow, underflow, invalid, division by zero).

///|
priv enum RandomKind {
  Arithmetic
  Elementary(MpfrElementaryOperation)
  Strtofr
  Getstr
  Shortest
}

///|
priv struct MpfrRandomCase {
  id : String
  op : String
  kind : RandomKind
  rounding : @bin_float.BinaryRoundingMode
  precision : Int32
  range : (Int32, Int32, @bin_float.TininessDetection)?
  a : @bin_float.BinFloat?
  literal : String
  b : @bin_float.BinFloat?
  c : @bin_float.BinFloat?
  n : Int32
  expected : String
  expected_value : @bin_float.BinFloat?
  flags : String
}

///|
pub struct MpfrRandomDocument {
  priv source : String
  priv cases : Array[MpfrRandomCase]
}

///|
pub fn MpfrRandomDocument::source(self : MpfrRandomDocument) -> String {
  self.source
}

///|
pub fn MpfrRandomDocument::case_count(self : MpfrRandomDocument) -> Int32 {
  self.cases.length()
}

///|
/// The row ids of the document, in order.
pub fn MpfrRandomDocument::case_ids(self : MpfrRandomDocument) -> Array[String] {
  self.cases.map(case => case.id)
}

///|
/// Parses an exact operand or result: `[-]0x<hex>p<exp>`, `inf`, `-inf`, `nan`.
/// The value keeps every digit written, so the precision is the digit count.
fn parse_random_value(
  token : String,
  precision : Int32,
) -> Result[@bin_float.BinFloat, String] {
  match token {
    "nan" => Ok(@bin_float.BinFloat::nan())
    "inf" => Ok(@bin_float.BinFloat::inf(@def.Sign::Positive))
    "-inf" => Ok(@bin_float.BinFloat::inf(@def.Sign::Negative))
    _ => {
      // Reading below the smallest subnormal of the parse precision would
      // round the value onto that grid, so read at least at the precision of
      // the row and wide enough that the lowest written bit, 2^exponent, lies
      // on the grid 2^(e_min - (width - 1)) of the implementation range.
      let precision = Int32::max(Int32::max(token.length() * 4, 8), precision)
      let precision = match token.find("p") {
        Some(index) =>
          match parse_int(token[index + 1:].to_owned()) {
            Some(exponent) =>
              Int32::max(
                precision,
                Int32::min(
                  @bin_float.binary_precision_max,
                  @bin_float.binary_implementation_e_min - exponent + 1,
                ),
              )
            None => precision
          }
        None => precision
      }
      match @bin_float.BinFloat::from_hex(token, precision) {
        Ok(value) => Ok(value)
        Err(_) => Err("invalid exact value " + token)
      }
    }
  }
}

///|
fn parse_random_operand(
  token : String,
  precision : Int32,
) -> Result[@bin_float.BinFloat?, String] {
  if token == "-" {
    Ok(None)
  } else {
    parse_random_value(token, precision).map(value => Some(value))
  }
}

///|
fn random_kind(name : String) -> RandomKind? {
  match name {
    "add" | "sub" | "mul" | "div" | "sqrt" | "fma" => Some(Arithmetic)
    "strtofr" => Some(Strtofr)
    "getstr" => Some(Getstr)
    "shortest" => Some(Shortest)
    _ =>
      match parse_elementary_operation(name) {
        Some(operation) => Some(Elementary(operation))
        None => None
      }
  }
}

///|
fn valid_random_flags(flags : String) -> Bool {
  if flags == "-" {
    return true
  }
  flags.length() > 0 &&
  flags.iter().all(character => "xouvz".contains_char(character))
}

///|
pub fn parse_random_data(
  source : String,
  text : String,
) -> Result[MpfrRandomDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrRandomCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  for line_index, line_view in text.split("\n") {
    let line_number = line_index + 1
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let tokens = tokenize(line)
    if tokens.length() != 13 {
      diagnostics.push(
        row_diagnostic(
          source, line_number, "MPFR random row must contain thirteen fields",
        ),
      )
      continue
    }
    match parse_random_row(tokens) {
      Ok(case) => cases.push(case)
      Err(message) =>
        diagnostics.push(row_diagnostic(source, line_number, message))
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases, })
  } else {
    Err(diagnostics)
  }
}

///|
fn parse_random_row(tokens : Array[String]) -> Result[MpfrRandomCase, String] {
  let kind = match random_kind(tokens[1]) {
    Some(kind) => kind
    None => return Err("unknown MPFR random operation " + tokens[1])
  }
  let rounding = match parse_rounding(tokens[2]) {
    Some(rounding) => rounding
    None => return Err("invalid MPFR random rounding " + tokens[2])
  }
  let precision = match parse_int(tokens[3]) {
    Some(value) if value >= 1 => value
    _ => return Err("invalid MPFR random precision " + tokens[3])
  }
  let range = if tokens[4] == "-" {
    None
  } else {
    match (parse_int(tokens[4]), parse_int(tokens[5]), tokens[6]) {
      // The column must agree with the constructor, which derives
      // e_min = 1 - e_max (IEEE 754-2019 3.3); the legal e_max and
      // precision are the constructor's to decide.
      (Some(low), Some(high), _) if low != 1 - high ||
        not_legal_range(precision, high) =>
        return Err("MPFR random exponent range is not an IEEE 754-2019 format")
      (Some(low), Some(high), "a") =>
        Some((low, high, @bin_float.TininessDetection::AfterRounding))
      (Some(low), Some(high), "b") =>
        Some((low, high, @bin_float.TininessDetection::BeforeRounding))
      _ => return Err("invalid MPFR random exponent range")
    }
  }
  let n = match parse_int(tokens[10]) {
    Some(value) => value
    None => return Err("invalid MPFR random integer " + tokens[10])
  }
  if !valid_random_flags(tokens[12]) {
    return Err("invalid MPFR random flags " + tokens[12])
  }
  let (a, literal) = match kind {
    Strtofr => (None, tokens[7])
    _ =>
      match parse_random_operand(tokens[7], precision) {
        Ok(value) => (value, "")
        Err(message) => return Err(message)
      }
  }
  let b = match parse_random_operand(tokens[8], precision) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let c = match parse_random_operand(tokens[9], precision) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let expected_value = match kind {
    Getstr | Shortest => None
    _ =>
      match parse_random_value(tokens[11], precision) {
        Ok(value) => Some(value)
        Err(message) => return Err(message)
      }
  }
  Ok({
    id: tokens[0],
    op: tokens[1],
    kind,
    rounding,
    precision,
    range,
    a,
    literal,
    b,
    c,
    n,
    expected: tokens[11],
    expected_value,
    flags: tokens[12],
  })
}

///|
fn not_legal_range(precision : Int32, e_max : Int32) -> Bool {
  @bin_float.BinaryContext::try_new(precision~, e_max~) is Err(_)
}

///|
fn random_context(case : MpfrRandomCase) -> @bin_float.BinaryContext {
  match case.range {
    Some((_, e_max, tininess)) =>
      @bin_float.BinaryContext::new(
        precision=case.precision,
        rounding=case.rounding,
        e_max~,
        tininess~,
      )
    None =>
      @bin_float.BinaryContext::new(
        precision=case.precision,
        rounding=case.rounding,
      )
  }
}

///|
fn random_flags_text(flags : @bin_float.BinaryFlags) -> String {
  let builder = StringBuilder()
  if flags.inexact() {
    builder.write_char('x')
  }
  if flags.overflow() {
    builder.write_char('o')
  }
  if flags.underflow() {
    builder.write_char('u')
  }
  if flags.invalid_operation() {
    builder.write_char('v')
  }
  if flags.division_by_zero() {
    builder.write_char('z')
  }
  let text = builder.to_string()
  if text.length() == 0 {
    "-"
  } else {
    text
  }
}

///|
/// Same value, same class and, for zeros and infinities, the same sign. A NaN
/// result only has to be a quiet NaN: IEEE 754 leaves the payload open.
fn same_random_value(
  actual : @bin_float.BinFloat,
  expected : @bin_float.BinFloat,
) -> Bool {
  if expected.is_quiet_nan() {
    return actual.is_quiet_nan()
  }
  if actual.is_quiet_nan() || actual.is_signaling_nan() {
    return false
  }
  @def.is_infinite(actual) == @def.is_infinite(expected) &&
  @def.is_zero(actual) == @def.is_zero(expected) &&
  actual.is_negative() == expected.is_negative() &&
  actual.compare(expected) == 0
}

///|
fn require_operand(
  value : @bin_float.BinFloat?,
  name : String,
) -> @bin_float.BinFloat {
  match value {
    Some(value) => value
    None => abort("MPFR random row misses operand " + name)
  }
}

///|
fn random_digits_message(
  case : MpfrRandomCase,
  actual : String,
  flags : @bin_float.BinaryFlags,
) -> String {
  case.op +
  " mismatch: expected " +
  case.expected +
  " flags=" +
  case.flags +
  ", actual " +
  actual +
  " flags=" +
  random_flags_text(flags)
}

///|
fn run_random_case(case : MpfrRandomCase) -> (Bool, String) {
  match case.kind {
    Getstr => run_random_getstr(case)
    Shortest => run_random_shortest(case)
    _ => run_random_real(case)
  }
}

///|
fn run_random_real(case : MpfrRandomCase) -> (Bool, String) {
  let context = random_context(case)
  let evaluated : Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @lf_arith.ArithmeticError,
  ] = match case.kind {
    Arithmetic =>
      match case.op {
        "add" =>
          Ok(
            require_operand(case.a, "a").add_ctx(
              require_operand(case.b, "b"),
              context,
            ),
          )
        "sub" =>
          Ok(
            require_operand(case.a, "a").sub_ctx(
              require_operand(case.b, "b"),
              context,
            ),
          )
        "mul" =>
          Ok(
            require_operand(case.a, "a").mul_ctx(
              require_operand(case.b, "b"),
              context,
            ),
          )
        "div" =>
          Ok(
            require_operand(case.a, "a").div_ctx(
              require_operand(case.b, "b"),
              context,
            ),
          )
        "sqrt" => Ok(require_operand(case.a, "a").sqrt_ctx(context))
        _ =>
          Ok(
            require_operand(case.a, "a").fma_ctx(
              require_operand(case.b, "b"),
              require_operand(case.c, "c"),
              context,
            ),
          )
      }
    Elementary(operation) =>
      evaluate_elementary(
        operation,
        require_operand(case.a, "a"),
        case.b,
        case.n,
        context,
      )
    _ =>
      match @bin_float.BinFloat::from_string_ctx(case.literal, context) {
        Ok(outcome) => Ok(outcome)
        Err(error) => Err(error)
      }
  }
  match evaluated {
    Err(error) =>
      // A domain error is the invalid operation of IEEE 754 (a quiet NaN and
      // the invalid flag); any other error is a refusal to answer.
      if error.is_domain_error() &&
        case.expected_value.unwrap().is_quiet_nan() &&
        case.flags == "v" {
        (true, "")
      } else {
        (
          false,
          case.op +
          " returned an error (" +
          error.message +
          ") for " +
          (if case.literal.length() > 0 {
            case.literal
          } else {
            "the operands"
          }) +
          ", expected " +
          case.expected +
          " flags=" +
          case.flags,
        )
      }
    Ok((actual, flags)) => {
      let passed = same_random_value(actual, case.expected_value.unwrap()) &&
        random_flags_text(flags) == case.flags
      (
        passed,
        if passed {
          ""
        } else {
          random_digits_message(case, actual.to_hex(), flags)
        },
      )
    }
  }
}

///|
fn run_random_getstr(case : MpfrRandomCase) -> (Bool, String) {
  let value = case.a.unwrap()
  // The operand is read at the precision of the row, as the context of a
  // conversion is that of the value written.
  let value = match
    @bin_float.BinFloat::from_hex(value.to_hex(), case.precision) {
    Ok(value) => value
    Err(_) => value
  }
  let context = @bin_float.BinaryContext::new(
    precision=value.precision(),
    rounding=case.rounding,
  )
  let (text, flags) = value.to_decimal_string_ctx(case.n, context)
  let actual_flags = random_flags_text(flags)
  match split_scientific(text) {
    None => (false, "unparsable decimal output " + text)
    Some((digits, exponent)) => {
      let actual = digits + "e" + exponent.to_string()
      let passed = actual == case.expected &&
        text.has_prefix("-") == value.is_negative() &&
        actual_flags == case.flags
      (
        passed,
        if passed {
          ""
        } else {
          "getstr mismatch for " +
          value.to_hex() +
          " with " +
          case.n.to_string() +
          " digits: expected " +
          case.expected +
          " flags=" +
          case.flags +
          ", actual " +
          text +
          " flags=" +
          actual_flags
        },
      )
    }
  }
}

///|
fn run_random_shortest(case : MpfrRandomCase) -> (Bool, String) {
  let value = case.a.unwrap()
  let value = match
    @bin_float.BinFloat::from_hex(value.to_hex(), case.precision) {
    Ok(value) => value
    Err(_) => value
  }
  let text = value.to_shortest_string()
  let count = significant_digit_count(text)
  let reads_back = match
    @bin_float.BinFloat::from_string(text, precision=value.precision()) {
    Ok(parsed) =>
      parsed.compare(value) == 0 && parsed.is_negative() == value.is_negative()
    Err(_) => false
  }
  let passed = reads_back && count.to_string() == case.expected
  (
    passed,
    if passed {
      ""
    } else {
      "shortest mismatch for " +
      value.to_hex() +
      ": expected " +
      case.expected +
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

///|
pub fn execute_random_data(document : MpfrRandomDocument) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let (passed, message) = run_random_case(case)
    results.push({
      inner: @conformance.CaseResult::executable(case.id, passed, message~),
    })
  }
  summary_of(results)
}
