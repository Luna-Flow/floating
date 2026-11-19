///|
#skip("performance benchmark")
async test "binary elementary core and full paths" {
  for operation in elementary_operations() {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/bin-float/elementary/" + name,
    )
    let summary = @benchkit.run(
      elementary_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "bin-float-elementary",
        "bin-float-elementary-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<3 {
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "bin-float/elementary/" + name,
        dataset_id,
        "core/bin-float",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=bin-float/elementary/" +
        name +
        "/" +
        dataset_id.to_string() +
        " full_pct=" +
        full.relative_delta_pct.to_string(),
      )
    }
  }
}
