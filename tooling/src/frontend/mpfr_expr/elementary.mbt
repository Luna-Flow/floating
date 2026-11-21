///|
priv enum MpfrElementaryOperation {
  Exp
  Exp2
  Exp10
  Expm1
  Exp2m1
  Exp10m1
  Ln
  Log2
  Log10
  Log1p
  Log2p1
  Log10p1
  Sqrt
  Rootn
  Pown
  Pow
  Hypot
  Rsqrt
  Compound
  Powr
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
  Asinpi
  Acospi
  Atanpi
  Atan2pi
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
  integer : Int32
  expected : @bin_float.BinFloat
  output_precision : Int32
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
    "exp2m1" => Some(Exp2m1)
    "exp10m1" => Some(Exp10m1)
    "ln" => Some(Ln)
    "log2" => Some(Log2)
    "log10" => Some(Log10)
    "log1p" => Some(Log1p)
    "log2p1" => Some(Log2p1)
    "log10p1" => Some(Log10p1)
    "sqrt" => Some(Sqrt)
    "rootn" => Some(Rootn)
    "pown" => Some(Pown)
    "pow" => Some(Pow)
    "hypot" => Some(Hypot)
    "rsqrt" => Some(Rsqrt)
    "compound" => Some(Compound)
    "powr" => Some(Powr)
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
    "asinpi" => Some(Asinpi)
    "acospi" => Some(Acospi)
    "atanpi" => Some(Atanpi)
    "atan2pi" => Some(Atan2pi)
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
/// The operations that read the second operand field.
fn elementary_operation_is_binary(operation : MpfrElementaryOperation) -> Bool {
  operation is (Pow | Hypot | Atan2 | Powr | Atan2pi)
}

///|
/// The precision at which an operand token is read: `max(512, 4 * length)`, so
/// that the digits written always fit (a row whose operand has more bits than its
/// result precision is read exactly, never rounded).
fn operand_precision(token : String) -> Int32 {
  Int32::max(512, token.length() * 4)
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
    // An operand is read at a precision that cannot round it: four bits per
    // character of its token (at least 512), more than its hexadecimal digits hold.
    let left = @bin_float.BinFloat::from_hex(
      tokens[3],
      operand_precision(tokens[3]),
    )
    let right = if tokens[4] == "-" {
      Ok(None)
    } else {
      @bin_float.BinFloat::from_hex(tokens[4], operand_precision(tokens[4])).map(value => {
          Some(value)
        },
      )
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
      ) if right is Some(_) || !elementary_operation_is_binary(operation) =>
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
    Ok({ source, cases, })
  } else {
    Err(diagnostics)
  }
}

///|
pub fn MpfrElementaryDocument::source(self : MpfrElementaryDocument) -> String {
  self.source
}

///|
pub fn MpfrElementaryDocument::case_count(
  self : MpfrElementaryDocument,
) -> Int32 {
  self.cases.length()
}

///|
fn evaluate_elementary(
  operation : MpfrElementaryOperation,
  left : @bin_float.BinFloat,
  right : @bin_float.BinFloat?,
  integer : Int32,
  context : @bin_float.BinaryContext,
) -> Result[
  (@bin_float.BinFloat, @bin_float.BinaryFlags),
  @lf_arith.ArithmeticError,
] {
  match operation {
    Exp => left.try_exp_ctx(context)
    Exp2 => left.try_exp2_ctx(context)
    Exp10 => left.try_exp10_ctx(context)
    Expm1 => left.try_expm1_ctx(context)
    Exp2m1 => left.try_exp2m1_ctx(context)
    Exp10m1 => left.try_exp10m1_ctx(context)
    Ln => left.try_ln_ctx(context)
    Log2 => left.try_log2_ctx(context)
    Log10 => left.try_log10_ctx(context)
    Log1p => left.try_log1p_ctx(context)
    Log2p1 => left.try_log2p1_ctx(context)
    Log10p1 => left.try_log10p1_ctx(context)
    Sqrt => Ok(left.sqrt_ctx(context))
    Rootn => left.try_rootn_ctx(integer, context)
    Pown => Ok(left.pown_ctx(integer, context))
    Pow => left.try_pow_ctx(right.unwrap(), context)
    Hypot => left.try_hypot_ctx(right.unwrap(), context)
    Rsqrt => left.try_rsqrt_ctx(context)
    Compound => left.try_compound_ctx(integer, context)
    Powr => left.try_powr_ctx(right.unwrap(), context)
    Sin => left.try_sin_ctx(context)
    Cos => left.try_cos_ctx(context)
    Tan => left.try_tan_ctx(context)
    Sinpi => left.try_sinpi_ctx(context)
    Cospi => left.try_cospi_ctx(context)
    Tanpi => left.try_tanpi_ctx(context)
    Asin => left.try_asin_ctx(context)
    Acos => left.try_acos_ctx(context)
    Atan => left.try_atan_ctx(context)
    Atan2 => left.try_atan2_ctx(right.unwrap(), context)
    Asinpi => left.try_asinpi_ctx(context)
    Acospi => left.try_acospi_ctx(context)
    Atanpi => left.try_atanpi_ctx(context)
    Atan2pi => left.try_atan2pi_ctx(right.unwrap(), context)
    Sinh => left.try_sinh_ctx(context)
    Cosh => left.try_cosh_ctx(context)
    Tanh => left.try_tanh_ctx(context)
    Asinh => left.try_asinh_ctx(context)
    Acosh => left.try_acosh_ctx(context)
    Atanh => left.try_atanh_ctx(context)
  }
}

///|
fn evaluate_elementary_case(
  case : MpfrElementaryCase,
) -> Result[
  (@bin_float.BinFloat, @bin_float.BinaryFlags),
  @lf_arith.ArithmeticError,
] {
  let context = @bin_float.BinaryContext::new(
    precision=case.output_precision,
    rounding=case.rounding,
  )
  evaluate_elementary(
    case.operation,
    case.left,
    case.right,
    case.integer,
    context,
  )
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
        // `compare` treats -0 and +0 as equal; MPFR results carry the sign.
        let passed = actual.compare(case.expected) == 0 &&
          (
            !actual.is_zero() ||
            actual.is_negative() == case.expected.is_negative()
          ) &&
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
