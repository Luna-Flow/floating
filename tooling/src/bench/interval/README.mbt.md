# `bench/interval`

Maremark benchmarks for interval arithmetic. Exact singleton inputs isolate
the cost of the `BinFloat` kernel, `Interval` interval core, and
`IntervalResult` checked full path for add, multiply, and divide.

```sh
just bench interval
```

Paired bootstrap comparisons report the core and checked overhead separately,
making interval construction and wrapper costs visible.
