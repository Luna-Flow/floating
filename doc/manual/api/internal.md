# internal API

## Purpose

`internal` holds exact integer and rational helpers for the numeric cores:
powers of 2, 5 and 10, digit counting, removal of trailing factors, integer
division with an explicit rounding mode, a decimal string splitter, reduced
rationals, dyadic enclosures and the refinement budget of the certified
elementary functions. It is an internal package: it cannot be imported from
outside `Luna-Flow/floating`, and its interface may change without notice. The
[design page](../design/internal.md) proves the rounding and enclosure
invariants; the [tutorial](../tutorial/internal.md) shows how the helpers
combine.

Not every helper is used by every core. On the current branch the library
code uses:

| Package | Helpers it uses |
| --- | --- |
| `decimal`, `decimal_gda` | `split_decimal_string`, `round_positive_div`, `pow5`, `pow10`, `digits10`, `abs_bigint`, `bigint_zero`, `bigint_one`, `CertifiedRefinementBudget`, `certified_failure` |
| `bin_float`, `ball_float` | `CertifiedRefinementBudget`, `certified_failure` |
| `semantic` | `ExactRat` |

The binary and decimal cores round their own coefficients with their own
kernels. The remaining helpers (`round_shift`, `remove_factor2`,
`remove_factor10`, `trim_trailing_decimal_zeros`,
`exact_divide_by_power_of_ten`, `compare_abs`, `sign_of_bigint`, `pow2`, the
`CertifiedDyadic` family and the `result_lift2` combinators) are exercised by
the `consistency` and package tests only.

## Importing

Inside the module, add the package to `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal",
}
```

The examples call the package as `@internal.` and `Luna-Flow/arithmetic` as
`@lf_arith.`; `BigInt` literals are written `12N`. The interface prints
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
`Positive`, and `compare_abs(a, b)` compares $|a|$ with $|b|$.

```mbti
pub fn abs_bigint(@bigint.BigInt) -> @bigint.BigInt
pub fn sign_of_bigint(@bigint.BigInt) -> @def.Sign
pub fn compare_abs(@bigint.BigInt, @bigint.BigInt) -> Int
```

`compare_abs` returns a negative, zero or positive `Int` (the result of
`BigInt::compare` on the magnitudes).

```moonbit
///|
test "integer basics" {
  inspect(@internal.abs_bigint(-7N), content="7")
  inspect(@internal.sign_of_bigint(0N) == @def.Sign::Zero, content="true")
  inspect(@internal.compare_abs(-3N, 2N) > 0, content="true")
}
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

```moonbit
///|
test "powers and digit counts" {
  inspect(@internal.pow5(3), content="125")
  inspect(@internal.digits10(0N), content="1")
  inspect(@internal.digits10(-999N), content="3")
  inspect(@internal.digits10(@internal.pow10(5000)), content="5001")
}
```

## Trailing factors

### `remove_factor2`

`remove_factor2(sig, exp)` removes all factors 2 from `sig`, adjusting the
binary exponent.

```mbti
pub fn remove_factor2(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)
```

For $\mathit{sig} \ne 0$ it returns $(\mathit{sig}/2^t, \mathit{exp} + t)$ with
$t$ the number of trailing zero bits of $|\mathit{sig}|$, so
$\mathit{sig} \cdot 2^{\mathit{exp}}$ is unchanged, the sign is kept and the
new significand is odd. For $\mathit{sig} = 0$ it returns $(0, 0)$: the
exponent of a zero is not kept.

### `remove_factor10`

`remove_factor10(coeff, exp)` removes all factors 10 from `coeff`, adjusting
the decimal exponent.

```mbti
pub fn remove_factor10(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)
```

The value $\mathit{coeff} \cdot 10^{\mathit{exp}}$ and the sign are preserved
and the new coefficient is not divisible by 10. Zero gives $(0, 0)$.

### `trim_trailing_decimal_zeros`

`trim_trailing_decimal_zeros(coeff, exp, max_drop?)` removes up to
`max_drop` trailing decimal zeros.

```mbti
pub fn trim_trailing_decimal_zeros(@bigint.BigInt, Int, max_drop? : Int) -> (@bigint.BigInt, Int, Int)
```

It returns $(c', e', k)$ with $c = c' \cdot 10^{k}$, $e' = e + k$, and $k$
maximal subject to $k \le$ `max_drop`. A negative `max_drop` (the default
$-1$) sets the limit to `digits10(c) - 1`, which never binds because a
non-zero integer with $k$ trailing zeros has at least $k + 1$ digits; so the
default removes every trailing zero. Zero gives $(0, 0, 0)$. A limit lets a
caller stop at a target exponent, as decNumber-style trimming to an ideal
exponent does.

### `exact_divide_by_power_of_ten`

`exact_divide_by_power_of_ten(coeff, shift)` is `Some(coeff / 10^shift)` when
the division is exact and `None` otherwise.

```mbti
pub fn exact_divide_by_power_of_ten(@bigint.BigInt, Int) -> @bigint.BigInt?
```

The sign is kept. Zero gives `Some(0)` for every `shift`; for a non-zero
coefficient a negative `shift` aborts.

```moonbit
///|
test "trailing factors" {
  debug_inspect(@internal.remove_factor2(-12N, 0), content="(-3, 2)")
  debug_inspect(@internal.remove_factor10(-1200N, 3), content="(-12, 5)")
  debug_inspect(
    @internal.trim_trailing_decimal_zeros(1000N, 0, max_drop=2),
    content="(10, 2, 2)",
  )
  debug_inspect(@internal.exact_divide_by_power_of_ten(1201N, 2), content="None")
}
```

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

```moonbit
///|
test "rounding -5/2 and -7/2" {
  let modes = [
    @lf_arith.RoundingMode::ToNearestEven,
    @lf_arith.RoundingMode::TowardZero,
    @lf_arith.RoundingMode::TowardPositive,
    @lf_arith.RoundingMode::TowardNegative,
    @lf_arith.RoundingMode::AwayFromZero,
  ]
  let five = modes.map(m => @internal.round_positive_div(5N, 2N, true, m).to_string())
  let seven = modes.map(m => @internal.round_positive_div(7N, 2N, true, m).to_string())
  inspect(five.join(" "), content="2 2 2 3 3")
  inspect(seven.join(" "), content="4 3 3 4 4")
}
```

### `round_shift`

`round_shift(m, s, negative, mode)` is `round_positive_div(m, 2^s, negative,
mode)` computed with shifts.

```mbti
pub fn round_shift(@bigint.BigInt, Int, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt
```

For $s \le 0$ it returns $m$ unchanged (it never shifts left). $m$ should be
non-negative; this is not checked. For a negative $m$ the quotient is the
floor $\lfloor m / 2^{s} \rfloor$ of an arithmetic shift and the remainder is
non-negative, so the table above no longer describes the rounding of $|m|$:
`round_shift(-5N, 1, false, TowardZero)` is $-3$, not $-2$.

## Decimal strings

### `split_decimal_string`, `split_decimal_string_wide`

`split_decimal_string(text)` splits a finite decimal literal into sign,
digits and exponent; `split_decimal_string_wide` returns the exponent as an
`Int64`.

```mbti
pub fn split_decimal_string(String) -> (Bool, String, Int)?
pub fn split_decimal_string_wide(String) -> (Bool, String, Int64)?
```

The accepted grammar is

```text
[+|-] digit* [. digit*] [(e|E) [+|-] digit+]     with at least one mantissa digit
```

The result $(\mathit{neg}, D, q)$ satisfies
$\text{value} = (-1)^{\mathit{neg}} \cdot D \cdot 10^{q}$, where $D$ is the
string of all mantissa digits (leading zeros kept) and $q$ is the written
exponent minus the number of fraction digits. In the wide form the written
exponent is exact up to $10^{18}$ in magnitude and saturates there, which is
far outside every exponent range. `split_decimal_string` returns `None` when
$q$ does not fit `Int`. Anything else, including `inf` and `nan`, gives
`None`.

> [!WARNING]
> The magnitude of the written exponent saturates at $1\,500\,000\,000$ before
> the fraction digits are subtracted, so `1e1600000000` and `1e1500000000`
> split to the same exponent. `@decimal.Decimal::from_string` and
> `@decimal_gda.Decimal::from_string` (which keep any exponent when no context
> is given), and `from_string_ctx` with a context whose `e_max` exceeds
> $1.5 \cdot 10^{9}$, therefore return `1E+1500000000` for `1e1600000000`
> instead of overflowing or keeping its value. Tracked in [#108](https://github.com/Luna-Flow/floating/issues/108); a fix is
> proposed in [#117](https://github.com/Luna-Flow/floating/pull/117).

```moonbit
///|
test "split decimal string" {
  debug_inspect(
    @internal.split_decimal_string("-12.50e3"),
    content="Some((true, \"1250\", 1))",
  )
  debug_inspect(@internal.split_decimal_string(".5"), content="Some((false, \"5\", -1))")
  debug_inspect(@internal.split_decimal_string("1e"), content="None")
  debug_inspect(@internal.split_decimal_string("1e3000000000"), content="None")
  debug_inspect(@internal.split_decimal_string_wide("1e3000000000"), content="Some((false, \"1\", 3000000000))")
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
an `Err` in `right` is returned. `f` runs only when both are `Ok`.

```moonbit
///|
test "lift two results" {
  let ok : Result[Int, String] = Ok(2)
  let bad : Result[Int, String] = Err("left")
  debug_inspect(@internal.result_lift2(ok, Ok(3), (a, b) => a * b), content="Ok(6)")
  debug_inspect(@internal.result_lift2(bad, Err("right"), (a, b) => a * b), content="Err(\"left\")")
}
```

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

```moonbit
///|
test "exact rational" {
  let r = @internal.ExactRat::new(-6N, -8N)
  inspect(r.numerator(), content="3")
  inspect(r.denominator(), content="4")
  inspect(r == @internal.ExactRat::new(9N, 12N), content="true")
  inspect(@internal.ExactRat::new(0N, -5N).denominator(), content="1")
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

The fields are readable but the struct cannot be built literally outside the
package; build values with `new` or `from_int`.

### `CertifiedDyadic::new`, `CertifiedDyadic::from_int`, `CertifiedDyadic::numerator`, `CertifiedDyadic::scale`

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

### `CertifiedDyadic::add`, `CertifiedDyadic::sub`, `CertifiedDyadic::mul`, `CertifiedDyadic::neg`, `CertifiedDyadic::compare`

These methods are exact arithmetic and comparison of dyadic numbers.

```mbti
pub fn CertifiedDyadic::add(Self, Self) -> Self
pub fn CertifiedDyadic::sub(Self, Self) -> Self
pub fn CertifiedDyadic::mul(Self, Self) -> Self
pub fn CertifiedDyadic::neg(Self) -> Self
pub fn CertifiedDyadic::compare(Self, Self) -> Int
```

`add` and `sub` align to the larger scale; `mul` adds the scales; `compare`
compares the numbers (not the representations), so
`new(2N, 1).compare(from_int(1))` is `0`.

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
re-expressed exactly (the numerator is shifted left). Both directions are
true floor and ceiling for negative numbers too: $-5/4$ rounds down to $-2$
and up to $-1$ at scale $0$.

### `CertifiedInterval`

`CertifiedInterval[T]` is an ordered pair `lower <= upper` used as an
enclosure.

```mbti
pub struct CertifiedInterval[T] {
  lower_ : T
  upper_ : T
}
```

### `CertifiedInterval::new`, `CertifiedInterval::lower`, `CertifiedInterval::upper`

`new(lower, upper, compare)` checks the order with the given comparison and
builds the pair; `lower` and `upper` return the endpoints.

```mbti
pub fn[T] CertifiedInterval::new(T, T, (T, T) -> Int) -> Result[Self[T], @arithmetic.ArithmeticError]
pub fn[T] CertifiedInterval::lower(Self[T]) -> T
pub fn[T] CertifiedInterval::upper(Self[T]) -> T
```

When `compare(lower, upper) > 0`, `new` returns a certification-failure error
for the operation `"interval"` with stage `EnclosurePropagation`, reason
`InvalidEnclosure`, target and working precision 1 and 0 refinements.

### `certified_dyadic_fraction`

`certified_dyadic_fraction(n, d, s)` encloses $n/d$ between two dyadics of
scale $s$.

```mbti
pub fn certified_dyadic_fraction(@bigint.BigInt, @bigint.BigInt, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]
```

The result is
$[\lfloor n 2^{s}/d \rfloor 2^{-s},\ \lceil n 2^{s}/d \rceil 2^{-s}]$ for
either sign of $n$: it contains $n/d$, has width $0$ or $2^{-s}$, and is a
point exactly when $d \mid n 2^{s}$. A non-positive $d$ gives a domain error.

### `certified_dyadic_div`

`certified_dyadic_div(a, b, s)` encloses the quotient $a/b$ of two dyadics at
scale $s$.

```mbti
pub fn certified_dyadic_div(CertifiedDyadic, CertifiedDyadic, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]
```

$b = 0$ gives a division-by-zero error. Otherwise the result is
`certified_dyadic_fraction` applied to $a/b$ written with a positive
denominator.

```moonbit
///|
test "one third at scale 8" {
  let third = @internal.certified_dyadic_div(
    @internal.CertifiedDyadic::from_int(1),
    @internal.CertifiedDyadic::from_int(3),
    8,
  ).unwrap()
  inspect(third.lower().numerator(), content="85") // 85/256 <= 1/3
  inspect(third.upper().numerator(), content="86") // 86/256 >= 1/3
  let negative = @internal.certified_dyadic_fraction(-1N, 3N, 2).unwrap()
  inspect(negative.lower().numerator(), content="-2") // -2/4 <= -1/3
  inspect(negative.upper().numerator(), content="-1") // -1/4 >= -1/3
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

### `CertifiedRefinementBudget::new`, `CertifiedRefinementBudget::next`, `CertifiedRefinementBudget::available`, `CertifiedRefinementBudget::precision`, `CertifiedRefinementBudget::refinements`

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

`next` does not check `available`; a loop must test `available()` itself.

```moonbit
///|
test "budget schedule" {
  let mut budget = @internal.CertifiedRefinementBudget::new(64, limit=3)
  let seen = []
  while budget.available() {
    seen.push(budget.precision().to_string())
    budget = budget.next()
  }
  inspect(seen.join(" -> "), content="64 -> 96 -> 144")
  inspect(budget.precision(), content="216")
  inspect(budget.refinements(), content="3")
}
```

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

pub fn split_decimal_string_wide(String) -> (Bool, String, Int64)?

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
