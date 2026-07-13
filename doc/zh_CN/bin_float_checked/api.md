# `bin_float_checked` API

`BinFloatResult` 包装 `Result[BinFloat, ArithmeticError]`，让 checked 二进制算术始终返回同一类型。

## 构造与观察

- `ok`、`err`、`from_result` 包装现有结果；`result` 在应用边界取回原始 `Result`。
- `from_int`、`from_coefficient`、`from_float`、`from_double` 构造成功值。
  `from_coefficient` 接受 `@bin_float.BinCoeff` 与独立的 `negative?` 符号。

## 组合

`map` 接受不会失败的值变换；`bind` 与 `flat_map` 接受返回 `BinFloatResult` 的变换。已有错误会短路，不调用回调。

## 数值运算

`abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、`pow_nat`、`pow_int`、`normalized`、`with_precision`、`ulp`、`min`、`max` 和 `clamp` 均返回 `Self`，并实现标准算术运算符。

## 完整公开接口

以下快照是 `0.6.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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
