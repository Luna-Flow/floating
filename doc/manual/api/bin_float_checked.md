# bin_float_checked API

## Purpose

`bin_float_checked` provides `BinFloatResult`, a closed wrapper around
`Result[BinFloat, ArithmeticError]`. Every operation takes and returns a
`BinFloatResult`, applies the corresponding [`bin_float`](bin_float.md)
operation when all operands are successes, and otherwise passes on the first
error without running the operation. The wrapper keeps no IEEE flags. The
[tutorial](../tutorial/bin_float_checked.md) builds pipelines step by step; the
[design page](../design/bin_float_checked.md) models the wrapper as the error
monad and proves the composition laws it relies on.

## Importing

Add the wrapper and the packages whose types appear in its signatures to your
`moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/bin_float_checked",
  "Luna-Flow/floating/def",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples call the packages as `@bin_float_checked.`, `@bin_float.`,
`@def.` and `@lf_arith.` (`Luna-Flow/arithmetic`, printed as `@arithmetic` in
the interface). They print a result with this helper:

```moonbit
///|
fn show(r : @bin_float_checked.BinFloatResult) -> String {
  match r.result() {
    Ok(v) => v.to_string()
    Err(e) => "error: " + e.message
  }
}
```

`BinFloat::to_string` prints the exact value as `coefficient p exponent`, so
`3p-1` is $3 \cdot 2^{-1} = 1.5$.

## The wrapper type

### `BinFloatResult`

`BinFloatResult` is either a successful `BinFloat` or an `ArithmeticError`.

```mbti
pub struct BinFloatResult {
  // private fields
}
```

The only field is private; it holds a `Result[@bin_float.BinFloat,
@arithmetic.ArithmeticError]`. The type has no `Eq` or `Show` instance; compare
or print through `result()`.

## Construction

### `BinFloatResult::ok`, `BinFloatResult::err`, `BinFloatResult::from_result`

These functions wrap an existing value, error or `Result` without changing it.

```mbti
pub fn BinFloatResult::ok(@bin_float.BinFloat) -> Self
pub fn BinFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BinFloatResult::from_result(Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]) -> Self
```

`from_result(r).result() == r` for every `r`, and `ok(x)` is the unit of the
monad described in the design page.

### `BinFloatResult::from_int`, `BinFloatResult::from_coefficient`, `BinFloatResult::from_double`, `BinFloatResult::from_float`

These constructors build a successful wrapper from a MoonBit number through the
matching `BinFloat` constructor.

```mbti
pub fn BinFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BinFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BinFloatResult::from_float(Float, precision? : Int) -> Self
```

| Constructor | Default `precision` | Delegates to |
| --- | --- | --- |
| `from_int` | 53 | `BinFloat::from_int` |
| `from_coefficient` | 53 (`negative` defaults to `false`) | `BinFloat::from_coefficient` |
| `from_double` | 53 | `BinFloat::from_double` |
| `from_float` | 24 | `BinFloat::from_float` |

They never produce an error: NaN and infinity inputs become successful NaN or
infinite values, and a value that does not fit `precision` is rounded to
nearest-even as by the delegated constructor. `from_float` widens through a
host `Double`, so a signaling `Float` NaN may arrive quiet (see
[`BinFloat::from_float`](bin_float.md#binfloatfrom_double-binfloatfrom_float)).

## Observation

### `BinFloatResult::result`, `BinFloatResult::is_ok`, `BinFloatResult::is_err`

These methods expose the wrapped `Result` and test its branch.

```mbti
pub fn BinFloatResult::result(Self) -> Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]
pub fn BinFloatResult::is_ok(Self) -> Bool
pub fn BinFloatResult::is_err(Self) -> Bool
```

`is_err(r) == !is_ok(r)`. Call `result()` once, at the boundary where the
error is handled.

## Composition

### `BinFloatResult::map`

`map(f)` applies an infallible function to a success and leaves an error
unchanged.

```mbti
pub fn BinFloatResult::map(Self, (@bin_float.BinFloat) -> @bin_float.BinFloat) -> Self
```

$\texttt{map}(\texttt{Ok}(x), f) = \texttt{Ok}(f(x))$ and
$\texttt{map}(\texttt{Err}(e), f) = \texttt{Err}(e)$; `f` is not called on an
error. `map` can never turn a success into an error.

### `BinFloatResult::bind`

`bind(f)` applies a function that may itself fail.

```mbti
pub fn BinFloatResult::bind(Self, (@bin_float.BinFloat) -> Self) -> Self
```

$\texttt{bind}(\texttt{Ok}(x), f) = f(x)$ and
$\texttt{bind}(\texttt{Err}(e), f) = \texttt{Err}(e)$. With `ok` it satisfies
the monad laws (left and right identity, associativity), derived in the
[design page](../design/bin_float_checked.md#the-monad-laws).

```moonbit
///|
test "map and bind" {
  let halve = fn(x : @bin_float.BinFloat) { x * @bin_float.BinFloat::from_double(0.5) }
  let positive = fn(x : @bin_float.BinFloat) {
    if x.sign() == @def.Sign::Positive {
      @bin_float_checked.BinFloatResult::ok(x)
    } else {
      @bin_float_checked.BinFloatResult::err(
        @lf_arith.ArithmeticError::domain_error("expected a positive value"),
      )
    }
  }
  let good = @bin_float_checked.BinFloatResult::from_int(3).map(halve).bind(positive)
  inspect(show(good), content="3p-1")
  let bad = @bin_float_checked.BinFloatResult::from_int(-3).bind(positive).map(halve)
  inspect(show(bad), content="error: expected a positive value")
}
```

## Unary value maps

### `BinFloatResult::neg`, `BinFloatResult::abs`, `BinFloatResult::ulp`, `BinFloatResult::normalized`, `BinFloatResult::with_precision`

These methods are `map` of the `BinFloat` method of the same name; they never
introduce an error.

```mbti
pub fn BinFloatResult::neg(Self) -> Self
pub fn BinFloatResult::abs(Self) -> Self
pub fn BinFloatResult::ulp(Self) -> Self
pub fn BinFloatResult::normalized(Self) -> Self
pub fn BinFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

`with_precision(p, mode)` rounds to $\max(1,p)$ bits in direction `mode` with
an unbounded exponent; `ulp` is the unit in the last place at the value's
precision (NaN for non-finite values).

## Arithmetic

### `BinFloatResult::add`, `BinFloatResult::sub`, `BinFloatResult::mul`

These methods combine two wrappers with the `BinFloat` operator.

```mbti
pub fn BinFloatResult::add(Self, Self) -> Self
pub fn BinFloatResult::sub(Self, Self) -> Self
pub fn BinFloatResult::mul(Self, Self) -> Self
```

If `self` is an error it is returned; otherwise if `other` is an error that
error is returned; otherwise the result is `Ok(lhs op rhs)`. The `BinFloat`
operators round to nearest-even at the larger of the two operand precisions and
never fail: invalid cases such as $\infty - \infty$ produce a successful NaN.

### `BinFloatResult::div`

`div` divides two wrappers and reports division by a zero.

```mbti
pub fn BinFloatResult::div(Self, Self) -> Self
```

After the operand errors (left first), the result is
`BinFloat::div_checked(lhs, rhs)`: a `DivisionByZero` error when the divisor is
a finite zero ($\pm 0$), whatever the dividend (including $0/0$ and NaN$/0$),
and the rounded quotient otherwise.

### `BinFloatResult::min`, `BinFloatResult::max`

These methods take the smaller or larger operand with `BinFloat::min` /
`BinFloat::max`, which ignore a NaN operand in favour of the other one and
return the receiver when the operands compare equal (so `min(-0, +0)` is
$-0$ and `min(+0, -0)` is $+0$).

```mbti
pub fn BinFloatResult::min(Self, Self) -> Self
pub fn BinFloatResult::max(Self, Self) -> Self
```

### `BinFloatResult::clamp`

`clamp(min~, max~)` restricts a value to an interval.

```mbti
pub fn BinFloatResult::clamp(Self, min~ : Self, max~ : Self) -> Self
```

Errors are taken in the order `self`, `min`, `max`; then
`BinFloat::clamp_checked` returns a `DomainError` when a bound is NaN or when
`min > max`, and the clamped value otherwise.

```moonbit
///|
test "arithmetic keeps the first error" {
  let one = @bin_float_checked.BinFloatResult::from_int(1)
  let zero = @bin_float_checked.BinFloatResult::from_int(0)
  inspect(show(one + one * one), content="1p1")
  inspect(show(one / zero), content="error: division by zero")
  let left = @bin_float_checked.BinFloatResult::err(
    @lf_arith.ArithmeticError::unsupported("left"),
  )
  inspect(show(left + one / zero), content="error: left")
  inspect(show(one / zero + left), content="error: division by zero")
  let clamped = @bin_float_checked.BinFloatResult::from_int(5).clamp(
    min=zero,
    max=@bin_float_checked.BinFloatResult::from_int(3),
  )
  inspect(show(clamped), content="3p0")
  let reversed = one.clamp(min=@bin_float_checked.BinFloatResult::from_int(3), max=zero)
  inspect(show(reversed), content="error: min must not exceed max")
}
```

## Contextual arithmetic

### `BinFloatResult::add_ctx`, `BinFloatResult::sub_ctx`, `BinFloatResult::mul_ctx`, `BinFloatResult::div_ctx`

These methods apply the `BinFloat::*_ctx` operation under an explicit
`BinaryContext` and keep only its value.

```mbti
pub fn BinFloatResult::add_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sub_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::mul_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::div_ctx(Self, Self, @bin_float.BinaryContext) -> Self
```

The result has the context's precision, rounding direction and exponent range,
with IEEE overflow, underflow and subnormal handling. The `BinaryFlags` of the
step are **discarded**, and IEEE exceptional cases are successful values:
`div_ctx` by zero returns $\pm\infty$ (or NaN for $0/0$) where `div` returns an
error. Use `bin_float` directly when the flags matter.

```moonbit
///|
test "context arithmetic rounds to the context and drops flags" {
  let binary32 = @bin_float.BinaryContext::binary32()
  let tenth = @bin_float_checked.BinFloatResult::from_double(0.1)
  let zero = @bin_float_checked.BinFloatResult::from_int(0)
  inspect(show(tenth.add_ctx(zero, binary32)), content="13421773p-27")
  let one = @bin_float_checked.BinFloatResult::from_int(1)
  inspect(show(one.div_ctx(zero, binary32)), content="inf")
  inspect(show(one.div(zero)), content="error: division by zero")
}
```

## Powers and roots

### `BinFloatResult::sqrt`, `BinFloatResult::sqrt_ctx`

`sqrt` takes the square root at the operand's precision; `sqrt_ctx` under a
context.

```mbti
pub fn BinFloatResult::sqrt(Self) -> Self
pub fn BinFloatResult::sqrt_ctx(Self, @bin_float.BinaryContext) -> Self
```

`sqrt` is `BinFloat::sqrt`, which returns a `DomainError` for a negative
non-zero argument, including $-\infty$ and a NaN whose sign bit is set;
$\sqrt{-0} = -0$ and a positive NaN gives a successful NaN. `sqrt_ctx` never
fails: a negative argument gives a successful NaN (the invalid flag is
dropped).

### `BinFloatResult::pow_nat`, `BinFloatResult::pow_int`, `BinFloatResult::pow_int_ctx`, `BinFloatResult::pown`, `BinFloatResult::pown_ctx`

These methods raise a value to an integer power.

```mbti
pub fn BinFloatResult::pow_nat(Self, UInt) -> Self
pub fn BinFloatResult::pow_int(Self, Int) -> Self
pub fn BinFloatResult::pow_int_ctx(Self, Int, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::pown(Self, Int) -> Self
pub fn BinFloatResult::pown_ctx(Self, Int, @bin_float.BinaryContext) -> Self
```

`pow_nat(n)` calls the Luna-Flow/arithmetic trait method
`PowNatChecked::pow_nat_checked` with `ArithmeticContext::new(x.precision())`,
which `bin_float` maps to an unbounded binary context at that precision with
nearest-even rounding. `pow_int` and `pown` (the same operation, IEEE name)
return a `DivisionByZero` error for a zero base with a negative exponent and
the rounded power otherwise, at the operand's precision. The `_ctx` forms
never fail and return $\pm\infty$ for a zero base with a negative exponent.

### `BinFloatResult::rootn`, `BinFloatResult::rootn_ctx`

`rootn(n)` computes the real $n$-th root with `BinFloat::try_rootn_ctx`.

```mbti
pub fn BinFloatResult::rootn(Self, Int) -> Self
pub fn BinFloatResult::rootn_ctx(Self, Int, @bin_float.BinaryContext) -> Self
```

`rootn` uses an unbounded context at the operand's precision; `rootn_ctx` the
given context. Both report a `DomainError` for degree $0$ and for an even root
of a negative finite number, and can report a `CertificationFailure`. Odd
roots of negative numbers are negative: `rootn(-8, 3)` is $-2$. An even root
of $-\infty$ is a successful $+\infty$ on the current branch, not an error
(see [`BinFloat::rootn`](bin_float.md#binfloatrootn-binfloatrootn_ctx-binfloattry_rootn_ctx);
tracked in [#90](https://github.com/Luna-Flow/floating/issues/90), with a fix proposed in [#106](https://github.com/Luna-Flow/floating/pull/106)).

### `BinFloatResult::pow`, `BinFloatResult::pow_ctx`

`pow(y)` computes $x^{y}$ for a binary exponent with `BinFloat::try_pow_ctx`.

```mbti
pub fn BinFloatResult::pow(Self, Self) -> Self
pub fn BinFloatResult::pow_ctx(Self, Self, @bin_float.BinaryContext) -> Self
```

`pow` uses an unbounded context at the larger operand precision. Errors of the
operands come first (base, then exponent); the operation itself reports a
`DomainError` for a negative base with a non-integer exponent (for example
$(-2)^{0.5}$) and can report a `CertificationFailure`. On the current branch
it also reports a `DomainError` for some inputs IEEE 754 defines (a base of
$-0$, a negative base with an infinite exponent or an integral exponent of
magnitude at least $2^{31}$); the list is in
[`BinFloat::pow`](bin_float.md#binfloatpow-binfloatpow_ctx-binfloattry_pow_ctx).
Tracked in [#49](https://github.com/Luna-Flow/floating/issues/49) and [#89](https://github.com/Luna-Flow/floating/issues/89); a fix is proposed in [#106](https://github.com/Luna-Flow/floating/pull/106).

### `BinFloatResult::hypot`, `BinFloatResult::hypot_ctx`

`hypot(y)` computes $\sqrt{x^2 + y^2}$ without intermediate overflow, with
`BinFloat::try_hypot_ctx`.

```mbti
pub fn BinFloatResult::hypot(Self, Self) -> Self
pub fn BinFloatResult::hypot_ctx(Self, Self, @bin_float.BinaryContext) -> Self
```

`hypot` uses an unbounded context at the larger operand precision.

```moonbit
///|
test "powers and roots" {
  let r = fn(n : Int) { @bin_float_checked.BinFloatResult::from_int(n) }
  inspect(show(@bin_float_checked.BinFloatResult::from_int(81, precision=48).sqrt()), content="9p0")
  inspect(show(r(-4).sqrt()), content="error: sqrt requires a non-negative value")
  inspect(show(r(3).pow_nat(10)), content="59049p0")
  inspect(show(r(0).pow_int(-1)), content="error: negative exponent requires a non-zero base")
  inspect(show(r(-8).rootn(3)), content="-1p1")
  inspect(show(r(8).rootn(0)), content="error: rootn degree must not be zero")
  inspect(show(r(3).hypot(r(4))), content="5p0")
}
```

## Elementary functions

Each unary elementary function `name` has two wrapper methods. `name()` is
`bind` of `BinFloat::try_name_ctx` under `BinaryContext::unbounded(x.precision())`,
that is nearest-even rounding to the operand's precision with no exponent
limit; `name_ctx(ctx)` uses the given context instead. A success is the
correctly rounded value of `bin_float`; the flags are dropped. Besides the
domain errors listed below, every function can report a
`CertificationFailure` when `bin_float` cannot certify the rounding within its
refinement budget, which on the current branch happens for some tiny
arguments of `exp`, `expm1`, `exp2`, `sin` and `atan` (see
[`bin_float` elementary functions](bin_float.md#elementary-functions); tracked
in [#102](https://github.com/Luna-Flow/floating/issues/102), with a fix proposed in [#107](https://github.com/Luna-Flow/floating/pull/107)). Poles
are values, not errors: $\ln 0 = -\infty$. A NaN operand gives a successful
NaN.

### `BinFloatResult::exp`, `BinFloatResult::exp_ctx`

$e^x$, delegated to [`BinFloat::try_exp_ctx`](bin_float.md#binfloatexp-binfloatexp_ctx-binfloattry_exp_ctx).

```mbti
pub fn BinFloatResult::exp(Self) -> Self
pub fn BinFloatResult::exp_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::expm1`, `BinFloatResult::expm1_ctx`

$e^x - 1$, delegated to [`BinFloat::try_expm1_ctx`](bin_float.md#binfloatexpm1-binfloatexpm1_ctx-binfloattry_expm1_ctx).

```mbti
pub fn BinFloatResult::expm1(Self) -> Self
pub fn BinFloatResult::expm1_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::exp2`, `BinFloatResult::exp2_ctx`

$2^x$, delegated to [`BinFloat::try_exp2_ctx`](bin_float.md#binfloatexp2-binfloatexp2_ctx-binfloattry_exp2_ctx).

```mbti
pub fn BinFloatResult::exp2(Self) -> Self
pub fn BinFloatResult::exp2_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::exp10`, `BinFloatResult::exp10_ctx`

$10^x$, delegated to [`BinFloat::try_exp10_ctx`](bin_float.md#binfloatexp10-binfloatexp10_ctx-binfloattry_exp10_ctx).

```mbti
pub fn BinFloatResult::exp10(Self) -> Self
pub fn BinFloatResult::exp10_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::ln`, `BinFloatResult::ln_ctx`

$\ln x$, delegated to [`BinFloat::try_ln_ctx`](bin_float.md#binfloatln-binfloatln_ctx-binfloattry_ln_ctx).

```mbti
pub fn BinFloatResult::ln(Self) -> Self
pub fn BinFloatResult::ln_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative finite argument; $\ln 0 = -\infty$ and $\ln(-\infty)$ is a successful NaN.

### `BinFloatResult::log1p`, `BinFloatResult::log1p_ctx`

$\ln(1 + x)$, delegated to [`BinFloat::try_log1p_ctx`](bin_float.md#binfloatlog1p-binfloatlog1p_ctx-binfloattry_log1p_ctx).

```mbti
pub fn BinFloatResult::log1p(Self) -> Self
pub fn BinFloatResult::log1p_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` below $-1$; $\operatorname{log1p}(-1) = -\infty$.

### `BinFloatResult::log2`, `BinFloatResult::log2_ctx`

$\log_2 x$, delegated to [`BinFloat::try_log2_ctx`](bin_float.md#binfloatlog2-binfloatlog2_ctx-binfloattry_log2_ctx).

```mbti
pub fn BinFloatResult::log2(Self) -> Self
pub fn BinFloatResult::log2_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative finite argument; $\log_2 0 = -\infty$.

### `BinFloatResult::log10`, `BinFloatResult::log10_ctx`

$\log_{10} x$, delegated to [`BinFloat::try_log10_ctx`](bin_float.md#binfloatlog10-binfloatlog10_ctx-binfloattry_log10_ctx).

```mbti
pub fn BinFloatResult::log10(Self) -> Self
pub fn BinFloatResult::log10_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative finite argument; $\log_{10} 0 = -\infty$.

### `BinFloatResult::exp_ln`, `BinFloatResult::exp_ln_ctx`

$\ln(e^x)$ as one fused operation, delegated to [`BinFloat::try_exp_ln_ctx`](bin_float.md#binfloatexp_ln-binfloatexp_ln_ctx-binfloattry_exp_ln_ctx).

```mbti
pub fn BinFloatResult::exp_ln(Self) -> Self
pub fn BinFloatResult::exp_ln_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `CertificationFailure` (stage `RangeReduction`, reason `RangeNotCertified`) for a finite $|x| > 1/8$.

### `BinFloatResult::sin`, `BinFloatResult::sin_ctx`

$\sin x$, delegated to [`BinFloat::try_sin_ctx`](bin_float.md#binfloatsin-binfloatsin_ctx-binfloattry_sin_ctx).

```mbti
pub fn BinFloatResult::sin(Self) -> Self
pub fn BinFloatResult::sin_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinFloatResult::cos`, `BinFloatResult::cos_ctx`

$\cos x$, delegated to [`BinFloat::try_cos_ctx`](bin_float.md#binfloatcos-binfloatcos_ctx-binfloattry_cos_ctx).

```mbti
pub fn BinFloatResult::cos(Self) -> Self
pub fn BinFloatResult::cos_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinFloatResult::tan`, `BinFloatResult::tan_ctx`

$\tan x$, delegated to [`BinFloat::try_tan_ctx`](bin_float.md#binfloattan-binfloattan_ctx-binfloattry_tan_ctx).

```mbti
pub fn BinFloatResult::tan(Self) -> Self
pub fn BinFloatResult::tan_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinFloatResult::sinpi`, `BinFloatResult::sinpi_ctx`

$\sin(\pi x)$, delegated to [`BinFloat::try_sinpi_ctx`](bin_float.md#binfloatsinpi-binfloatsinpi_ctx-binfloattry_sinpi_ctx).

```mbti
pub fn BinFloatResult::sinpi(Self) -> Self
pub fn BinFloatResult::sinpi_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinFloatResult::cospi`, `BinFloatResult::cospi_ctx`

$\cos(\pi x)$, delegated to [`BinFloat::try_cospi_ctx`](bin_float.md#binfloatcospi-binfloatcospi_ctx-binfloattry_cospi_ctx).

```mbti
pub fn BinFloatResult::cospi(Self) -> Self
pub fn BinFloatResult::cospi_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinFloatResult::tanpi`, `BinFloatResult::tanpi_ctx`

$\tan(\pi x)$, delegated to [`BinFloat::try_tanpi_ctx`](bin_float.md#binfloattanpi-binfloattanpi_ctx-binfloattry_tanpi_ctx).

```mbti
pub fn BinFloatResult::tanpi(Self) -> Self
pub fn BinFloatResult::tanpi_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument; at half-integers the result is a successful $\pm\infty$.

### `BinFloatResult::asin`, `BinFloatResult::asin_ctx`

$\arcsin x$, delegated to [`BinFloat::try_asin_ctx`](bin_float.md#binfloatasin-binfloatasin_ctx-binfloattry_asin_ctx).

```mbti
pub fn BinFloatResult::asin(Self) -> Self
pub fn BinFloatResult::asin_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` outside $[-1, 1]$, infinities included.

### `BinFloatResult::acos`, `BinFloatResult::acos_ctx`

$\arccos x$, delegated to [`BinFloat::try_acos_ctx`](bin_float.md#binfloatacos-binfloatacos_ctx-binfloattry_acos_ctx).

```mbti
pub fn BinFloatResult::acos(Self) -> Self
pub fn BinFloatResult::acos_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` outside $[-1, 1]$, infinities included.

### `BinFloatResult::atan`, `BinFloatResult::atan_ctx`

$\arctan x$, delegated to [`BinFloat::try_atan_ctx`](bin_float.md#binfloatatan-binfloatatan_ctx-binfloattry_atan_ctx).

```mbti
pub fn BinFloatResult::atan(Self) -> Self
pub fn BinFloatResult::atan_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::sinh`, `BinFloatResult::sinh_ctx`

$\sinh x$, delegated to [`BinFloat::try_sinh_ctx`](bin_float.md#binfloatsinh-binfloatsinh_ctx-binfloattry_sinh_ctx).

```mbti
pub fn BinFloatResult::sinh(Self) -> Self
pub fn BinFloatResult::sinh_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::cosh`, `BinFloatResult::cosh_ctx`

$\cosh x$, delegated to [`BinFloat::try_cosh_ctx`](bin_float.md#binfloatcosh-binfloatcosh_ctx-binfloattry_cosh_ctx).

```mbti
pub fn BinFloatResult::cosh(Self) -> Self
pub fn BinFloatResult::cosh_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::tanh`, `BinFloatResult::tanh_ctx`

$\tanh x$, delegated to [`BinFloat::try_tanh_ctx`](bin_float.md#binfloattanh-binfloattanh_ctx-binfloattry_tanh_ctx).

```mbti
pub fn BinFloatResult::tanh(Self) -> Self
pub fn BinFloatResult::tanh_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::asinh`, `BinFloatResult::asinh_ctx`

$\operatorname{asinh} x$, delegated to [`BinFloat::try_asinh_ctx`](bin_float.md#binfloatasinh-binfloatasinh_ctx-binfloattry_asinh_ctx).

```mbti
pub fn BinFloatResult::asinh(Self) -> Self
pub fn BinFloatResult::asinh_ctx(Self, @bin_float.BinaryContext) -> Self
```

### `BinFloatResult::acosh`, `BinFloatResult::acosh_ctx`

$\operatorname{acosh} x$, delegated to [`BinFloat::try_acosh_ctx`](bin_float.md#binfloatacosh-binfloatacosh_ctx-binfloattry_acosh_ctx).

```mbti
pub fn BinFloatResult::acosh(Self) -> Self
pub fn BinFloatResult::acosh_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` below $1$.

### `BinFloatResult::atanh`, `BinFloatResult::atanh_ctx`

$\operatorname{atanh} x$, delegated to [`BinFloat::try_atanh_ctx`](bin_float.md#binfloatatanh-binfloatatanh_ctx-binfloattry_atanh_ctx).

```mbti
pub fn BinFloatResult::atanh(Self) -> Self
pub fn BinFloatResult::atanh_ctx(Self, @bin_float.BinaryContext) -> Self
```

Errors: a `DomainError` for $|x| > 1$; $\operatorname{atanh}(\pm 1) = \pm\infty$.

### `BinFloatResult::atan2`, `BinFloatResult::atan2_ctx`

The angle of the point $(\text{abscissa}, \text{self})$, delegated to
[`BinFloat::try_atan2_ctx`](bin_float.md#binfloatatan2-binfloatatan2_ctx-binfloattry_atan2_ctx).

```mbti
pub fn BinFloatResult::atan2(Self, Self) -> Self
pub fn BinFloatResult::atan2_ctx(Self, Self, @bin_float.BinaryContext) -> Self
```

Errors are taken in the order ordinate, abscissa, operation. `atan2` uses
`BinaryContext::unbounded` at the larger operand precision. The signed-zero
defects of `BinFloat::atan2` carry over (tracked in [#48](https://github.com/Luna-Flow/floating/issues/48); a fix is
proposed in [#101](https://github.com/Luna-Flow/floating/pull/101)).

```moonbit
///|
test "elementary functions" {
  let r = fn(n : Int) { @bin_float_checked.BinFloatResult::from_int(n) }
  inspect(show(r(2).ln()), content="6243314768165359p-53")
  inspect(
    show(r(2).ln_ctx(@bin_float.BinaryContext::unbounded(24))),
    content="1453635p-21",
  )
  inspect(show(r(0).ln()), content="-inf")
  inspect(show(r(-4).ln()), content="error: ln requires a positive value")
  inspect(show(r(2).asin()), content="error: asin requires an input in [-1, 1]")
  inspect(show(r(3).exp_ln()), content="error: certified evaluation failed for exp_ln")
  inspect(show(r(0).exp().ln()), content="0")
}
```

## Trait implementations

### `Add`, `Sub`, `Mul`, `Div` and `Neg` for `BinFloatResult`

The operators `+`, `-`, `*`, `/` and unary `-` call `add`, `sub`, `mul`, `div`
and `neg`.

```mbti
pub impl Add for BinFloatResult
pub impl Sub for BinFloatResult
pub impl Mul for BinFloatResult
pub impl Div for BinFloatResult
pub impl Neg for BinFloatResult
```

So `/` on wrappers reports division by zero, while `/` on plain `BinFloat`
values returns an infinity.

## Deprecated

### `BinFloatResult::flat_map`

`flat_map` is the former name of `bind`. Replace `r.flat_map(f)` with
`r.bind(f)`.

```mbti
#deprecated
pub fn BinFloatResult::flat_map(Self, (@bin_float.BinFloat) -> Self) -> Self
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BinFloatResult {
  // private fields
}
pub fn BinFloatResult::abs(Self) -> Self
pub fn BinFloatResult::acos(Self) -> Self
pub fn BinFloatResult::acos_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::acosh(Self) -> Self
pub fn BinFloatResult::acosh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::add(Self, Self) -> Self
pub fn BinFloatResult::add_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::asin(Self) -> Self
pub fn BinFloatResult::asin_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::asinh(Self) -> Self
pub fn BinFloatResult::asinh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::atan(Self) -> Self
pub fn BinFloatResult::atan2(Self, Self) -> Self
pub fn BinFloatResult::atan2_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::atan_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::atanh(Self) -> Self
pub fn BinFloatResult::atanh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::bind(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloatResult::cos(Self) -> Self
pub fn BinFloatResult::cos_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::cosh(Self) -> Self
pub fn BinFloatResult::cosh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::cospi(Self) -> Self
pub fn BinFloatResult::cospi_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::div(Self, Self) -> Self
pub fn BinFloatResult::div_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BinFloatResult::exp(Self) -> Self
pub fn BinFloatResult::exp10(Self) -> Self
pub fn BinFloatResult::exp10_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::exp2(Self) -> Self
pub fn BinFloatResult::exp2_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::exp_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::exp_ln(Self) -> Self
pub fn BinFloatResult::exp_ln_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::expm1(Self) -> Self
pub fn BinFloatResult::expm1_ctx(Self, @bin_float.BinaryContext) -> Self
#deprecated
pub fn BinFloatResult::flat_map(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BinFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BinFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BinFloatResult::from_result(Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BinFloatResult::hypot(Self, Self) -> Self
pub fn BinFloatResult::hypot_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::is_err(Self) -> Bool
pub fn BinFloatResult::is_ok(Self) -> Bool
pub fn BinFloatResult::ln(Self) -> Self
pub fn BinFloatResult::ln_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::log10(Self) -> Self
pub fn BinFloatResult::log10_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::log1p(Self) -> Self
pub fn BinFloatResult::log1p_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::log2(Self) -> Self
pub fn BinFloatResult::log2_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::map(Self, (@bin_float.BinFloat) -> @bin_float.BinFloat) -> Self
pub fn BinFloatResult::max(Self, Self) -> Self
pub fn BinFloatResult::min(Self, Self) -> Self
pub fn BinFloatResult::mul(Self, Self) -> Self
pub fn BinFloatResult::mul_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::neg(Self) -> Self
pub fn BinFloatResult::normalized(Self) -> Self
pub fn BinFloatResult::ok(@bin_float.BinFloat) -> Self
pub fn BinFloatResult::pow(Self, Self) -> Self
pub fn BinFloatResult::pow_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::pow_int(Self, Int) -> Self
pub fn BinFloatResult::pow_int_ctx(Self, Int, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::pow_nat(Self, UInt) -> Self
pub fn BinFloatResult::pown(Self, Int) -> Self
pub fn BinFloatResult::pown_ctx(Self, Int, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::result(Self) -> Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]
pub fn BinFloatResult::rootn(Self, Int) -> Self
pub fn BinFloatResult::rootn_ctx(Self, Int, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sin(Self) -> Self
pub fn BinFloatResult::sin_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sinh(Self) -> Self
pub fn BinFloatResult::sinh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sinpi(Self) -> Self
pub fn BinFloatResult::sinpi_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sqrt(Self) -> Self
pub fn BinFloatResult::sqrt_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::sub(Self, Self) -> Self
pub fn BinFloatResult::sub_ctx(Self, Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::tan(Self) -> Self
pub fn BinFloatResult::tan_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::tanh(Self) -> Self
pub fn BinFloatResult::tanh_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::tanpi(Self) -> Self
pub fn BinFloatResult::tanpi_ctx(Self, @bin_float.BinaryContext) -> Self
pub fn BinFloatResult::ulp(Self) -> Self
pub fn BinFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BinFloatResult
pub impl Div for BinFloatResult
pub impl Mul for BinFloatResult
pub impl Neg for BinFloatResult
pub impl Sub for BinFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
