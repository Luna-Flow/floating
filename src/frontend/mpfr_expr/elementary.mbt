///|
priv enum MpfrElementaryOperation {
  Exp
  Exp2
  Exp10
  Expm1
  Ln
  Log2
  Log10
  Log1p
  Sqrt
  Rootn
  Pown
  Pow
  Hypot
  Sin
  Cos
  Tan
  Sinpi
  Cospi
  Tanpi
  Asin
  Acos
  Atan
  Atan2
  Sinh
  Cosh
  Tanh
  Asinh
  Acosh
  Atanh
}

///|
priv struct MpfrElementaryCase {
  id : String
  operation : MpfrElementaryOperation
  left : @bin_float.BinFloat
  right : @bin_float.BinFloat?
  integer : Int
  expected : @bin_float.BinFloat
  output_precision : Int
  rounding : @bin_float.BinaryRoundingMode
  inexact : Bool
  invalid : Bool
  division_by_zero : Bool
}

///|
pub struct MpfrElementaryDocument {
  priv source : String
  priv cases : Array[MpfrElementaryCase]
}

///|
fn parse_elementary_operation(source : String) -> MpfrElementaryOperation? {
  match source {
    "exp" => Some(Exp)
    "exp2" => Some(Exp2)
    "exp10" => Some(Exp10)
    "expm1" => Some(Expm1)
    "ln" => Some(Ln)
    "log2" => Some(Log2)
    "log10" => Some(Log10)
    "log1p" => Some(Log1p)
    "sqrt" => Some(Sqrt)
    "rootn" => Some(Rootn)
    "pown" => Some(Pown)
    "pow" => Some(Pow)
    "hypot" => Some(Hypot)
    "sin" => Some(Sin)
    "cos" => Some(Cos)
    "tan" => Some(Tan)
    "sinpi" => Some(Sinpi)
    "cospi" => Some(Cospi)
    "tanpi" => Some(Tanpi)
    "asin" => Some(Asin)
    "acos" => Some(Acos)
    "atan" => Some(Atan)
    "atan2" => Some(Atan2)
    "sinh" => Some(Sinh)
    "cosh" => Some(Cosh)
    "tanh" => Some(Tanh)
    "asinh" => Some(Asinh)
    "acosh" => Some(Acosh)
    "atanh" => Some(Atanh)
    _ => None
  }
}

///|
pub fn parse_elementary_data(
  source : String,
  text : String,
) -> Result[MpfrElementaryDocument, Array[ParseDiagnostic]] {
  let cases : Array[MpfrElementaryCase] = []
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
        message: "MPFR elementary row must contain ten fields",
      })
      continue
    }
    let operation = parse_elementary_operation(tokens[0])
    let output_precision = parse_int(tokens[1])
    let rounding = parse_rounding(tokens[2])
    let left = @bin_float.BinFloat::from_hex(tokens[3], 512)
    let right = if tokens[4] == "-" {
      Ok(None)
    } else {
      @bin_float.BinFloat::from_hex(tokens[4], 512).map(value => Some(value))
    }
    let integer = parse_int(tokens[5])
    let inexact = parse_bool_digit(tokens[7])
    let invalid = parse_bool_digit(tokens[8])
    let division_by_zero = parse_bool_digit(tokens[9])
    match
      (
        operation, output_precision, rounding, left, right, integer, inexact, invalid,
        division_by_zero,
      ) {
      (
        Some(operation),
        Some(output_precision),
        Some(rounding),
        Ok(left),
        Ok(right),
        Some(integer),
        Some(inexact),
        Some(invalid),
        Some(division_by_zero),
      ) =>
        match @bin_float.BinFloat::from_hex(tokens[6], output_precision) {
          Ok(expected) =>
            cases.push({
              id: tokens[0] + ":" + line_number.to_string(),
              operation,
              left,
              right,
              integer,
              expected,
              output_precision,
              rounding,
              inexact,
              invalid,
              division_by_zero,
            })
          Err(_) =>
            diagnostics.push({
              location: @conformance.SourceLocation::new(source, line_number),
              message: "invalid MPFR elementary expected value",
            })
        }
      _ =>
        diagnostics.push({
          location: @conformance.SourceLocation::new(source, line_number),
          message: "invalid MPFR elementary field",
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
pub fn MpfrElementaryDocument::source(self : MpfrElementaryDocument) -> String {
  self.source
}

///|
pub fn MpfrElementaryDocument::case_count(self : MpfrElementaryDocument) -> Int {
  self.cases.length()
}

///|
fn evaluate_elementary_case(
  case : MpfrElementaryCase,
) -> Result[
  (@bin_float.BinFloat, @bin_float.BinaryFlags),
  @lf_arith.ArithmeticError,
] {
  let context = @bin_float.BinaryContext::unbounded(
    case.output_precision,
    rounding=case.rounding,
  )
  match case.operation {
    Exp => case.left.try_exp_ctx(context)
    Exp2 => case.left.try_exp2_ctx(context)
    Exp10 => case.left.try_exp10_ctx(context)
    Expm1 => case.left.try_expm1_ctx(context)
    Ln => case.left.try_ln_ctx(context)
    Log2 => case.left.try_log2_ctx(context)
    Log10 => case.left.try_log10_ctx(context)
    Log1p => case.left.try_log1p_ctx(context)
    Sqrt => Ok(case.left.sqrt_ctx(context))
    Rootn => case.left.try_rootn_ctx(case.integer, context)
    Pown => Ok(case.left.pown_ctx(case.integer, context))
    Pow => case.left.try_pow_ctx(case.right.unwrap(), context)
    Hypot => case.left.try_hypot_ctx(case.right.unwrap(), context)
    Sin => case.left.try_sin_ctx(context)
    Cos => case.left.try_cos_ctx(context)
    Tan => case.left.try_tan_ctx(context)
    Sinpi => case.left.try_sinpi_ctx(context)
    Cospi => case.left.try_cospi_ctx(context)
    Tanpi => case.left.try_tanpi_ctx(context)
    Asin => case.left.try_asin_ctx(context)
    Acos => case.left.try_acos_ctx(context)
    Atan => case.left.try_atan_ctx(context)
    Atan2 => case.left.try_atan2_ctx(case.right.unwrap(), context)
    Sinh => case.left.try_sinh_ctx(context)
    Cosh => case.left.try_cosh_ctx(context)
    Tanh => case.left.try_tanh_ctx(context)
    Asinh => case.left.try_asinh_ctx(context)
    Acosh => case.left.try_acosh_ctx(context)
    Atanh => case.left.try_atanh_ctx(context)
  }
}

///|
pub fn execute_elementary_data(document : MpfrElementaryDocument) -> RunSummary {
  let results : Array[CaseResult] = []
  for case in document.cases {
    match evaluate_elementary_case(case) {
      Err(_) =>
        results.push({
          inner: @conformance.CaseResult::executable(
            case.id,
            false,
            message="certification failure for MPFR differential case",
          ),
        })
      Ok((actual, flags)) => {
        let passed = actual.compare(case.expected) == 0 &&
          flags.inexact() == case.inexact &&
          flags.invalid_operation() == case.invalid &&
          flags.division_by_zero() == case.division_by_zero &&
          !flags.underflow() &&
          !flags.overflow()
        results.push({
          inner: @conformance.CaseResult::executable(
            case.id,
            passed,
            message=if passed {
              ""
            } else {
              "elementary mismatch: expected " +
              case.expected.to_hex() +
              " flags=" +
              case.inexact.to_string() +
              "/" +
              case.invalid.to_string() +
              "/" +
              case.division_by_zero.to_string() +
              ", actual " +
              actual.to_hex() +
              " flags=" +
              flags.inexact().to_string() +
              "/" +
              flags.invalid_operation().to_string() +
              "/" +
              flags.division_by_zero().to_string()
            },
          ),
        })
      }
    }
  }
  {
    inner: @conformance.RunSummary::from_results(
      document.cases.length(),
      results.map(result => result.inner),
    ),
  }
}
