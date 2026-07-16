# `decimal_gda_checked` API

`GdaDecimalChecked` is a closed GDA decimal pipeline over
`GdaOutcome[Decimal]`. It automatically passes the returned sticky context to
the next operation and retains a complete trapped outcome.

## Construction And Observation

`parse`, `from_decimal`, and `from_outcome` create a pipeline. `value`,
`context`, `raised`, `status`, and `outcome` expose the GDA state.
`is_trapped` and `trapped_signal` observe control state without discarding the
defined result.

## Trap Control

Operations continue only from `Completed`. A `Trapped` pipeline returns itself
unchanged until `resume_defined` explicitly converts the defined result and
next context back into a completed state.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`.

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
