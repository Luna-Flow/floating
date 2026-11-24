# bench/binary API

## Purpose

`bench/binary` holds the binary arithmetic and elementary-function benchmarks of `floating`. It is a test-only package: all
content is in `*_test.mbt` files built on the [`bench`](../bench.md) toolkit,
and it exports no MoonBit items. This page records the benchmark cases it
defines; the [tutorial](../../tutorial/bench/binary.md) shows how to run them and the
[design page](../../design/bench/binary.md) explains the workloads.

## Importing

The package is test-only and exports no items, so there is nothing to import
from it. Its tests import the toolkit as `@benchkit`, the packages under test
and Maremark:

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/bench" @benchkit,
  "Luna-Flow/floating/binary" @bin,
  "Luna-Flow/floating/binary_checked" @checked,
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/experiment",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
} for "test"
```

## Benchmark cases

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `binary/add`, `binary/mul`, `binary/div` | 53, 128, 512, 2048 bits | `kernel/coefficient` (`BigInt`), `core/binary` (`Binary` operators), `full/checked` (`BinaryChecked`) | `Development` |
| `binary/elementary/OP` for 28 functions (`exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `sqrt`, `rootn`, `pow`, `hypot`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`) | 53, 128, 512 bits of precision | `core/binary` (aborting methods), `full/checked` (`BinaryChecked`) | `Development` |

Every specification has a plan test that runs in normal test runs and checks
that it compiles (`binary benchmark plans compile`, `elementary benchmark plans compile`), and a performance test marked
`#skip("performance benchmark")` that only `tools/benchmark.py` runs. In the
reported lines `DATASET` is the 0-based index into the datasets column. The
performance tests stream every observation as a `MAREMARK_JSONL=` line and
print the reduced results as `MAREMARK_HOTSPOT=binary/OP/DATASET core_pct=… full_pct=…` for arithmetic, `MAREMARK_HOTSPOT=binary/elementary/OP/DATASET full_pct=…` for elementary functions.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/bench/binary"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
