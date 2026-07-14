# @def

このページは `0.6.1` 基準の `@def` package を説明します。

## 内容

- `Sign`
- `FpClass`
- `RoundingMode`
- `Floating`
- `is_finite` / `is_nan` / `is_infinite` / `is_zero`

## `Floating` trait

```moonbit
trait Floating {
  fn classify(Self) -> FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```

現在この trait は次だけを共有能力として扱います。

- 分類
- 符号
- 精度
- 精度変更
- 正規化
## `Sign`、`FpClass`、`RoundingMode`

共有 enum は観測と rounding の語彙であり、具体表現を意味しません。

## `Floating` 必須 method

trait は classification、sign、precision、retuning、normalization だけを要求し、算術は別 capability です。

## 実装と helper predicate

`BinFloat`、`Decimal`、`BallFloat` が実装し、helper は `classify` の pure projection です。

## 完全な公開インターフェース

次の snapshot は `0.6.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/def"

import {
  "Luna-Flow/arithmetic",
  "moonbitlang/core/bigint",
}

// Values
pub fn[F : Floating] is_finite(F) -> Bool

pub fn[F : Floating] is_infinite(F) -> Bool

pub fn[F : Floating] is_nan(F) -> Bool

pub fn[F : Floating] is_zero(F) -> Bool

// Errors

// Types and methods
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
} derive(Eq)

pub(all) enum Sign {
  Negative
  Zero
  Positive
} derive(Eq)

// Type aliases
pub using @arithmetic {type ArithmeticContext}

pub using @arithmetic {type ArithmeticError}

pub using @arithmetic {type ArithmeticErrorKind}

pub using @bigint {type BigInt}

pub using @arithmetic {type FpClass}

pub using @arithmetic {type RoundingMode}

// Traits
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```
<!-- generated-api-end -->
