///|
enum IntervalOperation {
  Add
  Mul
  Div
}

///|
fn IntervalOperation::name(self : IntervalOperation) -> String {
  match self {
    Add => "add"
    Mul => "mul"
    Div => "div"
  }
}

///|
struct IntervalInput {
  bits : Int32
  left_big : BigInt
  right_big : BigInt
  left_binary : @binary.Binary
  right_binary : @binary.Binary
  left : @ivl.Interval
  right : @ivl.Interval
  left_checked : @checked.IntervalChecked
  right_checked : @checked.IntervalChecked
}

///|
enum IntervalOutput {
  BinaryKernel(@binary.Binary)
  Core(@ivl.Interval)
  Checked(@checked.IntervalChecked)
}

///|
/// The coefficient arithmetic of `BinCoeff` is internal, so the operands are
/// built with `BigInt`.
fn interval_pattern(bits : Int32, phase : Int32) -> BigInt {
  let one = BigInt::from_int(1)
  let mut value = one << (bits - 1)
  let mut index = phase % 13
  while index < bits - 1 {
    value = value + (one << index)
    index += 13 + phase % 7
  }
  value + one
}

///|
fn interval_coeff(value : BigInt) -> @binary.BinCoeff {
  @binary.BinCoeff::parse(value.to_string()).unwrap()
}

///|
fn interval_input(operation : IntervalOperation, bits : Int32) -> IntervalInput {
  let raw_left = interval_pattern(bits, 5)
  let raw_right = interval_pattern((bits - 1).max(2), 9)
  let (left_big, right_big) = match operation {
    Add | Mul => (raw_left, raw_right)
    Div => (raw_left * raw_right, raw_right)
  }
  let left_coeff = interval_coeff(left_big)
  let right_coeff = interval_coeff(right_big)
  let precision = left_coeff.bit_length() + right_coeff.bit_length() + 4
  let left_binary = @binary.Binary::from_coefficient(left_coeff, precision~)
  let right_binary = @binary.Binary::from_coefficient(right_coeff, precision~)
  {
    bits,
    left_big,
    right_big,
    left_binary,
    right_binary,
    left: @ivl.Interval::exact(left_binary, precision~),
    right: @ivl.Interval::exact(right_binary, precision~),
    left_checked: @checked.IntervalChecked::exact(left_binary, precision~),
    right_checked: @checked.IntervalChecked::exact(right_binary, precision~),
  }
}

///|
/// Timing harness check. The expected value is computed with core `BigInt`
/// (another implementation, level A for integer arithmetic on these operands):
/// the operands are exact integers and the precision is the sum of their bit
/// lengths plus 4, so the sum, the product and the quotient (the left operand
/// of a division is built as a multiple of the right one) are exact. The
/// oracles for rounded `interval` results are the interval corpora and the
/// external baseline's differential stage, not this benchmark.
fn interval_expected(
  operation : IntervalOperation,
  input : IntervalInput,
) -> @binary.Binary {
  let value = match operation {
    Add => input.left_big + input.right_big
    Mul => input.left_big * input.right_big
    Div => input.left_big / input.right_big
  }
  let coefficient = interval_coeff(value)
  @binary.Binary::from_coefficient(
    coefficient,
    precision=coefficient.bit_length().max(1),
  )
}

///|
fn interval_matches(expected : @binary.Binary, output : IntervalOutput) -> Bool {
  match output {
    BinaryKernel(actual) => actual.compare(expected) == 0
    Core(actual) =>
      actual.is_singleton() && actual.lower_bound().compare(expected) == 0
    Checked(actual) =>
      match actual.result() {
        Ok(value) =>
          value.is_singleton() && value.lower_bound().compare(expected) == 0
        Err(_) => false
      }
  }
}

///|
fn interval_output_text(output : IntervalOutput) -> String {
  match output {
    BinaryKernel(value) => value.to_hex()
    Core(value) => value.midpoint().to_hex() + "+/-" + value.radius().to_hex()
    Checked(value) =>
      match value.result() {
        Ok(result) =>
          result.midpoint().to_hex() + "+/-" + result.radius().to_hex()
        Err(_) => "error"
      }
  }
}

///|
fn interval_implementations(
  operation : IntervalOperation,
) -> Array[@runner.Implementation[IntervalInput, IntervalOutput, Unit]] {
  [
    @runner.Implementation::stateless("kernel/binary", "0.8.0", input => {
      let output = match operation {
        Add => input.left_binary.add(input.right_binary)
        Mul => input.left_binary.mul(input.right_binary)
        Div => input.left_binary.div(input.right_binary)
      }
      @model.OperationResult::completed(
        IntervalOutput::BinaryKernel(output),
        (),
      )
    }),
    @runner.Implementation::stateless("core/interval", "0.8.0", input => {
      let output = match operation {
        Add => input.left.add(input.right)
        Mul => input.left.mul(input.right)
        Div => input.left.div(input.right)
      }
      @model.OperationResult::completed(IntervalOutput::Core(output), ())
    }),
    @runner.Implementation::stateless("full/checked", "0.8.0", input => {
      let output = match operation {
        Add => input.left_checked.add(input.right_checked)
        Mul => input.left_checked.mul(input.right_checked)
        Div => input.left_checked.div(input.right_checked)
      }
      @model.OperationResult::completed(IntervalOutput::Checked(output), ())
    }),
  ]
}

///|
fn interval_spec(
  operation : IntervalOperation,
) -> @runner.BenchSpec[
  Int32,
  IntervalInput,
  IntervalInput,
  @binary.Binary,
  IntervalOutput,
  Unit,
  IntervalOutput?,
  IntervalOutput?,
] {
  let name = operation.name()
  @benchkit.immutable_bench(
    "interval/" + name,
    name,
    [53, 128, 512, 2048],
    bits => bits.to_string() + "bit",
    context => interval_input(operation, context.dataset_key.scale),
    input => name + ":" + input.bits.to_string(),
    interval_implementations(operation),
    input => interval_expected(operation, input),
    interval_matches,
    input => input.bits.to_string(),
    interval_output_text,
  )
}

///|
// oracle: S
// source: no expected value: the block only requires that each benchmark spec compiles (the unwrap of the compile
//   result), so the verdict is the absence of a compile error
// shares: interval_spec and BenchSpec::compile (the code under test)
test "interval benchmark plans compile" {
  for operation in [IntervalOperation::Add, Mul, Div] {
    ignore(interval_spec(operation).compile().unwrap())
  }
}
