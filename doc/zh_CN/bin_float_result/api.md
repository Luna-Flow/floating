# `bin_float_result` API

`BinFloatResult` 包装 `Result[BinFloat, ArithmeticError]`，让 checked 二进制算术始终返回同一类型。

## 构造与观察

- `ok`、`err`、`from_result` 包装现有结果；`result` 在应用边界取回原始 `Result`。
- `from_int`、`from_bigint`、`from_float`、`from_double` 构造成功值。

## 组合

`map` 接受不会失败的值变换；`bind` 与 `flat_map` 接受返回 `BinFloatResult` 的变换。已有错误会短路，不调用回调。

## 数值运算

`abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、`pow_nat`、`pow_int`、`normalized`、`with_precision`、`ulp`、`min`、`max` 和 `clamp` 均返回 `Self`，并实现标准算术运算符。
