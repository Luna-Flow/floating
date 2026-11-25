///|
enum ElementaryOperation {
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
fn elementary_operations() -> Array[ElementaryOperation] {
  [
    Exp,
    Exp2,
    Exp10,
    Expm1,
    Ln,
    Log2,
    Log10,
    Log1p,
    Sqrt,
    Rootn,
    Pow,
    Hypot,
    Sin,
    Cos,
    Tan,
    Sinpi,
    Cospi,
    Tanpi,
    Asin,
    Acos,
    Atan,
    Atan2,
    Sinh,
    Cosh,
    Tanh,
    Asinh,
    Acosh,
    Atanh,
  ]
}

///|
fn ElementaryOperation::name(self : ElementaryOperation) -> String {
  match self {
    Exp => "exp"
    Exp2 => "exp2"
    Exp10 => "exp10"
    Expm1 => "expm1"
    Ln => "ln"
    Log2 => "log2"
    Log10 => "log10"
    Log1p => "log1p"
    Sqrt => "sqrt"
    Rootn => "rootn"
    Pow => "pow"
    Hypot => "hypot"
    Sin => "sin"
    Cos => "cos"
    Tan => "tan"
    Sinpi => "sinpi"
    Cospi => "cospi"
    Tanpi => "tanpi"
    Asin => "asin"
    Acos => "acos"
    Atan => "atan"
    Atan2 => "atan2"
    Sinh => "sinh"
    Cosh => "cosh"
    Tanh => "tanh"
    Asinh => "asinh"
    Acosh => "acosh"
    Atanh => "atanh"
  }
}

///|
struct ElementaryInput {
  precision : Int32
  positive : @bin.Binary
  unit : @bin.Binary
  quarter : @bin.Binary
  positive_checked : @checked.BinaryChecked
  unit_checked : @checked.BinaryChecked
  quarter_checked : @checked.BinaryChecked
}

///|
enum ElementaryOutput {
  Core(@bin.Binary)
  Checked(@checked.BinaryChecked)
}

///|
fn elementary_input(precision : Int32) -> ElementaryInput {
  let positive = @bin.Binary::from_double(1.25, precision~)
  let unit = @bin.Binary::from_double(0.5, precision~)
  let quarter = @bin.Binary::from_double(0.25, precision~)
  {
    precision,
    positive,
    unit,
    quarter,
    positive_checked: @checked.BinaryChecked::ok(positive),
    unit_checked: @checked.BinaryChecked::ok(unit),
    quarter_checked: @checked.BinaryChecked::ok(quarter),
  }
}

///|
fn elementary_core(
  operation : ElementaryOperation,
  input : ElementaryInput,
) -> @bin.Binary {
  match operation {
    Exp => input.unit.exp()
    Exp2 => input.unit.exp2()
    Exp10 => input.unit.exp10()
    Expm1 => input.unit.expm1()
    Ln => input.positive.ln()
    Log2 => input.positive.log2()
    Log10 => input.positive.log10()
    Log1p => input.unit.log1p()
    Sqrt => input.positive.sqrt()
    Rootn => input.positive.rootn(3)
    Pow => input.positive.pow(input.unit)
    Hypot => input.positive.hypot(input.unit)
    Sin => input.unit.sin()
    Cos => input.unit.cos()
    Tan => input.unit.tan()
    Sinpi => input.quarter.sinpi()
    Cospi => input.quarter.cospi()
    Tanpi => input.quarter.tanpi()
    Asin => input.unit.asin()
    Acos => input.unit.acos()
    Atan => input.unit.atan()
    Atan2 => input.unit.atan2(input.positive)
    Sinh => input.unit.sinh()
    Cosh => input.unit.cosh()
    Tanh => input.unit.tanh()
    Asinh => input.unit.asinh()
    Acosh => input.positive.acosh()
    Atanh => input.unit.atanh()
  }
}

///|
fn elementary_checked(
  operation : ElementaryOperation,
  input : ElementaryInput,
) -> @checked.BinaryChecked {
  match operation {
    Exp => input.unit_checked.exp()
    Exp2 => input.unit_checked.exp2()
    Exp10 => input.unit_checked.exp10()
    Expm1 => input.unit_checked.expm1()
    Ln => input.positive_checked.ln()
    Log2 => input.positive_checked.log2()
    Log10 => input.positive_checked.log10()
    Log1p => input.unit_checked.log1p()
    Sqrt => input.positive_checked.sqrt()
    Rootn => input.positive_checked.rootn(3)
    Pow => input.positive_checked.pow(input.unit_checked)
    Hypot => input.positive_checked.hypot(input.unit_checked)
    Sin => input.unit_checked.sin()
    Cos => input.unit_checked.cos()
    Tan => input.unit_checked.tan()
    Sinpi => input.quarter_checked.sinpi()
    Cospi => input.quarter_checked.cospi()
    Tanpi => input.quarter_checked.tanpi()
    Asin => input.unit_checked.asin()
    Acos => input.unit_checked.acos()
    Atan => input.unit_checked.atan()
    Atan2 => input.unit_checked.atan2(input.positive_checked)
    Sinh => input.unit_checked.sinh()
    Cosh => input.unit_checked.cosh()
    Tanh => input.unit_checked.tanh()
    Asinh => input.unit_checked.asinh()
    Acosh => input.positive_checked.acosh()
    Atanh => input.unit_checked.atanh()
  }
}

///|
fn elementary_matches(
  expected : @bin.Binary,
  output : ElementaryOutput,
) -> Bool {
  match output {
    Core(actual) => actual.compare(expected) == 0
    Checked(actual) =>
      match actual.result() {
        Ok(value) => value.compare(expected) == 0
        Err(_) => false
      }
  }
}

///|
fn elementary_output_text(output : ElementaryOutput) -> String {
  match output {
    Core(value) => value.to_hex()
    Checked(value) =>
      match value.result() {
        Ok(result) => result.to_hex()
        Err(_) => "error"
      }
  }
}

///|
fn elementary_spec(
  operation : ElementaryOperation,
) -> @runner.BenchSpec[
  Int32,
  ElementaryInput,
  ElementaryInput,
  @bin.Binary,
  ElementaryOutput,
  Unit,
  ElementaryOutput?,
  ElementaryOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "binary/elementary/" + name,
    name,
    [53, 128, 512],
    precision => precision.to_string() + "bit",
    context => elementary_input(context.dataset_key.scale),
    input => name + ":" + input.precision.to_string(),
    [
      @runner.Implementation::stateless("core/binary", "0.8.0", input => {
        @model.OperationResult::completed(
          ElementaryOutput::Core(elementary_core(operation, input)),
          (),
        )
      }),
      @runner.Implementation::stateless("full/checked", "0.8.0", input => {
        @model.OperationResult::completed(
          ElementaryOutput::Checked(elementary_checked(operation, input)),
          (),
        )
      }),
    ],
    // Timing harness check, no validation claim (level S): the reference of this
    // comparison is the library function that the first implementation times, so
    // it can only show that the two timed paths agree with each other, not that
    // either is right. The correctness oracles are the corpora and the
    // external baseline (`bench/external`, MPFR and libmpdec).
    input => elementary_core(operation, input),
    elementary_matches,
    input => input.precision.to_string(),
    elementary_output_text,
  )
}

///|
// oracle: S
// source: no expected value: the block only requires that each benchmark spec compiles (the unwrap of the compile
//   result), so the verdict is the absence of a compile error
// shares: elementary_spec and BenchSpec::compile (the code under test)
test "elementary benchmark plans compile" {
  for operation in elementary_operations() {
    ignore(elementary_spec(operation).compile().unwrap())
  }
}
