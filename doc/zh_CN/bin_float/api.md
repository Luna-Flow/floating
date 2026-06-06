# @bin_float.BinFloat

本文档描述当前 `0.1.0` 基线中的 `@bin_float.BinFloat`。

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

## 常量与超越函数接口

当前直接导出的 helper 包括：

- `pi_for_precision`
- `tau_for_precision`
- `half_pi_for_precision`
- `quarter_pi_for_precision`
- `ln2_for_precision`
- `e_for_precision`
- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `cbrt_for_precision`
- `exp_for_precision`
- `exp2_for_precision`
- `ln_for_precision`
- `log2_for_precision`
- `log10_for_precision`
- `sin_for_precision`
- `cos_for_precision`
- `tan_for_precision`
- `atan_for_precision`
- `atan2_for_precision`
- `asin_for_precision`
- `acos_for_precision`
- `sinh_for_precision`
- `cosh_for_precision`
- `tanh_for_precision`
- `asinh_for_precision`
- `acosh_for_precision`
- `atanh_for_precision`
- `pow_for_precision`
- `bin_floor_integer`
- `bin_ceil_integer`
- `bin_nearest_integer`

定义域说明：

- `sqrt*` 需要非负有限输入。
- `ln*` 需要正有限输入。
- `asin` / `acos` 需要输入落在 `[-1, 1]`。
- `atanh` 需要输入落在 `(-1, 1)`。
- `acosh` 需要输入 `>= 1`。
- `pow_for_precision` 在非整数指数且底数非正时会直接拒绝。
- `tan_for_precision` 在计算得到的余弦为零时会拒绝。

## Trait 面

`BinFloat` 当前实现了：

- `@def.Floating`
- `@arithmetic.Constants`
- `@arithmetic.Sqrt`
- `@arithmetic.Cbrt`
- `@arithmetic.Radical`
- `@arithmetic.Exponential`
- `@arithmetic.Logarithmic`
- `@arithmetic.Power`
- `@arithmetic.Trigonometric`
- `@arithmetic.InverseTrigonometric`
- `@arithmetic.Hyperbolic`
- `@arithmetic.InverseHyperbolic`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.Num`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `@luna-generic.Field`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
