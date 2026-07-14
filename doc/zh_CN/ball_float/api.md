# `ball_float` API

## 稳定性

bare/decorated 区间构造、关系、正向算术、context 和 flags 是 `0.6.1` 支持的
API。reverse operations 与必然 tight 不属于当前契约。

本文档描述 `0.6.1` 基线中的 `@ball_float.BallFloat`、
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
- IEEE set-based 关系的端点公式与验证边界见[一致性说明](./conformance.md)。

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

## 完整公开接口

以下快照是 `0.6.1` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub struct BallContext {
  // private fields
}
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::e_max(Self) -> Int
pub fn BallContext::e_min(Self) -> Int
pub fn BallContext::new(precision? : Int, e_min? : Int, e_max? : Int) -> Self
pub fn BallContext::precision(Self) -> Int
pub fn BallContext::try_new(precision? : Int, e_min? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]

pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::new() -> Self
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool

pub struct BallFloat {
  // private fields
} derive(Eq)
pub fn BallFloat::abs(Self) -> Self
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::add_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::cancel_minus(Self, Self) -> Self
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::center(Self) -> @bin_float.BinFloat
pub fn BallFloat::classify(Self) -> @arithmetic.FpClass
pub fn BallFloat::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloat::contains_zero(Self) -> Bool
pub fn BallFloat::convex_hull(Self, Self) -> Self
pub fn BallFloat::cos_interval(Self) -> Self
pub fn BallFloat::definitely_gt(Self, Self) -> Bool
pub fn BallFloat::definitely_le(Self, Self) -> Bool
pub fn BallFloat::definitely_lt(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
pub fn BallFloat::div(Self, Self) -> Self
pub fn BallFloat::div_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::empty(precision? : Int) -> Self
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::exp10_interval(Self) -> Self
pub fn BallFloat::exp2_interval(Self) -> Self
pub fn BallFloat::exp_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::exp_interval(Self) -> Self
pub fn BallFloat::fma(Self, Self, Self) -> Self
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloat::from_double(Double, precision? : Int) -> Self
pub fn BallFloat::from_float(Float, precision? : Int) -> Self
pub fn BallFloat::from_int(Int, precision? : Int) -> Self
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::is_bounded(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::ln_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::ln_interval(Self) -> Self
pub fn BallFloat::log10_interval(Self) -> Self
pub fn BallFloat::log2_interval(Self) -> Self
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::maximum(Self, Self) -> Self
pub fn BallFloat::maybe_eq(Self, Self) -> Bool
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::minimum(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::mul_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::normalized(Self) -> Self
pub fn BallFloat::overlap_state(Self, Self) -> OverlapState
pub fn BallFloat::overlaps(Self, Self) -> Bool
pub fn BallFloat::pow_interval(Self, Self) -> Self
pub fn BallFloat::pown(Self, Int) -> Self
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::precision(Self) -> Int
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius_extended(Self) -> @bin_float.BinFloat
pub fn BallFloat::reciprocal(Self) -> Self
pub fn BallFloat::separated_from(Self, Self) -> Bool
pub fn BallFloat::set_equal(Self, Self) -> Bool
pub fn BallFloat::sign(Self) -> @def.Sign
pub fn BallFloat::sin_interval(Self) -> Self
pub fn BallFloat::sqrt_interval(Self) -> Self
pub fn BallFloat::square(Self) -> Self
pub fn BallFloat::strictly_less(Self, Self) -> Bool
pub fn BallFloat::strictly_precedes(Self, Self) -> Bool
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::sub_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::tan_interval(Self) -> Self
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_double(Double, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_float(Float, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::whole(precision? : Int) -> Self
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl @def.Floating for BallFloat
pub impl Add for BallFloat
pub impl Div for BallFloat
pub impl Mul for BallFloat
pub impl Neg for BallFloat
pub impl Show for BallFloat
pub impl Sub for BallFloat

pub struct BallFloatDecorated {
  // private fields
} derive(Eq)
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cos_interval(Self) -> Self
pub fn BallFloatDecorated::decoration(Self) -> Decoration
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::exp10_interval(Self) -> Self
pub fn BallFloatDecorated::exp2_interval(Self) -> Self
pub fn BallFloatDecorated::exp_interval(Self) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_nai(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::ln_interval(Self) -> Self
pub fn BallFloatDecorated::log10_interval(Self) -> Self
pub fn BallFloatDecorated::log2_interval(Self) -> Self
pub fn BallFloatDecorated::maximum(Self, Self) -> Self
pub fn BallFloatDecorated::minimum(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::nai(precision? : Int) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
pub fn BallFloatDecorated::overlap_state(Self, Self) -> OverlapState
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::pow_interval(Self, Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::reciprocal(Self) -> Self
pub fn BallFloatDecorated::set_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::sin_interval(Self) -> Self
pub fn BallFloatDecorated::sqrt_interval(Self) -> Self
pub fn BallFloatDecorated::square(Self) -> Self
pub fn BallFloatDecorated::strictly_less(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::tan_interval(Self) -> Self
pub impl Add for BallFloatDecorated
pub impl Div for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Show for BallFloatDecorated
pub impl Sub for BallFloatDecorated

pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, @debug.Debug)
pub impl Show for Decoration

pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, @debug.Debug)

// Type aliases

// Traits
```
<!-- generated-api-end -->
