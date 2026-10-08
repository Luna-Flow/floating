# bench/bin_float tutorial

This page shows how to run the binary arithmetic and elementary-function benchmarks and the square auto-tune experiment and how to read their output. The
suite compares implementation paths on identical inputs with paired
measurements; see the [bench tutorial](../bench.md) for the toolkit and the
artifact format.

| I want to | Use |
| --- | --- |
| run the suite | [`just bench bin-float`](#quick-start) |
| run only the elementary functions or the auto-tune | [`just bench elementary`, `just bench auto-tune`](#quick-start) |
| read the reported percentages | [`MAREMARK_HOTSPOT` lines](#read-the-analysis-lines) |
| check that the specifications still compile | [the plan tests](#check-the-plans-without-measuring) |
| change workloads or paths | [the `*_test.mbt` files](#going-further) |
| understand the statistics | [bench design](../../design/bench.md) |

## Quick start

The suite runs from a checkout of the repository; it is not part of the
published package, so there is nothing to `moon add`. From the repository
root:

```bash
just bench bin-float
just bench elementary
just bench auto-tune
```

The runner executes the skipped performance tests of `src/bench/bin_float` on the
native target in release mode and writes `.tmp/bench/SUITE.jsonl` (all
observations) and `.tmp/bench/SUITE.analysis.txt` (the reduced lines), where
`SUITE` is the name given to `just bench`.

## Everyday tasks

### Read the analysis lines

The analysis file contains `MAREMARK_HOTSPOT=bin-float/OP/DATASET core_pct=… full_pct=…` for arithmetic, `MAREMARK_HOTSPOT=bin-float/elementary/OP/DATASET full_pct=…` for elementary functions, and `MAREMARK_TUNE`, `MAREMARK_CROSSOVER` and `MAREMARK_POLICY` lines for the square experiment. A `core_pct` value is the median
paired difference between the core path and the kernel, in percent of the
kernel's median time; `full_pct` is the same for the checked path against the
core path. Positive values mean the higher layer is slower.

### Check the plans without measuring

```bash
sh tools/run_moon_clean_exec.sh test src/bench/bin_float --target native
```

runs only the plan tests, which compile every specification.

## Going further

- Change datasets or implementations in the `*_test.mbt` files; keep the
  reference oracle so a faster but wrong path fails the run.
- Compare two runs only when their recorded environments agree.
- The [performance audit](../../performance_audit.md) and the `performance/`
  pages summarize measured results.

## Common pitfalls

- Benchmarks are skipped in normal `moon test` runs; use `just bench`.
- Results depend on the machine; percentages are more stable than absolute
  microseconds.

## Next steps

- [bench/bin_float API](../../api/bench/bin_float.md)
- [bench/bin_float design](../../design/bench/bin_float.md)
- [bench design](../../design/bench.md) for the statistics.
