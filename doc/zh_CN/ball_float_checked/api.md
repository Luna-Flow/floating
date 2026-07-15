# `ball_float_checked` API

`BallFloatResult` 包装 `Result[BallFloat, ArithmeticError]`，同时保留区间语义。

## 构造与观察

`ok`、`err`、`from_result`、`result` 连接原始结果；`exact`、`from_bounds`、`whole` 及各类 `from_*` 构造包装区间。非法边界返回 `Err`。

## 组合与算术

`map`、`bind`、`flat_map` 会短路已有错误。绝对值、取负、四则运算、整数幂、规范化与精度调整均返回 `Self`，并实现标准运算符。

除数区间含零时会按 `BallFloat` 语义返回 whole-real enclosure，不会转成 `Err`。

完整数值接口包括 `from_int`、`from_coefficient`、`from_float`、`from_double`、
`abs`、`neg`、`add`、`sub`、`mul`、`div`、`pow_nat`、`pow_int`、
`normalized` 和 `with_precision`。

`from_coefficient` 接受 `@bin_float.BinCoeff` 与独立的 `negative?` 符号；二进制
checked API 不接受 `BigInt`。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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
