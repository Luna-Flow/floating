# `decimal_checked` API

`DecimalChecked` 是封闭的 IEEE 十进制流水线，保存一个不可变
`DecimalContext`、当前定义 `Decimal`、本步 flags 与全流程累计 flags。

## 构造与观察

`parse` 和 `from_*` 构造器会先强制 context 使用 IEEE profile。
`value`、`context`、`raised` 与 `flags` 分别观察状态；`outcome` 返回值与累计
flags。`clear_flags` 开始新的观察窗口，但不改变值或 context。

## Contextual 运算

每个算术方法委托给 `decimal` 对应 contextual 运算并组合 flags。二元方法接收普通
`Decimal`，不会隐式合并两个独立的 context 与 flag 历史。IEEE NaN 与 infinity
仍是定义结果，不会被改写成 `ArithmeticError`。

## 完整公开接口

以下快照是 `0.7.1` 的完整生成包接口。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/decimal",
  "moonbitlang/core/bigint",
}

// Values

// Errors

// Types and methods
pub struct DecimalChecked {
  // private fields
}
pub fn DecimalChecked::abs(Self) -> Self
pub fn DecimalChecked::acos(Self) -> Self
pub fn DecimalChecked::acosh(Self) -> Self
pub fn DecimalChecked::add(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::apply(Self) -> Self
pub fn DecimalChecked::asin(Self) -> Self
pub fn DecimalChecked::asinh(Self) -> Self
pub fn DecimalChecked::atan(Self) -> Self
pub fn DecimalChecked::atan2(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::atanh(Self) -> Self
pub fn DecimalChecked::clear_flags(Self) -> Self
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::cos(Self) -> Self
pub fn DecimalChecked::cosh(Self) -> Self
pub fn DecimalChecked::cospi(Self) -> Self
pub fn DecimalChecked::div(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::error(Self) -> @arithmetic.ArithmeticError?
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::exp10(Self) -> Self
pub fn DecimalChecked::exp2(Self) -> Self
pub fn DecimalChecked::expm1(Self) -> Self
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::fma(Self, @decimal.Decimal, @decimal.Decimal) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_decimal(@decimal.Decimal, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_int(Int, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_outcome(@decimal.Decimal, @decimal.DecimalContext, @decimal.DecimalFlags) -> Self
pub fn DecimalChecked::hypot(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::is_err(Self) -> Bool
pub fn DecimalChecked::is_ok(Self) -> Bool
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
pub fn DecimalChecked::log1p(Self) -> Self
pub fn DecimalChecked::log2(Self) -> Self
pub fn DecimalChecked::max(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::min(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::minus(Self) -> Self
pub fn DecimalChecked::mul(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::next_minus(Self) -> Self
pub fn DecimalChecked::next_plus(Self) -> Self
pub fn DecimalChecked::next_toward(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::outcome(Self) -> (@decimal.Decimal, @decimal.DecimalFlags)
pub fn DecimalChecked::parse(String, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::plus(Self) -> Self
pub fn DecimalChecked::power(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::pown(Self, Int) -> Self
pub fn DecimalChecked::quantize(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::reduce(Self) -> Self
pub fn DecimalChecked::remainder(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::result(Self) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @arithmetic.ArithmeticError]
pub fn DecimalChecked::rootn(Self, Int) -> Self
pub fn DecimalChecked::sin(Self) -> Self
pub fn DecimalChecked::sinh(Self) -> Self
pub fn DecimalChecked::sinpi(Self) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::sub(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::tan(Self) -> Self
pub fn DecimalChecked::tanh(Self) -> Self
pub fn DecimalChecked::tanpi(Self) -> Self
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
