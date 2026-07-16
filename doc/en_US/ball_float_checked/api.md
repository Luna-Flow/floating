# `ball_float_checked` API

`BallFloatResult` wraps `Result[BallFloat, ArithmeticError]` while preserving
interval semantics.

## Construction And Observation

`ok`, `err`, `from_result`, and `result` bridge raw results. `exact`,
`from_bounds`, `whole`, `from_int`, `from_coefficient`, `from_float`, and
`from_double` construct wrapped intervals. Invalid bounds become `Err`.

`from_coefficient` takes `@bin_float.BinCoeff` plus the independent
`negative?` sign flag; binary checked APIs do not accept `BigInt`.

## Composition And Arithmetic

`map`, `bind`, and `flat_map` short-circuit existing errors. `abs`, `neg`,
`add`, `sub`, `mul`, `div`, `pow_nat`, `pow_int`, `normalized`, and
`with_precision` return `BallFloatResult`; standard arithmetic operators are
implemented.

Division by an interval containing zero follows `BallFloat` semantics and
returns the whole-real enclosure. It is not converted into `Err`.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BallFloatResult {
  // private fields
}
pub fn BallFloatResult::abs(Self) -> Self
pub fn BallFloatResult::acos(Self) -> Self
pub fn BallFloatResult::acosh(Self) -> Self
pub fn BallFloatResult::add(Self, Self) -> Self
pub fn BallFloatResult::asin(Self) -> Self
pub fn BallFloatResult::asinh(Self) -> Self
pub fn BallFloatResult::atan(Self) -> Self
pub fn BallFloatResult::atan2(Self, Self) -> Self
pub fn BallFloatResult::atanh(Self) -> Self
pub fn BallFloatResult::bind(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::cos(Self) -> Self
pub fn BallFloatResult::cosh(Self) -> Self
pub fn BallFloatResult::cospi(Self) -> Self
pub fn BallFloatResult::div(Self, Self) -> Self
pub fn BallFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BallFloatResult::error(Self) -> @arithmetic.ArithmeticError?
pub fn BallFloatResult::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::exp(Self) -> Self
pub fn BallFloatResult::exp10(Self) -> Self
pub fn BallFloatResult::exp2(Self) -> Self
pub fn BallFloatResult::expm1(Self) -> Self
#deprecated
pub fn BallFloatResult::flat_map(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BallFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BallFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BallFloatResult::from_result(Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BallFloatResult::hypot(Self, Self) -> Self
pub fn BallFloatResult::is_err(Self) -> Bool
pub fn BallFloatResult::is_ok(Self) -> Bool
pub fn BallFloatResult::ln(Self) -> Self
pub fn BallFloatResult::log10(Self) -> Self
pub fn BallFloatResult::log1p(Self) -> Self
pub fn BallFloatResult::log2(Self) -> Self
pub fn BallFloatResult::map(Self, (@ball_float.BallFloat) -> @ball_float.BallFloat) -> Self
pub fn BallFloatResult::mul(Self, Self) -> Self
pub fn BallFloatResult::neg(Self) -> Self
pub fn BallFloatResult::normalized(Self) -> Self
pub fn BallFloatResult::ok(@ball_float.BallFloat) -> Self
pub fn BallFloatResult::pow(Self, Self) -> Self
pub fn BallFloatResult::pow_int(Self, Int) -> Self
pub fn BallFloatResult::pow_nat(Self, UInt) -> Self
pub fn BallFloatResult::result(Self) -> Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]
pub fn BallFloatResult::rootn(Self, Int) -> Self
pub fn BallFloatResult::sin(Self) -> Self
pub fn BallFloatResult::sinh(Self) -> Self
pub fn BallFloatResult::sinpi(Self) -> Self
pub fn BallFloatResult::sub(Self, Self) -> Self
pub fn BallFloatResult::tan(Self) -> Self
pub fn BallFloatResult::tanh(Self) -> Self
pub fn BallFloatResult::tanpi(Self) -> Self
pub fn BallFloatResult::whole(precision? : Int) -> Self
pub fn BallFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BallFloatResult
pub impl Div for BallFloatResult
pub impl Mul for BallFloatResult
pub impl Neg for BallFloatResult
pub impl Sub for BallFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
