# bench tutorial

This tutorial shows how to run the `floating` benchmark suites, where their
results go, how to read the analysis lines, and how to write a new benchmark
with the `bench` toolkit. The suites measure kernel, core and checked paths of
each numeric package with the Maremark framework and report paired
comparisons with bootstrap confidence intervals.

| I want to | Use |
| --- | --- |
| run the benchmarks of one package | [`just bench SUITE`](#choose-a-suite) |
| read the hotspot lines | [`MAREMARK_HOTSPOT`](#quick-start) |
| read the square auto-tune result | [`MAREMARK_TUNE`, `MAREMARK_CROSSOVER`](#read-an-auto-tune-result) |
| decide whether a change is a regression | [`confirmatory_regression`, `is_significant_regression`](#check-a-regression-in-code) |
| add a benchmark | [`immutable_bench`, `run`, `paired_hotspot`](#write-a-new-benchmark) |
| understand the statistics | [bench design](../design/bench.md) |

## Quick start

To use the reduction functions in your own module, add the library and import
the package in `moon.pkg`:

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/bench",
}
```

The smallest useful program compares two paired sample arrays, for example
per-call times measured before and after a change in the same ten blocks:

```moonbit
///|
test "quick start" {
  let before = [10.0, 10.2, 9.9, 10.1, 10.0, 10.3, 9.8, 10.0, 10.1, 10.0]
  let after = before.map(x => x * 1.08)
  let comparison = @bench.confirmatory_regression(before, after, 42UL).unwrap()
  inspect(comparison.relative_delta_pct > 7.9, content="true")
  inspect(@bench.is_significant_regression(comparison), content="true")
}
```

An 8 % slowdown is above the 3 % practical threshold, and every paired
difference is positive, so the 95 % interval of the median difference lies
above zero.

The `floating` suites themselves run from a checkout of the repository. Run
one suite from the repository root:

```bash
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

meaning: for dataset 2 of `bin-float/mul`, the median paired difference
between the `core/bin-float` path and the coefficient kernel is `core_pct`
percent of the kernel's median per-call time (negative when the core is
faster), and `full_pct` is the same for the checked path against the core.

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
that dataset, and `samples` the number of valid confirmatory observations
behind it. When the winner changes exactly once along the scales, the
crossover line gives the last scale `below` the change and the first scale
`at_or_above` it, and the policy line is the per-scale lookup table a kernel
can embed. When it changes more than once the suite prints
`MAREMARK_CROSSOVER=non-monotonic` and a `MAREMARK_POLICY=lookup` line; when
it never changes, `MAREMARK_CROSSOVER=none` and no policy line.

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
- **The tuning threshold does nothing.** `tune_dataset` always returns the
  candidate with the smallest median; its `practical_delta_pct` argument does
  not create ties, so two nearly equal candidates can alternate between
  datasets and make the crossover non-monotonic. Which secondary criterion
  is intended is open in [#60](https://github.com/Luna-Flow/floating/issues/60).

## Next steps

- [bench API](../api/bench.md)
- [bench design](../design/bench.md)
- Per-core suites: [bin_float](bench/bin_float.md), [decimal](bench/decimal.md),
  [decimal_gda](bench/decimal_gda.md), [ball_float](bench/ball_float.md).
