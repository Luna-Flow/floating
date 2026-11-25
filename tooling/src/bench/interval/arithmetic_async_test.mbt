///|
#skip("performance benchmark")
// oracle: A, S
// source: the check inside the timed run (assert_eq failed_count 0): the kernel/binary, core/interval and full/checked
//   results are compared with the sum, product or quotient computed by core BigInt on the same integer operands
//   (operands are exact integers at precision equal to the sum of their bit lengths plus 4, and the dividend is
//   a multiple of the divisor, so no rounding is involved: BigInt is not this library); the MAREMARK_HOTSPOT
//   lines are timing output with no expected value (level S). The block is #skip (performance benchmark); the
//   correctness oracles for rounded results are the corpora of the gates and bench/external
// shares: BinCoeff::parse and Binary::from_coefficient (build the operands and the reference value from the BigInt),
//   Binary::compare, Interval::is_singleton and lower_bound (read the interval result)
async test "interval kernel core and full paths" {
  for operation in [IntervalOperation::Add, Mul, Div] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/interval/" + name,
    )
    let summary = @benchkit.run(
      interval_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "interval",
        "interval-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<4 {
      let core = @benchkit.paired_hotspot(
        memory.observations,
        "interval/" + name,
        dataset_id,
        "kernel/binary",
        "core/interval",
        3.0,
        20260715UL,
      ).unwrap()
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "interval/" + name,
        dataset_id,
        "core/interval",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=interval/" +
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
