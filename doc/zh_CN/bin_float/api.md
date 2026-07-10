# @bin_float.BinFloat

本文档描述当前 `0.4.0` 基线中的 `@bin_float.BinFloat`。

## 表示

有限值按下式存储：

`significand * 2^exponent2`

并附带工作精度 `precision`。

## 构造与存储形式

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::from_int`
- `BinFloat::from_bigint`
- `BinFloat::from_float`
- `BinFloat::from_double`

说明：

- 公开的有限构造函数都会先做规范化。
- `compare` 遇到 `NaN` 会直接拒绝。
- 当前实现中，`sign()` 对 `NaN` 返回 `Sign::Zero`。

## 访问、规范化与比较

- `classify`
- `precision`
- `sign`
- `significand`
- `exponent2`
- `is_zero`
- `normalized`
- `with_precision`
- `ulp`
- `compare`
- `min`
- `max`
- `clamp`

说明：

- `clamp` 在边界无序或出现 `NaN` 时会直接拒绝。
- `ulp()` 对非有限值返回 `NaN`。

## 算术与转换

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

支持的运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

特殊值行为：

- `NaN` 一般会传播。
- 异号的 `inf - inf` 会得到 `NaN`。
- 除以零时会根据分子类别得到 `inf` 或 `NaN`。

## checked 算术接口

当前直接导出的 checked helper 包括：

- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `compare_checked`
- `div_checked`
- `sqrt`
- `pow_int`

checked 行为说明：

- `sqrt*` 需要非负有限输入。
- `compare_checked` 遇到 `NaN` 会返回 unordered-comparison error。
- `div_checked` 会对零除返回 structured error。
- `pow_int` 在负指数且底数为零时返回 division-by-zero error。

## Trait 面

`BinFloat` 当前实现了：

- `@def.Floating`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
