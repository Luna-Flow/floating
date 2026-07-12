# `ball_float` API

## 稳定性

bare/decorated 区间构造、关系、正向算术、context 和 flags 是 `0.5.0` 支持的
API。reverse operations 与必然 tight 不属于当前契约。

本文档描述 `0.5.0` 基线中的 `@ball_float.BallFloat`、
`@ball_float.Decoration` 与 `@ball_float.BallFloatDecorated`。

## 语义

`BallFloat` 表示以下包络：

`center +/- radius`

当前实现会把它存成 `BinFloat` 下界与上界。基础算术按 IEEE 1788 tightest enclosure 端点公式计算，并向外舍入。

## 构造

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_bounds`
- `BallFloat::from_coefficient`
- `BallFloat::from_int`
- `BallFloat::from_float`
- `BallFloat::from_double`
- `BallFloat::whole`
- `BallFloat::empty`

`from_coefficient` 接受非负的 `@bin_float.BinCoeff` 和独立的 `negative?` 符号。
二进制栈不再接受 `BigInt` 构造边界；Decimal 的 `BigInt` API 不受影响。

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
- `radius_extended`
- `midpoint`
- `midpoint_ctx`
- `width`
- `magnitude`
- `mignitude`
- `precision`
- `classify`
- `sign`
- `is_bounded`
- `is_entire`
- `is_empty`
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
- `set_equal`
- `subset`
- `interior`
- `less`
- `strictly_less`
- `precedes`
- `strictly_precedes`
- `disjoint`
- `is_common_interval`
- `is_singleton`
- `intersection`
- `convex_hull`
- `overlap_state`

说明：

- 这些关系都是 enclosure-oriented 的，不伪装成标量总序。
- IEEE set-based 关系的端点公式见 [`ieee1788_research.md`](./ieee1788_research.md)。

## 算术与 checked capability 行为

- `add`
- `sub`
- `mul`
- `div`
- `abs`
- `neg`
- `add_ctx`
- `sub_ctx`
- `mul_ctx`
- `div_ctx`
- `apply_ctx`
- `cancel_plus`
- `cancel_minus`
- `reciprocal`
- `square`
- `sqrt_interval`
- `exp_interval`
- `exp2_interval`
- `exp10_interval`
- `ln_interval`
- `log2_interval`
- `log10_interval`
- `pow_interval`
- `sin_interval`
- `cos_interval`
- `tan_interval`
- `exp_ctx`
- `ln_ctx`
- `fma`
- `pown`
- `minimum`
- `maximum`

支持的运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

checked 行为说明：

- 仅含 `0` 的分母产生 Empty；单侧含零分母产生半无限紧包络；严格跨零分母按集合商的凸包处理。
- checked integer power 会保持 enclosure 正确性，并在零交叉逆幂上采用相同的 whole-real fallback。
- `BallFloat` 不实现标量 `CompareChecked`。
- 指数/对数族使用纯 MoonBit 的有向 dyadic 区间内核：`exp` 采用缩放平方和 Taylor 尾界；`ln` 采用 `atanh` 变换级数和尾界；每步外向舍入，换底函数保留整数幂与 `log2(2^n)`/`log10(10^n)` 的精确代数关系。
- 通用 `pow_interval` 遵循 IEEE 1788 非负底定义域；负底整数幂属于 `pown`，不会在通用 `pow` 中偷换为另一套标量语义。
- `sin_interval`、`cos_interval` 和 `tan_interval` 使用认证 `π`、可证明的 `π/2` 象限约化、交错级数尾界和周期关键点检测；无法证明象限或超过约化 cutoff 时返回保守包络。
- 该包暂不公开双曲/反三角函数、微积分、矩阵、复 ball 或特殊函数。

## Decorated interval

`BallFloatDecorated` 与 `BallFloat` 属于同一个 `ball_float` 包。使用方只需导入
`Luna-Flow/floating/ball_float`；本模块不再提供独立的
`Luna-Flow/floating/decorated_ball_float` 包。这样 bare interval、decorated
interval、上下文和 IEEE 1788 集合语义共享同一包边界。

`Decoration` 的等级从低到高为 `Ill`、`Trv`、`Def`、`Dac`、`Com`。
`BallFloatDecorated` 保存 underlying `BallFloat`、decoration 与独立 NaI 状态：

- `BallFloatDecorated::new` 从 bare interval 构造 decorated interval。
- `BallFloatDecorated::nai` 构造 NaI；NaI 使用 `Ill`，但不等同于 Empty。
- `interval`、`decoration` 与 `is_nai` 分别观察底层集合、等级与 NaI 状态。
- Empty 自动规范化为 `Trv`；非 common interval 不能保持 `Com`，会降为 `Dac`。
- 每次运算取输入等级与本次操作等级的最低值，因此 decoration 只能保持或降低。
- 部分定义域、除零可能性、三角函数极点等情况把操作等级降为 `Trv`。
- 任一数值运算输入为 NaI 时传播 NaI；NaI 上的布尔关系返回 `false`，
  `overlap_state` 返回 `Undefined`。

`BallFloatDecorated` 公开对应的集合运算、关系、基础算术、cancellation、
指数/对数、幂、三角函数、FMA、整数幂、极值与 `apply_ctx`，并支持
`+`、`-`、`*`、`/` 和 `Show`。

## 上下文与状态

- `BallContext::new`
- `BallContext::try_new`
- `BallContext::binary32`
- `BallContext::binary64`
- `BallFlags::new`
- `exp_ctx`
- `ln_ctx`

`BallContext` 显式携带 precision、`e_min` 和 `e_max`。外部参数应通过 total 的 `try_new` 验证；`new` 保留带前置条件的便捷语义。上下文算术返回 `(BallFloat, BallFlags)`；flags 通过 `inexact`、`overflow`、`underflow` 和 `combine` 稳定访问。

## Trait 面

`BallFloat` 当前实现了：

- `@def.Floating`
- `@lf_arith.Contains`
- `@lf_arith.Overlaps`
- `@lf_arith.DefinitelyLt`
- `@lf_arith.DefinitelyLe`
- `@lf_arith.MaybeEq`
- `@lf_arith.DivChecked`
- `@lf_arith.PowNatChecked`
- `@lf_arith.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
