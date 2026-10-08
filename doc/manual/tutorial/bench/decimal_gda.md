# bench/decimal_gda tutorial

This page shows how to run the General Decimal Arithmetic benchmarks and how to read their output. The
suite compares implementation paths on identical inputs with paired
measurements; see the [bench tutorial](../bench.md) for the toolkit and the
artifact format.

## Quick start

From the repository root:

```sh
just bench decimal-gda
```

The runner executes the skipped performance tests of `src/bench/decimal_gda` on the
native target in release mode and writes `.tmp/bench/SUITE.jsonl` (all
observations) and `.tmp/bench/SUITE.analysis.txt` (the reduced lines), where
`SUITE` is the name given to `just bench`.

## Everyday tasks

### Read the analysis lines

The analysis file contains `MAREMARK_HOTSPOT=decimal-gda/OP/DATASET full_pct=…`. A `core_pct` value is the median
paired difference between the core path and the kernel, in percent of the
kernel's median time; `full_pct` is the same for the checked path against the
core path. Positive values mean the higher layer is slower.

### Check the plans without measuring

```sh
sh tools/run_moon_clean_exec.sh test src/bench/decimal_gda --target native
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

- [bench/decimal_gda API](../../api/bench/decimal_gda.md)
- [bench/decimal_gda design](../../design/bench/decimal_gda.md)
- [bench design](../../design/bench.md) for the statistics.
