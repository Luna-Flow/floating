# @ball_float.BallFloat

本文档描述当前 `0.2.0` 基线中的 `@ball_float.BallFloat`。

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

约束：

- 中心值必须有限。
- 半径必须有限且非负。
- `exact`、`from_float`、`from_double` 遇到非有限源值会直接拒绝。

说明：

- 中心值重调精度时，中心位移会被并入半径，保证包络不会缩小。
- 半径量化始终向外舍入。

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
- `separated_from`
- `definitely_lt`
- `definitely_le`
- `definitely_gt`
- `maybe_eq`

说明：

- 这些关系都是 enclosure-oriented 的，不伪装成标量总序。

## 算术与 checked capability 行为

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

checked 行为说明：

- checked division 在分母包络包含 `0` 时可能扩张到 whole-real enclosure。
- checked integer power 会保持 enclosure 正确性，并在零交叉逆幂上采用相同的 whole-real fallback。
- `BallFloat` 不实现标量 `CompareChecked`。
- 这一轮不会公开非整数幂、超越函数、微积分、矩阵、复 ball 或特殊函数。

## Trait 面

`BallFloat` 当前实现了：

- `@def.Floating`
- `@arithmetic.Contains`
- `@arithmetic.Overlaps`
- `@arithmetic.DefinitelyLt`
- `@arithmetic.DefinitelyLe`
- `@arithmetic.MaybeEq`
- `@arithmetic.DivChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
