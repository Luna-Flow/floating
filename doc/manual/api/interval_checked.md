# interval_checked API

## Purpose

`interval_checked` provides `IntervalResult`, a closed wrapper around
`Result[Interval, ArithmeticError]` for interval computations. Construction
validates its inputs, every operation passes on the first error, and the
interval operations of [`interval`](interval.md) are applied when all
operands are successes. A valid but uninformative enclosure (the empty set, the
whole line) is a success, not an error. The wrapper stores no decorations and
no `IntervalFlags`. The [tutorial](../tutorial/interval_checked.md) builds
pipelines; the [design page](../design/interval_checked.md) explains which
outcomes are errors and why.

## Importing

Add the wrapper and the endpoint package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/interval",
  "Luna-Flow/floating/interval_checked",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples refer to the packages as `@interval_checked.`,
`@interval.`, `@bin_float.`, `@def.` (for the `Sign` of an infinity) and
`@lf_arith.` (for `Luna-Flow/arithmetic`). They print a result with this
helper (`to_midpoint_radius_string` of a bounded interval is `center +/- radius` in exact binary
notation, `mpe` meaning $m \cdot 2^{e}$):

```moonbit
///|
fn show(r : @interval_checked.IntervalResult) -> String {
  match r.result() {
    Ok(v) => v.to_midpoint_radius_string()
    Err(e) => "error: " + e.message
  }
}
```

## The wrapper type

### `IntervalResult`

`IntervalResult` is either a successful `Interval` or an `ArithmeticError`.

```mbti
pub struct IntervalResult {
  // private fields
}
```

The single private field holds a `Result[@interval.Interval,
@arithmetic.ArithmeticError]`. The type has no `Eq` or `Show`; use `result()`.

## Construction

### `IntervalResult::ok`, `IntervalResult::err`, `IntervalResult::from_result`

These functions wrap an existing interval, error or `Result` unchanged.

```mbti
pub fn IntervalResult::ok(@interval.Interval) -> Self
pub fn IntervalResult::err(@arithmetic.ArithmeticError) -> Self
pub fn IntervalResult::from_result(Result[@interval.Interval, @arithmetic.ArithmeticError]) -> Self
```

### `IntervalResult::from_int`, `IntervalResult::from_coefficient`

These constructors enclose an integer through `Interval::from_int` /
`Interval::from_coefficient`; they never fail.

```mbti
pub fn IntervalResult::from_int(Int, precision? : Int) -> Self
pub fn IntervalResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
```

The default precision is **53 bits**. The integer is converted exactly and
then rounded outward to the precision, so the result always contains it: a
singleton when the integer fits in the precision, otherwise the two-point
interval of its neighbours (for example `from_int(100001, precision=8)`, a
17-bit odd integer, gives an interval of width 2^9). Pass a precision large
enough for the integer to get a point.

### `IntervalResult::from_double`, `IntervalResult::from_float`

These constructors enclose a finite `Double` or `Float`.

```mbti
pub fn IntervalResult::from_double(Double, precision? : Int) -> Self
pub fn IntervalResult::from_float(Float, precision? : Int) -> Self
```

The source is converted exactly (at least 53 or 24 bits) and then rounded
outward to `precision` (defaults 53 and 24), so the result always contains the
source value. A NaN or infinite source gives a `DomainError`
(`interval double source must be finite`, `interval float source must be finite`).

### `IntervalResult::exact`

`exact(x, precision~)` encloses a finite `BinFloat`.

```mbti
pub fn IntervalResult::exact(@bin_float.BinFloat, precision? : Int) -> Self
```

`precision` defaults to `x.precision()`. The bounds are `x` rounded down and up
to that precision, so the result contains `x`. A non-finite `x` gives a
`DomainError` (`interval exact source must be finite`).

### `IntervalResult::from_bounds`

`from_bounds(lo, hi, precision~)` builds the interval $[\textit{lo},
\textit{hi}]$.

```mbti
pub fn IntervalResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
```

`precision` defaults to the larger bound precision; `lo` is rounded down and
`hi` up. It returns a `DomainError` when a bound is NaN, when `lo` is
$+\infty$, when `hi` is $-\infty$ (IEEE 1788 intervals are subsets of
$\mathbb{R}$, so $[+\infty, +\infty]$ is not an interval), or when
`lo > hi`. Infinite bounds on the open side are allowed: $[-\infty, 0]$ is
valid.

### `IntervalResult::entire`

`entire(precision~)` is the entire real line $[-\infty, +\infty]$ (default
precision 53); it never fails.

```mbti
pub fn IntervalResult::entire(precision? : Int) -> Self
```

```moonbit
///|
test "construction validates its inputs" {
  let one = @bin_float.BinFloat::from_int(1)
  let three = @bin_float.BinFloat::from_int(3)
  inspect(show(@interval_checked.IntervalResult::from_bounds(one, three)), content="1p1 +/- 1p0")
  inspect(
    show(@interval_checked.IntervalResult::from_bounds(three, one)),
    content="error: interval lower bound must not exceed upper bound",
  )
  inspect(
    show(@interval_checked.IntervalResult::from_double(0.1, precision=8)),
    content="409p-12 +/- 1p-12",
  )
  inspect(
    show(@interval_checked.IntervalResult::from_double(0.0 / 0.0)),
    content="error: interval double source must be finite",
  )
  let infinity = @bin_float.BinFloat::inf(@def.Sign::Positive)
  inspect(
    show(@interval_checked.IntervalResult::from_bounds(infinity, infinity)),
    content="error: interval lower bound must not be positive infinity",
  )
  inspect(show(@interval_checked.IntervalResult::entire()), content="[-inf, inf]")
}
```

## Observation

### `IntervalResult::result`, `IntervalResult::is_ok`, `IntervalResult::is_err`, `IntervalResult::error`

These methods expose the wrapped `Result`, test its branch, or return the
error as an option.

```mbti
pub fn IntervalResult::result(Self) -> Result[@interval.Interval, @arithmetic.ArithmeticError]
pub fn IntervalResult::is_ok(Self) -> Bool
pub fn IntervalResult::is_err(Self) -> Bool
pub fn IntervalResult::error(Self) -> @arithmetic.ArithmeticError?
```

`error()` is `Some(e)` exactly when `result()` is `Err(e)`.

## Composition

### `IntervalResult::map`, `IntervalResult::bind`

`map(f)` applies an infallible interval function to a success; `bind(f)`
applies one that may fail. Errors pass through unchanged.

```mbti
pub fn IntervalResult::map(Self, (@interval.Interval) -> @interval.Interval) -> Self
pub fn IntervalResult::bind(Self, (@interval.Interval) -> Self) -> Self
```

They satisfy the monad and functor laws proved in the
[`bin_float_checked` design](../design/bin_float_checked.md#the-monad-laws);
the proof does not depend on the value type.

## Unary value maps

### `IntervalResult::neg`, `IntervalResult::abs`, `IntervalResult::normalized`, `IntervalResult::with_precision`

These methods are `map` of the `Interval` method of the same name.

```mbti
pub fn IntervalResult::neg(Self) -> Self
pub fn IntervalResult::abs(Self) -> Self
pub fn IntervalResult::normalized(Self) -> Self
pub fn IntervalResult::with_precision(Self, Int) -> Self
```

`neg` and `abs` are the exact interval images $\{-t\}$ and $\{|t|\}$;
`with_precision` rounds the endpoints outward to the new precision, which is
the tightest enclosure of the input. Neither it nor `normalized` changes an interval that is already
representable at the target precision (see
[`Interval::with_precision`](interval.md#intervalwith_precision)).

## Arithmetic

### `IntervalResult::add`, `IntervalResult::sub`, `IntervalResult::mul`, `IntervalResult::div`

These methods combine two wrappers with the `Interval` operators.

```mbti
pub fn IntervalResult::add(Self, Self) -> Self
pub fn IntervalResult::sub(Self, Self) -> Self
pub fn IntervalResult::mul(Self, Self) -> Self
pub fn IntervalResult::div(Self, Self) -> Self
```

The left operand's error comes first, then the right one's. Interval
arithmetic itself never fails: the result encloses
$\{\, s \circ t : s \in X, t \in Y \,\}$. Division by an interval that is
exactly $\{0\}$ gives the empty set, and division by an interval that contains
zero in its interior gives the whole line.

### `IntervalResult::sqrt`, `IntervalResult::sqr`, `IntervalResult::recip`

These methods are `map` of the `Interval` method of the same name (IEEE
1788-2015 Table 9.1): the directed square root, the square of one point
(`sqr`, so the square of $[-1, 1]$ is $[0, 1]$) and the reciprocal. None of
them can fail.

```mbti
pub fn IntervalResult::sqrt(Self) -> Self
pub fn IntervalResult::sqr(Self) -> Self
pub fn IntervalResult::recip(Self) -> Self
```

### `IntervalResult::sign`, `IntervalResult::ceil`, `IntervalResult::floor`, `IntervalResult::trunc`, `IntervalResult::round_ties_to_even`, `IntervalResult::round_ties_to_away`

These methods are `map` of the `Interval` integer functions of Table 9.1
(see the [`interval` page](interval.md#intervalsign-intervalceil-intervalfloor-intervaltrunc-intervalround_ties_to_even-intervalround_ties_to_away)).
They are exact and cannot fail.

```mbti
pub fn IntervalResult::sign(Self) -> Self
pub fn IntervalResult::ceil(Self) -> Self
pub fn IntervalResult::floor(Self) -> Self
pub fn IntervalResult::trunc(Self) -> Self
pub fn IntervalResult::round_ties_to_even(Self) -> Self
pub fn IntervalResult::round_ties_to_away(Self) -> Self
```

### `IntervalResult::sqr_rev`, `IntervalResult::abs_rev`, `IntervalResult::pown_rev` and `IntervalResult::cosh_rev`

These methods apply the `Interval` method of the same name to the interval part
(see the [`interval` page](interval.md#intervalsqr_rev-intervalabs_rev-intervalpown_rev-and-intervalcosh_rev)).
They cannot fail themselves; an earlier failure in the receiver or in the
optional prior is passed on.

```mbti
pub fn IntervalResult::sqr_rev(Self, x? : Self) -> Self
pub fn IntervalResult::abs_rev(Self, x? : Self) -> Self
pub fn IntervalResult::pown_rev(Self, Int, x? : Self) -> Self
pub fn IntervalResult::cosh_rev(Self, x? : Self) -> Self
```

### `IntervalResult::sin_rev`, `IntervalResult::cos_rev` and `IntervalResult::tan_rev`

These methods apply the `Interval` method of the same name to the interval part (see the
[`interval` page](interval.md#intervalsin_rev-intervalcos_rev-and-intervaltan_rev)).
They cannot fail themselves; an earlier failure in the receiver or in the optional prior is
passed on.

```mbti
pub fn IntervalResult::sin_rev(Self, x? : Self) -> Self
pub fn IntervalResult::cos_rev(Self, x? : Self) -> Self
pub fn IntervalResult::tan_rev(Self, x? : Self) -> Self
```

### `IntervalResult::pow_rev1`

`Interval::pow_rev1` on the interval parts (see the [`interval` page](interval.md#intervalpow_rev1)).
It cannot fail itself; an earlier failure in the receiver, in `c` or in the optional prior is passed on.

```mbti
pub fn IntervalResult::pow_rev1(Self, Self, x? : Self) -> Self
```

### `IntervalResult::pow_rev2`

`Interval::pow_rev2` on the interval parts (see the [`interval` page](interval.md#intervalpow_rev2)).
It cannot fail itself; an earlier failure in the receiver, in `c` or in the optional prior is passed on.

```mbti
pub fn IntervalResult::pow_rev2(Self, Self, x? : Self) -> Self
```

### `IntervalResult::atan2_rev1` and `IntervalResult::atan2_rev2`

`Interval::atan2_rev1` and `Interval::atan2_rev2` on the interval parts (see the [`interval` page](interval.md#intervalatan2_rev1-and-intervalatan2_rev2)).
They cannot fail themselves; an earlier failure in the receiver, in `c` or in the optional prior is passed on.

```mbti
pub fn IntervalResult::atan2_rev1(Self, Self, x? : Self) -> Self
pub fn IntervalResult::atan2_rev2(Self, Self, x? : Self) -> Self
```

### `IntervalResult::from_string`

`Interval::from_string` (see the [`interval` page](interval.md#intervalfrom_string-and-decoratedintervalfrom_string)) as a result: the failed call is the failure of the result.

```mbti
pub fn IntervalResult::from_string(String, precision? : Int32) -> Self
```

### `IntervalResult::mul_rev` and `IntervalResult::mul_rev_to_pair`

These methods apply `Interval::mul_rev` and `Interval::mul_rev_to_pair` to
the interval parts (see the [`interval` page](interval.md#intervalmul_rev_to_pair-and-intervalmul_rev)).
They cannot fail themselves; an earlier failure in an input is passed on, and
for `mul_rev_to_pair` both outputs carry it. `x` is optional.

```mbti
pub fn IntervalResult::mul_rev(Self, Self, x? : Self) -> Self
pub fn IntervalResult::mul_rev_to_pair(Self, Self) -> (Self, Self)
```

### `IntervalResult::min`, `IntervalResult::max`, `IntervalResult::fma`, `IntervalResult::intersection`, `IntervalResult::convex_hull`, `IntervalResult::cancel_plus`, `IntervalResult::cancel_minus`

These methods combine two or three wrappers with the `Interval` method of the
same name (Table 9.1 `min`, `max`, `fma`; 9.2 and 9.3 the cancellative and set
operations). The first error comes first, in argument order, as for `add`.

```mbti
pub fn IntervalResult::min(Self, Self) -> Self
pub fn IntervalResult::max(Self, Self) -> Self
pub fn IntervalResult::fma(Self, Self, Self) -> Self
pub fn IntervalResult::intersection(Self, Self) -> Self
pub fn IntervalResult::convex_hull(Self, Self) -> Self
pub fn IntervalResult::cancel_plus(Self, Self) -> Self
pub fn IntervalResult::cancel_minus(Self, Self) -> Self
```

### `IntervalResult::pown`

`pown` raises an interval to an integer power through the
Luna-Flow/arithmetic trait `PowIntChecked`.

```mbti
pub fn IntervalResult::pown(Self, Int) -> Self
```

The context is `ArithmeticContext::new(x.precision())`; `interval` uses only
its precision, and re-rounds the base and the result outward with
`with_precision`, which adds nothing when they are already representable. `pown` encloses $\{t^{n}\}$ with
`Interval::pown`, which treats the base as one point (so `pown(2)` of
$[-1, 1]$ is $[0, 1]$, tighter than `x * x`, which is $[-1, 1]$). A zero base
with a negative exponent gives the empty set. An empty base stays empty for
every exponent, including `pown(0)`. There is no `pow_nat` here: a
non-negative exponent is a `pown`, and the trait form
`Interval::pow_nat_checked` takes a `UInt`.

### `IntervalResult::rootn`

`rootn(n)` encloses the real $n$-th root with `Interval::try_rootn`.

```mbti
pub fn IntervalResult::rootn(Self, Int) -> Self
```

Degree $0$ gives a `DomainError`. Even roots ignore the negative part of the
interval (set semantics): the root of $[-1, 1]$ is $[0, 1]$.

### `IntervalResult::pow`, `IntervalResult::hypot`, `IntervalResult::atan2`

These binary functions enclose $x^{y}$, $\sqrt{x^2+y^2}$ and the angle of
$(\text{abscissa}, \text{self})$.

```mbti
pub fn IntervalResult::pow(Self, Self) -> Self
pub fn IntervalResult::hypot(Self, Self) -> Self
pub fn IntervalResult::atan2(Self, Self) -> Self
```

They call `try_pow`, `try_hypot` and `try_atan2`. Operand
errors are taken left first; the operation can fail with a
`CertificationFailure`. Points outside the real domain are dropped from the
result set, so $(-2)^{0.5}$ is the empty interval.

```moonbit
///|
test "interval arithmetic in the wrapper" {
  let x = @interval_checked.IntervalResult::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_int(3),
  )
  inspect(show(x * x - x), content="3p0 +/- 5p0")
  inspect(show(x.pown(2)), content="5p0 +/- 1p2")
  let unit = @interval_checked.IntervalResult::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(show(unit.pown(2)), content="1p-1 +/- 1p-1")
  let one = @interval_checked.IntervalResult::from_int(1)
  let zero = @interval_checked.IntervalResult::from_int(0)
  inspect(show(one / zero), content="[empty]")
  let around_zero = @interval_checked.IntervalResult::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(show(one / around_zero), content="[-inf, inf]")
  inspect(show(around_zero.rootn(2)), content="1p-1 +/- 1p-1")
  inspect(show(x.rootn(0)), content="error: rootn degree must not be zero")
}
```

## Elementary functions

### `IntervalResult::exp`, `IntervalResult::exp2`, `IntervalResult::exp10`, `IntervalResult::expm1`, `IntervalResult::ln`, `IntervalResult::log2`, `IntervalResult::log10`, `IntervalResult::log1p`

These methods enclose the image of the interval under the exponentials and
logarithms.

```mbti
pub fn IntervalResult::exp(Self) -> Self
pub fn IntervalResult::exp2(Self) -> Self
pub fn IntervalResult::exp10(Self) -> Self
pub fn IntervalResult::expm1(Self) -> Self
pub fn IntervalResult::ln(Self) -> Self
pub fn IntervalResult::log2(Self) -> Self
pub fn IntervalResult::log10(Self) -> Self
pub fn IntervalResult::log1p(Self) -> Self
```

### `IntervalResult::sin`, `IntervalResult::cos`, `IntervalResult::tan`, `IntervalResult::sinpi`, `IntervalResult::cospi`, `IntervalResult::tanpi`, `IntervalResult::asin`, `IntervalResult::acos`, `IntervalResult::atan`

These methods enclose the image of the interval under the trigonometric
functions and their inverses.

```mbti
pub fn IntervalResult::sin(Self) -> Self
pub fn IntervalResult::cos(Self) -> Self
pub fn IntervalResult::tan(Self) -> Self
pub fn IntervalResult::sinpi(Self) -> Self
pub fn IntervalResult::cospi(Self) -> Self
pub fn IntervalResult::tanpi(Self) -> Self
pub fn IntervalResult::asin(Self) -> Self
pub fn IntervalResult::acos(Self) -> Self
pub fn IntervalResult::atan(Self) -> Self
```

### `IntervalResult::sinh`, `IntervalResult::cosh`, `IntervalResult::tanh`, `IntervalResult::asinh`, `IntervalResult::acosh`, `IntervalResult::atanh`

These methods enclose the image of the interval under the hyperbolic
functions and their inverses.

```mbti
pub fn IntervalResult::sinh(Self) -> Self
pub fn IntervalResult::cosh(Self) -> Self
pub fn IntervalResult::tanh(Self) -> Self
pub fn IntervalResult::asinh(Self) -> Self
pub fn IntervalResult::acosh(Self) -> Self
pub fn IntervalResult::atanh(Self) -> Self
```

Each method is `bind` of `Interval::try_<name>_interval` at the interval's
precision. The result $Y$ satisfies $f(X \cap \operatorname{dom} f) \subseteq
Y$; parts of $X$ outside the domain are ignored, so $\ln([-1, 1]) =
[-\infty, 0]$ and $\ln([-2, -2])$ is empty. The only error is a
`CertificationFailure` when an enclosure cannot be certified, for example the
cosine of $2^{8000000}$ (reason `ResourceLimit`). There are no context variants;
precision is set with `with_precision`.

```moonbit
///|
test "elementary enclosures" {
  let two = @interval_checked.IntervalResult::from_int(2, precision=53)
  inspect(show(two.ln()), content="12486629536330719p-54 +/- 1p-54")
  inspect(show(two.ln().exp()), content="18014398509481985p-53 +/- 3p-53")
  let around_zero = @interval_checked.IntervalResult::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(show(around_zero.ln()), content="[-inf, 0]")
  let huge = @interval_checked.IntervalResult::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 8000000, 53),
  )
  match huge.cos().error() {
    Some(e) => {
      let detail = e.certification_failure_detail().unwrap()
      inspect(detail.operation(), content="cos")
      inspect(
        detail.reason() == @lf_arith.CertificationFailureReason::ResourceLimit,
        content="true",
      )
    }
    None => fail("expected a certification failure")
  }
}
```

## Trait implementations

### `Add`, `Sub`, `Mul`, `Div`, `Neg` for `IntervalResult`

The operators `+`, `-`, `*`, `/` and unary `-` call `add`, `sub`, `mul`, `div`
and `neg`.

```mbti
pub impl Add for IntervalResult
pub impl Sub for IntervalResult
pub impl Mul for IntervalResult
pub impl Neg for IntervalResult
pub impl Div for IntervalResult
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/interval_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/interval",
}

// Values

// Errors

// Types and methods
pub struct IntervalResult {
  // private fields
}
pub fn IntervalResult::abs(Self) -> Self
pub fn IntervalResult::abs_rev(Self, x? : Self) -> Self
pub fn IntervalResult::acos(Self) -> Self
pub fn IntervalResult::acosh(Self) -> Self
pub fn IntervalResult::add(Self, Self) -> Self
pub fn IntervalResult::asin(Self) -> Self
pub fn IntervalResult::asinh(Self) -> Self
pub fn IntervalResult::atan(Self) -> Self
pub fn IntervalResult::atan2(Self, Self) -> Self
pub fn IntervalResult::atan2_rev1(Self, Self, x? : Self) -> Self
pub fn IntervalResult::atan2_rev2(Self, Self, x? : Self) -> Self
pub fn IntervalResult::atanh(Self) -> Self
pub fn IntervalResult::bind(Self, (@interval.Interval) -> Self) -> Self
pub fn IntervalResult::cancel_minus(Self, Self) -> Self
pub fn IntervalResult::cancel_plus(Self, Self) -> Self
pub fn IntervalResult::ceil(Self) -> Self
pub fn IntervalResult::convex_hull(Self, Self) -> Self
pub fn IntervalResult::cos(Self) -> Self
pub fn IntervalResult::cos_rev(Self, x? : Self) -> Self
pub fn IntervalResult::cosh(Self) -> Self
pub fn IntervalResult::cosh_rev(Self, x? : Self) -> Self
pub fn IntervalResult::cospi(Self) -> Self
pub fn IntervalResult::div(Self, Self) -> Self
pub fn IntervalResult::entire(precision? : Int32) -> Self
pub fn IntervalResult::err(@arithmetic.ArithmeticError) -> Self
pub fn IntervalResult::error(Self) -> @arithmetic.ArithmeticError?
pub fn IntervalResult::exact(@bin_float.BinFloat, precision? : Int32) -> Self
pub fn IntervalResult::exp(Self) -> Self
pub fn IntervalResult::exp10(Self) -> Self
pub fn IntervalResult::exp2(Self) -> Self
pub fn IntervalResult::expm1(Self) -> Self
pub fn IntervalResult::floor(Self) -> Self
pub fn IntervalResult::fma(Self, Self, Self) -> Self
pub fn IntervalResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int32) -> Self
pub fn IntervalResult::from_coefficient(@bin_float.BinCoeff, precision? : Int32, negative? : Bool) -> Self
pub fn IntervalResult::from_double(Double, precision? : Int32) -> Self
pub fn IntervalResult::from_float(Float, precision? : Int32) -> Self
pub fn IntervalResult::from_int(Int32, precision? : Int32) -> Self
pub fn IntervalResult::from_result(Result[@interval.Interval, @arithmetic.ArithmeticError]) -> Self
pub fn IntervalResult::from_string(String, precision? : Int32) -> Self
pub fn IntervalResult::hypot(Self, Self) -> Self
pub fn IntervalResult::intersection(Self, Self) -> Self
pub fn IntervalResult::is_err(Self) -> Bool
pub fn IntervalResult::is_ok(Self) -> Bool
pub fn IntervalResult::ln(Self) -> Self
pub fn IntervalResult::log10(Self) -> Self
pub fn IntervalResult::log1p(Self) -> Self
pub fn IntervalResult::log2(Self) -> Self
pub fn IntervalResult::map(Self, (@interval.Interval) -> @interval.Interval) -> Self
pub fn IntervalResult::max(Self, Self) -> Self
pub fn IntervalResult::min(Self, Self) -> Self
pub fn IntervalResult::mul(Self, Self) -> Self
pub fn IntervalResult::mul_rev(Self, Self, x? : Self) -> Self
pub fn IntervalResult::mul_rev_to_pair(Self, Self) -> (Self, Self)
pub fn IntervalResult::neg(Self) -> Self
pub fn IntervalResult::normalized(Self) -> Self
pub fn IntervalResult::ok(@interval.Interval) -> Self
pub fn IntervalResult::pow(Self, Self) -> Self
pub fn IntervalResult::pow_rev1(Self, Self, x? : Self) -> Self
pub fn IntervalResult::pow_rev2(Self, Self, x? : Self) -> Self
pub fn IntervalResult::pown(Self, Int32) -> Self
pub fn IntervalResult::pown_rev(Self, Int32, x? : Self) -> Self
pub fn IntervalResult::recip(Self) -> Self
pub fn IntervalResult::result(Self) -> Result[@interval.Interval, @arithmetic.ArithmeticError]
pub fn IntervalResult::rootn(Self, Int32) -> Self
pub fn IntervalResult::round_ties_to_away(Self) -> Self
pub fn IntervalResult::round_ties_to_even(Self) -> Self
pub fn IntervalResult::sign(Self) -> Self
pub fn IntervalResult::sin(Self) -> Self
pub fn IntervalResult::sin_rev(Self, x? : Self) -> Self
pub fn IntervalResult::sinh(Self) -> Self
pub fn IntervalResult::sinpi(Self) -> Self
pub fn IntervalResult::sqr(Self) -> Self
pub fn IntervalResult::sqr_rev(Self, x? : Self) -> Self
pub fn IntervalResult::sqrt(Self) -> Self
pub fn IntervalResult::sub(Self, Self) -> Self
pub fn IntervalResult::tan(Self) -> Self
pub fn IntervalResult::tan_rev(Self, x? : Self) -> Self
pub fn IntervalResult::tanh(Self) -> Self
pub fn IntervalResult::tanpi(Self) -> Self
pub fn IntervalResult::trunc(Self) -> Self
pub fn IntervalResult::with_precision(Self, Int32) -> Self
pub impl Add for IntervalResult
pub impl Div for IntervalResult
pub impl Mul for IntervalResult
pub impl Neg for IntervalResult
pub impl Sub for IntervalResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
