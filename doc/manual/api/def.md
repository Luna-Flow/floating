# def API

## Purpose

`def` is the shared vocabulary of the `floating` packages. It defines the sign
classification `Sign`, the ten-valued IEEE class `IeeeClass`, the four-way
comparison result `PartialOrder`, the `Floating` trait implemented by the
scalar representations, four generic predicates built on that trait, and
re-exports the context, rounding, classification and error types of
[Luna-Flow/arithmetic](https://lunaflow.cn/en/arithmetic/) so that callers need
only one import. It contains no arithmetic. The
[tutorial](../tutorial/def.md) shows the vocabulary in use; the
[design page](../design/def.md) states the trait laws and explains why
`PartialOrder` is not a total order.

## Importing

Add the package to your `moon.pkg`, next to the representation you use:

```moonbit nocheck
import {
  "Luna-Flow/floating/def",
  "Luna-Flow/floating/binary",
}
```

The examples on this page are complete tests. They call the package as
`@def.`, the representations as `@binary.`, `@decimal.`, `@decimal_gda.`
and `@interval.`, and `Luna-Flow/arithmetic` as `@lf_arith.`.

## Sign and comparison results

### `Sign`

`Sign` classifies the sign returned by [`Floating::signum`](#floatingsignum).

```mbti
#derive(Eq)
pub(all) enum Sign {
  Negative
  Zero
  Positive
}
```

| Input | Result |
| --- | --- |
| negative value, including $-\infty$ | `Negative` |
| either signed zero | `Zero` |
| positive value, including $+\infty$ | `Positive` |
| NaN | `Zero` |

`Sign` does not distinguish $-0$ from $+0$; use the concrete package (for
example `Binary::is_negative_zero`) when the sign bit of a zero matters.
`Sign` is also the payload of `SemanticScalar::Infinity` in the
[`semantic`](semantic.md) package.

```moonbit
///|
test "Sign values" {
  let s = @def.Floating::signum(@binary.Binary::from_int(-3))
  inspect(s == @def.Sign::Negative, content="true")
  let z = @def.Floating::signum(@binary.Binary::from_double(-0.0))
  inspect(z == @def.Sign::Zero, content="true")
}
```

### `IeeeClass`

`IeeeClass` is the ten-valued `class` of IEEE 754-2019 clause 5.7.2. Unlike
`FpClass`, it separates the two NaNs, the sign of every class and the normal,
subnormal and zero cases.

```mbti
#derive(Eq)
pub(all) enum IeeeClass {
  SignalingNaN
  QuietNaN
  NegativeInfinity
  NegativeNormal
  NegativeSubnormal
  NegativeZero
  PositiveZero
  PositiveSubnormal
  PositiveNormal
  PositiveInfinity
}
```

`Binary::class_of` and `Decimal::class_of` return it. Normal and subnormal
depend on the format's $e_{\min}$, so these methods take the context that fixes
the bound.

```moonbit
///|
test "IeeeClass of a binary32 value" {
  let ctx = @binary.BinaryInterchangeFormat::Binary32.context()
  let tiny = @binary.Binary::make(@binary.BinCoeff::one(), -127, 24)
  inspect(tiny.class_of(ctx) == @def.IeeeClass::PositiveSubnormal, content="true")
  inspect(tiny.neg().class_of(ctx) == @def.IeeeClass::NegativeSubnormal, content="true")
}
```

### `PartialOrder`

`PartialOrder` records the result of an IEEE 754 comparison. Exactly one of the
four mutually exclusive relations *less*, *equal*, *greater* and *unordered*
holds between two floating-point data.

```mbti
#derive(Eq)
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
}
```

| Operands | Result |
| --- | --- |
| at least one NaN | `Unordered` |
| equal numeric values, including $-0$ and $+0$ | `Equal` |
| one numeric value is less than the other | `Less` or `Greater` |

`Binary::compare_quiet` and `Binary::compare_signaling` in
[`binary`](binary.md) return this type with the comparison flags. `def` does
not perform comparisons itself. The [design page](../design/def.md#partialorder-is-the-ieee-four-way-relation)
explains why the type has four results instead of a `Compare` instance.

```moonbit
///|
test "PartialOrder from an IEEE comparison" {
  let one = @binary.Binary::from_int(1)
  let nan = @binary.Binary::nan()
  let (relation, flags) = one.compare_quiet(nan)
  inspect(relation == @def.PartialOrder::Unordered, content="true")
  inspect(flags.invalid_operation(), content="false")
  let (signaling, signaling_flags) = one.compare_signaling(nan)
  inspect(signaling == @def.PartialOrder::Unordered, content="true")
  inspect(signaling_flags.invalid_operation(), content="true")
  let zeros = @binary.Binary::from_double(-0.0).compare_quiet(
    @binary.Binary::zero(),
  )
  inspect(zeros.0 == @def.PartialOrder::Equal, content="true")
}
```

## The `Floating` trait

### `Floating`

`Floating` is the observation and re-precision interface shared by the scalar
representations in this repository.

```mbti
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn signum(Self) -> Sign
  fn precision(Self) -> Int32
  fn with_precision(Self, Int32) -> Self
  fn normalized(Self) -> Self
}
```

`Floating` is implemented only by `@binary.Binary`, `@decimal.Decimal` and
`@decimal_gda.Decimal`. `@interval.Interval` does not implement it (see
[Intervals are not `Floating`](../design/def.md#intervals-are-not-floating)).
Implementing it for a type outside this module is not supported or covered by
the compatibility promise because methods may be added to the trait in a minor
release. It is declared `pub(open)` because implementations are in other
packages of this module; the [design page](../design/def.md#why-floating-is-declared-open)
gives the reason. Since the MoonBit 0.10 migration, trait methods are not
promoted automatically, so
generic code calls them in the qualified form `@def.Floating::classify(x)`;
the concrete types also provide inherent methods with the same names
(`x.classify()`). The [design page](../design/def.md#the-floating-laws) lists
the laws every implementation is expected to satisfy.

### `Floating::classify`

`classify` returns the class of a value: `Finite`, `Infinity` or `NaN`.

```mbti
fn classify(Self) -> @arithmetic.FpClass
```

For the scalar types this is the IEEE class with signaling and quiet NaNs
merged. The operation is total and never aborts.

### `Floating::signum`

`signum` returns the sign classification of a value.

```mbti
fn signum(Self) -> Sign
```

| Implementation | `Negative` | `Zero` | `Positive` |
| --- | --- | --- | --- |
| `Binary`, both `Decimal`s | value $< 0$, including $-\infty$ | $\pm 0$ and every NaN | value $> 0$, including $+\infty$ |

### `Floating::precision`

`precision` returns the working precision stored on the value.

```mbti
fn precision(Self) -> Int32
```

It counts significant bits for `Binary` and significant decimal digits for both `Decimal` types. Every
constructor requires a precision of at least $1$ and aborts otherwise, so the result is
always at least $1$.

### `Floating::with_precision`

`with_precision(x, p)` returns `x` re-expressed at precision $q = p$.
`Binary` and `@decimal.Decimal` abort when $p < 1$ or $p$ exceeds
`binary_precision_max` or `decimal_precision_max`, and `@decimal_gda.Decimal`
uses $q = \max(1, p)$.

```mbti
fn with_precision(Self, Int32) -> Self
```

For a finite scalar, the value is rounded to $q$ significant digits of its
radix, to nearest with ties to even (IEEE 754-2019 4.3.1). The trait method has
no rounding parameter, because it cannot return an error; the inherent
`with_precision` of each scalar type takes a rounding mode. No context exponent bounds apply and no flags
are reported (use the `*_ctx` APIs of the concrete package for both). Each
type keeps the range of its stored values. For `Binary` a result whose exponent leaves
$[1 - e_{\max}, e_{\max}]$ with $e_{\max} = 2^{30} - 1$
(`binary_value_e_max`, `binary_value_e_min`) overflows to an infinity or to the largest
finite value, or underflows, as in IEEE 754. The decimal types behave alike at
their stored ranges: the exponent of the least digit is at least
`decimal_value_e_tiny` or `gda_value_e_tiny` ($-2147483645$) and the adjusted
exponent is at most `decimal_value_e_max` or `gda_value_e_max` ($2147483646$).
Zeros keep their sign.
Infinities and NaNs keep their class, sign and payload and only change the
stored precision.

### `Floating::normalized`

`normalized` returns the canonical representative of a value.

```mbti
fn normalized(Self) -> Self
```

For `Binary` this is the representation with an odd coefficient (or zero);
for both `Decimal` types it removes trailing zeros of the coefficient, so
`1.500` becomes `1.5` (the cohort changes, the value does not) and `-0.000`
becomes `-0`. Non-finite scalars are returned unchanged. On the scalar types
`normalized` keeps the value and is idempotent.

```moonbit
///|
fn[F : @def.Floating] describe(x : F) -> String {
  let class = match @def.Floating::classify(x) {
    Finite => "finite"
    Infinity => "infinite"
    NaN => "nan"
  }
  let sign = match @def.Floating::signum(x) {
    Negative => "-"
    Zero => "0"
    Positive => "+"
  }
  "\{class} \{sign} precision=\{@def.Floating::precision(x)}"
}

///|
test "Floating observations" {
  inspect(
    describe(@binary.Binary::from_double(-0.0)),
    content="finite 0 precision=53",
  )
  inspect(
    describe(@decimal.Decimal::from_string("-1.50").unwrap()),
    content="finite - precision=34",
  )
  inspect(
    describe(@decimal_gda.Decimal::from_string("-Inf").unwrap()),
    content="infinite - precision=34",
  )
}

///|
test "Floating re-precision and normalization" {
  let d = @decimal.Decimal::from_string("2.71828").unwrap()
  let cut = @def.Floating::with_precision(d, 3)
  inspect(cut.to_string(), content="2.72")
  let ten = @def.Floating::with_precision(
    @binary.Binary::from_int(10),
    2,
  )
  inspect(ten.to_string(), content="1p3")
  inspect(ten.precision(), content="2")
  let cohort = @decimal.Decimal::from_string("1.500").unwrap()
  inspect(@def.Floating::normalized(cohort).to_string(), content="1.5")
}

```

## Generic predicates

### `is_finite`, `is_infinite`, `is_nan`, `is_zero`

These functions test the class of any `Floating` value.

```mbti
pub fn[F : Floating] is_finite(F) -> Bool
pub fn[F : Floating] is_infinite(F) -> Bool
pub fn[F : Floating] is_nan(F) -> Bool
pub fn[F : Floating] is_zero(F) -> Bool
```

$$
\begin{aligned}
\texttt{is\_finite}(x) &\iff \texttt{classify}(x) = \texttt{Finite},\\
\texttt{is\_infinite}(x) &\iff \texttt{classify}(x) = \texttt{Infinity},\\
\texttt{is\_nan}(x) &\iff \texttt{classify}(x) = \texttt{NaN},\\
\texttt{is\_zero}(x) &\iff \texttt{classify}(x) = \texttt{Finite} \wedge \texttt{signum}(x) = \texttt{Zero}.
\end{aligned}
$$

Exactly one of the first three is true for every value. `is_zero` is true for
both signed zeros and false for NaN.

```moonbit
///|
test "generic predicates" {
  inspect(@def.is_zero(@binary.Binary::from_double(-0.0)), content="true")
  inspect(
    @def.is_finite(@decimal.Decimal::from_string("NaN").unwrap()),
    content="false",
  )
}
```

## Re-exported types

`def` re-exports these types with `pub using`, so `@def.RoundingMode` and
`@lf_arith.RoundingMode` name the same type and no conversion is needed. Their
definitions and full semantics are documented by
[Luna-Flow/arithmetic](https://lunaflow.cn/en/arithmetic/).

### `ArithmeticContext`

`ArithmeticContext` is the precision, rounding direction and optional exponent
bounds passed to the contextual traits of Luna-Flow/arithmetic.

```mbti
pub using @arithmetic {type ArithmeticContext}
```

`BinaryContext` and `DecimalContext` are built from it by their
`from_arithmetic_context` constructors.

### `ArithmeticError`, `ArithmeticErrorKind`

`ArithmeticError` is the structured error of every `Result`-returning
(`*_checked`, `try_*`) API and of the checked wrapper packages;
`ArithmeticErrorKind` is its kind.

```mbti
pub using @arithmetic {type ArithmeticError}
pub using @arithmetic {type ArithmeticErrorKind}
```

The kinds are `DivisionByZero`, `ParseError`, `DomainError`, `FormatError`,
`UnsupportedOperation`, `UnorderedComparison` and
`CertificationFailure(detail)`; `ArithmeticError` has one `is_*` predicate per
kind and a `message`.

### `CertificationFailureDetail`, `CertificationFailureReason`, `CertificationStage`

These types are the payload of an `ArithmeticError` of kind
`CertificationFailure`: an elementary function whose correctly rounded result
could not be certified within its refinement budget.

```mbti
pub using @arithmetic {type CertificationFailureDetail}
pub using @arithmetic {type CertificationFailureReason}
pub using @arithmetic {type CertificationStage}
```

The detail records the operation, the stage and reason, the target precision,
and the final working precision and refinement count (see
`certified_failure` in the [internal API](internal.md)).

### `FpClass`

`FpClass` is the result of `Floating::classify`: `Finite`, `Infinity` or
`NaN`.

```mbti
pub using @arithmetic {type FpClass}
```

### `RoundingMode`

`RoundingMode` lists the five rounding directions that an `ArithmeticContext`
carries: `ToNearestEven`,
`TowardZero`, `TowardPositive`, `TowardNegative` and `AwayFromZero`. The inherent
`with_precision` methods and the concrete constructors take the rounding type of
their own package (`BinaryRoundingMode`, `DecimalRoundingMode`, `GdaRoundingMode`)
and the trait method `Floating::with_precision` takes none; `AwayFromZero` has no
`BinaryRoundingMode` or `DecimalRoundingMode` counterpart.

```mbti
pub using @arithmetic {type RoundingMode}
```

### `BigInt`

`BigInt` is the arbitrary-precision integer of `moonbitlang/core/bigint`, used
for coefficients and exact values.

```mbti
pub using @bigint {type BigInt}
```

```moonbit
///|
test "aliases name the arithmetic types" {
  let ctx : @def.ArithmeticContext = @lf_arith.ArithmeticContext::new(10)
  inspect(ctx.precision, content="10")
  let mode : @def.RoundingMode = ToNearestEven
  inspect(mode == @lf_arith.RoundingMode::ToNearestEven, content="true")
}
```

## Trait implementations

### `Sign::equal`, `Sign::not_equal`, `PartialOrder::equal`, `PartialOrder::not_equal`

These methods are the derived `Eq` instance, promoted explicitly so that
`a.equal(b)` remains available; prefer `==` and `!=`.

```mbti
pub fn Sign::equal(Self, Self) -> Bool
pub fn Sign::not_equal(Self, Self) -> Bool
pub fn PartialOrder::equal(Self, Self) -> Bool
pub fn PartialOrder::not_equal(Self, Self) -> Bool
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
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
#derive(Eq)
pub(all) enum IeeeClass {
  SignalingNaN
  QuietNaN
  NegativeInfinity
  NegativeNormal
  NegativeSubnormal
  NegativeZero
  PositiveZero
  PositiveSubnormal
  PositiveNormal
  PositiveInfinity
}

#derive(Eq)
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
}
pub fn PartialOrder::equal(Self, Self) -> Bool
pub fn PartialOrder::not_equal(Self, Self) -> Bool

#derive(Eq)
pub(all) enum Sign {
  Negative
  Zero
  Positive
}
pub fn Sign::equal(Self, Self) -> Bool
pub fn Sign::not_equal(Self, Self) -> Bool

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
  fn signum(Self) -> Sign
  fn precision(Self) -> Int32
  fn with_precision(Self, Int32) -> Self
  fn normalized(Self) -> Self
}
```
<!-- generated-api-end -->
