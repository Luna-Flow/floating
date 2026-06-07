# @decimal.Decimal

本文档描述当前 `0.2.0` 基线中的 `@decimal.Decimal`。

## 表示

有限值按下式存储：

`coefficient * 10^exponent10`

并附带工作精度 `precision`。

## 构造与解析

- `Decimal::make`
- `Decimal::zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_bin_float`

说明：

- 公开的有限构造函数会去除可剥离的 `10` 因子。
- `from_string` 支持普通十进制与科学计数法。
- 非法字符串返回 `None`。

## 访问、规范化与比较

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent10`
- `is_zero`
- `normalized`
- `with_precision`
- `compare`
- `min`
- `max`
- `clamp`

说明：

- `compare` 遇到 `NaN` 会直接拒绝。
- `clamp` 在边界无序或出现 `NaN` 时会直接拒绝。

## 算术与转换

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`
- `to_bin_float`

支持的运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

转换语义：

- 十进制转二进制时，非 dyadic 值可能只能近似表示。
- 二进制转十进制时，会精确保留当前 `BinFloat` 内部已经存储的有限值。

## Trait 面

`Decimal` 当前实现了：

- `@def.Floating`
- `@arithmetic.ParseChecked`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`

补充：

- 这一轮不会从 `Decimal` 暴露常量 trait 或超越函数 trait。
- 与 `Luna-Flow/arithmetic` 的集成面是 checked arithmetic traits。
