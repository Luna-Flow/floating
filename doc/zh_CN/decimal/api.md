# @decimal.Decimal

本文档描述当前 `0.1.0` 基线中的 `@decimal.Decimal`。

## 表示

有限值表示为：

`coefficient * 10^exponent10`

## 构造与特殊值

- `Decimal::make`
- `Decimal::zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_string`

## 访问与分类

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent10`
- `is_zero`

## 规范化与精度控制

- `normalized`
- `with_precision`

## 算术

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

## 转换

- `to_bin_float`
- `Decimal::from_bin_float`

注意：

- 十进制转二进制时，非 dyadic 值可能只能近似表示
- 二进制转十进制时，当前实现会精确保留已存储的有限二进制表示
