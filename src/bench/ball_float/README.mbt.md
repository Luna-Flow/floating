# `bench/ball_float`

Maremark benchmarks for interval arithmetic. Exact singleton inputs isolate
the cost of the `BinFloat` kernel, `BallFloat` interval core, and
`BallFloatResult` checked full path for add, multiply, and divide.

```sh
just bench ball-float
```

Paired bootstrap comparisons report the core and checked overhead separately,
making interval construction and wrapper costs visible.
