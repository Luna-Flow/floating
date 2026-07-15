///|
enum BallOperation {
  Add
  Mul
  Div
}

///|
fn BallOperation::name(self : BallOperation) -> String {
  match self {
    Add => "add"
    Mul => "mul"
    Div => "div"
  }
}

///|
struct BallInput {
  bits : Int
  left_binary : @binary.BinFloat
  right_binary : @binary.BinFloat
  left : @ball.BallFloat
  right : @ball.BallFloat
  left_checked : @checked.BallFloatResult
  right_checked : @checked.BallFloatResult
}

///|
enum BallOutput {
  BinaryKernel(@binary.BinFloat)
  Core(@ball.BallFloat)
  Checked(@checked.BallFloatResult)
}

///|
fn ball_pattern(bits : Int, phase : Int) -> @binary.BinCoeff {
  let one = @binary.BinCoeff::one()
  let mut value = one.shift_left(bits - 1)
  let mut index = phase % 13
  while index < bits - 1 {
    value = value.bit_or(one.shift_left(index))
    index += 13 + phase % 7
  }
  value.bit_or(one)
}

///|
fn ball_input(operation : BallOperation, bits : Int) -> BallInput {
  let raw_left = ball_pattern(bits, 5)
  let raw_right = ball_pattern((bits - 1).max(2), 9)
  let (left_coeff, right_coeff) = match operation {
    Add | Mul => (raw_left, raw_right)
    Div => (raw_left.mul(raw_right), raw_right)
  }
  let precision = left_coeff.bit_length() + right_coeff.bit_length() + 4
  let left_binary = @binary.BinFloat::from_coefficient(left_coeff, precision~)
  let right_binary = @binary.BinFloat::from_coefficient(right_coeff, precision~)
  {
    bits,
    left_binary,
    right_binary,
    left: @ball.BallFloat::exact(left_binary, precision~),
    right: @ball.BallFloat::exact(right_binary, precision~),
    left_checked: @checked.BallFloatResult::exact(left_binary, precision~),
    right_checked: @checked.BallFloatResult::exact(right_binary, precision~),
  }
}

///|
fn ball_expected(
  operation : BallOperation,
  input : BallInput,
) -> @binary.BinFloat {
  match operation {
    Add => input.left_binary.add(input.right_binary)
    Mul => input.left_binary.mul(input.right_binary)
    Div => input.left_binary.div(input.right_binary)
  }
}

///|
fn ball_matches(expected : @binary.BinFloat, output : BallOutput) -> Bool {
  match output {
    BinaryKernel(actual) => actual.compare(expected) == 0
    Core(actual) =>
      actual.is_singleton() && actual.center().compare(expected) == 0
    Checked(actual) =>
      match actual.result() {
        Ok(value) =>
          value.is_singleton() && value.center().compare(expected) == 0
        Err(_) => false
      }
  }
}

///|
fn ball_output_text(output : BallOutput) -> String {
  match output {
    BinaryKernel(value) => value.to_hex()
    Core(value) => value.center().to_hex() + "+/-" + value.radius().to_hex()
    Checked(value) =>
      match value.result() {
        Ok(result) =>
          result.center().to_hex() + "+/-" + result.radius().to_hex()
        Err(_) => "error"
      }
  }
}

///|
fn ball_implementations(
  operation : BallOperation,
) -> Array[@runner.Implementation[BallInput, BallOutput, Unit]] {
  [
    @runner.Implementation::stateless("kernel/bin-float", "0.7.0", input => {
      let output = match operation {
        Add => input.left_binary.add(input.right_binary)
        Mul => input.left_binary.mul(input.right_binary)
        Div => input.left_binary.div(input.right_binary)
      }
      @model.OperationResult::completed(BallOutput::BinaryKernel(output), ())
    }),
    @runner.Implementation::stateless("core/ball-float", "0.7.0", input => {
      let output = match operation {
        Add => input.left.add(input.right)
        Mul => input.left.mul(input.right)
        Div => input.left.div(input.right)
      }
      @model.OperationResult::completed(BallOutput::Core(output), ())
    }),
    @runner.Implementation::stateless("full/checked", "0.7.0", input => {
      let output = match operation {
        Add => input.left_checked.add(input.right_checked)
        Mul => input.left_checked.mul(input.right_checked)
        Div => input.left_checked.div(input.right_checked)
      }
      @model.OperationResult::completed(BallOutput::Checked(output), ())
    }),
  ]
}

///|
fn ball_spec(
  operation : BallOperation,
) -> @runner.BenchSpec[
  Int,
  BallInput,
  BallInput,
  @binary.BinFloat,
  BallOutput,
  Unit,
  BallOutput?,
  BallOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "ball-float/" + name,
    name,
    [53, 128, 512, 2048],
    bits => bits.to_string() + "bit",
    context => ball_input(operation, context.dataset_key.scale),
    input => name + ":" + input.bits.to_string(),
    ball_implementations(operation),
    input => ball_expected(operation, input),
    ball_matches,
    input => input.bits.to_string(),
    ball_output_text,
  )
}

///|
test "ball benchmark plans compile" {
  for operation in [BallOperation::Add, Mul, Div] {
    ignore(ball_spec(operation).compile().unwrap())
  }
}

///|
#skip("performance benchmark")
async test "ball kernel core and full paths" {
  for operation in [BallOperation::Add, Mul, Div] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/ball-float/" + name,
    )
    let summary = @benchkit.run(
      ball_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "ball-float",
        "ball-float-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<4 {
      let core = @benchkit.paired_hotspot(
        memory.observations,
        "ball-float/" + name,
        dataset_id,
        "kernel/bin-float",
        "core/ball-float",
        3.0,
        20260715UL,
      ).unwrap()
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "ball-float/" + name,
        dataset_id,
        "core/ball-float",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=ball-float/" +
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
