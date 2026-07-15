# `ball_float` 设计

`ball_float` 是 0.7.0 的认证实数包络域，基于 `BinFloat` endpoint 构建 bare/decorated
interval，并对齐声明范围内的 IEEE 1788-2015。正确性首先由集合包含定义：更宽可能
不够有用，但漏掉精确结果一定错误。

## 设计契约

流水线为：输入 interval → Empty/Entire/domain 分类 → monotone endpoint、critical-point
或全 endpoint-product 规则 → lower 向负无穷、upper 向正无穷计算 → `BallContext` →
可选 decoration。`bin_float` 拥有 dyadic rounding/certificate；`ball_float` 拥有集合像
所需的 endpoint 组合与 domain fallback。

## 表示与不变量

非空 bare interval 保存 `lo_ <= hi_` 的两个非 NaN endpoint 与 precision；Empty、
Entire 显式表示。`new(center,radius)` 只是构造视图，storage 仍为 bounds。Precision
变化时 lower 向下、upper 向上，因此只会扩宽。`exact(x)` 只保证嵌入给定 dyadic
`BinFloat`，不会把先前十进制到二进制的近似重新变成原十进制实数。

`BallFloatDecorated` 加入 decoration 与独立 NaI。Empty 是合法空集，NaI 表示无效的
decorated operation，二者不能合并。

## IEEE 1788 对齐

Bare operation 计算集合包络；decorated operation 按 operand/continuity/domain 降级；
NaI 独立；subset/interior/overlap/precedes 是集合关系；reverse operation 不在 0.7.0
边界。固定 strict ITF1788 的 4,656/4,656 条 selected case 全部通过，含 general power、
trigonometric、hyperbolic、inverse 与 375 条 `atan2`。`rootn` 和 extension 单独报告。

## 基本算术选择

| 操作 | 包络规则 | 关键边界 |
| --- | --- | --- |
| add | `[a.lo+b.lo,a.hi+b.hi]` directed | Empty 传播 |
| sub | `[a.lo-b.hi,a.hi-b.lo]` | subtrahend endpoint 反向 |
| mul | 四个 endpoint product 的 min/max | sign shortcut 不得漏 candidate |
| reciprocal/div | 分母排除零时倒置 endpoint | 内部跨零得 Entire；单侧零可得 half-infinite |
| square/root | monotone piece + zero/domain | 全负 sqrt domain 得 Empty |
| intersection/hull | endpoint max/min | disjoint intersection 得 Empty |

`BallContext` 再施加 precision/exponent，并返回 inexact/overflow/underflow flags。
Entire 是成功 enclosure，不是通用错误。

## 认证初等函数

初等函数使用 `BinCoeff` 上的 directed dyadic certificate，每一步外向舍入，并以解析
remainder bound 包住截断尾项。实现包含 exp range reduction/series、ln power-of-two
reduction、certified log、Machin pi bounds、quadrant reduction、alternating series、
critical-point/pole detection、inverse/hyperbolic monotonic endpoint 与 guarded power。

共享预算最多 12 次 refinement，按 `max(32, work/2)` 增长。`try_*` 暴露 range、
resource、rounding failure；total API 在契约允许时使用安全 fallback：sin/cos 为
`[-1,1]`，tan pole 或 uncertified reduction 为 Entire。

## Critical Point、Pole 与切换边界

周期函数在认证 index space 中计算 quadrant/critical range；包含 extremum 就加入 ±1，
包含 tan pole 就返回 Entire，而不是以近似 remainder 与 epsilon 比较。无界输入或 adjusted
binary exponent 超过 `max(65,536, 4 × precision)` 时，total path 直接安全放宽，
`try_*` 返回 resource detail；这是 proof-resource boundary，不是函数定义域声明。

## Decoration 与关系

Decoration 取 operand/operation 允许的最弱 grade。`contains` 检查点包含，
`subset/interior/set_equal` 比较集合，`overlap_state` 描述几何，`definitely_lt/gt`
只在所有点均满足时证明顺序，`maybe_eq` 表示相容性。区间没有 scalar total order；
`Sign::Zero` 也可能表示跨零而非 singleton zero。

## 优化与取舍

基本操作做常数次 endpoint arithmetic，成本约 `O(M(p))`；初等函数再增加 range
reduction、bounded series 与最多 12 次 refinement。实现优先复用 constant、exact
special case、monotonicity 与共享 trig reduction，但绝不删除 endpoint candidate 或用
nearest 替代 outward rounding。资源与 tightness 冲突时，total API 放宽，checked API
说明原因。

## 证据映射

- [API](./api.md) 列出 bare/decorated/context/`try_*`。
- [Tutorial](./tutorial.md) 演示安全构造、关系、初等函数与失败策略。
- [Conformance](./conformance.md) 定义 ITF1788 声明。
- [`bin_float` Design](../bin_float/design.md) 与 [Performance](../bin_float/performance.md)
  拥有 endpoint kernel 与 crossover 证据。
