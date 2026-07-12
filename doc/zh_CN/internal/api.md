# @internal

本文档描述 `0.5.0` 基线中的 `@internal` 包。它是实现辅助层，不是稳定公开 API。

## BigInt 辅助

- `bigint_zero`
- `bigint_one`
- `abs_bigint`
- `sign_of_bigint`

## 幂与位数辅助

- `pow2`
- `pow5`
- `pow10`
- `digits10`

## 规范化辅助

- `remove_factor2`
- `remove_factor10`
- `exact_divide_by_power_of_ten`：仅在能被指定的 `10` 的幂整除时返回精确商。
- `trim_trailing_decimal_zeros`：在可选上限内移除末尾十进制零，并返回新系数、指数和移除数量。

## 舍入辅助

- `round_positive_div`
- `round_shift`
- `compare_abs`

## 十进制解析辅助

- `split_decimal_string`

它把十进制字符串拆成：

- 是否为负
- 去掉分隔后的 digit 串
- 十进制指数修正量
