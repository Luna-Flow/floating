# `decimal_gda_checked` API

`GdaDecimalChecked` 是基于 `GdaOutcome[Decimal]` 的封闭 GDA 十进制流水线。
它自动把返回的 sticky context 传入下一步，并完整保留 trapped outcome。

## 构造与观察

`parse`、`from_decimal` 与 `from_outcome` 创建流水线。`value`、`context`、
`raised`、`status` 与 `outcome` 观察 GDA 状态；`is_trapped` 与
`trapped_signal` 观察控制状态，但不会丢弃定义结果。

## Trap 控制

只有 `Completed` 会继续运算。`Trapped` 流水线保持不变，直到
`resume_defined` 显式把定义结果与 next context 恢复为 completed 状态。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda_checked"

import {
  "Luna-Flow/floating/decimal_gda",
}

// Values

// Errors

// Types and methods
pub struct GdaDecimalChecked {
  // private fields
}
pub fn GdaDecimalChecked::abs(Self) -> Self
pub fn GdaDecimalChecked::add(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::apply(Self) -> Self
pub fn GdaDecimalChecked::context(Self) -> @decimal_gda.GdaContext
pub fn GdaDecimalChecked::divide(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::exp(Self) -> Self
pub fn GdaDecimalChecked::fma(Self, @decimal_gda.Decimal, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::from_decimal(@decimal_gda.Decimal, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::from_outcome(@decimal_gda.GdaOutcome[@decimal_gda.Decimal]) -> Self
pub fn GdaDecimalChecked::is_trapped(Self) -> Bool
pub fn GdaDecimalChecked::ln(Self) -> Self
pub fn GdaDecimalChecked::log10(Self) -> Self
pub fn GdaDecimalChecked::minus(Self) -> Self
pub fn GdaDecimalChecked::multiply(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::next_minus(Self) -> Self
pub fn GdaDecimalChecked::next_plus(Self) -> Self
pub fn GdaDecimalChecked::next_toward(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::outcome(Self) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
pub fn GdaDecimalChecked::parse(String, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::plus(Self) -> Self
pub fn GdaDecimalChecked::power(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::quantize(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::raised(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::reduce(Self) -> Self
pub fn GdaDecimalChecked::remainder(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::resume_defined(Self) -> Self
pub fn GdaDecimalChecked::sqrt(Self) -> Self
pub fn GdaDecimalChecked::status(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::subtract(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::trapped_signal(Self) -> @decimal_gda.GdaSignal?
pub fn GdaDecimalChecked::value(Self) -> @decimal_gda.Decimal

// Type aliases

// Traits
```
<!-- generated-api-end -->
