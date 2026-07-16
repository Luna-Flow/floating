///|
enum GdaOperation {
  Add
  Sub
  Mul
  Div
  Fma
  Parse
}

///|
fn GdaOperation::name(self : GdaOperation) -> String {
  match self {
    Add => "add"
    Sub => "sub"
    Mul => "mul"
    Div => "div"
    Fma => "fma"
    Parse => "parse"
  }
}

///|
struct GdaInput {
  digits : Int
  source : String
  left : @gda.Decimal
  right : @gda.Decimal
  addend : @gda.Decimal
  context : @gda.GdaContext
  left_checked : @checked.GdaDecimalChecked
}

///|
enum GdaOutput {
  Core(@gda.Decimal)
  Checked(@checked.GdaDecimalChecked)
}

///|
fn gda_source(digits : Int) -> String {
  let text = StringBuilder::new()
  for index in 0..<digits {
    let digit = if index == 0 { 7 } else { (index * 7 + 3) % 10 }
    text.write_char((digit + 48).to_char().unwrap())
  }
  text.to_string()
}

///|
fn gda_input(digits : Int) -> GdaInput {
  let source = gda_source(digits)
  let context = @gda.GdaContext::new(
    precision=(digits * 2 + 4).max(9),
    e_min=-999999,
    e_max=999999,
  )
  let left = @gda.Decimal::from_string(source).unwrap()
  let right = @gda.Decimal::from_string("2").unwrap()
  let addend = @gda.Decimal::from_string("3").unwrap()
  {
    digits,
    source,
    left,
    right,
    addend,
    context,
    left_checked: @checked.GdaDecimalChecked::from_decimal(left, context),
  }
}

///|
fn gda_core(operation : GdaOperation, input : GdaInput) -> @gda.Decimal {
  match operation {
    Add => @gda.add(input.left, input.right, input.context).value()
    Sub => @gda.subtract(input.left, input.right, input.context).value()
    Mul => @gda.multiply(input.left, input.right, input.context).value()
    Div => @gda.divide(input.left, input.right, input.context).value()
    Fma =>
      @gda.fma(input.left, input.right, input.addend, input.context).value()
    Parse => @gda.parse(input.source, input.context).value()
  }
}

///|
fn gda_checked(
  operation : GdaOperation,
  input : GdaInput,
) -> @checked.GdaDecimalChecked {
  match operation {
    Add => input.left_checked.add(input.right)
    Sub => input.left_checked.subtract(input.right)
    Mul => input.left_checked.multiply(input.right)
    Div => input.left_checked.divide(input.right)
    Fma => input.left_checked.fma(input.right, input.addend)
    Parse => @checked.GdaDecimalChecked::parse(input.source, input.context)
  }
}

///|
fn gda_matches(expected : @gda.Decimal, output : GdaOutput) -> Bool {
  match output {
    Core(actual) => actual == expected
    Checked(actual) => actual.value() == expected
  }
}

///|
fn gda_output_text(output : GdaOutput) -> String {
  match output {
    Core(value) => value.to_string()
    Checked(value) => value.value().to_string()
  }
}

///|
fn gda_spec(
  operation : GdaOperation,
) -> @runner.BenchSpec[
  Int,
  GdaInput,
  GdaInput,
  @gda.Decimal,
  GdaOutput,
  Unit,
  GdaOutput?,
  GdaOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "decimal-gda/" + name,
    name,
    [1, 9, 18, 34, 128],
    digits => digits.to_string() + "digit",
    context => gda_input(context.dataset_key.scale),
    input => name + ":" + input.digits.to_string(),
    [
      @runner.Implementation::stateless("core/gda", "0.7.1", input => {
        @model.OperationResult::completed(
          GdaOutput::Core(gda_core(operation, input)),
          (),
        )
      }),
      @runner.Implementation::stateless("full/checked", "0.7.1", input => {
        @model.OperationResult::completed(
          GdaOutput::Checked(gda_checked(operation, input)),
          (),
        )
      }),
    ],
    input => gda_core(operation, input),
    gda_matches,
    input => input.source,
    gda_output_text,
  )
}

///|
test "GDA benchmark plans compile" {
  for operation in [GdaOperation::Add, Sub, Mul, Div, Fma, Parse] {
    ignore(gda_spec(operation).compile().unwrap())
  }
}

///|
#skip("performance benchmark")
async test "GDA core and full paths" {
  for operation in [GdaOperation::Add, Sub, Mul, Div, Fma, Parse] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/decimal-gda/" + name,
    )
    let summary = @benchkit.run(
      gda_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "decimal-gda",
        "decimal-gda-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<5 {
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "decimal-gda/" + name,
        dataset_id,
        "core/gda",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=decimal-gda/" +
        name +
        "/" +
        dataset_id.to_string() +
        " full_pct=" +
        full.relative_delta_pct.to_string(),
      )
    }
  }
}
