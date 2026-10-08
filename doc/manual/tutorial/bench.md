# bench tutorial

This tutorial shows how to run the `floating` benchmark suites, where their
results go, how to read the analysis lines, and how to write a new benchmark
with the `bench` toolkit. The suites measure kernel, core and checked paths of
each numeric package with the Maremark framework and report paired
comparisons with bootstrap confidence intervals.

## Quick start

Run one suite from the repository root:

```sh
just bench bin-float
```

The command runs the skipped performance tests of `src/bench/bin_float` in
release mode on the native target, then writes

```text
Maremark artifact: .tmp/bench/bin-float.jsonl
Maremark analysis: .tmp/bench/bin-float.analysis.txt
```

The `.jsonl` file holds one versioned (`mmka_1`) event per line: every
observation, the environment and the run summary. The `.analysis.txt` file
holds the reduced results, one line per comparison, for example

```text
MAREMARK_HOTSPOT=bin-float/mul/2 core_pct=… full_pct=…
```

meaning: for dataset 2 of `bin-float/mul`, the median per-call time of the
`core/bin-float` path is `core_pct` percent above (or below, if negative) the
coefficient kernel, and the checked path is `full_pct` percent above the core.

## Everyday tasks

### Choose a suite

| Suite | Runs |
| --- | --- |
| `just bench bin-float` | all tests of `src/bench/bin_float` (arithmetic, elementary functions, square auto-tune) |
| `just bench elementary` | only the binary elementary-function benchmark |
| `just bench auto-tune` | only the `mul(x, x)` versus `square(x)` crossover |
| `just bench decimal` | `src/bench/decimal` |
| `just bench decimal-gda` | `src/bench/decimal_gda` |
| `just bench ball-float` | `src/bench/ball_float` |
| `just bench all` | the four package suites |

Add `--output PATH` to choose the artifact path or `--dry-run` to print the
`moon test` commands without running them.

### Read an auto-tune result

The auto-tune suite prints one decision per dataset and a crossover:

```text
MAREMARK_TUNE=bin-float/autotune/square/64 candidate=square median_us=… samples=20
MAREMARK_CROSSOVER=bin-float/autotune/square below=… at_or_above=…
MAREMARK_POLICY=piecewise case=bin-float/autotune/square lookup=4:…,8:…
```

`candidate` is the implementation with the smallest median per-call time on
that dataset; the crossover is the first scale from which the other candidate
wins; the policy line is a lookup table a kernel can embed.

### Check a regression in code

`confirmatory_regression` compares paired samples (same order, same blocks)
and `is_significant_regression` applies the verdict:

```moonbit
///|
test "is it slower?" {
  let before = [10.0, 10.2, 9.9, 10.1, 10.0, 10.3, 9.8, 10.0]
  let after = [10.1, 10.2, 10.0, 10.0, 10.1, 10.2, 9.9, 10.1]
  let comparison = @bench.confirmatory_regression(before, after, 42UL).unwrap()
  inspect(@bench.is_significant_regression(comparison), content="false")
}
```

A change of about 0.5 % is below the 3 % practical threshold, so it is not a
regression even if it were statistically clear.

### Write a new benchmark

A benchmark is an `immutable_bench` specification plus a skipped async test
that runs it and prints Maremark lines. The pattern used by every suite:

```moonbit nocheck
///|
fn square_spec() -> @runner.BenchSpec[Int, BigInt, BigInt, BigInt, BigInt, Unit, BigInt?, BigInt?] {
  @benchkit.immutable_bench(
    "example/square",
    "square",
    [64, 256, 1024],                        // datasets: bit sizes
    bits => bits.to_string() + "bit",
    context => (1N << context.dataset_key.scale) - 1N,
    value => value.bit_length().to_string(),
    [
      @runner.Implementation::stateless("mul-self", "0.8.0", x => {
        @model.OperationResult::completed(x * x, ())
      }),
      @runner.Implementation::stateless("pow", "0.8.0", x => {
        @model.OperationResult::completed(x.pow(2N), ())
      }),
    ],
    x => x * x,                              // reference
    (expected, actual) => expected == actual,
    x => x.bit_length().to_string(),
    y => y.bit_length().to_string(),
  )
}

///|
test "plan compiles" {
  ignore(square_spec().compile().unwrap())
}

///|
#skip("performance benchmark")
async test "square paths" {
  let memory = @event.InMemorySink::new()
  let stream = @event.streaming_jsonl(
    line => println("MAREMARK_JSONL=" + line),
    "stdout://bench/example/square",
  )
  let summary = @benchkit.run(
    square_spec(),
    @benchkit.environment(@model.ExecutionTarget::Native, "bigint", "example-square"),
    @event.tee(memory.as_sink(), stream),
    20260715UL,
    @runner.ProtocolPreset::Development.validated(),
  )
  assert_eq(summary.failed_count, 0)
  for dataset_id in 0..<3 {
    let comparison = @benchkit.paired_hotspot(
      memory.observations, "example/square", dataset_id, "mul-self", "pow", 3.0, 20260715UL,
    ).unwrap()
    println("MAREMARK_HOTSPOT=example/square/" + dataset_id.to_string() +
      " pow_pct=" + comparison.relative_delta_pct.to_string())
  }
}
```

Keep the plan-compiles test unskipped: it checks the specification in every
normal test run. Register the package in `tools/benchmark.py` so `just bench`
collects its output.

## Going further

- The protocol presets of Maremark fix warm-up, batch calibration, sample
  counts and order: `QuickCheck` (3 confirmatory blocks), `Development` (10
  blocks, used by the suites) and `RegressionGate` (20 blocks, used by the
  auto-tune suite). See the
  [Maremark documentation](https://lunaflow.cn/en/mare_mark/).
- [bench design](../design/bench.md) explains the estimators and the
  confidence interval.
- [Performance audit](../performance_audit.md) and the `performance/` pages
  record measured results.

## Common pitfalls

- **Benchmarks are skipped by default.** `moon test` runs only the
  plan-compiles tests; use `just bench` (it passes `--include-skipped`,
  `--release` and `--no-parallelize`).
- **Native only.** `tools/benchmark.py` accepts only the native target.
- **Pairing needs equal sample counts.** Both implementations of a
  comparison must have the same number of valid confirmatory observations;
  otherwise `paired_hotspot` returns `MismatchedPairs`.
- **The hotspot interval is not a 95 % interval.** `paired_hotspot` passes a
  confidence of `0.95` percent; rely on its relative delta and decision.

## Next steps

- [bench API](../api/bench.md)
- [bench design](../design/bench.md)
- Per-core suites: [bin_float](bench/bin_float.md), [decimal](bench/decimal.md),
  [decimal_gda](bench/decimal_gda.md), [ball_float](bench/ball_float.md).
