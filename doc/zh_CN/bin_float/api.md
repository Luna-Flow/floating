# @bin_float.BinFloat

本文档描述当前 `0.1.0` 基线中的 `@bin_float.BinFloat`。

## 表示

有限值表示为：

`significand * 2^exponent2`

并额外携带：

- `class`
- `precision`

## 主要构造函数

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::from_int`
- `BinFloat::from_bigint`

## 访问与分类

- `classify`
- `precision`
- `sign`
- `significand`
- `exponent2`
- `is_zero`

## 规范化与精度控制

- `normalized`
- `with_precision`
- `ulp`

## 算术

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

支持运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

## 比较

- `compare`

注意：

- `compare` 遇到 `NaN` 会直接拒绝
- 有限值比较会先对齐指数再比较 significand
