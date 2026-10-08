# `semantic` API

`semantic` projects concrete values of `floating` onto a small
representation-independent model: an exact reduced rational, a signed
infinity, NaN, a closed interval of such scalars, and a short error
vocabulary. Two values of different representations (for example a binary64
`BinFloat` and an IEEE `Decimal`) project to equal semantic values exactly when
they denote the same number. The package performs no arithmetic and no
rounding. The [tutorial](../tutorial/semantic.md) shows typical comparisons;
the [design page](../design/semantic.md) derives why the projection is exact
and what it forgets.

The examples assume this helper, which prints a semantic scalar as
`numerator/denominator`:

```moonbit
///|
fn show(s : @semantic.SemanticScalar) -> String {
  match s {
    Rational(q) => q.numerator().to_string() + "/" + q.denominator().to_string()
    Infinity(@def.Sign::Negative) => "-inf"
    Infinity(_) => "+inf"
    NaN => "nan"
  }
}
```

## Exact rationals

### `ExactRational`

`ExactRational` is an exact rational number kept in lowest terms with a
positive denominator.

```mbti
pub struct ExactRational {
  // private fields
} derive(Eq)
```

The fields are private, so every value is built by `ExactRational::new` or
`ExactRational::from_scaled_integer` and satisfies the invariant

$$
\frac{n}{d}\ \text{ with }\ d > 0,\quad \gcd(|n|, d) = 1,\quad n = 0 \implies d = 1.
$$

Because this form is unique for every rational number, the derived `==` is
equality of rational numbers.

### `ExactRational::new`

`new(numerator, denominator)` builds the rational $n/d$ and reduces it.

```mbti
pub fn ExactRational::new(@bigint.BigInt, @bigint.BigInt) -> Self
```

A negative denominator moves its sign to the numerator; both parts are divided
by their greatest common divisor (Euclid's algorithm on `BigInt`); zero becomes
$0/1$. **Aborts** when `denominator` is zero.

### `ExactRational::from_scaled_integer`

`from_scaled_integer(significand, radix, exponent)` builds the exact value
$m \cdot r^{e}$.

```mbti
pub fn ExactRational::from_scaled_integer(@bigint.BigInt, Int, Int) -> Self
```

For $e \ge 0$ the result is $(m r^{e})/1$; for $e < 0$ it is $m / r^{-e}$,
reduced. **Aborts** when `radix` $\le 1$. The power is computed exactly, so the
size of the result grows linearly with $|e|$ (about $|e| \log_2 r$ bits).

### `ExactRational::numerator`, `ExactRational::denominator`

These accessors return the reduced numerator (carrying the sign) and the
positive denominator.

```mbti
pub fn ExactRational::numerator(Self) -> @bigint.BigInt
pub fn ExactRational::denominator(Self) -> @bigint.BigInt
```

```moonbit
///|
test "exact rationals are reduced" {
  let q = @semantic.ExactRational::new(6N, -8N)
  inspect(q.numerator().to_string() + "/" + q.denominator().to_string(), content="-3/4")
  let scaled = @semantic.ExactRational::from_scaled_integer(-12N, 10, -3)
  inspect(
    scaled.numerator().to_string() + "/" + scaled.denominator().to_string(),
    content="-3/250",
  )
  inspect(
    @semantic.ExactRational::from_scaled_integer(3N, 2, 4) ==
    @semantic.ExactRational::new(48N, 1N),
    content="true",
  )
}
```

## Scalars

### `SemanticScalar`

`SemanticScalar` is the meaning of one floating-point datum.

```mbti
pub(all) enum SemanticScalar {
  Rational(ExactRational)
  Infinity(@def.Sign)
  NaN
} derive(Eq)
```

`Rational` holds every finite value, including both signed zeros as $0/1$.
`Infinity` carries `Negative` or `Positive`. `NaN` stands for every NaN: quiet
or signalling, any payload, any sign. Equality is structural, so
`NaN == NaN` is `true` here, unlike IEEE comparison.

### `SemanticScalar::from_bin_float`

`from_bin_float(x)` returns the exact meaning of a `BinFloat`.

```mbti
pub fn SemanticScalar::from_bin_float(@bin_float.BinFloat) -> Self
```

A finite $x = (-1)^{s} c\, 2^{e}$ maps to `Rational` of
`from_scaled_integer(±c, 2, e)`; an infinity maps to `Infinity(x.sign())`; a
NaN maps to `NaN`. Precision is dropped. Never aborts.

### `SemanticScalar::from_decimal`

`from_decimal(x)` returns the exact meaning of an IEEE `@decimal.Decimal`.

```mbti
pub fn SemanticScalar::from_decimal(@decimal.Decimal) -> Self
```

A finite $x = (-1)^{s} c\, 10^{q}$ maps to `Rational` of
`from_scaled_integer(±c, 10, q)`, so every member of a cohort (`1.5`, `1.50`,
`1.500`) maps to the same value $3/2$. Infinities and NaNs map as for binary.
The GDA type `@decimal_gda.Decimal` has no projection in this package.

```moonbit
///|
test "project binary and decimal values" {
  let binary = @semantic.SemanticScalar::from_bin_float(
    @bin_float.BinFloat::from_double(0.1),
  )
  inspect(show(binary), content="3602879701896397/36028797018963968")
  let decimal = @semantic.SemanticScalar::from_decimal(
    @decimal.Decimal::from_string("0.1").unwrap(),
  )
  inspect(show(decimal), content="1/10")
  inspect(binary == decimal, content="false")
  let half = @semantic.SemanticScalar::from_bin_float(
    @bin_float.BinFloat::from_double(0.5),
  )
  let half_decimal = @semantic.SemanticScalar::from_decimal(
    @decimal.Decimal::from_string("0.500").unwrap(),
  )
  inspect(half == half_decimal, content="true")
  inspect(
    show(@semantic.SemanticScalar::from_bin_float(@bin_float.BinFloat::from_double(-0.0))),
    content="0/1",
  )
  inspect(
    @semantic.SemanticScalar::from_bin_float(@bin_float.BinFloat::nan()) ==
    @semantic.SemanticScalar::NaN,
    content="true",
  )
}
```

## Intervals

### `SemanticInterval`

`SemanticInterval` is a closed interval given by two semantic endpoints.

```mbti
pub struct SemanticInterval {
  lower : SemanticScalar
  upper : SemanticScalar
} derive(Eq)
```

The fields are public and read-only outside the package. The type does not
check that `lower` does not exceed `upper`; the projection below uses the
reversed pair $(+\infty, -\infty)$ for the empty set.

### `SemanticInterval::from_ball_float`

`from_ball_float(x)` projects the two endpoints of a `BallFloat`.

```mbti
pub fn SemanticInterval::from_ball_float(@ball_float.BallFloat) -> Self
```

`lower` is `from_bin_float(x.lower_bound())` and `upper` is
`from_bin_float(x.upper_bound())`. A bounded interval gives two `Rational`
endpoints, an unbounded side gives `Infinity`, the entire line gives
$(-\infty, +\infty)$, and the empty interval gives
$(\texttt{Infinity(Positive)}, \texttt{Infinity(Negative)})$. Decorations,
precision and flags are dropped.

```moonbit
///|
test "project intervals" {
  let x = @semantic.SemanticInterval::from_ball_float(
    @ball_float.BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(1),
      @bin_float.BinFloat::from_double(2.5),
    ),
  )
  inspect(show(x.lower) + " .. " + show(x.upper), content="1/1 .. 5/2")
  let whole = @semantic.SemanticInterval::from_ball_float(
    @ball_float.BallFloat::whole(),
  )
  inspect(show(whole.lower) + " .. " + show(whole.upper), content="-inf .. +inf")
  let empty = @semantic.SemanticInterval::from_ball_float(
    @ball_float.BallFloat::empty(),
  )
  inspect(show(empty.lower) + " .. " + show(empty.upper), content="+inf .. -inf")
}
```

## Errors and checked results

### `SemanticError`

`SemanticError` is the representation-independent error vocabulary.

```mbti
pub(all) enum SemanticError {
  DivisionByZero
  ParseError
  DomainError
  FormatError
  UnsupportedOperation
  UnorderedComparison
  CertificationFailure
} derive(Eq)
```

It mirrors `ArithmeticErrorKind` of Luna-Flow/arithmetic without messages and
without the certification detail.

### `SemanticError::from_arithmetic`

`from_arithmetic(err)` classifies an `ArithmeticError`.

```mbti
pub fn SemanticError::from_arithmetic(@arithmetic.ArithmeticError) -> Self
```

The kind is tested in the order division by zero, parse, domain, format,
unordered comparison, certification failure; anything else (the
`UnsupportedOperation` kind) maps to `UnsupportedOperation`. The message and
the `CertificationFailureDetail` are discarded.

### `SemanticResult`

`SemanticResult[T]` is a semantic value or a semantic error.

```mbti
pub(all) enum SemanticResult[T] {
  Value(T)
  Error(SemanticError)
} derive(Eq)
```

### `semantic_scalar_result`, `semantic_interval_result`

These functions turn a checked result of a concrete package into a semantic
result, using a caller-supplied projection for the success case.

```mbti
pub fn[T] semantic_scalar_result(Result[T, @arithmetic.ArithmeticError], (T) -> SemanticScalar) -> SemanticResult[SemanticScalar]
pub fn[T] semantic_interval_result(Result[T, @arithmetic.ArithmeticError], (T) -> SemanticInterval) -> SemanticResult[SemanticInterval]
```

$$
\begin{aligned}
\texttt{semantic\_scalar\_result}(\texttt{Ok}(v), f) &= \texttt{Value}(f(v)),\\
\texttt{semantic\_scalar\_result}(\texttt{Err}(e), f) &= \texttt{Error}(\texttt{from\_arithmetic}(e)),
\end{aligned}
$$

and likewise for intervals. `f` is called at most once.

```moonbit
///|
test "checked results become semantic results" {
  let failed = @semantic.semantic_scalar_result(
    @bin_float.BinFloat::from_int(1).div_checked(@bin_float.BinFloat::zero()),
    @semantic.SemanticScalar::from_bin_float,
  )
  inspect(
    failed == @semantic.SemanticResult::Error(@semantic.SemanticError::DivisionByZero),
    content="true",
  )
  let root = @semantic.semantic_scalar_result(
    @bin_float.BinFloat::from_int(4).sqrt(),
    @semantic.SemanticScalar::from_bin_float,
  )
  let two = @semantic.SemanticScalar::from_decimal(@decimal.Decimal::from_int(2))
  inspect(root == @semantic.SemanticResult::Value(two), content="true")
}
```

## Trait implementations

### Equality

Every type of the package derives `Eq`; the `equal` and `not_equal` methods are
promoted explicitly. Prefer `==` and `!=`.

```mbti
pub fn ExactRational::equal(Self, Self) -> Bool
pub fn ExactRational::not_equal(Self, Self) -> Bool
pub fn SemanticScalar::equal(Self, Self) -> Bool
pub fn SemanticScalar::not_equal(Self, Self) -> Bool
pub fn SemanticInterval::equal(Self, Self) -> Bool
pub fn SemanticInterval::not_equal(Self, Self) -> Bool
pub fn SemanticError::equal(Self, Self) -> Bool
pub fn SemanticError::not_equal(Self, Self) -> Bool
pub fn[T : Eq] SemanticResult::equal(Self[T], Self[T]) -> Bool
pub fn[T : Eq] SemanticResult::not_equal(Self[T], Self[T]) -> Bool
```

Equality of `ExactRational` is numeric equality because of the reduced form;
equality of `SemanticScalar` adds `NaN == NaN` and distinguishes the two
infinities. No ordering is provided.

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
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
pub fn ExactRational::equal(Self, Self) -> Bool
pub fn ExactRational::from_scaled_integer(@bigint.BigInt, Int, Int) -> Self
pub fn ExactRational::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRational::not_equal(Self, Self) -> Bool
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
pub fn SemanticError::equal(Self, Self) -> Bool
pub fn SemanticError::from_arithmetic(@arithmetic.ArithmeticError) -> Self
pub fn SemanticError::not_equal(Self, Self) -> Bool

pub struct SemanticInterval {
  lower : SemanticScalar
  upper : SemanticScalar
} derive(Eq)
pub fn SemanticInterval::equal(Self, Self) -> Bool
pub fn SemanticInterval::from_ball_float(@ball_float.BallFloat) -> Self
pub fn SemanticInterval::not_equal(Self, Self) -> Bool

pub(all) enum SemanticResult[T] {
  Value(T)
  Error(SemanticError)
} derive(Eq)
pub fn[T : Eq] SemanticResult::equal(Self[T], Self[T]) -> Bool
pub fn[T : Eq] SemanticResult::not_equal(Self[T], Self[T]) -> Bool

pub(all) enum SemanticScalar {
  Rational(ExactRational)
  Infinity(@def.Sign)
  NaN
} derive(Eq)
pub fn SemanticScalar::equal(Self, Self) -> Bool
pub fn SemanticScalar::from_bin_float(@bin_float.BinFloat) -> Self
pub fn SemanticScalar::from_decimal(@decimal.Decimal) -> Self
pub fn SemanticScalar::not_equal(Self, Self) -> Bool

// Type aliases

// Traits
```
<!-- generated-api-end -->
