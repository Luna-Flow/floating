# def API

## Purpose

`def` is the shared vocabulary of the `floating` packages. It defines the sign
classification `Sign`, the four-way comparison result `PartialOrder`, the open
`Floating` trait that every scalar or interval representation of this
repository implements, four generic predicates built on that trait, and
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
  "Luna-Flow/floating/bin_float",
}
```

The examples on this page are complete tests. They call the package as
`@def.`, the representations as `@bin_float.`, `@decimal.`, `@decimal_gda.`
and `@ball_float.`, and `Luna-Flow/arithmetic` as `@lf_arith.`.

## Sign and comparison results

### `Sign`

`Sign` is the three-way sign classification returned by `Floating::sign`.

```mbti
pub(all) enum Sign {
  Negative
  Zero
  Positive
} derive(Eq)
```

`Zero` is returned for both signed zeros, so `Sign` does not distinguish $-0$
from $+0$; use the concrete package (for example `BinFloat::is_negative_zero`)
when the sign bit of a zero matters. The scalar implementations also return
`Zero` for every NaN, and an interval returns `Zero` when it contains $0$ (see
[`Floating::sign`](#floatingsign)). `Sign` is also the payload of
`SemanticScalar::Infinity` in the [`semantic`](semantic.md) package and the
argument of constructors such as `BinFloat::inf`.

```moonbit
///|
test "Sign values" {
  let s = @def.Floating::sign(@bin_float.BinFloat::from_int(-3))
  inspect(s == @def.Sign::Negative, content="true")
  let z = @def.Floating::sign(@bin_float.BinFloat::from_double(-0.0))
  inspect(z == @def.Sign::Zero, content="true")
}
```

### `PartialOrder`

`PartialOrder` is the result of an IEEE 754 comparison: exactly one of the four
mutually exclusive relations *less*, *equal*, *greater* and *unordered* holds
between two floating-point data.

```mbti
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
} derive(Eq)
```

`Unordered` holds exactly when at least one operand is NaN; $-0$ and $+0$
compare `Equal`. The type is returned by `BinFloat::compare_quiet` and
`BinFloat::compare_signaling` in [`bin_float`](bin_float.md) (each paired with
the flags of the comparison). It is a value type only; `def` performs no
comparison itself. Why four results and not a `Compare` instance is derived in
the [design page](../design/def.md#partialorder-is-the-ieee-four-way-relation).

```moonbit
///|
test "PartialOrder from an IEEE comparison" {
  let one = @bin_float.BinFloat::from_int(1)
  let nan = @bin_float.BinFloat::nan()
  let (relation, flags) = one.compare_quiet(nan)
  inspect(relation == @def.PartialOrder::Unordered, content="true")
  inspect(flags.invalid_operation(), content="false")
  let (signaling, signaling_flags) = one.compare_signaling(nan)
  inspect(signaling == @def.PartialOrder::Unordered, content="true")
  inspect(signaling_flags.invalid_operation(), content="true")
  let zeros = @bin_float.BinFloat::from_double(-0.0).compare_quiet(
    @bin_float.BinFloat::zero(),
  )
  inspect(zeros.0 == @def.PartialOrder::Equal, content="true")
}
```

## The `Floating` trait

### `Floating`

`Floating` is the observation and re-precision interface shared by every
representation in this repository.

```mbti
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```

The trait is `pub(open)`, so downstream types may implement it. In this
repository it is implemented by `@bin_float.BinFloat`, `@decimal.Decimal`,
`@decimal_gda.Decimal` and `@ball_float.BallFloat`. Since the MoonBit 0.10
migration trait methods are not promoted automatically, so generic code calls
them in the qualified form `@def.Floating::classify(x)`; the concrete types also
provide inherent methods with the same names (`x.classify()`). The laws every
implementation is expected to satisfy, and the places where `BallFloat` only
satisfies a weaker form, are listed in the
[design page](../design/def.md#the-floating-laws).

### `Floating::classify`

`classify` returns the class of a value: `Finite`, `Infinity` or `NaN`.

```mbti
fn classify(Self) -> @arithmetic.FpClass
```

For the scalar types this is the IEEE class with signalling and quiet NaNs
merged. For `BallFloat` it is `Finite` for a bounded non-empty interval,
`Infinity` for an interval with an infinite endpoint (including the entire
line), and `NaN` for the empty interval. Total; never aborts.

### `Floating::sign`

`sign` returns the sign classification of a value.

```mbti
fn sign(Self) -> Sign
```

| Implementation | `Negative` | `Zero` | `Positive` |
| --- | --- | --- | --- |
| `BinFloat`, both `Decimal`s | value $< 0$, including $-\infty$ | $\pm 0$ and every NaN | value $> 0$, including $+\infty$ |
| `BallFloat` $[\ell, u]$ | $u < 0$ | $\ell \le 0 \le u$ | $\ell > 0$ |

The interval rule also applies to unbounded intervals: $[-\infty, -1]$ is
`Negative`.

> [!WARNING]
> `BallFloat::sign` aborts on the empty interval, which has no sign. Test
> `@def.is_nan(x)` (true exactly for the empty interval) before calling `sign`
> on an interval.

### `Floating::precision`

`precision` returns the working precision stored on the value.

```mbti
fn precision(Self) -> Int
```

It counts significant bits for `BinFloat` and for the endpoints of a
`BallFloat`, and significant decimal digits for both `Decimal` types. Every
constructor clamps the stored precision to at least $1$, so the result is
always at least $1$.

### `Floating::with_precision`

`with_precision(x, p, mode)` returns `x` re-expressed at precision
$q = \max(1, p)$.

```mbti
fn with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

For a finite scalar the value is rounded to $q$ significant digits of its
radix in the direction `mode`. No context exponent bounds apply and no flags
are reported (use the `*_ctx` APIs of the concrete package for both). The
decimal types have no other exponent limit. `BinFloat` keeps its
implementation range: a result whose exponent leaves
$\pm(2^{30} - 1)$ (`binary_implementation_e_max`,
`binary_implementation_e_min`) overflows to an infinity or to the largest
finite value, or underflows, as in IEEE 754. Zeros keep their sign.
Infinities and NaNs keep their class, sign and payload and only change the
stored precision.

For `BallFloat` the result is an enclosure of the input: the centre is rounded
with `mode` and the rounding error is added to the radius, so every member of
`x` remains a member of the result whatever `mode` is. The result can be wider
than `x` even when `p` equals the current precision, because the exact centre
of $[\ell, u]$ may need one bit more than the endpoints.

### `Floating::normalized`

`normalized` returns the canonical representative of a value.

```mbti
fn normalized(Self) -> Self
```

For `BinFloat` this is the representation with an odd coefficient (or zero);
for both `Decimal` types it removes trailing zeros of the coefficient, so
`1.500` becomes `1.5` (the cohort changes, the value does not) and `-0.000`
becomes `-0`. Non-finite scalars are returned unchanged. On the scalar types
`normalized` keeps the value and is idempotent.

> [!WARNING]
> `BallFloat::normalized` rebuilds the interval from its centre and radius at
> the stored precision, like `with_precision`. It returns an enclosure of the
> input, which can be strictly wider: at 53 bits, $[1, 1 + 2^{-52}]$ becomes
> $[1 - 2^{-52}, 1 + 2^{-52}]$. Do not use it where the interval must stay
> unchanged. Tracked in [#69](https://github.com/Luna-Flow/floating/issues/69); a fix is proposed in [#91](https://github.com/Luna-Flow/floating/pull/91).

```moonbit
///|
fn[F : @def.Floating] describe(x : F) -> String {
  let class = match @def.Floating::classify(x) {
    Finite => "finite"
    Infinity => "infinite"
    NaN => "nan"
  }
  let sign = match @def.Floating::sign(x) {
    Negative => "-"
    Zero => "0"
    Positive => "+"
  }
  "\{class} \{sign} precision=\{@def.Floating::precision(x)}"
}

///|
test "Floating observations" {
  inspect(
    describe(@bin_float.BinFloat::from_double(-0.0)),
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
  let around_zero = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(describe(around_zero), content="finite 0 precision=53")
}

///|
test "Floating re-precision and normalization" {
  let d = @decimal.Decimal::from_string("2.71828").unwrap()
  let cut = @def.Floating::with_precision(d, 3, @lf_arith.RoundingMode::TowardZero)
  inspect(cut.to_string(), content="2.71")
  let ten = @def.Floating::with_precision(
    @bin_float.BinFloat::from_int(10),
    2,
    @lf_arith.RoundingMode::ToNearestEven,
  )
  inspect(ten.to_string(), content="1p3")
  inspect(ten.precision(), content="2")
  let cohort = @decimal.Decimal::from_string("1.500").unwrap()
  inspect(@def.Floating::normalized(cohort).to_string(), content="1.5")
}

///|
test "BallFloat normalization encloses but may widen" {
  let x = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_hex("0x10000000000001p-52", 53).unwrap(),
  )
  let n = @def.Floating::normalized(x)
  inspect(n.lower_bound().to_hex(), content="0xfffffffffffffp-52")
  inspect(n.upper_bound().to_hex(), content="0x10000000000001p-52")
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
\texttt{is\_zero}(x) &\iff \texttt{classify}(x) = \texttt{Finite} \wedge \texttt{sign}(x) = \texttt{Zero}.
\end{aligned}
$$

Exactly one of the first three is true for every value. For scalars `is_zero`
is true for both signed zeros. For a `BallFloat`, `is_zero` is true for every
bounded interval that *contains* zero (for example $[-1, 1]$), not only for
$[0, 0]$; use `BallFloat::contains_zero` or compare the bounds when you mean
something else. `is_zero` never calls `sign` on an empty interval, because the
conjunction stops at `classify`.

```moonbit
///|
test "generic predicates" {
  inspect(@def.is_zero(@bin_float.BinFloat::from_double(-0.0)), content="true")
  inspect(
    @def.is_finite(@decimal.Decimal::from_string("NaN").unwrap()),
    content="false",
  )
  inspect(@def.is_nan(@ball_float.BallFloat::empty()), content="true")
  let around_zero = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(@def.is_zero(around_zero), content="true")
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

`RoundingMode` lists the five rounding directions accepted by
`with_precision` and by the concrete constructors: `ToNearestEven`,
`TowardZero`, `TowardPositive`, `TowardNegative` and `AwayFromZero`.

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
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
} derive(Eq)
pub fn PartialOrder::equal(Self, Self) -> Bool
pub fn PartialOrder::not_equal(Self, Self) -> Bool

pub(all) enum Sign {
  Negative
  Zero
  Positive
} derive(Eq)
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
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```
<!-- generated-api-end -->
