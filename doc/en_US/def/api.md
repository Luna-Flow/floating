# @def

This page tracks the `0.7.1` API.

---

## `pub(all) enum Sign`

```moonbit
enum Sign {
  Negative
  Zero
  Positive
}
```

- **Description**
  Represents the sign classification shared by all floating packages.

- **Semantic Notes**
  - `Zero` means "numerically zero or sign-indeterminate zero-like result" in the current package set.
  - `ball_float` may return `Zero` when the enclosure straddles both negative and positive values.

---

## `pub(all) enum FpClass`

```moonbit
enum FpClass {
  Finite
  Infinity
  NaN
}
```

- **Description**
  Shared floating-point class used by `bin_float`, `decimal`, and `ball_float`.

---

## `pub(all) enum RoundingMode`

```moonbit
enum RoundingMode {
  ToNearestEven
  TowardZero
  TowardPositive
  TowardNegative
  AwayFromZero
}
```

- **Description**
  Requests a rounding direction when precision reduction or approximate conversion is required.

- **Semantic Notes**
  - `ToNearestEven` is the repository default for precision-controlled constructors and conversions unless a method documents otherwise.
  - `ball_float` uses outward-oriented rounding choices internally when widening an enclosure.

---

## `pub(open) trait Floating`

```moonbit
trait Floating {
  fn classify(Self) -> FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```

- **Description**
  The shared capability boundary for Luna Flow floating-like values.

**Required Methods**

- **`fn classify(Self) -> FpClass`**
  Returns the current classification: finite, infinity, or NaN.

- **`fn sign(Self) -> Sign`**
  Returns the sign classification for the current value.

- **`fn precision(Self) -> Int`**
  Returns the current working precision stored on the value.

- **`fn with_precision(Self, Int, RoundingMode) -> Self`**
  Retunes the value to a requested precision using the given rounding mode.

- **`fn normalized(Self) -> Self`**
  Returns the canonical normalized form for the value.

**Current Implementations**

- `@bin_float.BinFloat`
- `@decimal.Decimal`
- `@ball_float.BallFloat`

---

## Helper Predicates

- **`fn[F : Floating] is_finite(x : F) -> Bool`**
  Returns `true` when `classify(x) == FpClass::Finite`.

- **`fn[F : Floating] is_nan(x : F) -> Bool`**
  Returns `true` when `classify(x) == FpClass::NaN`.

- **`fn[F : Floating] is_infinite(x : F) -> Bool`**
  Returns `true` when `classify(x) == FpClass::Infinity`.

- **`fn[F : Floating] is_zero(x : F) -> Bool`**
  Returns `true` when `x` is finite and `sign(x) == Sign::Zero`.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`. Public declarations are authoritative; prose above groups them by behavior.

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
