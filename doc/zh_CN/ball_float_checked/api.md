# `ball_float_checked` API

`BallFloatResult` 包装 `Result[BallFloat, ArithmeticError]`，同时保留区间语义。

## 构造与观察

`ok`、`err`、`from_result`、`result` 连接原始结果；`exact`、`from_bounds`、`whole` 及各类 `from_*` 构造包装区间。非法边界返回 `Err`。

## 组合与算术

`map`、`bind`、`flat_map` 会短路已有错误。绝对值、取负、四则运算、整数幂、规范化与精度调整均返回 `Self`，并实现标准运算符。

除数区间含零时会按 `BallFloat` 语义返回 whole-real enclosure，不会转成 `Err`。

完整数值接口包括 `from_int`、`from_coefficient`、`from_float`、`from_double`、
`abs`、`neg`、`add`、`sub`、`mul`、`div`、`pow_nat`、`pow_int`、
`normalized` 和 `with_precision`。

`from_coefficient` 接受 `@bin_float.BinCoeff` 与独立的 `negative?` 符号；二进制
checked API 不接受 `BigInt`。
