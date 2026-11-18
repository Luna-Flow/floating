///|
priv struct Options {
  rows : String
  batch : Int32
  seed : UInt64
  run_id : String
  target : @model.ExecutionTarget
  replay_command : String
  replay_arguments : Array[String]
}

///|
fn usage() -> String {
  "usage: random-diff --rows <corpus> [--batch N] [--seed N] [--run-id ID] [--target native|js|wasm|llvm] [--replay-command CMD [--replay-argument ARG ...]]"
}

///|
fn parse_target(name : String) -> @model.ExecutionTarget? {
  match name {
    "native" => Some(@model.ExecutionTarget::Native)
    "js" => Some(@model.ExecutionTarget::Js)
    "wasm" => Some(@model.ExecutionTarget::Wasm)
    "wasm-gc" => Some(@model.ExecutionTarget::WasmGc)
    "llvm" => Some(@model.ExecutionTarget::Llvm)
    _ => None
  }
}

///|
fn parse_options(args : Array[String]) -> Result[Options, String] {
  let mut rows = ""
  let mut batch = 1000
  let mut seed = 1UL
  let mut run_id = "random-diff"
  let mut target = @model.ExecutionTarget::Native
  let mut replay_command = "python3"
  let replay_arguments : Array[String] = []
  // The program name, and under Node.js the script path too, come first.
  let mut index = 0
  while index < args.length() && !args[index].has_prefix("--") {
    index += 1
  }
  while index < args.length() {
    let argument = args[index]
    if index + 1 >= args.length() {
      return Err(argument + " requires a value; " + usage())
    }
    let value = args[index + 1]
    match argument {
      "--rows" => rows = value
      "--batch" =>
        match @runner_cli.parse_int("batch size", value) {
          Ok(number) => batch = number
          Err(message) => return Err(message)
        }
      "--seed" =>
        match @runner_cli.parse_int("seed", value) {
          Ok(number) => seed = number.to_uint64()
          Err(message) => return Err(message)
        }
      "--run-id" => run_id = value
      "--target" =>
        match parse_target(value) {
          Some(parsed) => target = parsed
          None => return Err("unknown target " + value)
        }
      "--replay-command" => replay_command = value
      "--replay-argument" => replay_arguments.push(value)
      _ => return Err("unknown option " + argument + "; " + usage())
    }
    index += 2
  }
  if rows.length() == 0 {
    return Err(usage())
  }
  Ok({ rows, batch, seed, run_id, target, replay_command, replay_arguments, })
}

///|
/// Candidates of the shrinker: the two halves of a failing batch, so that the
/// runner delta-debugs a million-case run down to the failing case.
fn halves(batch : Batch) -> Array[Batch] {
  let size = batch.length()
  if size <= 1 {
    return []
  }
  let middle = size / 2
  [batch.slice(0, middle), batch.slice(middle, size)]
}

///|
fn describe(batch : Batch) -> String {
  if batch.length() == 0 {
    "empty batch"
  } else if batch.length() == 1 {
    batch.ids[0]
  } else {
    batch.ids[0] +
    ".." +
    batch.ids[batch.length() - 1] +
    " (" +
    batch.length().to_string() +
    " cases)"
  }
}

///|
fn describe_range(batch : Batch) -> String {
  if batch.length() == 0 {
    ""
  } else if batch.length() == 1 {
    batch.ids[0]
  } else {
    batch.ids[0] + ".." + batch.ids[batch.length() - 1]
  }
}

///|
fn make_spec(
  batches : Array[Batch],
  label : String,
  options : Options,
) -> @runner.BenchSpec[
  String,
  Batch,
  Batch,
  Array[String],
  Array[String],
  Unit,
  Array[String]?,
  Array[String]?,
] {
  let empty : Batch = {
    kind: MpfrRandom,
    header: "",
    label,
    ids: [],
    texts: [],
  }
  let fixture : @fixture.Fixture[String, Batch, Batch] = @fixture.Fixture::immutable(
    "random-diff-batches",
    "1",
    context => {
      let index = context.dataset_key.dataset_id
      if index >= 0 && index < batches.length() {
        batches[index]
      } else {
        empty
      }
    },
    batch => @generator.stable_fingerprint(describe(batch)),
  )
  let floating = @runner.Implementation::stateless("floating", "0.10.2", (
    batch : Batch,
  ) => {
    match execute_batch(batch) {
      Ok(messages) => @model.OperationResult::completed(messages, ())
      Err(message) =>
        @model.OperationResult::new(
          @model.ExecutionOutcome::ParseFailure(message),
          None,
        )
    }
  })
  let oracle = @experiment.ReferenceOracle::new(
    "oracle-rows",
    () => (),
    _ => 1,
    (batch : Batch, _, context : Unit) => {
      // The oracle's answer is stored in every row, so the reference
      // behaviour of a batch is that every case agrees.
      @model.OperationResult::completed(
        Array::make(batch.length(), ""),
        context,
      )
    },
    (
      batch : Batch,
      _,
      expected : @model.ExecutionOutcome[Array[String]],
      actual : @model.ExecutionOutcome[Array[String]],
    ) => {
      match (expected, actual) {
        (Value(_), Value(messages)) => {
          let total = messages.fold(init=0, (count, message) => {
            if message.length() > 0 {
              count + 1
            } else {
              count
            }
          })
          if total == 0 {
            @model.ValidationStatus::Valid
          } else {
            @model.ValidationStatus::Invalid(failure_text(batch.ids, messages))
          }
        }
        (_, ParseFailure(message)) =>
          @model.ValidationStatus::InfrastructureFailure(message)
        _ => @model.ValidationStatus::Invalid("unexpected outcome")
      }
    },
    expected => expected.length().to_string() + " cases agree",
  )
  @runner.BenchSpec::advanced(
    "random-diff",
    fixture,
    [floating],
    @runner.OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(oracle),
    [label],
    scale => scale,
    1,
    (batch, _) => {
      @model.CaseDescriptor::new(
        match batch.kind {
          MpfrRandom => "mpfr-random"
          Decimal => "libmpdec-random"
        },
        if batch.length() == 0 {
          []
        } else {
          [
            batch.ids[0],
            batch.ids[batch.length() - 1],
            batch.length().to_string(),
          ]
        },
        batch.label,
        "",
      )
    },
    describe,
    messages => {
      let failing = messages.filter(message => message.length() > 0)
      failing.length().to_string() +
      " of " +
      messages.length().to_string() +
      " cases differ"
    },
    _ => "stateless",
    (batch, _) => {
      let arguments = options.replay_arguments.copy()
      arguments.push("--target")
      arguments.push(options.target.text())
      // A case id, or `first..last` for a batch: the replay regenerates the
      // rows from the seed named in the id and runs them again.
      arguments.push(describe_range(batch))
      @model.ReplaySpec::new(options.replay_command, arguments)
    },
    shrinker=@experiment.Shrinker::new(
      halves,
      batch => if batch.length() <= 2 { batch.text() } else { describe(batch) },
      max_steps=64,
    ),
  )
}

///|
/// One confirmatory block per batch, one iteration per block: the harness's
/// validation, seeding and recording are used, the timing is a by-product.
fn protocol_for(batches : Int32, seed : UInt64) -> @runner.ValidatedProtocol {
  @runner.validate_protocol(
    @model.RunProtocol::new(
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
      0,
      None,
      @model.CalibrationProtocol::new(
        1.0,
        1,
        1,
        1000000000.0,
        @model.BatchPolicy::PerImplementation,
      ),
      1.0,
      @model.OrderPolicy::BalancedBlocks(seed),
      @model.OutlierPolicy::ReportOnly,
      @model.ValidationCoverage::EveryDataset,
      0,
      batches,
    ),
  ).unwrap()
}

///|
async fn main {
  let options = match parse_options(@env.args()) {
    Ok(value) => value
    Err(message) => {
      println(message)
      @sys.exit(2)
      return
    }
  }
  let text = match @runner_cli.read_source(options.rows) {
    Ok(value) => value
    Err(message) => {
      println(message)
      @sys.exit(2)
      return
    }
  }
  let batches = match split_corpus(text, options.batch) {
    Ok(value) => value
    Err(message) => {
      println(message)
      @sys.exit(2)
      return
    }
  }
  if batches.length() == 0 {
    println("corpus has no cases")
    @sys.exit(2)
    return
  }
  let label = batches[0].label
  let spec = make_spec(batches, label, options)
  let memory = @event.InMemorySink::new()
  let stream = @event.streaming_jsonl(
    line => println(line),
    "stdout://random-diff/" + options.run_id,
  )
  let summary = @benchkit.run(
    spec,
    @benchkit.environment(options.target, "random-diff", options.run_id),
    @event.tee(memory.as_sink(), stream),
    options.seed,
    protocol_for(batches.length(), options.seed),
  )
  if summary.failed_count > 0 || summary.unsupported_count > 0 {
    @sys.exit(1)
  }
}
