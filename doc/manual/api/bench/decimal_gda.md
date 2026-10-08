# bench/decimal_gda API

## Purpose

`bench/decimal_gda` holds the General Decimal Arithmetic benchmarks of `floating`. It is a test-only package: all
content is in `*_test.mbt` files built on the [`bench`](../bench.md) toolkit,
and it exports no MoonBit items. This page records the benchmark cases it
defines; the [tutorial](../../tutorial/bench/decimal_gda.md) shows how to run them and the
[design page](../../design/bench/decimal_gda.md) explains the workloads.

## Importing

The package is test-only and exports no items, so there is nothing to import
from it. Its tests import the toolkit as `@benchkit`, the packages under test
and Maremark:

```moonbit nocheck
import {
  "Luna-Flow/floating/bench" @benchkit,
  "Luna-Flow/floating/decimal_gda" @gda,
  "Luna-Flow/floating/decimal_gda_checked" @checked,
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
} for "test"
```

## Benchmark cases

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `decimal-gda/add`, `sub`, `mul`, `div`, `fma`, `parse` | 1, 9, 18, 34, 128 digits | `core/gda` (`@decimal_gda.add` and the other functions with an explicit `GdaContext`), `full/checked` (`GdaDecimalChecked`, which threads the sticky context) | `Development` |

Every specification has a plan test that runs in normal test runs and checks
that it compiles (`GDA benchmark plans compile`), and a performance test marked
`#skip("performance benchmark")` that only `tools/benchmark.py` runs. In the
reported lines `DATASET` is the 0-based index into the datasets column. The
performance tests stream every observation as a `MAREMARK_JSONL=` line and
print the reduced results as `MAREMARK_HOTSPOT=decimal-gda/OP/DATASET full_pct=…`.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bench/decimal_gda"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
