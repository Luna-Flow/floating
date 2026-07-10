# `decimal` 设计说明

`Decimal` 是当前仓库里的十进制优先表示。本页对齐当前 `0.4.0` 实现基线与第一
阶段 GDA 表示迁移。

## 当前设计重点

- 以 GDA / IEEE 754 decimal 语义为基准，而不是只追求“测试看起来能过”。
- 区分“标量 decimal 值语义”和“interchange/raw bits 语义”。
- 默认保留与 `Luna-Flow` 现有生态的兼容入口，但在 context、flags、special values、
  canonicalization 等边界上逐步收敛到更明确的 GDA 行为。

## 核心不变式

- 有限值保存为 `(-1)^negative * magnitude * 10^exponent10`
- 存储层的 `magnitude` 是非负 coefficient，负号独立存放，这样才能表达 `-0`
  与带符号 NaN payload
- 数值构造路径会剥离所有可移除的 `10` 因子
- 零值在 canonical 形式下使用 exponent `0`，但保留符号
- 某些 GDA 风格操作会有意保留 exponent/quantum；需要 canonical cohort 时请显
  式调用 `normalized()`

## 解析路径

`Decimal::from_string` 会先调用 `@internal.split_decimal_string`：

- 处理符号
- 去掉小数点
- 合并科学计数法指数

当解析出的 coefficient 能装进请求精度时，解析路径会保留原始 exponent/quantum，
而不是总是先去掉尾随零。`"-0"` 也会保留为负零。

## 与 `bin_float` 的关系

- `bin_float -> decimal`：精确保留当前有限二进制表示
- `decimal -> bin_float`：对非 dyadic 值可能产生近似

## special values 与 cohort

- `-0` 是一等公民表示，不会在内部被静默折叠成 `+0`。
- qNaN / sNaN 会保留 sign 与 payload；需要 quiet 化时，会尽量沿用源操作数的诊断信息。
- 标量 `Decimal` 关注数值语义与可观察 cohort；若调用方需要保留非 canonical interchange
  编码，应使用 `DecimalInterchange`，而不是期待标量值保留 raw-bit 差异。

## context 与最终结果

- 大多数运算要区分“中间数学结果”和“context 下的最终结果”。
- flags、preferred exponent、subnormal / underflow / overflow、clamped 等判断，
  都属于最终结果语义的一部分，不能只看数值是否接近。
- 当前实现已经显式引入更多 GDA 风格 context 语义；subset arithmetic /
  `extended: 0` 相关规则仍在持续收敛中。
