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
