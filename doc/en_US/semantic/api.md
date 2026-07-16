# `semantic` API

The package projects concrete numeric representations into a small,
representation-independent semantic model.

## Exact And Scalar Values

- `ExactRational::new(numerator, denominator)` constructs a normalized rational.
- `ExactRational::from_scaled_integer(coefficient, exponent, radix)` constructs
  an exact scaled integer value.
- `SemanticScalar` is `Rational(ExactRational)`, `Infinity(Sign)`, or `NaN`.
- `SemanticScalar::from_bin_float` and `from_decimal` project concrete scalars.

## Intervals And Errors

- `SemanticInterval` stores public `lower` and `upper` semantic scalars;
  `from_ball_float` projects a `BallFloat`.
- `SemanticError` distinguishes division, parsing, domain, formatting,
  unsupported-operation, and unordered-comparison failures.
- `SemanticError::from_arithmetic` maps `ArithmeticError` into this vocabulary.
- `SemanticResult[T]` is either `Value(T)` or `Error(SemanticError)`.
- `semantic_scalar_result` and `semantic_interval_result` map checked concrete
  results through caller-supplied projection functions.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`. Public declarations are authoritative; prose above groups them by behavior.

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
