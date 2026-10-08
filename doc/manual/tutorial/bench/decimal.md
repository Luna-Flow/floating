# bench/decimal tutorial

This page shows how to run the IEEE decimal arithmetic benchmarks and how to read their output. The
suite compares implementation paths on identical inputs with paired
measurements; see the [bench tutorial](../bench.md) for the toolkit and the
artifact format.

| I want to | Use |
| --- | --- |
| run the suite | [`just bench decimal`](#quick-start) |
| read the reported percentages | [`MAREMARK_HOTSPOT` lines](#read-the-analysis-lines) |
| check that the specifications still compile | [the plan tests](#check-the-plans-without-measuring) |
| change workloads or paths | [the `*_test.mbt` files](#going-further) |
| understand the statistics | [bench design](../../design/bench.md) |

## Quick start

The suite runs from a checkout of the repository; it is not part of the
published package, so there is nothing to `moon add`. From the repository
root:

```bash
just bench decimal
```

The runner executes the skipped performance tests of `src/bench/decimal` on the
native target in release mode and writes `.tmp/bench/SUITE.jsonl` (all
observations) and `.tmp/bench/SUITE.analysis.txt` (the reduced lines), where
`SUITE` is the name given to `just bench`.

## Everyday tasks

### Read the analysis lines

The analysis file contains `MAREMARK_HOTSPOT=decimal/OP/DATASET core_pct=… full_pct=…`. A `core_pct` value is the median
paired difference between the core path and the kernel, in percent of the
kernel's median time; `full_pct` is the same for the checked path against the
core path. Positive values mean the higher layer is slower.

### Check the plans without measuring

```bash
sh tools/run_moon_clean_exec.sh test src/bench/decimal --target native
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

- [bench/decimal API](../../api/bench/decimal.md)
- [bench/decimal design](../../design/bench/decimal.md)
- [bench design](../../design/bench.md) for the statistics.
