# internal API

`internal` holds exact integer and rational helpers shared by the numeric
cores: powers of 2, 5 and 10, digit counting, removal of trailing factors,
integer division with an explicit rounding mode, a decimal string splitter,
reduced rationals, dyadic enclosures and the refinement budget of the
certified elementary functions. `bin_float`, `decimal`, `decimal_gda`,
`ball_float`, `semantic` and the `consistency` tests use it. It is an internal
package: it cannot be imported from outside `Luna-Flow/floating` and its
interface may change. Examples are therefore not compiled. The
[design page](../design/internal.md) proves the rounding and enclosure
invariants; the [tutorial](../tutorial/internal.md) shows how the cores use the
helpers.

Import (inside the module only):

```text
import {
  "Luna-Flow/floating/internal",
}
```

`@bigint.BigInt` is `moonbitlang/core/bigint`; the interface prints
`Luna-Flow/arithmetic` as `@arithmetic` (`RoundingMode`, `ArithmeticError`,
`CertificationStage`, `CertificationFailureReason`) and uses `@def.Sign`.

## Integer basics

### `bigint_zero`, `bigint_one`

These functions return the `BigInt` constants $0$ and $1$.

```mbti
pub fn bigint_zero() -> @bigint.BigInt
pub fn bigint_one() -> @bigint.BigInt
```

### `abs_bigint`, `sign_of_bigint`, `compare_abs`

`abs_bigint(x)` is $|x|$, `sign_of_bigint(x)` is `Negative`, `Zero` or
`Positive`, and `compare_abs(a, b)` compares $|a|$ with $|b|$ (returning a
negative, zero or positive `Int`).

```mbti
pub fn abs_bigint(@bigint.BigInt) -> @bigint.BigInt
pub fn sign_of_bigint(@bigint.BigInt) -> @def.Sign
pub fn compare_abs(@bigint.BigInt, @bigint.BigInt) -> Int
```

## Powers

### `pow2`, `pow5`, `pow10`

These functions return $2^n$, $5^n$ and $10^n$.

```mbti
pub fn pow2(Int) -> @bigint.BigInt
pub fn pow5(Int) -> @bigint.BigInt
pub fn pow10(Int) -> @bigint.BigInt
```

They abort when $n < 0$. `pow2` is a shift. `pow5` and `pow10` read a
process-wide cache that starts with $n \le 18$ and is extended on demand up to
$n = 4096$; larger powers are computed each time without caching.

### `digits10`

`digits10(x)` is the number of decimal digits of $|x|$, with
`digits10(0) == 1`.

```mbti
pub fn digits10(@bigint.BigInt) -> Int
```

For $x \ne 0$ it returns the unique $d$ with $10^{d-1} \le |x| < 10^{d}$,
starting from an estimate based on the bit length and correcting it with
comparisons against powers of ten (no decimal string is built).

## Trailing factors

### `remove_factor2`

`remove_factor2(sig, exp)` removes all factors 2 from `sig`, adjusting the
binary exponent.

```mbti
pub fn remove_factor2(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)
```

For $\mathit{sig} \ne 0$ it returns $(\mathit{sig}/2^t, \mathit{exp} + t)$ with
$t$ the number of trailing zero bits of $|\mathit{sig}|$, so
$\mathit{sig} \cdot 2^{\mathit{exp}}$ is unchanged and the new significand is
odd. For $\mathit{sig} = 0$ it returns $(0, 0)$.

### `remove_factor10`

`remove_factor10(coeff, exp)` removes all factors 10 from `coeff`, adjusting
the decimal exponent.

```mbti
pub fn remove_factor10(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)
```

The value $\mathit{coeff} \cdot 10^{\mathit{exp}}$ is preserved and the new
coefficient is not divisible by 10. Zero gives $(0, 0)$.

### `trim_trailing_decimal_zeros`

`trim_trailing_decimal_zeros(coeff, exp, max_drop?)` removes up to
`max_drop` trailing decimal zeros.

```mbti
pub fn trim_trailing_decimal_zeros(@bigint.BigInt, Int, max_drop? : Int) -> (@bigint.BigInt, Int, Int)
```

It returns $(c', e', k)$ with $c = c' \cdot 10^{k}$, $e' = e + k$, and $k$
maximal subject to $k \le$ `max_drop`. A negative `max_drop` (the default
$-1$) means no limit. Zero gives $(0, 0, 0)$. A limit lets a caller stop at
a target exponent, as decNumber-style trimming to an ideal exponent does.

### `exact_divide_by_power_of_ten`

`exact_divide_by_power_of_ten(coeff, shift)` is `Some(coeff / 10^shift)` when
the division is exact and `None` otherwise.

```mbti
pub fn exact_divide_by_power_of_ten(@bigint.BigInt, Int) -> @bigint.BigInt?
```

The sign is kept. Zero gives `Some(0)` for every `shift`; for a non-zero
coefficient a negative `shift` aborts.

## Rounding integer quotients

### `round_positive_div`

`round_positive_div(n, d, negative, mode)` rounds the quotient $n/d$ to an
integer magnitude.

```mbti
pub fn round_positive_div(@bigint.BigInt, @bigint.BigInt, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt
```

Requires $n \ge 0$ and $d > 0$ (aborts otherwise). `negative` is the sign of
the real quotient whose magnitude is $n/d$; the result is
$|\circ_{\text{mode}}((-1)^{\text{negative}}\, n/d)|$, where $\circ$ rounds to
an integer:

| `mode` | result for $n = qd + r$, $0 \le r < d$ |
| --- | --- |
| `TowardZero` | $q$ |
| `TowardPositive` | $q + [r > 0 \wedge \neg\text{negative}]$ |
| `TowardNegative` | $q + [r > 0 \wedge \text{negative}]$ |
| `AwayFromZero` | $q + [r > 0]$ |
| `ToNearestEven` | $q + [2r > d \vee (2r = d \wedge q \text{ odd})]$ |

The result is exact (equal to $n/d$) exactly when $r = 0$.

### `round_shift`

`round_shift(m, s, negative, mode)` is `round_positive_div(m, 2^s, negative,
mode)` computed with shifts.

```mbti
pub fn round_shift(@bigint.BigInt, Int, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt
```

$m$ should be non-negative (not checked). For $s \le 0$ it returns $m$
unchanged.

## Decimal strings

### `split_decimal_string`

`split_decimal_string(text)` splits a finite decimal literal into sign,
digits and exponent.

```mbti
pub fn split_decimal_string(String) -> (Bool, String, Int)?
```

The accepted grammar is

```text
[+|-] digit* [. digit*] [(e|E) [+|-] digit+]     with at least one mantissa digit
```

The result $(\mathit{neg}, D, q)$ satisfies
$\text{value} = (-1)^{\mathit{neg}} \cdot D \cdot 10^{q}$, where $D$ is the
string of all mantissa digits (leading zeros kept) and $q$ is the written
exponent minus the number of fraction digits. The written exponent saturates
at $\pm 1\,500\,000\,000$ before the subtraction, so huge exponents cannot
overflow `Int`. Anything else, including `inf` and `nan`, gives `None`.

```moonbit nocheck
///|
test "split decimal string" {
  debug_inspect(@internal.split_decimal_string("-12.50e3"), content="Some((true, \"1250\", 1))")
  debug_inspect(@internal.split_decimal_string(".5"), content="Some((false, \"5\", -1))")
  debug_inspect(@internal.split_decimal_string("1e"), content="None")
}
```

## Result combinators

### `result_lift2`, `result_lift2_checked`

These functions combine two `Result`s, returning the first error.

```mbti
pub fn[A, B, E, C] result_lift2(Result[A, E], Result[B, E], (A, B) -> C) -> Result[C, E]
pub fn[A, B, E, C] result_lift2_checked(Result[A, E], Result[B, E], (A, B) -> Result[C, E]) -> Result[C, E]
```

`result_lift2(Ok(a), Ok(b), f)` is `Ok(f(a, b))`; `result_lift2_checked`
returns `f(a, b)` itself. If `left` is `Err`, that error is returned; otherwise
an `Err` in `right` is returned.

## Exact rationals

### `ExactRat`

`ExactRat` is a rational number in lowest terms.

```mbti
pub struct ExactRat {
  // private fields
} derive(Eq)
```

### `ExactRat::new`, `ExactRat::numerator`, `ExactRat::denominator`

`ExactRat::new(n, d)` reduces $n/d$ to lowest terms with a positive
denominator; the accessors return the reduced parts.

```mbti
pub fn ExactRat::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRat::numerator(Self) -> @bigint.BigInt
pub fn ExactRat::denominator(Self) -> @bigint.BigInt
```

Aborts when $d = 0$. Zero is stored as $0/1$. Because the form is canonical,
`==` on `ExactRat` is equality of rational numbers.

### `ExactRat::equal`, `ExactRat::not_equal`

These methods compare canonical forms; use `==` and `!=`.

```mbti
pub fn ExactRat::equal(Self, Self) -> Bool
pub fn ExactRat::not_equal(Self, Self) -> Bool
```

```moonbit nocheck
///|
test "exact rational" {
  let r = @internal.ExactRat::new(-6N, -8N)
  inspect(r.numerator(), content="3")
  inspect(r.denominator(), content="4")
  inspect(r == @internal.ExactRat::new(9N, 12N), content="true")
}
```

## Dyadic enclosures

### `CertifiedDyadic`

`CertifiedDyadic` is the dyadic rational $n \cdot 2^{-s}$, where $n$ is
`numerator_` and the scale $s$ = `scale_` is non-negative.

```mbti
pub struct CertifiedDyadic {
  numerator_ : @bigint.BigInt
  scale_ : Int
}
```

The fields are readable; build values with `new` or `from_int`.

### `CertifiedDyadic::new`, `from_int`, `numerator`, `scale`

`new(n, s)` is $n \cdot 2^{-s}$ (aborts if $s < 0$); `from_int(k)` is
$k \cdot 2^{0}$; the accessors return the fields.

```mbti
pub fn CertifiedDyadic::new(@bigint.BigInt, Int) -> Self
pub fn CertifiedDyadic::from_int(Int) -> Self
pub fn CertifiedDyadic::numerator(Self) -> @bigint.BigInt
pub fn CertifiedDyadic::scale(Self) -> Int
```

The representation is not normalized: $2 \cdot 2^{-1}$ and $1 \cdot 2^{0}$
are different values of the struct with the same number.

### `CertifiedDyadic::add`, `sub`, `mul`, `neg`, `compare`

These methods are exact arithmetic and comparison of dyadic numbers.

```mbti
pub fn CertifiedDyadic::add(Self, Self) -> Self
pub fn CertifiedDyadic::sub(Self, Self) -> Self
pub fn CertifiedDyadic::mul(Self, Self) -> Self
pub fn CertifiedDyadic::neg(Self) -> Self
pub fn CertifiedDyadic::compare(Self, Self) -> Int
```

`add` and `sub` align to the larger scale; `mul` adds the scales; `compare`
compares the numbers (not the representations).

### `CertifiedDyadic::round_down`, `CertifiedDyadic::round_up`

`x.round_down(s)` and `x.round_up(s)` are the largest dyadic
$\le x$ and the smallest dyadic $\ge x$ with scale $s$:
$\lfloor x \cdot 2^{s} \rfloor \cdot 2^{-s}$ and
$\lceil x \cdot 2^{s} \rceil \cdot 2^{-s}$.

```mbti
pub fn CertifiedDyadic::round_down(Self, Int) -> Self
pub fn CertifiedDyadic::round_up(Self, Int) -> Self
```

Abort if $s < 0$. When $s$ is at least the current scale the value is
re-expressed exactly.

### `CertifiedInterval`

`CertifiedInterval[T]` is an ordered pair `lower <= upper` used as an
enclosure.

```mbti
pub struct CertifiedInterval[T] {
  lower_ : T
  upper_ : T
}
pub fn[T] CertifiedInterval::new(T, T, (T, T) -> Int) -> Result[Self[T], @arithmetic.ArithmeticError]
pub fn[T] CertifiedInterval::lower(Self[T]) -> T
pub fn[T] CertifiedInterval::upper(Self[T]) -> T
```

`new(lower, upper, compare)` returns a certification-failure error with stage
`EnclosurePropagation` and reason `InvalidEnclosure` when
`compare(lower, upper) > 0`.

### `certified_dyadic_fraction`

`certified_dyadic_fraction(n, d, s)` encloses $n/d$ between two dyadics of
scale $s$.

```mbti
pub fn certified_dyadic_fraction(@bigint.BigInt, @bigint.BigInt, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]
```

The result is
$[\lfloor n 2^{s}/d \rfloor 2^{-s},\ \lceil n 2^{s}/d \rceil 2^{-s}]$: it
contains $n/d$, has width $0$ or $2^{-s}$, and is a point exactly when
$d \mid n 2^{s}$. A non-positive $d$ gives a domain error.

### `certified_dyadic_div`

`certified_dyadic_div(a, b, s)` encloses the quotient $a/b$ of two dyadics at
scale $s$.

```mbti
pub fn certified_dyadic_div(CertifiedDyadic, CertifiedDyadic, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]
```

$b = 0$ gives a division-by-zero error. Otherwise the result is
`certified_dyadic_fraction` applied to $a/b$ written with a positive
denominator.

```moonbit nocheck
///|
test "one third at scale 8" {
  let third = @internal.certified_dyadic_div(
    @internal.CertifiedDyadic::from_int(1),
    @internal.CertifiedDyadic::from_int(3),
    8,
  ).unwrap()
  inspect(third.lower().numerator(), content="85") // 85/256 <= 1/3
  inspect(third.upper().numerator(), content="86") // 86/256 >= 1/3
}
```

## Refinement budgets

### `CertifiedRefinementBudget`

`CertifiedRefinementBudget` tracks the working precision and the number of
refinements of a Ziv-style evaluation loop.

```mbti
pub struct CertifiedRefinementBudget {
  work_precision : Int
  refinements_ : Int
  limit_ : Int
}
```

### `CertifiedRefinementBudget::new`, `next`, `available`, `precision`, `refinements`

`new(p, limit?)` starts at working precision $\max(1, p)$ with zero
refinements and a limit of $\max(1, \mathit{limit})$ refinements (default
12). `next()` increases the precision by $\max(32, \lfloor p/2 \rfloor)$ and
counts one refinement. `available()` is true while fewer than `limit`
refinements were made.

```mbti
pub fn CertifiedRefinementBudget::new(Int, limit? : Int) -> Self
pub fn CertifiedRefinementBudget::next(Self) -> Self
pub fn CertifiedRefinementBudget::available(Self) -> Bool
pub fn CertifiedRefinementBudget::precision(Self) -> Int
pub fn CertifiedRefinementBudget::refinements(Self) -> Int
```

For example $64 \to 96 \to 144 \to 216$.

### `certified_failure`

`certified_failure(operation, stage, reason, target_precision, budget)`
builds the `ArithmeticError` a certified operation returns when it gives up.

```mbti
pub fn certified_failure(String, @arithmetic.CertificationStage, @arithmetic.CertificationFailureReason, Int, CertifiedRefinementBudget) -> @arithmetic.ArithmeticError
```

The error's detail records the operation name, stage, reason, target
precision, and the budget's current working precision and refinement count.

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
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

pub fn certified_dyadic_div(CertifiedDyadic, CertifiedDyadic, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]

pub fn certified_dyadic_fraction(@bigint.BigInt, @bigint.BigInt, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]

pub fn certified_failure(String, @arithmetic.CertificationStage, @arithmetic.CertificationFailureReason, Int, CertifiedRefinementBudget) -> @arithmetic.ArithmeticError

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
pub struct CertifiedDyadic {
  numerator_ : @bigint.BigInt
  scale_ : Int
}
pub fn CertifiedDyadic::add(Self, Self) -> Self
pub fn CertifiedDyadic::compare(Self, Self) -> Int
pub fn CertifiedDyadic::from_int(Int) -> Self
pub fn CertifiedDyadic::mul(Self, Self) -> Self
pub fn CertifiedDyadic::neg(Self) -> Self
pub fn CertifiedDyadic::new(@bigint.BigInt, Int) -> Self
pub fn CertifiedDyadic::numerator(Self) -> @bigint.BigInt
pub fn CertifiedDyadic::round_down(Self, Int) -> Self
pub fn CertifiedDyadic::round_up(Self, Int) -> Self
pub fn CertifiedDyadic::scale(Self) -> Int
pub fn CertifiedDyadic::sub(Self, Self) -> Self

pub struct CertifiedInterval[T] {
  lower_ : T
  upper_ : T
}
pub fn[T] CertifiedInterval::lower(Self[T]) -> T
pub fn[T] CertifiedInterval::new(T, T, (T, T) -> Int) -> Result[Self[T], @arithmetic.ArithmeticError]
pub fn[T] CertifiedInterval::upper(Self[T]) -> T

pub struct CertifiedRefinementBudget {
  work_precision : Int
  refinements_ : Int
  limit_ : Int
}
pub fn CertifiedRefinementBudget::available(Self) -> Bool
pub fn CertifiedRefinementBudget::new(Int, limit? : Int) -> Self
pub fn CertifiedRefinementBudget::next(Self) -> Self
pub fn CertifiedRefinementBudget::precision(Self) -> Int
pub fn CertifiedRefinementBudget::refinements(Self) -> Int

pub struct ExactRat {
  // private fields
} derive(Eq)
pub fn ExactRat::denominator(Self) -> @bigint.BigInt
pub fn ExactRat::equal(Self, Self) -> Bool
pub fn ExactRat::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRat::not_equal(Self, Self) -> Bool
pub fn ExactRat::numerator(Self) -> @bigint.BigInt

// Type aliases

// Traits
```
<!-- generated-api-end -->
