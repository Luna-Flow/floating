# bench/external API

## Purpose

`bench/external` holds the benchmark that times `floating` on an operand file
shared with a C harness for MPFR and libmpdec. It is a test-only package: all
content is in `*_test.mbt` files built on the [`bench`](../bench.md) toolkit,
and it exports no MoonBit items. This page records the cases it defines; the
[tutorial](../../tutorial/bench/external.md) shows how to run them, the
[design page](../../design/bench/external.md) explains the method, and the
[performance page](../../performance/bench/external.md) holds the measured
ratios.

## Importing

The package is test-only and exports no items, so there is nothing to import
from it. Its tests import the toolkit as `@benchkit`, the packages under test,
Maremark, the file and environment access of the runner, and the async
runtime:

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/bench" @benchkit,
  "Luna-Flow/floating/binary" @binary,
  "Luna-Flow/floating/decimal_gda" @gda,
  "Luna-Flow/mare_mark/env_detect",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
  "moonbitlang/x/fs",
} for "test"
```

## Benchmark cases

| Case | Scale | Implementation | Oracle |
| --- | --- | --- | --- |
| `external/binary/OP` for `add`, `mul`, `div`, `sqrt`, `exp`, `ln`, `sin` | 53, 128, 512, 2048, 8192 bits | `floating` (`Binary` methods at the scale as precision, round to nearest even) | the MPFR result for each operand, bit for bit |
| `external/decimal_gda/OP` for `add`, `mul`, `div`, `sqrt`, `exp`, `ln` | 16, 34, 100, 1000 digits | `floating` (`decimal_gda` functions in a context of the scale as precision, `HalfEven`, exponent range ±999999) | the libmpdec result for each operand, value for value |

Every case has a second implementation, `null`, next to `floating`: the same
closure call and result store with the library call removed. Maremark runs the
blocks of the two implementations interleaved (each with its own calibration),
and the runner pairs them by block number. The null reads `expected` instead of
the operands so that its output validates against the reference.

One iteration of the timed function is one pass over the eight operand sets of
the case, so a reported time per operation is the observation divided by
eight. The scales and the operation list come from the operand file: the test
runs the cases named by `EXTBENCH_CASES`, in that order, or every case of the
file.

The inputs of the test are environment variables set by the runner:

| Variable | Meaning |
| --- | --- |
| `EXTBENCH_INPUTS` | operand file (required) |
| `EXTBENCH_REFERENCE` | MPFR/libmpdec reference results, the oracle |
| `EXTBENCH_CASES` | comma-separated `kind/op/size`, in measurement order |
| `EXTBENCH_SEED`, `EXTBENCH_ROUND` | Maremark seed and the round number copied to the log |
| `EXTBENCH_WARMUP_ITERATIONS`, `EXTBENCH_WARMUP_US`, `EXTBENCH_TARGET_BATCH_US`, `EXTBENCH_MIN_BATCH`, `EXTBENCH_MAX_BATCH`, `EXTBENCH_MAX_SAMPLE_US`, `EXTBENCH_EXPLORATORY`, `EXTBENCH_CONFIRMATORY` | the measurement protocol, the same numbers the C harness receives |

The performance test is built for native, wasm (run by `moonrun`) and js (run by
node), which is how the runner measures the floating side on those runtimes
(`--target`). It is not built for wasm-gc: the module initialiser of the
`moonbitlang/async` dependency (a cast between two struct types) is rejected by the
runtime at validation there. The environment variables and the files are read the
same way on the three targets.

Three plan tests run in normal test runs (`external input rows group by case`,
`external binary and decimal_gda plans compile`, `external operand parsing is
exact`). The performance test `external baseline floating` is marked
`#skip("performance benchmark")` and builds on native only; the runner prints
a `MAREMARK_JSONL=` line for every event, `EXTBENCH_CASE=kind/op/size
round=R passed=P failed=F` for every case, and `EXTBENCH_FAILED=N` at the end.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/bench/external"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
