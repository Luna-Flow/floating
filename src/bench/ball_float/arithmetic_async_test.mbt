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
