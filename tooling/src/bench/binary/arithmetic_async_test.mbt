///|
#skip("performance benchmark")
// oracle: A, S
// source: the check inside the timed run (assert_eq failed_count 0): the core/binary and full/checked results are
//   compared with the sum, product or quotient computed by core BigInt on the same integer operands (operands
//   are exact integers at precision equal to the sum of their bit lengths plus 4, and the dividend is a multiple
//   of the divisor, so no rounding is involved: BigInt is not this library); kernel/coefficient is that BigInt
//   arithmetic itself and is only timed; the MAREMARK_HOTSPOT lines are timing output with no expected value
//   (level S). The block is #skip (performance benchmark); the correctness oracles for rounded results are the
//   corpora of the gates and bench/external
// shares: BinCoeff::parse and Binary::from_coefficient (build the operands and the reference value from the BigInt),
//   Binary::compare and to_hex (compare and print)
async test "binary kernel core and full paths" {
  for operation in [BinaryOperation::Add, Mul, Div] {
    let name = operation.name()
    let memory = @event.InMemorySink::new()
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://bench/binary/" + name,
    )
    let summary = @benchkit.run(
      binary_spec(operation),
      @benchkit.environment(
        @model.ExecutionTarget::Native,
        "binary",
        "binary-" + name,
      ),
      @event.tee(memory.as_sink(), stream),
      20260715UL,
      @runner.ProtocolPreset::Development.validated(),
    )
    assert_eq(summary.failed_count, 0)
    for dataset_id in 0..<4 {
      let core = @benchkit.paired_hotspot(
        memory.observations,
        "binary/" + name,
        dataset_id,
        "kernel/coefficient",
        "core/binary",
        3.0,
        20260715UL,
      ).unwrap()
      let full = @benchkit.paired_hotspot(
        memory.observations,
        "binary/" + name,
        dataset_id,
        "core/binary",
        "full/checked",
        3.0,
        20260715UL,
      ).unwrap()
      println(
        "MAREMARK_HOTSPOT=binary/" +
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
