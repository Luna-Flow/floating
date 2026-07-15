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
  precision : Int
  positive : @binary.BinFloat
  unit : @binary.BinFloat
  quarter : @binary.BinFloat
  positive_checked : @checked.BinFloatResult
  unit_checked : @checked.BinFloatResult
  quarter_checked : @checked.BinFloatResult
}

///|
enum ElementaryOutput {
  Core(@binary.BinFloat)
  Checked(@checked.BinFloatResult)
}

///|
fn elementary_input(precision : Int) -> ElementaryInput {
  let positive = @binary.BinFloat::from_double(1.25, precision~)
  let unit = @binary.BinFloat::from_double(0.5, precision~)
  let quarter = @binary.BinFloat::from_double(0.25, precision~)
  {
    precision,
    positive,
    unit,
    quarter,
    positive_checked: @checked.BinFloatResult::ok(positive),
    unit_checked: @checked.BinFloatResult::ok(unit),
    quarter_checked: @checked.BinFloatResult::ok(quarter),
  }
}

///|
fn elementary_core(
  operation : ElementaryOperation,
  input : ElementaryInput,
) -> @binary.BinFloat {
  match operation {
    Exp => input.unit.exp()
    Exp2 => input.unit.exp2()
    Exp10 => input.unit.exp10()
    Expm1 => input.unit.expm1()
    Ln => input.positive.ln()
    Log2 => input.positive.log2()
    Log10 => input.positive.log10()
    Log1p => input.unit.log1p()
    Sqrt => input.positive.sqrt().unwrap()
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
) -> @checked.BinFloatResult {
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
  expected : @binary.BinFloat,
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
  Int,
  ElementaryInput,
  ElementaryInput,
  @binary.BinFloat,
  ElementaryOutput,
  Unit,
  ElementaryOutput?,
  ElementaryOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "bin-float/elementary/" + name,
    name,
    [53, 128, 512],
    precision => precision.to_string() + "bit",
    context => elementary_input(context.dataset_key.scale),
    input => name + ":" + input.precision.to_string(),
    [
      @runner.Implementation::stateless("core/bin-float", "0.7.0", input => {
        @model.OperationResult::completed(
          ElementaryOutput::Core(elementary_core(operation, input)),
          (),
        )
      }),
      @runner.Implementation::stateless("full/checked", "0.7.0", input => {
        @model.OperationResult::completed(
          ElementaryOutput::Checked(elementary_checked(operation, input)),
          (),
        )
      }),
    ],
    input => elementary_core(operation, input),
    elementary_matches,
    input => input.precision.to_string(),
    elementary_output_text,
  )
}

///|
test "elementary benchmark plans compile" {
  for operation in elementary_operations() {
    ignore(elementary_spec(operation).compile().unwrap())
  }
}

///|
#skip("performance benchmark")
async test "binary elementary core and full paths" {
  for operation in elementary_operations() {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/bin-float/elementary/" + name,
    )
    let summary = @benchkit.run(
      elementary_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "bin-float-elementary",
        "bin-float-elementary-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<3 {
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "bin-float/elementary/" + name,
        dataset_id,
        "core/bin-float",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=bin-float/elementary/" +
        name +
        "/" +
        dataset_id.to_string() +
        " full_pct=" +
        full.relative_delta_pct.to_string(),
      )
    }
  }
}
