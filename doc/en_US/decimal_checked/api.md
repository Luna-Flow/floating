# `decimal_checked` API

`DecimalChecked` is a closed IEEE decimal pipeline. It keeps one immutable
`DecimalContext`, the current defined `Decimal`, flags raised by the latest
operation, and flags accumulated across all operations.

## Construction And Observation

`parse` and the `from_*` constructors apply the supplied context after forcing
its IEEE profile. `value`, `context`, `raised`, and `flags` expose each state
component; `outcome` returns the value with accumulated flags. `clear_flags`
starts a new observation window without changing the value or context.

## Contextual Operations

Every arithmetic method delegates to the matching `decimal` contextual
operation and combines its flags. Binary methods take a plain `Decimal`, so two
independently accumulated contexts are never merged implicitly. IEEE NaN and
infinity results remain values rather than becoming `ArithmeticError`.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.1`.

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
