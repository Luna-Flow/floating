///|
fn square_tune_pattern(limbs : Int) -> @binary.BinCoeff {
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
  Int,
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
      @runner.Implementation::stateless("mul-self", "0.7.0", value => {
        @model.OperationResult::completed(value.mul(value), ())
      }),
      @runner.Implementation::stateless("square", "0.7.0", value => {
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

///|
#skip("performance benchmark")
async test "auto tune binary square crossover" {
  let limbs = [4, 8, 16, 32, 64, 128, 256, 512, 1024]
  let memory = @event.InMemorySink::new()
  let stream = @event.streaming_jsonl(
    line => println("MAREMARK_JSONL=" + line),
    "stdout://bench/bin-float/autotune/square",
  )
  let summary = @benchkit.run(
    square_tune_spec(),
    @benchkit.environment(
      @model.ExecutionTarget::Native,
      "bin-coeff-square",
      "bin-coeff-square-autotune",
    ),
    @event.tee(memory.as_sink(), stream),
    20260715UL,
    @runner.ProtocolPreset::RegressionGate.validated(),
  )
  assert_eq(summary.failed_count, 0)
  let labels = []
  for dataset_id in 0..<limbs.length() {
    let decision = @benchkit.tune_dataset(
      memory.observations,
      "bin-float/autotune/square",
      dataset_id,
      ["mul-self", "square"],
      1.0,
    ).unwrap()
    labels.push(decision.candidate_id)
    println(
      "MAREMARK_TUNE=bin-float/autotune/square/" +
      limbs[dataset_id].to_string() +
      " candidate=" +
      decision.candidate_id +
      " median_us=" +
      decision.median_us.to_string() +
      " samples=" +
      decision.valid_samples.to_string(),
    )
  }
  let crossover = @experiment.crossover_from_labels(
    @experiment.ScaleDomain::new(limbs, (left, right) => left.compare(right), value => {
      value.to_string()
    }),
    labels,
  )
  let lookup = Array::makei(limbs.length(), index => {
    limbs[index].to_string() + ":" + labels[index]
  }).join(",")
  match crossover {
    @model.CrossoverResult::Found(boundary, _, _) => {
      println(
        "MAREMARK_CROSSOVER=bin-float/autotune/square below=" +
        boundary.below.to_string() +
        " at_or_above=" +
        boundary.at_or_above.to_string(),
      )
      println(
        "MAREMARK_POLICY=piecewise case=bin-float/autotune/square lookup=" +
        lookup,
      )
    }
    @model.CrossoverResult::NoCrossover(reason, _) =>
      println("MAREMARK_CROSSOVER=none reason=" + reason)
    @model.CrossoverResult::NonMonotonic(_) => {
      println("MAREMARK_CROSSOVER=non-monotonic")
      println(
        "MAREMARK_POLICY=lookup case=bin-float/autotune/square lookup=" + lookup,
      )
    }
    @model.CrossoverResult::Inconclusive(reason, _) =>
      println("MAREMARK_CROSSOVER=inconclusive reason=" + reason)
  }
}
