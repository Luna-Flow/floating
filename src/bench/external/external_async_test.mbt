///|
fn env_text(name : String) -> String? {
  @env.get_env_var(name)
}

///|
fn env_int(name : String, default : Int32) -> Int32 {
  match env_text(name) {
    Some(text) => @string.parse_int(text) catch { _ => default }
    None => default
  }
}

///|
fn env_double(name : String, default : Double) -> Double {
  match env_text(name) {
    Some(text) => @string.parse_double(text) catch { _ => default }
    None => default
  }
}

///|
fn external_protocol_from_env() -> ExternalProtocol {
  let base = ExternalProtocol::default()
  {
    warmup_iterations: env_int(
      "EXTBENCH_WARMUP_ITERATIONS",
      base.warmup_iterations,
    ),
    warmup_time_us: env_double("EXTBENCH_WARMUP_US", base.warmup_time_us),
    target_batch_time_us: env_double(
      "EXTBENCH_TARGET_BATCH_US",
      base.target_batch_time_us,
    ),
    min_batch_iterations: env_int(
      "EXTBENCH_MIN_BATCH",
      base.min_batch_iterations,
    ),
    max_batch_iterations: env_int(
      "EXTBENCH_MAX_BATCH",
      base.max_batch_iterations,
    ),
    max_sample_time_us: env_double(
      "EXTBENCH_MAX_SAMPLE_US",
      base.max_sample_time_us,
    ),
    exploratory: env_int("EXTBENCH_EXPLORATORY", base.exploratory),
    confirmatory: env_int("EXTBENCH_CONFIRMATORY", base.confirmatory),
  }
}

///|
/// Reads the operand file and the MPFR/libmpdec reference file named by
/// `EXTBENCH_INPUTS` and `EXTBENCH_REFERENCE`, then times floating on every
/// case of `EXTBENCH_CASES` (comma separated `kind/op/size`, in that order;
/// all cases of the file when unset). Every implementation is validated
/// against the reference results before it is timed.
#skip("performance benchmark")
async test "external baseline floating" {
  let inputs_path = match env_text("EXTBENCH_INPUTS") {
    Some(path) => path
    None => abort("EXTBENCH_INPUTS is not set; run `just bench external run`")
  }
  let inputs = parse_cases(@fs.read_file_to_string(inputs_path))
  let references = match env_text("EXTBENCH_REFERENCE") {
    Some(path) => parse_cases(@fs.read_file_to_string(path))
    None => Map([])
  }
  let case_ids : Array[String] = match env_text("EXTBENCH_CASES") {
    Some(list) => list.split(",").map(part => part.to_owned()).collect()
    None => inputs.keys().collect()
  }
  let protocol = external_protocol_from_env().run_protocol()
  let seed = env_int("EXTBENCH_SEED", 20261118).to_uint64()
  let round = env_int("EXTBENCH_ROUND", 0)
  let detected = @env_detect.detect(
    compiler_flags="moon --release",
    dtype_abi="bin_float+decimal_gda",
    concurrency=1,
  )
  let mut failures = 0
  for id in case_ids {
    guard parse_case_id(id) is Some((kind, op, size)) else {
      abort("malformed case " + id)
    }
    guard inputs.get(id) is Some(rows) else { abort("no input rows for " + id) }
    let reference_rows = references.get(id).unwrap_or([])
    let stream = @event.streaming_jsonl(
      line => println("MAREMARK_JSONL=" + line),
      "stdout://external/" + id + "/round-" + round.to_string(),
    )
    let summary = match kind {
      "binary" =>
        match binary_spec(op, size, rows, reference_rows) {
          Some(spec) =>
            @benchkit.run(spec, detected.snapshot, stream, seed, protocol)
          None => abort("unknown binary operation " + op)
        }
      "decimal" =>
        match decimal_spec(op, size, rows, reference_rows) {
          Some(spec) =>
            @benchkit.run(spec, detected.snapshot, stream, seed, protocol)
          None => abort("unknown decimal operation " + op)
        }
      _ => abort("unknown kind " + kind)
    }
    failures += summary.failed_count
    println(
      "EXTBENCH_CASE=" +
      id +
      " round=" +
      round.to_string() +
      " passed=" +
      summary.passed_count.to_string() +
      " failed=" +
      summary.failed_count.to_string(),
    )
  }
  println("EXTBENCH_FAILED=" + failures.to_string())
}
