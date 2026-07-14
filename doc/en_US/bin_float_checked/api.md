# `bin_float_checked` API

`BinFloatResult` wraps `Result[BinFloat, ArithmeticError]` and keeps checked
binary arithmetic closed over one type.

## Construction And Observation

- `ok`, `err`, and `from_result` wrap existing outcomes.
- `from_int`, `from_coefficient`, `from_float`, and `from_double` create successful values.
- `result` exposes the wrapped `Result` at an application boundary.

## Composition

- `map` applies a non-failing `BinFloat -> BinFloat` transform to `Ok` values.
- `bind` and `flat_map` apply a `BinFloat -> BinFloatResult` transform.
- Existing errors short-circuit all composition methods.

## Numeric Operations

`abs`, `neg`, `add`, `sub`, `mul`, `div`, `sqrt`, `pow_nat`, `pow_int`,
`normalized`, `with_precision`, `ulp`, `min`, `max`, and labeled-argument
`clamp` all return `BinFloatResult`. Operators `+`, `-`, `*`, `/`, and unary
`-` delegate to the corresponding methods.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.1`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BinFloatResult {
  // private fields
}
pub fn BinFloatResult::abs(Self) -> Self
pub fn BinFloatResult::add(Self, Self) -> Self
pub fn BinFloatResult::bind(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloatResult::div(Self, Self) -> Self
pub fn BinFloatResult::err(@arithmetic.ArithmeticError) -> Self
#deprecated
pub fn BinFloatResult::flat_map(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BinFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BinFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BinFloatResult::from_result(Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BinFloatResult::map(Self, (@bin_float.BinFloat) -> @bin_float.BinFloat) -> Self
pub fn BinFloatResult::max(Self, Self) -> Self
pub fn BinFloatResult::min(Self, Self) -> Self
pub fn BinFloatResult::mul(Self, Self) -> Self
pub fn BinFloatResult::neg(Self) -> Self
pub fn BinFloatResult::normalized(Self) -> Self
pub fn BinFloatResult::ok(@bin_float.BinFloat) -> Self
pub fn BinFloatResult::pow_int(Self, Int) -> Self
pub fn BinFloatResult::pow_nat(Self, UInt) -> Self
pub fn BinFloatResult::result(Self) -> Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]
pub fn BinFloatResult::sqrt(Self) -> Self
pub fn BinFloatResult::sub(Self, Self) -> Self
pub fn BinFloatResult::ulp(Self) -> Self
pub fn BinFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BinFloatResult
pub impl Div for BinFloatResult
pub impl Mul for BinFloatResult
pub impl Neg for BinFloatResult
pub impl Sub for BinFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
