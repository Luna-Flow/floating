# @def

本文档描述 `0.7.0` 基线中的 `@def` 包。

## 组成

- `Sign`：统一的符号分类，包含 `Negative`、`Zero`、`Positive`
- `FpClass`：统一的浮点分类，包含 `Finite`、`Infinity`、`NaN`
- `RoundingMode`：统一的舍入模式枚举
- `Floating`：仓库级共享 trait
- `is_finite` / `is_nan` / `is_infinite` / `is_zero`：基于 trait 的辅助谓词

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

它当前只约束：

- 分类
- 符号
- 精度
- 精度重整
- 规范化

当前实现者：

- `@bin_float.BinFloat`
- `@decimal.Decimal`
- `@ball_float.BallFloat`
## `Sign`、`FpClass` 与 `RoundingMode`

这些枚举是跨包共享的观察与舍入词汇；它们不暗示具体数值表示。

## `Floating` 必需方法

trait 只要求分类、符号、精度、精度调整和规范化；算术能力由更窄 trait 提供。

## 当前实现与辅助谓词

`BinFloat`、`Decimal` 和 `BallFloat` 实现该 trait，辅助函数是对 `classify` 的纯投影。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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

pub using @arithmetic {type CertificationFailureDetail}

pub using @arithmetic {type CertificationFailureReason}

pub using @arithmetic {type CertificationStage}

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
