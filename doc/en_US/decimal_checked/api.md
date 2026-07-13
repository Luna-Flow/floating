# `decimal_checked` API

`DecimalResult` wraps `Result[Decimal, ArithmeticError]` for closed checked
decimal composition.

## Construction And Observation

- `ok`, `err`, `from_result`, and `result` bridge the raw result boundary.
- `from_int`, `from_bigint`, `from_float`, `from_double`, and `parse` create values.
- `parse` records invalid input as `Err` instead of returning `Option`.

## Composition And Arithmetic

`map`, `bind`, and `flat_map` preserve an existing error without invoking the
callback. `abs`, `neg`, `add`, `sub`, `mul`, `div`, `sqrt`, `pow_nat`,
`pow_int`, `normalized`, `with_precision`, `min`, `max`, and `clamp` return
`DecimalResult`. Standard arithmetic operators delegate to these methods.

Context-and-flags Decimal operations remain on `@decimal.Decimal`; this wrapper
models `ArithmeticError`, not the full GDA status-flag state.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.0`. Public declarations are authoritative; prose above groups them by behavior.

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
pub struct DecimalResult {
  // private fields
}
pub fn DecimalResult::abs(Self) -> Self
pub fn DecimalResult::add(Self, Self) -> Self
pub fn DecimalResult::bind(Self, (@decimal.Decimal) -> Self) -> Self
pub fn DecimalResult::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn DecimalResult::div(Self, Self) -> Self
pub fn DecimalResult::err(@arithmetic.ArithmeticError) -> Self
#deprecated
pub fn DecimalResult::flat_map(Self, (@decimal.Decimal) -> Self) -> Self
pub fn DecimalResult::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn DecimalResult::from_double(Double, precision? : Int) -> Self
pub fn DecimalResult::from_float(Float, precision? : Int) -> Self
pub fn DecimalResult::from_int(Int, precision? : Int) -> Self
pub fn DecimalResult::from_result(Result[@decimal.Decimal, @arithmetic.ArithmeticError]) -> Self
pub fn DecimalResult::map(Self, (@decimal.Decimal) -> @decimal.Decimal) -> Self
pub fn DecimalResult::max(Self, Self) -> Self
pub fn DecimalResult::min(Self, Self) -> Self
pub fn DecimalResult::mul(Self, Self) -> Self
pub fn DecimalResult::neg(Self) -> Self
pub fn DecimalResult::normalized(Self) -> Self
pub fn DecimalResult::ok(@decimal.Decimal) -> Self
pub fn DecimalResult::parse(String, precision? : Int) -> Self
pub fn DecimalResult::pow_int(Self, Int) -> Self
pub fn DecimalResult::pow_nat(Self, UInt) -> Self
pub fn DecimalResult::result(Self) -> Result[@decimal.Decimal, @arithmetic.ArithmeticError]
pub fn DecimalResult::sqrt(Self) -> Self
pub fn DecimalResult::sub(Self, Self) -> Self
pub fn DecimalResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for DecimalResult
pub impl Div for DecimalResult
pub impl Mul for DecimalResult
pub impl Neg for DecimalResult
pub impl Sub for DecimalResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
