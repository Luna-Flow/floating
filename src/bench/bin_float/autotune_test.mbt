///|
fn square_tune_pattern(limbs : Int32) -> @binary.BinCoeff {
  let bits = limbs * 32
  let one = @binary.BinCoeff::one()
  let mut value = one.shift_left(bits - 1)
  let mut index = 7
  while index < bits - 1 {
    value = value.bit_or(one.shift_left(index))
    index += 23
  }
  value.bit_or(one)
}

///|
fn square_tune_spec() -> @runner.BenchSpec[
  Int32,
  @binary.BinCoeff,
  @binary.BinCoeff,
  @binary.BinCoeff,
  @binary.BinCoeff,
  Unit,
  @binary.BinCoeff?,
  @binary.BinCoeff?,
] {
  @benchkit.immutable_bench(
    "bin-float/autotune/square",
    "square",
    [4, 8, 16, 32, 64, 128, 256, 512, 1024],
    limbs => limbs.to_string() + "limb",
    context => square_tune_pattern(context.dataset_key.scale),
    value => value.bit_length().to_string(),
    [
      @runner.Implementation::stateless("mul-self", "0.8.0", value => {
        @model.OperationResult::completed(value.mul(value), ())
      }),
      @runner.Implementation::stateless("square", "0.8.0", value => {
        @model.OperationResult::completed(value.square(), ())
      }),
    ],
    value => value.square(),
    (expected, actual) => expected.compare(actual) == 0,
    value => value.bit_length().to_string(),
    value => value.bit_length().to_string(),
  )
}

///|
test "binary auto tune plan compiles" {
  ignore(square_tune_spec().compile().unwrap())
}
