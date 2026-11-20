# `bench/bin_float`

Maremark benchmarks for binary arithmetic. The package compares `BigInt`,
`BinFloat`, and `BinFloatResult` on exact arithmetic inputs and measures the full
elementary-function matrix.

```sh
just bench bin-float
just bench elementary
```

All timed tests are skipped during normal correctness runs and emit versioned
`mmka_1` JSONL when explicitly selected by the unified benchmark runner.
