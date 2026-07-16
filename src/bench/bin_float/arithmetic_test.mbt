///|
enum BinaryOperation {
  Add
  Mul
  Div
}

///|
fn BinaryOperation::name(self : BinaryOperation) -> String {
  match self {
    Add => "add"
    Mul => "mul"
    Div => "div"
  }
}

///|
struct BinaryInput {
  bits : Int
  left_coeff : @binary.BinCoeff
  right_coeff : @binary.BinCoeff
  left : @binary.BinFloat
  right : @binary.BinFloat
  left_checked : @checked.BinFloatResult
  right_checked : @checked.BinFloatResult
}

///|
enum BinaryOutput {
  Coefficient(@binary.BinCoeff)
  Core(@binary.BinFloat)
  Checked(@checked.BinFloatResult)
}

///|
fn binary_pattern(bits : Int, phase : Int) -> @binary.BinCoeff {
  let one = @binary.BinCoeff::one()
  let mut value = one.shift_left(bits - 1)
  let mut index = phase % 17
  while index < bits - 1 {
    value = value.bit_or(one.shift_left(index))
    index += 17 + phase % 5
  }
  value.bit_or(one)
}

///|
fn binary_input(operation : BinaryOperation, bits : Int) -> BinaryInput {
  let raw_left = binary_pattern(bits, 3)
  let raw_right = binary_pattern((bits - 1).max(2), 11)
  let (left_coeff, right_coeff) = match operation {
    Add | Mul => (raw_left, raw_right)
    Div => (raw_left.mul(raw_right), raw_right)
  }
  let precision = left_coeff.bit_length() + right_coeff.bit_length() + 4
  let left = @binary.BinFloat::from_coefficient(left_coeff, precision~)
  let right = @binary.BinFloat::from_coefficient(right_coeff, precision~)
  {
    bits,
    left_coeff,
    right_coeff,
    left,
    right,
    left_checked: @checked.BinFloatResult::ok(left),
    right_checked: @checked.BinFloatResult::ok(right),
  }
}

///|
fn binary_expected(
  operation : BinaryOperation,
  input : BinaryInput,
) -> @binary.BinCoeff {
  match operation {
    Add => input.left_coeff.add(input.right_coeff)
    Mul => input.left_coeff.mul(input.right_coeff)
    Div => input.left_coeff.div_rem_checked(input.right_coeff).unwrap().0
  }
}

///|
fn binary_output_matches(
  expected : @binary.BinCoeff,
  output : BinaryOutput,
) -> Bool {
  match output {
    Coefficient(actual) => actual.compare(expected) == 0
    Core(actual) => {
      let reference = @binary.BinFloat::from_coefficient(
        expected,
        precision=expected.bit_length().max(1),
      )
      actual.compare(reference) == 0
    }
    Checked(actual) =>
      match actual.result() {
        Ok(value) => {
          let reference = @binary.BinFloat::from_coefficient(
            expected,
            precision=expected.bit_length().max(1),
          )
          value.compare(reference) == 0
        }
        Err(_) => false
      }
  }
}

///|
fn binary_output_text(output : BinaryOutput) -> String {
  match output {
    Coefficient(value) => value.to_string()
    Core(value) => value.to_hex()
    Checked(value) =>
      match value.result() {
        Ok(result) => result.to_hex()
        Err(_) => "error"
      }
  }
}

///|
fn binary_implementations(
  operation : BinaryOperation,
) -> Array[@runner.Implementation[BinaryInput, BinaryOutput, Unit]] {
  [
    @runner.Implementation::stateless("kernel/coefficient", "0.7.1", input => {
      let output = match operation {
        Add => input.left_coeff.add(input.right_coeff)
        Mul => input.left_coeff.mul(input.right_coeff)
        Div => input.left_coeff.div_rem_checked(input.right_coeff).unwrap().0
      }
      @model.OperationResult::completed(BinaryOutput::Coefficient(output), ())
    }),
    @runner.Implementation::stateless("core/bin-float", "0.7.1", input => {
      let output = match operation {
        Add => input.left.add(input.right)
        Mul => input.left.mul(input.right)
        Div => input.left.div(input.right)
      }
      @model.OperationResult::completed(BinaryOutput::Core(output), ())
    }),
    @runner.Implementation::stateless("full/checked", "0.7.1", input => {
      let output = match operation {
        Add => input.left_checked.add(input.right_checked)
        Mul => input.left_checked.mul(input.right_checked)
        Div => input.left_checked.div(input.right_checked)
      }
      @model.OperationResult::completed(BinaryOutput::Checked(output), ())
    }),
  ]
}

///|
fn binary_spec(
  operation : BinaryOperation,
) -> @runner.BenchSpec[
  Int,
  BinaryInput,
  BinaryInput,
  @binary.BinCoeff,
  BinaryOutput,
  Unit,
  BinaryOutput?,
  BinaryOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "bin-float/" + name,
    name,
    [53, 128, 512, 2048],
    bits => bits.to_string() + "bit",
    context => binary_input(operation, context.dataset_key.scale),
    input => name + ":" + input.bits.to_string(),
    binary_implementations(operation),
    input => binary_expected(operation, input),
    binary_output_matches,
    input => input.bits.to_string(),
    binary_output_text,
  )
}

///|
test "binary benchmark plans compile" {
  for operation in [BinaryOperation::Add, Mul, Div] {
    ignore(binary_spec(operation).compile().unwrap())
  }
}

///|
#skip("performance benchmark")
async test "binary kernel core and full paths" {
  for operation in [BinaryOperation::Add, Mul, Div] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/bin-float/" + name,
    )
    let summary = @benchkit.run(
      binary_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "bin-float",
        "bin-float-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<4 {
      let core = @benchkit.paired_hotspot(
        memory.observations,
        "bin-float/" + name,
        dataset_id,
        "kernel/coefficient",
        "core/bin-float",
        3.0,
        20260715UL,
      ).unwrap()
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "bin-float/" + name,
        dataset_id,
        "core/bin-float",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=bin-float/" +
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
