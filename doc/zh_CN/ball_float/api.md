# @ball_float.BallFloat

本文档描述当前 `0.1.0` 基线中的 `@ball_float.BallFloat`。

## 语义

`BallFloat` 表示以下包络：

`center +/- radius`

当前实现会把它存成 `BinFloat` 下界与上界，并优先保证“绝不漏包络”，而不是追求尽可能窄的结果。

## 构造

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_int`
- `BallFloat::from_bigint`
- `BallFloat::from_float`
- `BallFloat::from_double`
- `BallFloat::from_decimal`

约束：

- 中心值必须有限。
- 半径必须有限且非负。
- `exact`、`from_float`、`from_double`、`from_decimal` 遇到非有限源值会直接拒绝。

说明：

- 中心值重调精度时，中心位移会被并入半径，保证包络不会缩小。
- 半径量化始终向外舍入。
- `from_decimal` 生成的是基于 `BinFloat` 的包络，不是“原样包住十进制对象”的薄封装。

## 访问器与区间形态

- `lower_bound`
- `upper_bound`
- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `is_bounded`
- `is_entire`
- `contains_zero`
- `normalized`
- `with_precision`

说明：

- `center()` 与 `radius()` 对无界区间会直接拒绝。
- 如果包络同时覆盖负值和正值，`sign()` 返回 `Sign::Zero`。
- `classify()` 对无界区间返回 `Infinity`。

## 关系与比较

- `contains`
- `overlaps`
- `maybe_overlap`
- `separated_from`
- `definitely_lt`
- `definitely_gt`
- `compare`
- `min`
- `max`
- `clamp`

说明：

- `compare` 对重叠或不可比较的区间会直接拒绝。
- `clamp` 在 `min` 与 `max` 自身无序时会直接拒绝。

## 算术与超越函数行为

- `add`
- `sub`
- `mul`
- `div`
- `pow`

支持的运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

定义域说明：

- 除法在分母包络包含 `0` 时会直接拒绝。
- `pow` 在指数包络不是精确点值时会直接拒绝。
- `pow` 在非整数指数且底数区间不严格为正时会直接拒绝。
- `sqrt`、`ln`、`log2`、`log10`、`asin`、`acos`、`acosh`、`atanh` 在越出定义域时会直接拒绝。
- `atan2` 在输入矩形跨过负实轴分支切换，或者直接覆盖原点时，会退化为完整主值角包络 `[-pi, pi]`；这是为了保证 enclosure 正确，而不是精度退化 bug。

## Trait 面

`BallFloat` 当前实现了：

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
