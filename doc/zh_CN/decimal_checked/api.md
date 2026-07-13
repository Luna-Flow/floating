# `decimal_checked` API

`DecimalResult` 包装 `Result[Decimal, ArithmeticError]`，用于闭合的 checked 十进制组合。

## 构造与观察

`ok`、`err`、`from_result`、`result` 连接原始结果边界；`from_int`、`from_bigint`、`from_float`、`from_double` 和 `parse` 构造值。`parse` 用 `Err` 表示非法输入。

## 组合与算术

`map`、`bind`、`flat_map` 会保留已有错误。`abs`、`neg`、四则运算、`sqrt`、幂、`normalized`、`with_precision`、`min`、`max` 和 `clamp` 均返回 `Self`，并实现标准运算符。

带 context 和 flags 的 Decimal 运算仍属于 `@decimal.Decimal`；本包装只建模 `ArithmeticError`。

完整数值方法名为 `abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、
`pow_nat`、`pow_int`、`normalized`、`with_precision`、`min`、`max`、`clamp`。

## 完整公开接口

以下快照是 `0.6.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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
