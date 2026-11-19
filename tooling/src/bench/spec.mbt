///|
pub fn[Scale, Input, Expected, Output] immutable_bench(
  id : String,
  operation : String,
  scales : Array[Scale],
  scale_text : (Scale) -> String,
  generate : (@model.GenerationContext[Scale]) -> Input,
  fingerprint : (Input) -> String,
  implementations : Array[@runner.Implementation[Input, Output, Unit]],
  reference : (Input) -> Expected,
  comparator : (Expected, Output) -> Bool,
  input_text : (Input) -> String,
  output_text : (Output) -> String,
) -> @runner.BenchSpec[
  Scale,
  Input,
  Input,
  Expected,
  Output,
  Unit,
  Output?,
  Output?,
] {
  @runner.BenchSpec::advanced(
    id,
    @fixture.Fixture::immutable(id + "-fixture", "1", generate, fingerprint),
    implementations,
    @runner.OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal(
        id + "-reference",
        reference,
        comparator,
      ),
    ),
    scales,
    scale_text,
    1,
    (input, _) => {
      @model.CaseDescriptor::new(
        operation,
        [input_text(input)],
        "stateless",
        "exact",
      )
    },
    input_text,
    output_text,
    _ => "unit",
    (_, implementation_id) => {
      @model.ReplaySpec::new("", [id, implementation_id])
    },
  )
}

///|
pub fn environment(
  target : @model.ExecutionTarget,
  dtype_abi : String,
  run_id : String,
) -> @model.EnvironmentSnapshot {
  @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      target, "moon-0.1.20260713", "release", dtype_abi,
    ),
    @model.PerformanceEnvironment::new(
      "moon",
      "external-metadata",
      "runtime-default",
      1,
      "monotonic",
      frequency_policy="external-metadata",
    ),
    @model.ProvenanceEnvironment::new(
      "external-metadata", "external-metadata", "external-metadata", "working-tree",
      run_id,
    ),
  )
}

///|
pub async fn[
  Scale,
  Input,
  Prepared,
  Expected,
  Output,
  Context,
  State,
  SinkValue,
] run(
  spec : @runner.BenchSpec[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  environment : @model.EnvironmentSnapshot,
  sink : @event.ObservationSink,
  seed : UInt64,
  protocol : @runner.ValidatedProtocol,
) -> @model.RunSummary {
  @runner.run(
    spec.compile().unwrap(),
    @runner.RunContext::new(environment, sink, seed, protocol),
  )
}
