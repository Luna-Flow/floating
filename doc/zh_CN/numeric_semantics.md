# 数值语义

本文定义 `0.6.0` 文档共享的术语，区分数学值、存储表示、舍入状态、checked 失败
与区间包络。

## 值与表示

有限二进制值是带符号的非负系数乘以二的幂。有限十进制值是带符号的非负系数
乘以十的幂。不同表示可以对应同一个数学值。

对 Decimal 而言，`12.3400`、`12.340` 与 `12.34` 数值相同但属于不同 cohort；
其存储指数就是 quantum。解析保留 quantum，`normalized()` 或 `reduce_ctx()` 可
移除系数尾零并调整指数，而不改变数学值。

Precision 是表示元数据与舍入上限，不证明每个存储数字都具有相同的有效意义。
`with_precision` 可能舍入，但不会改变 radix，也不会在 binary/decimal 间转换。

## 舍入与 Context

共享二进制式舍入词汇包括 nearest-even、toward-zero、toward-positive、
toward-negative 与 away-from-zero。Decimal 还包含 half-up、half-down、
zero-five-up 等 GDA 模式。

`BinaryContext`、`DecimalContext` 与 `BallContext` 显式描述 bounded-format 策略。
根据数值域不同，context 携带 precision、指数边界、clamp、rounding 与 tininess
detection。`binary64`、`decimal64` 及对应 ball preset 提供标准边界。

以下任一项目可观察时都应使用 context API：

- 精确舍入方向；
- overflow、underflow、subnormal、inexact 或 rounded 状态；
- before/after-rounding tininess；
- decimal clamp 或指数 cohort 规则；
- 固定 interchange format。

## Flags、Status、Traps 与错误

operation flag 表示在产生一个已定义结果时触发的条件，不会自动变成异常。需要
累计 IEEE 状态时，应显式组合每步 flags。

GDA 区分三组相关数据：

- `raised`：当前运算产生的条件；
- `status`：所有已传递运算条件的 sticky 并集；
- `traps`：把 `Completed` 改为 `Trapped` 的启用条件。

触发 trap 的 `GdaOutcome` 仍包含 GDA 定义结果、next context 与 raised flags。
一次运算同时触发多个已启用 signal 时，按照固定优先级选择 trap。

`ArithmeticError` 语义不同：它表示 checked capability 无法产生所请求的标量结果。
checked wrapper 对它短路，但不表示 IEEE flags 或 GDA traps。

## 标量特殊值

二进制与十进制标量按各自能力公开 signed zero、正负 infinity、quiet NaN 与
signaling NaN。NaN payload 和 signaling 状态属于表示数据；算术可能 quiet 一个
signaling NaN 并触发 invalid condition。

数值相等与表示相等并不等价：

- signed zero 数值相等但符号不同；
- Decimal cohort 成员数值相等，但 `same_quantum` 可能为 false；
- NaN 在普通比较中 unordered；
- total comparison 为排序或协议用途显式排列表示，包括 NaN 与 cohort。

应使用 classification 与显式 total-order API，而不是从格式化文本猜测行为。

## 区间语义

`BallFloat` 表示由二进制端点限定的实数集合。算术结果必须包含从各输入集合任取
一个值所得的全部数学结果，外向舍入保护这个 inclusion invariant。

关键状态包括：

- **Empty**：不包含实数；
- **Entire**：包含所有实数；
- **非空有界或无界区间**：包含端点之间的值；
- **NaI**：decorated invalid interval，区别于 Empty。

包含、subset、overlap、disjointness 与 definite comparison 取代标量全序。除以
含零区间可以合法地产生 Entire。保守包络即使不 tight，也仍是成功值。

Decoration 记录结果满足连续性/定义域条件的强度，不是标量 flags，也不由
`BallFloatResult` 保存。

## 转换与投影

binary-to-decimal 与 decimal-to-binary 可能需要舍入，因为一个 radix 中的有限值
在另一个 radix 中未必有限。转换结果属于合同时，应显式选择 precision 与 rounding。

Interchange 转换比任意精度转换更窄：binary16/32/64/128 与 decimal32/64/128
强制固定字段宽度、指数范围、特殊编码和状态行为。

`semantic` 对所保留的数学值做精确投影，但有意丢失表示元数据。它适合跨包比较
与诊断，不可用来往返 quantum、payload、signed zero、decoration 或 flags。

## 决策清单

选择 API 前应回答：

1. 需要的是标量值、表示，还是实数集合？
2. radix、precision、指数边界或 quantum 是否必须可观察？
3. 调用方需要逐 operation flags、sticky GDA status，还是 checked 短路错误？
4. 是否可能出现 NaN、infinity、signed zero、Empty、Entire 或 NaI？
5. 普通偏序是否足够，还是需要 total order/集合关系？
6. 转换是任意精度还是固定 interchange？
7. 哪个有限 conformance matrix 支撑该行为声明？

