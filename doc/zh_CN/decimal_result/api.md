# `decimal_result` API

`DecimalResult` 包装 `Result[Decimal, ArithmeticError]`，用于闭合的 checked 十进制组合。

## 构造与观察

`ok`、`err`、`from_result`、`result` 连接原始结果边界；`from_int`、`from_bigint`、`from_float`、`from_double` 和 `parse` 构造值。`parse` 用 `Err` 表示非法输入。

## 组合与算术

`map`、`bind`、`flat_map` 会保留已有错误。`abs`、`neg`、四则运算、`sqrt`、幂、`normalized`、`with_precision`、`min`、`max` 和 `clamp` 均返回 `Self`，并实现标准运算符。

带 context 和 flags 的 Decimal 运算仍属于 `@decimal.Decimal`；本包装只建模 `ArithmeticError`。

完整数值方法名为 `abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、
`pow_nat`、`pow_int`、`normalized`、`with_precision`、`min`、`max`、`clamp`。
