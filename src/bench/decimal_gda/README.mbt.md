# `bench/decimal_gda`

Maremark benchmarks for GDA decimal arithmetic. Add, multiply, divide, fused
multiply-add, and parse workloads compare the GDA core with its sticky-context
checked wrapper.

```sh
just bench decimal-gda
```

The benchmark uses exact, non-trapping inputs so both paths are validated
against the same reference value before measurement.
