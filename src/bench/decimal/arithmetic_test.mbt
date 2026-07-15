///|
enum DecimalOperation {
  Add
  Mul
  Div
}

///|
fn DecimalOperation::name(self : DecimalOperation) -> String {
  match self {
    Add => "add"
    Mul => "mul"
    Div => "div"
  }
}

///|
struct DecimalInput {
  digits : Int
  left_coeff : BigInt
  right_coeff : BigInt
  left : @decimal_core.Decimal
  right : @decimal_core.Decimal
  context : @decimal_core.DecimalContext
  left_checked : @checked.DecimalChecked
}

///|
enum DecimalOutput {
  Coefficient(BigInt)
  Core(@decimal_core.Decimal)
  Checked(@checked.DecimalChecked)
}

///|
fn decimal_pattern(digits : Int, phase : Int) -> BigInt {
  let text = StringBuilder::new()
  for index in 0..<digits {
    let digit = if index == 0 { 7 } else { (index * 7 + phase * 3) % 10 }
    text.write_char((digit + 48).to_char().unwrap())
  }
  BigInt::from_string(text.to_string())
}

///|
fn decimal_input(operation : DecimalOperation, digits : Int) -> DecimalInput {
  let raw_left = decimal_pattern(digits, 3)
  let raw_right = decimal_pattern((digits - 1).max(1), 11)
  let (left_coeff, right_coeff) = match operation {
    Add | Mul => (raw_left, raw_right)
    Div => (raw_left * raw_right, raw_right)
  }
  let precision = left_coeff.to_string().length() +
    right_coeff.to_string().length() +
    4
  let context = @decimal_core.DecimalContext::new(precision~)
  let left = @decimal_core.Decimal::from_bigint(left_coeff, precision~)
  let right = @decimal_core.Decimal::from_bigint(right_coeff, precision~)
  {
    digits,
    left_coeff,
    right_coeff,
    left,
    right,
    context,
    left_checked: @checked.DecimalChecked::from_decimal(left, context),
  }
}

///|
fn decimal_expected(
  operation : DecimalOperation,
  input : DecimalInput,
) -> BigInt {
  match operation {
    Add => input.left_coeff + input.right_coeff
    Mul => input.left_coeff * input.right_coeff
    Div => input.left_coeff / input.right_coeff
  }
}

///|
fn decimal_matches(expected : BigInt, output : DecimalOutput) -> Bool {
  let reference = @decimal_core.Decimal::from_bigint(
    expected,
    precision=expected.to_string().length().max(1),
  )
  match output {
    Coefficient(actual) => actual == expected
    Core(actual) => actual.compare(reference) == 0
    Checked(actual) =>
      match actual.result() {
        Ok((value, _)) => value.compare(reference) == 0
        Err(_) => false
      }
  }
}

///|
fn decimal_output_text(output : DecimalOutput) -> String {
  match output {
    Coefficient(value) => value.to_string()
    Core(value) => value.to_string()
    Checked(value) =>
      match value.result() {
        Ok((result, _)) => result.to_string()
        Err(_) => "error"
      }
  }
}

///|
fn decimal_implementations(
  operation : DecimalOperation,
) -> Array[@runner.Implementation[DecimalInput, DecimalOutput, Unit]] {
  [
    @runner.Implementation::stateless("kernel/coefficient", "0.7.0", input => {
      let output = match operation {
        Add => input.left_coeff + input.right_coeff
        Mul => input.left_coeff * input.right_coeff
        Div => input.left_coeff / input.right_coeff
      }
      @model.OperationResult::completed(DecimalOutput::Coefficient(output), ())
    }),
    @runner.Implementation::stateless("core/decimal", "0.7.0", input => {
      let output = match operation {
        Add => input.left.add_ctx(input.right, input.context).0
        Mul => input.left.mul_ctx(input.right, input.context).0
        Div => input.left.div_ctx(input.right, input.context).0
      }
      @model.OperationResult::completed(DecimalOutput::Core(output), ())
    }),
    @runner.Implementation::stateless("full/checked", "0.7.0", input => {
      let output = match operation {
        Add => input.left_checked.add(input.right)
        Mul => input.left_checked.mul(input.right)
        Div => input.left_checked.div(input.right)
      }
      @model.OperationResult::completed(DecimalOutput::Checked(output), ())
    }),
  ]
}

///|
fn decimal_spec(
  operation : DecimalOperation,
) -> @runner.BenchSpec[
  Int,
  DecimalInput,
  DecimalInput,
  BigInt,
  DecimalOutput,
  Unit,
  DecimalOutput?,
  DecimalOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "decimal/" + name,
    name,
    [9, 34, 128, 512],
    digits => digits.to_string() + "digit",
    context => decimal_input(operation, context.dataset_key.scale),
    input => name + ":" + input.digits.to_string(),
    decimal_implementations(operation),
    input => decimal_expected(operation, input),
    decimal_matches,
    input => input.digits.to_string(),
    decimal_output_text,
  )
}

///|
test "decimal benchmark plans compile" {
  for operation in [DecimalOperation::Add, Mul, Div] {
    ignore(decimal_spec(operation).compile().unwrap())
  }
}

///|
#skip("performance benchmark")
async test "decimal kernel core and full paths" {
  for operation in [DecimalOperation::Add, Mul, Div] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/decimal/" + name,
    )
    let summary = @benchkit.run(
      decimal_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "decimal",
        "decimal-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<4 {
      let core = @benchkit.paired_hotspot(
        memory.observations,
        "decimal/" + name,
        dataset_id,
        "kernel/coefficient",
        "core/decimal",
        3.0,
        20260715UL,
      ).unwrap()
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "decimal/" + name,
        dataset_id,
        "core/decimal",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=decimal/" +
        name +
        "/" +
        dataset_id.to_string() +
        " core_pct=" +
        core.relative_delta_pct.to_string() +
        " full_pct=" +
        full.relative_delta_pct.to_string(),
      )
    }
  }
}
