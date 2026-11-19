# `bench/bin_float`

Maremark benchmarks for binary arithmetic. The package compares `BinCoeff`,
`BinFloat`, and `BinFloatResult` on exact arithmetic inputs, measures the full
elementary-function matrix, and auto-tunes the semantically equivalent
`mul(x, x)` versus `square(x)` crossover.

```sh
just bench bin-float
just bench elementary
just bench auto-tune
```

All timed tests are skipped during normal correctness runs and emit versioned
`mmka_1` JSONL when explicitly selected by the unified benchmark runner.
