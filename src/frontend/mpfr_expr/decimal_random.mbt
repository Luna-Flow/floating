///|
// `mpfr-decimal-random-v1`: seeded random differential rows for the IEEE
// decimal elementary functions, produced by
// `tools/generate_mpfr_decimal_random.py`. The expected result is the rounding
// of a certified 768-bit MPFR enclosure (never a single MPFR result): a row
// exists only if both enclosure endpoints round to one representation with one
// flag set and the rounded value lies outside the enclosure (so the true value
// is inexact). One row carries the operation, the decimal context, up to two
// exact operands and the expected value with its flags:
//
//   id op rounding precision emin emax clamp tininess a b n expected flags
//
// `rounding` is `half_even`, `half_up`, `half_down`, `down`, `ceiling`,
// `floor`, `up` or `05up`; `clamp` is `0` or `1`; `tininess` is `b` (before
// rounding) or `a` (after rounding); `-` stands for an absent field. `flags` is
// `-` or a subset of `xrosucvz` (inexact, rounded, overflow, subnormal,
// underflow, clamped, invalid operation, division by zero).

///|
priv struct DecimalRandomCase {
  id : String
  op : String
  context : @decimal.DecimalContext
  a : @decimal.Decimal
  b : @decimal.Decimal?
  n : Int32
  expected : @decimal.Decimal
  flags : String
}

///|
pub struct MpfrDecimalRandomDocument {
  priv source : String
  priv cases : Array[DecimalRandomCase]
}

///|
pub fn MpfrDecimalRandomDocument::source(
  self : MpfrDecimalRandomDocument,
) -> String {
  self.source
}

///|
pub fn MpfrDecimalRandomDocument::case_count(
  self : MpfrDecimalRandomDocument,
) -> Int32 {
  self.cases.length()
}

///|
/// The row ids of the document, in order.
pub fn MpfrDecimalRandomDocument::case_ids(
  self : MpfrDecimalRandomDocument,
) -> Array[String] {
  self.cases.map(case => case.id)
}

///|
fn parse_decimal_rounding(source : String) -> @decimal.DecimalRoundingMode? {
  match source {
    "half_even" => Some(@decimal.DecimalRoundingMode::HalfEven)
    "half_up" => Some(@decimal.DecimalRoundingMode::HalfUp)
    "half_down" => Some(@decimal.DecimalRoundingMode::HalfDown)
    "down" => Some(@decimal.DecimalRoundingMode::Down)
    "ceiling" => Some(@decimal.DecimalRoundingMode::Ceiling)
    "floor" => Some(@decimal.DecimalRoundingMode::Floor)
    "up" => Some(@decimal.DecimalRoundingMode::Up)
    "05up" => Some(@decimal.DecimalRoundingMode::ZeroFiveUp)
    _ => None
  }
}

///|
/// Operations whose operand count and shape are known to the executor.
/// 0: one decimal operand; 1: two decimal operands; 2: one decimal operand and
/// an integer.
fn decimal_random_shape(op : String) -> Int32? {
  match op {
    "exp"
    | "exp2"
    | "exp10"
    | "expm1"
    | "ln"
    | "log2"
    | "log10"
    | "log1p"
    | "sin"
    | "cos"
    | "tan"
    | "sinpi"
    | "cospi"
    | "tanpi"
    | "asin"
    | "acos"
    | "atan"
    | "sinh"
    | "cosh"
    | "tanh"
    | "asinh"
    | "acosh"
    | "atanh"
    | "exp2m1"
    | "exp10m1"
    | "log2p1"
    | "log10p1"
    | "rsqrt"
    | "asinpi"
    | "acospi"
    | "atanpi" => Some(0)
    "pow" | "hypot" | "atan2" | "powr" | "atan2pi" => Some(1)
    "rootn" | "pown" | "compound" => Some(2)
    _ => None
  }
}

///|
fn parse_decimal_random_operand(token : String) -> @decimal.Decimal? {
  // Every digit written is kept: the default precision of `from_string`
  // would round a wide operand or expected value.
  @decimal.Decimal::from_string(token, precision=Int32::max(token.length(), 1))
}

///|
pub fn parse_decimal_random_data(
  source : String,
  text : String,
) -> Result[MpfrDecimalRandomDocument, Array[ParseDiagnostic]] {
  let cases : Array[DecimalRandomCase] = []
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
          source, line_number, "MPFR decimal random row must contain thirteen fields",
        ),
      )
      continue
    }
    match parse_decimal_random_row(tokens) {
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
fn parse_decimal_random_row(
  tokens : Array[String],
) -> Result[DecimalRandomCase, String] {
  let shape = match decimal_random_shape(tokens[1]) {
    Some(shape) => shape
    None => return Err("unknown MPFR decimal random operation " + tokens[1])
  }
  let rounding = match parse_decimal_rounding(tokens[2]) {
    Some(rounding) => rounding
    None => return Err("invalid decimal rounding " + tokens[2])
  }
  let precision = match parse_int(tokens[3]) {
    Some(value) if value >= 1 => value
    _ => return Err("invalid decimal precision " + tokens[3])
  }
  let e_min = match parse_int(tokens[4]) {
    Some(value) => value
    None => return Err("invalid decimal e_min " + tokens[4])
  }
  let e_max = match parse_int(tokens[5]) {
    Some(value) => value
    None => return Err("invalid decimal e_max " + tokens[5])
  }
  let clamp = match parse_bool_digit(tokens[6]) {
    Some(value) => value
    None => return Err("invalid decimal clamp " + tokens[6])
  }
  let tininess = match tokens[7] {
    "b" => @decimal.DecimalTininessDetection::BeforeRounding
    "a" => @decimal.DecimalTininessDetection::AfterRounding
    _ => return Err("invalid decimal tininess " + tokens[7])
  }
  let context = match
    @decimal.DecimalContext::new(
      precision~,
      decimal_rounding=rounding,
      e_min~,
      e_max~,
      clamp~,
      tininess~,
    ) {
    Ok(context) => context
    Err(_) => return Err("invalid decimal context")
  }
  let a = match parse_decimal_random_operand(tokens[8]) {
    Some(value) => value
    None => return Err("invalid decimal operand " + tokens[8])
  }
  let b = if tokens[9] == "-" {
    None
  } else {
    match parse_decimal_random_operand(tokens[9]) {
      Some(value) => Some(value)
      None => return Err("invalid decimal operand " + tokens[9])
    }
  }
  if shape == 1 && b is None {
    return Err("operation " + tokens[1] + " needs a second operand")
  }
  let n = match parse_int(tokens[10]) {
    Some(value) => value
    None => return Err("invalid decimal integer " + tokens[10])
  }
  let expected = match parse_decimal_random_operand(tokens[11]) {
    Some(value) => value
    None => return Err("invalid decimal expected value " + tokens[11])
  }
  if !valid_decimal_random_flags(tokens[12]) {
    return Err("invalid decimal flags " + tokens[12])
  }
  Ok({
    id: tokens[0],
    op: tokens[1],
    context,
    a,
    b,
    n,
    expected,
    flags: tokens[12],
  })
}

///|
fn valid_decimal_random_flags(flags : String) -> Bool {
  if flags == "-" {
    return true
  }
  flags.length() > 0 &&
  flags.iter().all(character => "xrosucvz".contains_char(character))
}

///|
fn decimal_random_flags_text(flags : @decimal.DecimalFlags) -> String {
  let builder = StringBuilder()
  if flags.contains(Inexact) {
    builder.write_char('x')
  }
  if flags.contains(Rounded) {
    builder.write_char('r')
  }
  if flags.contains(Overflow) {
    builder.write_char('o')
  }
  if flags.contains(Subnormal) {
    builder.write_char('s')
  }
  if flags.contains(Underflow) {
    builder.write_char('u')
  }
  if flags.contains(Clamped) {
    builder.write_char('c')
  }
  if flags.contains(InvalidOperation) {
    builder.write_char('v')
  }
  if flags.contains(DivisionByZero) {
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
/// Runs the operation under test: the `try_*_ctx` form, so a certification
/// failure is a visible disagreement and not a quiet NaN.
fn run_decimal_random_operation(
  case : DecimalRandomCase,
) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), String] {
  let a = case.a
  let ctx = case.context
  let result = match case.op {
    "exp" => a.try_exp_ctx(ctx)
    "exp2" => a.try_exp2_ctx(ctx)
    "exp10" => a.try_exp10_ctx(ctx)
    "expm1" => a.try_expm1_ctx(ctx)
    "ln" => a.try_ln_ctx(ctx)
    "log2" => a.try_log2_ctx(ctx)
    "log10" => a.try_log10_ctx(ctx)
    "log1p" => a.try_log1p_ctx(ctx)
    "sin" => a.try_sin_ctx(ctx)
    "cos" => a.try_cos_ctx(ctx)
    "tan" => a.try_tan_ctx(ctx)
    "sinpi" => a.try_sinpi_ctx(ctx)
    "cospi" => a.try_cospi_ctx(ctx)
    "tanpi" => a.try_tanpi_ctx(ctx)
    "asin" => a.try_asin_ctx(ctx)
    "acos" => a.try_acos_ctx(ctx)
    "atan" => a.try_atan_ctx(ctx)
    "sinh" => a.try_sinh_ctx(ctx)
    "cosh" => a.try_cosh_ctx(ctx)
    "tanh" => a.try_tanh_ctx(ctx)
    "asinh" => a.try_asinh_ctx(ctx)
    "acosh" => a.try_acosh_ctx(ctx)
    "atanh" => a.try_atanh_ctx(ctx)
    "exp2m1" => a.try_exp2m1_ctx(ctx)
    "exp10m1" => a.try_exp10m1_ctx(ctx)
    "log2p1" => a.try_log2p1_ctx(ctx)
    "log10p1" => a.try_log10p1_ctx(ctx)
    "pow" => a.try_power_ctx(case.b.unwrap(), ctx)
    "hypot" => a.try_hypot_ctx(case.b.unwrap(), ctx)
    "atan2" => a.try_atan2_ctx(case.b.unwrap(), ctx)
    "rootn" => a.try_rootn_ctx(case.n, ctx)
    "pown" => a.try_pown_ctx(case.n, ctx)
    "rsqrt" => a.try_rsqrt_ctx(ctx)
    "asinpi" => a.try_asinpi_ctx(ctx)
    "acospi" => a.try_acospi_ctx(ctx)
    "atanpi" => a.try_atanpi_ctx(ctx)
    "atan2pi" => a.try_atan2pi_ctx(case.b.unwrap(), ctx)
    "powr" => a.try_powr_ctx(case.b.unwrap(), ctx)
    "compound" => a.try_compound_ctx(case.n, ctx)
    _ => abort("unreachable decimal random operation " + case.op)
  }
  match result {
    Ok(pair) => Ok(pair)
    Err(_) => Err("certification failure")
  }
}

///|
fn run_decimal_random_case(case : DecimalRandomCase) -> (Bool, String) {
  match run_decimal_random_operation(case) {
    Err(message) =>
      (
        false,
        case.op +
        " " +
        message +
        " (expected " +
        case.expected.to_string() +
        ")",
      )
    Ok((actual, flags)) => {
      let actual_flags = decimal_random_flags_text(flags)
      let same_value = actual.compare_total(case.expected) == 0
      let passed = same_value && actual_flags == case.flags
      (
        passed,
        if passed {
          ""
        } else {
          case.op +
          " mismatch: expected " +
          case.expected.to_string() +
          " flags=" +
          case.flags +
          ", actual " +
          actual.to_string() +
          " flags=" +
          actual_flags
        },
      )
    }
  }
}

///|
pub fn execute_decimal_random_data(
  document : MpfrDecimalRandomDocument,
) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    let (passed, message) = run_decimal_random_case(case)
    results.push({
      inner: @conformance.CaseResult::executable(case.id, passed, message~),
    })
  }
  summary_of(results)
}
