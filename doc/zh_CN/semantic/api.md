# `semantic` API

该包把具体数值表示投影到与表示无关的语义模型。

## 精确值与标量

- `ExactRational::new` 构造规范化有理数；`from_scaled_integer` 构造精确的带基数缩放整数。
- `SemanticScalar` 包含 `Rational`、`Infinity(Sign)` 和 `NaN`。
- `from_bin_float` 与 `from_decimal` 投影具体标量。

## 区间与错误

- `SemanticInterval` 保存公开的 `lower`、`upper`，`from_ball_float` 投影区间。
- `SemanticError` 区分除零、解析、定义域、格式、未支持操作和无序比较。
- `SemanticError::from_arithmetic` 把 `ArithmeticError` 映射到该语义错误词汇。
- `SemanticResult[T]` 为 `Value(T)` 或 `Error(SemanticError)`。
- `semantic_scalar_result`、`semantic_interval_result` 用调用方提供的投影函数转换 checked 结果。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/semantic"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/def",
  "moonbitlang/core/bigint",
}

// Values
pub fn[T] semantic_interval_result(Result[T, @arithmetic.ArithmeticError], (T) -> SemanticInterval) -> SemanticResult[SemanticInterval]

pub fn[T] semantic_scalar_result(Result[T, @arithmetic.ArithmeticError], (T) -> SemanticScalar) -> SemanticResult[SemanticScalar]

// Errors

// Types and methods
pub struct ExactRational {
  // private fields
} derive(Eq)
pub fn ExactRational::denominator(Self) -> @bigint.BigInt
pub fn ExactRational::from_scaled_integer(@bigint.BigInt, Int, Int) -> Self
pub fn ExactRational::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRational::numerator(Self) -> @bigint.BigInt

pub(all) enum SemanticError {
  DivisionByZero
  ParseError
  DomainError
  FormatError
  UnsupportedOperation
  UnorderedComparison
  CertificationFailure
} derive(Eq)
pub fn SemanticError::from_arithmetic(@arithmetic.ArithmeticError) -> Self

pub struct SemanticInterval {
  lower : SemanticScalar
  upper : SemanticScalar
} derive(Eq)
pub fn SemanticInterval::from_ball_float(@ball_float.BallFloat) -> Self

pub(all) enum SemanticResult[T] {
  Value(T)
  Error(SemanticError)
} derive(Eq)

pub(all) enum SemanticScalar {
  Rational(ExactRational)
  Infinity(@def.Sign)
  NaN
} derive(Eq)
pub fn SemanticScalar::from_bin_float(@bin_float.BinFloat) -> Self
pub fn SemanticScalar::from_decimal(@decimal.Decimal) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
