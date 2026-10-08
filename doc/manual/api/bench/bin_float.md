# bench/bin_float API

`bench/bin_float` holds the binary arithmetic and elementary-function benchmarks and the square auto-tune experiment of `floating`. It is a test-only package: all
content is in `*_test.mbt` files built on the [`bench`](../bench.md) toolkit,
and it exports no MoonBit items. This page records the benchmark cases it
defines; the [tutorial](../../tutorial/bench/bin_float.md) shows how to run them and the
[design page](../../design/bench/bin_float.md) explains the workloads.

## Benchmark cases

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `bin-float/add`, `bin-float/mul`, `bin-float/div` | 53, 128, 512, 2048 bits | `kernel/coefficient` (`BinCoeff`), `core/bin-float` (`BinFloat` operators), `full/checked` (`BinFloatResult`) | `Development` |
| `bin-float/elementary/OP` for 28 functions (`exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `sqrt`, `rootn`, `pow`, `hypot`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`) | 53, 128, 512 bits of precision | `core/bin-float` (aborting methods), `full/checked` (`BinFloatResult`) | `Development` |
| `bin-float/autotune/square` | 4, 8, 16, …, 1024 limbs of 32 bits | `mul-self` (`x.mul(x)`), `square` (`x.square()`) on `BinCoeff` | `RegressionGate` |

Every specification has a plan test that runs in normal test runs and checks
that it compiles (`binary benchmark plans compile`, `elementary benchmark plans compile`, `binary auto tune plan compiles`), and a performance test marked
`#skip("performance benchmark")` that only `tools/benchmark.py` runs. The
performance tests stream every observation as a `MAREMARK_JSONL=` line and
print the reduced results as `MAREMARK_HOTSPOT=bin-float/OP/DATASET core_pct=… full_pct=…` for arithmetic, `MAREMARK_HOTSPOT=bin-float/elementary/OP/DATASET full_pct=…` for elementary functions, and `MAREMARK_TUNE`, `MAREMARK_CROSSOVER` and `MAREMARK_POLICY` lines for the square experiment.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bench/bin_float"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
