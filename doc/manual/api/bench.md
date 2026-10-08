# bench API

`bench` is the shared benchmark toolkit of `floating`, built on the Maremark
framework (`Luna-Flow/mare_mark`). It builds immutable benchmark
specifications, describes the measurement environment, runs a specification
under a validated protocol, and reduces the recorded observations: paired
comparisons with bootstrap confidence intervals, a regression verdict, and
per-dataset auto-tuning decisions. The per-core suites
[bench/bin_float](bench/bin_float.md), [bench/decimal](bench/decimal.md),
[bench/decimal_gda](bench/decimal_gda.md) and
[bench/ball_float](bench/ball_float.md) use it. The
[tutorial](../tutorial/bench.md) shows how to run the suites and the
[design page](../design/bench.md) derives the statistics.

Import the package in `moon.pkg` (Maremark packages are needed to build
specifications and observations):

```text
import {
  "Luna-Flow/floating/bench",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/event",
}
```

Types prefixed `@model`, `@runner`, `@event` and `@stats` belong to
`Luna-Flow/mare_mark`. An `@model.Observation` records one timed batch: case,
implementation, dataset, repetition and block ids, phase (exploratory or
confirmatory), `raw_elapsed_us` (batch time divided by the batch's iteration
count, so the mean time of one call in microseconds), and a `valid` flag.

## Building and running benchmarks

### `immutable_bench`

`immutable_bench(id, operation, scales, scale_text, generate, fingerprint,
implementations, reference, comparator, input_text, output_text)` builds a
benchmark whose input is generated once per scale and never mutated.

```mbti
pub fn[Scale, Input, Expected, Output] immutable_bench(String, String, Array[Scale], (Scale) -> String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String, Array[@runner.Implementation[Input, Output, Unit]], (Input) -> Expected, (Expected, Output) -> Bool, (Input) -> String, (Output) -> String) -> @runner.BenchSpec[Scale, Input, Input, Expected, Output, Unit, Output?, Output?]
```

| Argument | Meaning |
| --- | --- |
| `id` | case id, also used for the fixture (`id-fixture`, version `"1"`) and the oracle (`id-reference`) |
| `operation` | operation name recorded in the case descriptor |
| `scales`, `scale_text` | the datasets (for example bit or digit sizes) and their labels; dataset $k$ is `scales[k]` |
| `generate`, `fingerprint` | build the input for a scale; identify it in reports |
| `implementations` | stateless implementations compared on the same input |
| `reference`, `comparator` | an independent expected value and the check of every output against it |
| `input_text`, `output_text` | text forms for reports and replay |

The specification keeps the last output of each batch as a sink (so the work
cannot be optimized away), validates outputs with the reference oracle, uses
one repetition unit, and describes each case as stateless and exact.

### `environment`

`environment(target, dtype_abi, run_id)` builds the environment snapshot
recorded with every run.

```mbti
pub fn environment(@model.ExecutionTarget, String, String) -> @model.EnvironmentSnapshot
```

It records the target, a fixed toolchain label, the `release` profile and the
given data-type ABI label; the performance and provenance fields that only the
calling tool knows (CPU, frequency policy, commit) are marked
`external-metadata`, and the source state as `working-tree`.

### `run`

`run(spec, environment, sink, seed, protocol)` compiles a specification and
executes it, streaming observations to `sink`.

```mbti
pub async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] run(@runner.BenchSpec[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], @model.EnvironmentSnapshot, @event.ObservationSink, UInt64, @runner.ValidatedProtocol) -> @model.RunSummary
```

`seed` fixes the measurement order of the implementations; `protocol` is
normally a preset such as `@runner.ProtocolPreset::Development.validated()`.
The function aborts if the specification does not compile. The returned
summary counts observations and oracle failures.

## Reducing observations

### `paired_hotspot`

`paired_hotspot(observations, case_id, dataset_id, baseline_id, candidate_id,
practical_delta_pct, seed)` compares two implementations on one dataset.

```mbti
pub fn paired_hotspot(Array[@model.Observation], String, Int, String, String, Double, UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]
```

It selects the valid confirmatory observations of each implementation for the
case and dataset, orders them by block id, pairs them by position and calls
`@stats.compare_paired_with_bootstrap` with 2000 resamples. The comparison's
`relative_delta_pct` is $100 \cdot \operatorname{med}(c - b) / \operatorname{med}(b)$
and its `decision` is `Faster`, `Slower` or `Equivalent` relative to
`practical_delta_pct`; its `interval` is the 95 % percentile-bootstrap
interval of the median paired difference. Errors:
`MismatchedPairs` when the two implementations have different numbers of
samples, `EmptySamples` when there are none, `NonFiniteSample`.

### `confirmatory_regression`

`confirmatory_regression(baseline, candidate, seed)` compares two paired
sample arrays with a 95 % percentile-bootstrap interval.

```mbti
pub fn confirmatory_regression(Array[Double], Array[Double], UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]
```

The practical threshold is 3 %, the bootstrap uses 10 000 resamples, and the
interval is on the median paired difference `candidate[j] - baseline[j]` in
the samples' unit. The labels identify the baseline and the current
candidate.

### `is_significant_regression`

`is_significant_regression(comparison)` is true when the candidate is
practically slower and the interval of the median difference lies entirely
above zero.

```mbti
pub fn is_significant_regression(@stats.Comparison) -> Bool
```

That is, `decision` is `Slower` and `interval.low > 0`.

```moonbit
///|
test "regression verdict" {
  let baseline = [100.0, 101.0, 99.0, 100.5, 99.5, 100.0, 101.0, 99.0, 100.0, 100.5]
  let slower = baseline.map(x => x * 1.1)
  let comparison = @bench.confirmatory_regression(baseline, slower, 7UL).unwrap()
  inspect(comparison.relative_delta_pct > 9.0, content="true")
  inspect(@bench.is_significant_regression(comparison), content="true")
  let same = @bench.confirmatory_regression(baseline, baseline, 7UL).unwrap()
  inspect(@bench.is_significant_regression(same), content="false")
}
```

## Auto-tuning

### `TuneDecision`

`TuneDecision` is the implementation chosen for one dataset.

```mbti
pub struct TuneDecision {
  dataset_id : Int
  candidate_id : String
  median_us : Double
  valid_samples : Int
}
```

`median_us` is the median per-call time of the chosen candidate and
`valid_samples` the number of finite, non-negative confirmatory samples it
was computed from.

### `tune_dataset`

`tune_dataset(observations, case_id, dataset_id, candidate_ids,
practical_delta_pct)` picks the fastest candidate for one dataset.

```mbti
pub fn tune_dataset(Array[@model.Observation], String, Int, Array[String], Double) -> TuneDecision?
```

For every candidate it takes the valid confirmatory observations of the case
and dataset, and scores the candidate by the median of the finite,
non-negative samples. Candidates without such samples are invalid. The result
is the valid candidate with the smallest median, ties broken by the smaller
candidate id; `None` when no candidate is valid. Because the score is used as
both the primary and the secondary criterion of `@tune.select_best`,
`practical_delta_pct` does not change the choice.

```moonbit
///|
test "no observations, no decision" {
  inspect(@bench.tune_dataset([], "mul", 0, ["kernel", "full"], 3.0) is None, content="true")
  inspect(
    @bench.paired_hotspot([], "mul", 0, "kernel", "full", 3.0, 1UL) is Err(_),
    content="true",
  )
}
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bench"

import {
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/stats",
}

// Values
pub fn confirmatory_regression(Array[Double], Array[Double], UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]

pub fn environment(@model.ExecutionTarget, String, String) -> @model.EnvironmentSnapshot

pub fn[Scale, Input, Expected, Output] immutable_bench(String, String, Array[Scale], (Scale) -> String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String, Array[@runner.Implementation[Input, Output, Unit]], (Input) -> Expected, (Expected, Output) -> Bool, (Input) -> String, (Output) -> String) -> @runner.BenchSpec[Scale, Input, Input, Expected, Output, Unit, Output?, Output?]

pub fn is_significant_regression(@stats.Comparison) -> Bool

pub fn paired_hotspot(Array[@model.Observation], String, Int, String, String, Double, UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]

pub async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] run(@runner.BenchSpec[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], @model.EnvironmentSnapshot, @event.ObservationSink, UInt64, @runner.ValidatedProtocol) -> @model.RunSummary

pub fn tune_dataset(Array[@model.Observation], String, Int, Array[String], Double) -> TuneDecision?

// Errors

// Types and methods
pub struct TuneDecision {
  dataset_id : Int
  candidate_id : String
  median_us : Double
  valid_samples : Int
}

// Type aliases

// Traits
```
<!-- generated-api-end -->
