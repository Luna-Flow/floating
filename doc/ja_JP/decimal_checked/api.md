# `decimal_checked` API

`DecimalChecked` は closed IEEE decimal pipeline です。一つの immutable
`DecimalContext`、current defined `Decimal`、latest flags、accumulated flags を
保持します。

## Construction And Observation

`parse` と `from_*` constructor は supplied context を IEEE profile に固定します。
`value`、`context`、`raised`、`flags` が state component を公開し、`outcome` は
value と accumulated flags を返します。`clear_flags` は value/context を変えずに
新しい observation window を開始します。

## Contextual Operations

各 arithmetic method は対応する `decimal` contextual operation に委譲し、flags を
combine します。Binary method は plain `Decimal` を取り、独立した context/history
を暗黙に merge しません。IEEE NaN/infinity は `ArithmeticError` ではなく defined
result のままです。

## Complete Public Interface

次の snapshot は `0.6.1` の完全な generated package interface です。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_checked"

import {
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
pub fn DecimalChecked::add(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::apply(Self) -> Self
pub fn DecimalChecked::clear_flags(Self) -> Self
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::div(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::fma(Self, @decimal.Decimal, @decimal.Decimal) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_decimal(@decimal.Decimal, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_int(Int, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_outcome(@decimal.Decimal, @decimal.DecimalContext, @decimal.DecimalFlags) -> Self
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
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
pub fn DecimalChecked::quantize(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::reduce(Self) -> Self
pub fn DecimalChecked::remainder(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::sub(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
