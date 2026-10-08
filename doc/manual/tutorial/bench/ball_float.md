# bench/ball_float tutorial

This page shows how to run the interval (ball) arithmetic benchmarks and how to read their output. The
suite compares implementation paths on identical inputs with paired
measurements; see the [bench tutorial](../bench.md) for the toolkit and the
artifact format.

## Quick start

From the repository root:

```sh
just bench ball-float
```

The runner executes the skipped performance tests of `src/bench/ball_float` on the
native target in release mode and writes `.tmp/bench/SUITE.jsonl` (all
observations) and `.tmp/bench/SUITE.analysis.txt` (the reduced lines), where
`SUITE` is the name given to `just bench`.

## Everyday tasks

### Read the analysis lines

The analysis file contains `MAREMARK_HOTSPOT=ball-float/OP/DATASET core_pct=… full_pct=…`. A `core_pct` value is the median
paired difference between the core path and the kernel, in percent of the
kernel's median time; `full_pct` is the same for the checked path against the
core path. Positive values mean the higher layer is slower.

### Check the plans without measuring

```sh
sh tools/run_moon_clean_exec.sh test src/bench/ball_float --target native
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

- [bench/ball_float API](../../api/bench/ball_float.md)
- [bench/ball_float design](../../design/bench/ball_float.md)
- [bench design](../../design/bench.md) for the statistics.
