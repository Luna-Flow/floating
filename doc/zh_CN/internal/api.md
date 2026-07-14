# @internal

本文档描述 `0.6.1` 基线中的 `@internal` 包。它是实现辅助层，不是稳定公开 API。

## BigInt 辅助

- `bigint_zero`
- `bigint_one`
- `abs_bigint`
- `sign_of_bigint`

## 幂与位数辅助

- `pow2`
- `pow5`
- `pow10`
- `digits10`

## 规范化辅助

- `remove_factor2`
- `remove_factor10`
- `exact_divide_by_power_of_ten`：仅在能被指定的 `10` 的幂整除时返回精确商。
- `trim_trailing_decimal_zeros`：在可选上限内移除末尾十进制零，并返回新系数、指数和移除数量。

## 舍入辅助

- `round_positive_div`
- `round_shift`
- `compare_abs`

## 十进制解析辅助

- `split_decimal_string`

它把十进制字符串拆成：

- 是否为负
- 去掉分隔后的 digit 串
- 十进制指数修正量

## 完整公开接口

以下快照是 `0.6.1` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/bigint",
}

// Values
pub fn abs_bigint(@bigint.BigInt) -> @bigint.BigInt

pub fn bigint_one() -> @bigint.BigInt

pub fn bigint_zero() -> @bigint.BigInt

pub fn compare_abs(@bigint.BigInt, @bigint.BigInt) -> Int

pub fn digits10(@bigint.BigInt) -> Int

pub fn exact_divide_by_power_of_ten(@bigint.BigInt, Int) -> @bigint.BigInt?

pub fn pow10(Int) -> @bigint.BigInt

pub fn pow2(Int) -> @bigint.BigInt

pub fn pow5(Int) -> @bigint.BigInt

pub fn remove_factor10(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn remove_factor2(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn[A, B, E, C] result_lift2(Result[A, E], Result[B, E], (A, B) -> C) -> Result[C, E]

pub fn[A, B, E, C] result_lift2_checked(Result[A, E], Result[B, E], (A, B) -> Result[C, E]) -> Result[C, E]

pub fn round_positive_div(@bigint.BigInt, @bigint.BigInt, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn round_shift(@bigint.BigInt, Int, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn sign_of_bigint(@bigint.BigInt) -> @def.Sign

pub fn split_decimal_string(String) -> (Bool, String, Int)?

pub fn trim_trailing_decimal_zeros(@bigint.BigInt, Int, max_drop? : Int) -> (@bigint.BigInt, Int, Int)

// Errors

// Types and methods
pub struct ExactRat {
  // private fields
} derive(Eq)
pub fn ExactRat::denominator(Self) -> @bigint.BigInt
pub fn ExactRat::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRat::numerator(Self) -> @bigint.BigInt

// Type aliases

// Traits
```
<!-- generated-api-end -->
