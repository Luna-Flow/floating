# `ball_float_checked` API

`ball_float_checked` provides `BallFloatResult`, a closed wrapper around
`Result[BallFloat, ArithmeticError]` for interval computations. Construction
validates its inputs, every operation passes on the first error, and the
interval operations of [`ball_float`](ball_float.md) are applied when all
operands are successes. A valid but uninformative enclosure (the empty set, the
whole line) is a success, not an error. The wrapper stores no decorations and
no `BallFlags`. The [tutorial](../tutorial/ball_float_checked.md) builds
pipelines; the [design page](../design/ball_float_checked.md) explains which
outcomes are errors and why.

The examples print a result with this helper (`to_string` of a bounded ball is
`centre +/- radius` in exact binary notation, `mpe` meaning
$m \cdot 2^{e}$):

```moonbit
///|
fn show(r : @ball_float_checked.BallFloatResult) -> String {
  match r.result() {
    Ok(v) => v.to_string()
    Err(e) => "error: " + e.message
  }
}
```

## The wrapper type

### `BallFloatResult`

`BallFloatResult` is either a successful `BallFloat` or an `ArithmeticError`.

```mbti
pub struct BallFloatResult {
  // private fields
}
```

The single private field holds a `Result[@ball_float.BallFloat,
@arithmetic.ArithmeticError]`. The type has no `Eq` or `Show`; use `result()`.

## Construction

### `BallFloatResult::ok`, `BallFloatResult::err`, `BallFloatResult::from_result`

These functions wrap an existing interval, error or `Result` unchanged.

```mbti
pub fn BallFloatResult::ok(@ball_float.BallFloat) -> Self
pub fn BallFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BallFloatResult::from_result(Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]) -> Self
```

### `BallFloatResult::from_int`, `BallFloatResult::from_coefficient`

These constructors build a point interval from an integer through
`BallFloat::from_int` / `BallFloat::from_coefficient`; they never fail.

```mbti
pub fn BallFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BallFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
```

The default precision is **16 bits**. The integer is first converted to a
`BinFloat` at $\max(\textit{precision}, 8)$ bits with nearest rounding and then
enclosed.

> [!WARNING]
> On the current branch the first conversion rounds, so an integer that needs
> more bits than the precision is not enclosed: `from_int(100001)` (17 bits)
> is the point $100000$. Pass a precision large enough for the integer, or use
> `from_bounds`, which rounds outward.

### `BallFloatResult::from_double`, `BallFloatResult::from_float`

These constructors enclose a finite `Double` or `Float`.

```mbti
pub fn BallFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BallFloatResult::from_float(Float, precision? : Int) -> Self
```

The source is converted exactly (at least 53 or 24 bits) and then rounded
outward to `precision` (defaults 53 and 24), so the result always contains the
source value. A NaN or infinite source gives a `DomainError`
(`ball double source must be finite`, `ball float source must be finite`).

### `BallFloatResult::exact`

`exact(x, precision~)` encloses a finite `BinFloat`.

```mbti
pub fn BallFloatResult::exact(@bin_float.BinFloat, precision? : Int) -> Self
```

`precision` defaults to `x.precision()`. The bounds are `x` rounded down and up
to that precision, so the result contains `x`. A non-finite `x` gives a
`DomainError` (`ball exact source must be finite`).

### `BallFloatResult::from_bounds`

`from_bounds(lo, hi, precision~)` builds the interval $[\textit{lo},
\textit{hi}]$.

```mbti
pub fn BallFloatResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
```

`precision` defaults to the larger bound precision; `lo` is rounded down and
`hi` up. It returns a `DomainError` when a bound is NaN, when `lo` is
$+\infty$, when `hi` is $-\infty$ (IEEE 1788 intervals are subsets of
$\mathbb{R}$, so $[+\infty, +\infty]$ is not an interval), or when
`lo > hi`. Infinite bounds on the open side are allowed: $[-\infty, 0]$ is
valid.

### `BallFloatResult::whole`

`whole(precision~)` is the entire real line $[-\infty, +\infty]$ (default
precision 53); it never fails.

```mbti
pub fn BallFloatResult::whole(precision? : Int) -> Self
```

```moonbit
///|
test "construction validates its inputs" {
  let one = @bin_float.BinFloat::from_int(1)
  let three = @bin_float.BinFloat::from_int(3)
  inspect(show(@ball_float_checked.BallFloatResult::from_bounds(one, three)), content="1p1 +/- 1p0")
  inspect(
    show(@ball_float_checked.BallFloatResult::from_bounds(three, one)),
    content="error: ball lower bound must not exceed upper bound",
  )
  inspect(
    show(@ball_float_checked.BallFloatResult::from_double(0.1, precision=8)),
    content="409p-12 +/- 1p-12",
  )
  inspect(
    show(@ball_float_checked.BallFloatResult::from_double(0.0 / 0.0)),
    content="error: ball double source must be finite",
  )
  let infinity = @bin_float.BinFloat::inf(@def.Sign::Positive)
  inspect(
    show(@ball_float_checked.BallFloatResult::from_bounds(infinity, infinity)),
    content="error: ball lower bound must not be positive infinity",
  )
  inspect(show(@ball_float_checked.BallFloatResult::whole()), content="[-inf, inf]")
}
```

## Observation

### `BallFloatResult::result`, `is_ok`, `is_err`, `error`

These methods expose the wrapped `Result`, test its branch, or return the
error as an option.

```mbti
pub fn BallFloatResult::result(Self) -> Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]
pub fn BallFloatResult::is_ok(Self) -> Bool
pub fn BallFloatResult::is_err(Self) -> Bool
pub fn BallFloatResult::error(Self) -> @arithmetic.ArithmeticError?
```

`error()` is `Some(e)` exactly when `result()` is `Err(e)`.

## Composition

### `BallFloatResult::map`, `BallFloatResult::bind`

`map(f)` applies an infallible interval function to a success; `bind(f)`
applies one that may fail. Errors pass through unchanged.

```mbti
pub fn BallFloatResult::map(Self, (@ball_float.BallFloat) -> @ball_float.BallFloat) -> Self
pub fn BallFloatResult::bind(Self, (@ball_float.BallFloat) -> Self) -> Self
```

They satisfy the monad and functor laws proved in the
[`bin_float_checked` design](../design/bin_float_checked.md#the-monad-laws);
the proof does not depend on the value type.

## Unary value maps

### `neg`, `abs`, `normalized`, `with_precision`

These methods are `map` of the `BallFloat` method of the same name.

```mbti
pub fn BallFloatResult::neg(Self) -> Self
pub fn BallFloatResult::abs(Self) -> Self
pub fn BallFloatResult::normalized(Self) -> Self
pub fn BallFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

`neg` and `abs` are the exact interval images $\{-t\}$ and $\{|t|\}$;
`with_precision` returns an enclosure of the input at the new precision for
every rounding mode (the mode only steers the centre).

## Arithmetic

### `add`, `sub`, `mul`, `div`

These methods combine two wrappers with the `BallFloat` operators.

```mbti
pub fn BallFloatResult::add(Self, Self) -> Self
pub fn BallFloatResult::sub(Self, Self) -> Self
pub fn BallFloatResult::mul(Self, Self) -> Self
pub fn BallFloatResult::div(Self, Self) -> Self
```

The left operand's error comes first, then the right one's. Interval
arithmetic itself never fails: the result encloses
$\{\, s \circ t : s \in X, t \in Y \,\}$. Division by an interval that is
exactly $\{0\}$ gives the empty set, and division by an interval that contains
zero in its interior gives the whole line.

### `pow_nat`, `pow_int`

These methods raise an interval to an integer power through the
Luna-Flow/arithmetic traits `PowNatChecked` and `PowIntChecked`.

```mbti
pub fn BallFloatResult::pow_nat(Self, UInt) -> Self
pub fn BallFloatResult::pow_int(Self, Int) -> Self
```

The context is `ArithmeticContext::new(x.precision())`; `ball_float` uses only
its precision. The result is the enclosure of $\{t^{n}\}$, computed as a power
(so `pow_int(2)` of $[1, 3]$ is $[1, 9]$, tighter than `x * x` would be for an
interval containing zero). A zero base with a negative exponent gives the empty
set.

### `rootn`

`rootn(n)` encloses the real $n$-th root with `BallFloat::try_rootn`.

```mbti
pub fn BallFloatResult::rootn(Self, Int) -> Self
```

Degree $0$ gives a `DomainError`. Even roots ignore the negative part of the
interval (set semantics): the root of $[-1, 1]$ is $[0, 1]$.

### `pow`, `hypot`, `atan2`

These binary functions enclose $x^{y}$, $\sqrt{x^2+y^2}$ and the angle of
$(\text{abscissa}, \text{self})$.

```mbti
pub fn BallFloatResult::pow(Self, Self) -> Self
pub fn BallFloatResult::hypot(Self, Self) -> Self
pub fn BallFloatResult::atan2(Self, Self) -> Self
```

They call `try_pow_interval`, `try_hypot` and `try_atan2_interval`. Operand
errors are taken left first; the operation can fail with a
`CertificationFailure`. Points outside the real domain are dropped from the
result set, so $(-2)^{0.5}$ is the empty interval.

```moonbit
///|
test "interval arithmetic in the wrapper" {
  let x = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_int(3),
  )
  inspect(show(x * x - x), content="3p0 +/- 5p0")
  inspect(show(x.pow_int(2)), content="5p0 +/- 1p2")
  let one = @ball_float_checked.BallFloatResult::from_int(1)
  let zero = @ball_float_checked.BallFloatResult::from_int(0)
  inspect(show(one / zero), content="[empty]")
  let around_zero = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(show(one / around_zero), content="[-inf, inf]")
  inspect(show(around_zero.rootn(2)), content="1p-1 +/- 1p-1")
  inspect(show(x.rootn(0)), content="error: rootn degree must not be zero")
}
```

## Elementary functions

### Exponentials, logarithms, trigonometric and hyperbolic functions

`exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `sin`, `cos`,
`tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `sinh`, `cosh`,
`tanh`, `asinh`, `acosh` and `atanh` enclose the image of the interval under
the function.

```mbti
pub fn BallFloatResult::exp(Self) -> Self
pub fn BallFloatResult::exp2(Self) -> Self
pub fn BallFloatResult::exp10(Self) -> Self
pub fn BallFloatResult::expm1(Self) -> Self
pub fn BallFloatResult::ln(Self) -> Self
pub fn BallFloatResult::log2(Self) -> Self
pub fn BallFloatResult::log10(Self) -> Self
pub fn BallFloatResult::log1p(Self) -> Self
pub fn BallFloatResult::sin(Self) -> Self
pub fn BallFloatResult::cos(Self) -> Self
pub fn BallFloatResult::tan(Self) -> Self
pub fn BallFloatResult::sinpi(Self) -> Self
pub fn BallFloatResult::cospi(Self) -> Self
pub fn BallFloatResult::tanpi(Self) -> Self
pub fn BallFloatResult::asin(Self) -> Self
pub fn BallFloatResult::acos(Self) -> Self
pub fn BallFloatResult::atan(Self) -> Self
pub fn BallFloatResult::sinh(Self) -> Self
pub fn BallFloatResult::cosh(Self) -> Self
pub fn BallFloatResult::tanh(Self) -> Self
pub fn BallFloatResult::asinh(Self) -> Self
pub fn BallFloatResult::acosh(Self) -> Self
pub fn BallFloatResult::atanh(Self) -> Self
```

Each method is `bind` of `BallFloat::try_<name>_interval` at the interval's
precision. The result $Y$ satisfies $f(X \cap \operatorname{dom} f) \subseteq
Y$; parts of $X$ outside the domain are ignored, so $\ln([-1, 1]) =
[-\infty, 0]$ and $\ln([-2, -2])$ is empty. The only error is a
`CertificationFailure` when an enclosure cannot be certified, for example the
cosine of $2^{70000}$ (reason `ResourceLimit`). There are no context variants;
precision is set with `with_precision`.

```moonbit
///|
test "elementary enclosures" {
  let two = @ball_float_checked.BallFloatResult::from_int(2, precision=53)
  inspect(show(two.ln()), content="12486629536330719p-54 +/- 1p-54")
  inspect(show(two.ln().exp()), content="18014398509481985p-53 +/- 3p-53")
  let around_zero = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(show(around_zero.ln()), content="[-inf, 0]")
  let huge = @ball_float_checked.BallFloatResult::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 70000, 53),
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

### `Add`, `Sub`, `Mul`, `Div`, `Neg`

The operators `+`, `-`, `*`, `/` and unary `-` call `add`, `sub`, `mul`, `div`
and `neg`.

```mbti
pub impl Add for BallFloatResult
pub impl Sub for BallFloatResult
pub impl Mul for BallFloatResult
pub impl Neg for BallFloatResult
pub impl Div for BallFloatResult
```

## Deprecated

### `BallFloatResult::flat_map`

`flat_map` is the former name of `bind`. Replace `r.flat_map(f)` with
`r.bind(f)`.

```mbti
#deprecated
pub fn BallFloatResult::flat_map(Self, (@ball_float.BallFloat) -> Self) -> Self
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BallFloatResult {
  // private fields
}
pub fn BallFloatResult::abs(Self) -> Self
pub fn BallFloatResult::acos(Self) -> Self
pub fn BallFloatResult::acosh(Self) -> Self
pub fn BallFloatResult::add(Self, Self) -> Self
pub fn BallFloatResult::asin(Self) -> Self
pub fn BallFloatResult::asinh(Self) -> Self
pub fn BallFloatResult::atan(Self) -> Self
pub fn BallFloatResult::atan2(Self, Self) -> Self
pub fn BallFloatResult::atanh(Self) -> Self
pub fn BallFloatResult::bind(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::cos(Self) -> Self
pub fn BallFloatResult::cosh(Self) -> Self
pub fn BallFloatResult::cospi(Self) -> Self
pub fn BallFloatResult::div(Self, Self) -> Self
pub fn BallFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BallFloatResult::error(Self) -> @arithmetic.ArithmeticError?
pub fn BallFloatResult::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::exp(Self) -> Self
pub fn BallFloatResult::exp10(Self) -> Self
pub fn BallFloatResult::exp2(Self) -> Self
pub fn BallFloatResult::expm1(Self) -> Self
#deprecated
pub fn BallFloatResult::flat_map(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BallFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BallFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BallFloatResult::from_result(Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BallFloatResult::hypot(Self, Self) -> Self
pub fn BallFloatResult::is_err(Self) -> Bool
pub fn BallFloatResult::is_ok(Self) -> Bool
pub fn BallFloatResult::ln(Self) -> Self
pub fn BallFloatResult::log10(Self) -> Self
pub fn BallFloatResult::log1p(Self) -> Self
pub fn BallFloatResult::log2(Self) -> Self
pub fn BallFloatResult::map(Self, (@ball_float.BallFloat) -> @ball_float.BallFloat) -> Self
pub fn BallFloatResult::mul(Self, Self) -> Self
pub fn BallFloatResult::neg(Self) -> Self
pub fn BallFloatResult::normalized(Self) -> Self
pub fn BallFloatResult::ok(@ball_float.BallFloat) -> Self
pub fn BallFloatResult::pow(Self, Self) -> Self
pub fn BallFloatResult::pow_int(Self, Int) -> Self
pub fn BallFloatResult::pow_nat(Self, UInt) -> Self
pub fn BallFloatResult::result(Self) -> Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]
pub fn BallFloatResult::rootn(Self, Int) -> Self
pub fn BallFloatResult::sin(Self) -> Self
pub fn BallFloatResult::sinh(Self) -> Self
pub fn BallFloatResult::sinpi(Self) -> Self
pub fn BallFloatResult::sub(Self, Self) -> Self
pub fn BallFloatResult::tan(Self) -> Self
pub fn BallFloatResult::tanh(Self) -> Self
pub fn BallFloatResult::tanpi(Self) -> Self
pub fn BallFloatResult::whole(precision? : Int) -> Self
pub fn BallFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BallFloatResult
pub impl Div for BallFloatResult
pub impl Mul for BallFloatResult
pub impl Neg for BallFloatResult
pub impl Sub for BallFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
