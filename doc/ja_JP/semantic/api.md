# `semantic` API

このパッケージは具体的な数値表現を、表現に依存しない小さな意味モデルへ投影します。

## 厳密値とスカラー

- `ExactRational::new` は正規化有理数、`from_scaled_integer` は厳密な基数付きスケール整数を作ります。
- `SemanticScalar` は `Rational`、`Infinity(Sign)`、`NaN` です。
- `from_bin_float` と `from_decimal` が具体的スカラーを投影します。

## 区間とエラー

- `SemanticInterval` は公開 `lower`、`upper` を持ち、`from_ball_float` が区間を投影します。
- `SemanticError` は除算、解析、定義域、形式、未対応操作、順序不能比較を区別します。
- `SemanticError::from_arithmetic` は `ArithmeticError` をこの意味エラー語彙へ写します。
- `SemanticResult[T]` は `Value(T)` または `Error(SemanticError)` です。
- `semantic_scalar_result` と `semantic_interval_result` は指定された投影関数で checked 結果を変換します。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

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
