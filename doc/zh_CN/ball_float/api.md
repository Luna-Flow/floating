# @ball_float.BallFloat

本文档描述当前 `0.1.0` 基线中的 `@ball_float.BallFloat`。

## 语义

`BallFloat` 表示：

`center +/- radius`

也就是闭球/闭区间式包络。

## 构造

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_decimal`

约束：

- `center` 必须有限
- `radius` 必须有限
- `radius` 不能是 `NaN`
- `radius` 必须非负

说明：

- `new` 在中心值降精度时，会把中心位移带来的误差并入半径，避免包络缩小。
- 半径自身在量化时总是向外舍入。
- `from_decimal` 生成的是基于 `BinFloat` 的包络，不是“把十进制对象原封不动包起来”。

## 访问与共享 floating 能力

- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `normalized`
- `with_precision`

补充：

- 半径为零时，`sign()` 等于中心值的符号。
- 如果包络同时覆盖负值和正值，当前实现返回 `Sign::Zero`。
- `with_precision` 会在中心重调精度发生位移时自动放大半径，以保持原包络仍被包含。

## 关系判断

- `contains`
- `overlaps`
- `separated_from`
- `definitely_lt`
- `definitely_gt`
- `maybe_overlap`

## 算术

- `add`
- `sub`
- `mul`
- `div`

支持：

- `+`
- `-`
- `*`
- `/`

注意：

- 除法时，如果分母球包含 0，会直接拒绝
- 算术结果不仅会按包络公式传播误差，也会把输出中心量化造成的位移并回半径
