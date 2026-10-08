# bench/ball_float API

## Purpose

`bench/ball_float` holds the interval (ball) arithmetic benchmarks of `floating`. It is a test-only package: all
content is in `*_test.mbt` files built on the [`bench`](../bench.md) toolkit,
and it exports no MoonBit items. This page records the benchmark cases it
defines; the [tutorial](../../tutorial/bench/ball_float.md) shows how to run them and the
[design page](../../design/bench/ball_float.md) explains the workloads.

## Importing

The package is test-only and exports no items, so there is nothing to import
from it. Its tests import the toolkit as `@benchkit`, the packages under test
and Maremark:

```moonbit nocheck
import {
  "Luna-Flow/floating/ball_float" @ball,
  "Luna-Flow/floating/ball_float_checked" @checked,
  "Luna-Flow/floating/bench" @benchkit,
  "Luna-Flow/floating/bin_float" @binary,
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
} for "test"
```

## Benchmark cases

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `ball-float/add`, `ball-float/mul`, `ball-float/div` | 53, 128, 512, 2048 bits | `kernel/bin-float` (`BinFloat`), `core/ball-float` (`BallFloat`), `full/checked` (`BallFloatResult`) | `Development` |

Every specification has a plan test that runs in normal test runs and checks
that it compiles (`ball benchmark plans compile`), and a performance test marked
`#skip("performance benchmark")` that only `tools/benchmark.py` runs. In the
reported lines `DATASET` is the 0-based index into the datasets column. The
performance tests stream every observation as a `MAREMARK_JSONL=` line and
print the reduced results as `MAREMARK_HOTSPOT=ball-float/OP/DATASET core_pct=… full_pct=…`.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bench/ball_float"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
