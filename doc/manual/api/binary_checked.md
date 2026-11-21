# binary_checked API

## Purpose

`binary_checked` provides `BinaryChecked`, a closed wrapper around
`Result[Binary, ArithmeticError]`. Every operation takes and returns a
`BinaryChecked`, applies the corresponding [`binary`](binary.md)
operation when all operands are successes, and otherwise passes on the first
error without running the operation. The wrapper keeps no IEEE flags: the
checked operations turn the invalid operation and divideByZero exceptions into
errors, and the arithmetic `_ctx` methods drop them. The
[tutorial](../tutorial/binary_checked.md) builds pipelines step by step; the
[design page](../design/binary_checked.md) models the wrapper as the error
monad and proves the composition laws it relies on.

## Importing

Add the wrapper and the packages whose types appear in its signatures to your
`moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/binary_checked",
  "Luna-Flow/floating/def",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples call the packages as `@binary_checked.`, `@binary.`,
`@def.` and `@lf_arith.` (`Luna-Flow/arithmetic`, printed as `@arithmetic` in
the interface). They print a result with this helper:

```moonbit
///|
fn show(r : @binary_checked.BinaryChecked) -> String {
  match r.result() {
    Ok(v) => v.to_string()
    Err(e) => "error: " + e.message
  }
}
```

`Binary::to_string` prints the exact value as `coefficient p exponent`, so
`3p-1` is $3 \cdot 2^{-1} = 1.5$.

## The wrapper type

### `BinaryChecked`

`BinaryChecked` is either a successful `Binary` or an `ArithmeticError`.

```mbti
pub struct BinaryChecked {
  // private fields
}
```

The only field is private; it holds a `Result[@binary.Binary,
@arithmetic.ArithmeticError]`. The type has no `Eq` or `Show` instance; compare
or print through `result()`.

## Construction

### `BinaryChecked::ok`, `BinaryChecked::err`, `BinaryChecked::from_result`

These functions wrap an existing value, error or `Result` without changing it.

```mbti
pub fn BinaryChecked::ok(@binary.Binary) -> Self
pub fn BinaryChecked::err(@arithmetic.ArithmeticError) -> Self
pub fn BinaryChecked::from_result(Result[@binary.Binary, @arithmetic.ArithmeticError]) -> Self
```

`from_result(r).result() == r` for every `r`, and `ok(x)` is the unit of the
monad described in the design page.

### `BinaryChecked::from_int`, `BinaryChecked::from_coefficient`, `BinaryChecked::from_double`, `BinaryChecked::from_float`

These constructors build a successful wrapper from a MoonBit number through the
matching `Binary` constructor.

```mbti
pub fn BinaryChecked::from_int(Int, precision? : Int) -> Self
pub fn BinaryChecked::from_coefficient(@binary.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinaryChecked::from_double(Double, precision? : Int) -> Self
pub fn BinaryChecked::from_float(Float, precision? : Int) -> Self
```

| Constructor | Default `precision` | Delegates to |
| --- | --- | --- |
| `from_int` | 53 | `Binary::from_int` |
| `from_coefficient` | 53 (`negative` defaults to `false`) | `Binary::from_coefficient` |
| `from_double` | 53 | `Binary::from_double` |
| `from_float` | 24 | `Binary::from_float` |

They never produce an error: NaN and infinity inputs become successful NaN or
infinite values, and a value that does not fit `precision` is rounded to
nearest-even as by the delegated constructor. `from_float` widens through a
host `Double`, so a signaling `Float` NaN may arrive quiet (see
[`Binary::from_float`](binary.md#binaryfrom_double-binaryfrom_float)).

## Observation

### `BinaryChecked::result`, `BinaryChecked::error`, `BinaryChecked::is_ok`, `BinaryChecked::is_err`

These methods expose the wrapped `Result`, its error, and test its branch. They are the exits of the pipeline types of the checked tiers: `DecimalChecked` and `GdaDecimalChecked` have the same four.

```mbti
pub fn BinaryChecked::result(Self) -> Result[@binary.Binary, @arithmetic.ArithmeticError]
pub fn BinaryChecked::error(Self) -> @arithmetic.ArithmeticError?
pub fn BinaryChecked::is_ok(Self) -> Bool
pub fn BinaryChecked::is_err(Self) -> Bool
```

`is_err(r) == !is_ok(r)`, and `error(r)` is `Some(e)` exactly when `result(r)`
is `Err(e)`. Call `result()` once, at the boundary where the error is handled.

## Composition

### `BinaryChecked::map`

`map(f)` applies an infallible function to a success and leaves an error
unchanged.

```mbti
pub fn BinaryChecked::map(Self, (@binary.Binary) -> @binary.Binary) -> Self
```

$\texttt{map}(\texttt{Ok}(x), f) = \texttt{Ok}(f(x))$ and
$\texttt{map}(\texttt{Err}(e), f) = \texttt{Err}(e)$; `f` is not called on an
error. `map` can never turn a success into an error.

### `BinaryChecked::bind`

`bind(f)` applies a function that may itself fail.

```mbti
pub fn BinaryChecked::bind(Self, (@binary.Binary) -> Self) -> Self
```

$\texttt{bind}(\texttt{Ok}(x), f) = f(x)$ and
$\texttt{bind}(\texttt{Err}(e), f) = \texttt{Err}(e)$. With `ok` it satisfies
the monad laws (left and right identity, associativity), derived in the
[design page](../design/binary_checked.md#the-monad-laws).

```moonbit
///|
test "map and bind" {
  let halve = fn(x : @binary.Binary) { x * @binary.Binary::from_double(0.5) }
  let positive = fn(x : @binary.Binary) {
    if x.sign() == @def.Sign::Positive {
      @binary_checked.BinaryChecked::ok(x)
    } else {
      @binary_checked.BinaryChecked::err(
        @lf_arith.ArithmeticError::domain_error("expected a positive value"),
      )
    }
  }
  let good = @binary_checked.BinaryChecked::from_int(3).map(halve).bind(positive)
  inspect(show(good), content="3p-1")
  let bad = @binary_checked.BinaryChecked::from_int(-3).bind(positive).map(halve)
  inspect(show(bad), content="error: expected a positive value")
}
```

## Unary value maps

### `BinaryChecked::neg`, `BinaryChecked::abs`, `BinaryChecked::ulp`, `BinaryChecked::normalized`, `BinaryChecked::with_precision`

These methods are `map` of the `Binary` method of the same name; they never
introduce an error.

```mbti
pub fn BinaryChecked::neg(Self) -> Self
pub fn BinaryChecked::abs(Self) -> Self
pub fn BinaryChecked::ulp(Self) -> Self
pub fn BinaryChecked::normalized(Self) -> Self
pub fn BinaryChecked::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

`with_precision(p, mode)` rounds to $\max(1,p)$ bits in direction `mode` with
an unbounded exponent; `ulp` is the unit in the last place at the value's
precision (NaN for non-finite values).

## Arithmetic

### `BinaryChecked::add`, `BinaryChecked::sub`, `BinaryChecked::mul`

These methods combine two wrappers with the `Binary` operator.

```mbti
pub fn BinaryChecked::add(Self, Self) -> Self
pub fn BinaryChecked::sub(Self, Self) -> Self
pub fn BinaryChecked::mul(Self, Self) -> Self
```

If `self` is an error it is returned; otherwise if `other` is an error that
error is returned; otherwise the result is `Ok(lhs op rhs)`. The `Binary`
operators round to nearest-even at the larger of the two operand precisions and
never fail: invalid cases such as $\infty - \infty$ produce a successful NaN.

### `BinaryChecked::div`

`div` divides two wrappers and reports invalid divisions and division by zero.

```mbti
pub fn BinaryChecked::div(Self, Self) -> Self
```

After the operand errors (left first), the result is
`DivChecked::div_checked` of `Binary` under the larger precision of the operands: a `DomainError` for $0/0$, $\infty/\infty$
or a signaling NaN operand, a `DivisionByZero` error for a finite non-zero
dividend over a zero divisor ($\pm 0$), and the IEEE 754-2019 result
otherwise: a quiet NaN for a quiet NaN operand (NaN$/0$ included),
$\pm\infty$ for $\infty/0$, and the rounded quotient.

### `BinaryChecked::min_num`, `BinaryChecked::max_num`

These methods take the smaller or larger operand with `Binary::min_num` /
`Binary::max_num`, which ignore a NaN operand in favour of the other one and
return the receiver when the operands compare equal (so `min(-0, +0)` is
$-0$ and `min(+0, -0)` is $+0$).

```mbti
pub fn BinaryChecked::min_num(Self, Self) -> Self
pub fn BinaryChecked::max_num(Self, Self) -> Self
```

### `BinaryChecked::clamp`

`clamp(min~, max~)` restricts a value to an interval.

```mbti
pub fn BinaryChecked::clamp(Self, min~ : Self, max~ : Self) -> Self
```

Errors are taken in the order `self`, `min`, `max`; then
`Binary::clamp_checked` returns a `DomainError` when a bound is NaN or when
`min > max`, and the clamped value otherwise.

```moonbit
///|
test "arithmetic keeps the first error" {
  let one = @binary_checked.BinaryChecked::from_int(1)
  let zero = @binary_checked.BinaryChecked::from_int(0)
  inspect(show(one + one * one), content="1p1")
  inspect(show(one / zero), content="error: div: division by zero")
  let left = @binary_checked.BinaryChecked::err(
    @lf_arith.ArithmeticError::unsupported("left"),
  )
  inspect(show(left + one / zero), content="error: left")
  inspect(show(one / zero + left), content="error: div: division by zero")
  let clamped = @binary_checked.BinaryChecked::from_int(5).clamp(
    min=zero,
    max=@binary_checked.BinaryChecked::from_int(3),
  )
  inspect(show(clamped), content="3p0")
  let reversed = one.clamp(min=@binary_checked.BinaryChecked::from_int(3), max=zero)
  inspect(show(reversed), content="error: min must not exceed max")
}
```

## Contextual arithmetic

### `BinaryChecked::add_ctx`, `BinaryChecked::sub_ctx`, `BinaryChecked::mul_ctx`, `BinaryChecked::div_ctx`

These methods apply the `Binary::*_ctx` operation under an explicit
`BinaryContext` and keep only its value.

```mbti
pub fn BinaryChecked::add_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sub_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::mul_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::div_ctx(Self, Self, @binary.BinaryContext) -> Self
```

The result has the context's precision, rounding direction and exponent range,
with IEEE overflow, underflow and subnormal handling. The flags of the step are
mapped as in `add`, `div` and the elementary methods: invalid operation is a
`DomainError` and divideByZero a `DivisionByZero`; overflow, underflow and
inexact are dropped. So `div_ctx` by a zero divisor is `DivisionByZero`, and
$0/0$, $\infty/\infty$, $\infty - \infty$ and $0 \cdot \infty$ are
`DomainError`, exactly as without a context; a quiet NaN operand is still a
successful NaN. The full table is in the
[design page](../design/binary_checked.md). Use `Binary::div_ctx` and its
siblings when the raw default result and the flags matter.

```moonbit
///|
test "context arithmetic rounds to the context and maps the flags" {
  let binary32 = @binary.BinaryContext::binary32()
  let tenth = @binary_checked.BinaryChecked::from_double(0.1)
  let zero = @binary_checked.BinaryChecked::from_int(0)
  inspect(show(tenth.add_ctx(zero, binary32)), content="13421773p-27")
  let one = @binary_checked.BinaryChecked::from_int(1)
  inspect(show(one.div_ctx(zero, binary32)), content="error: div: division by zero")
  inspect(show(one.div(zero)), content="error: div: division by zero")
  inspect(show(zero.div_ctx(zero, binary32)), content="error: div: invalid operation")
}
```

## Powers and roots

### `BinaryChecked::sqrt`, `BinaryChecked::sqrt_ctx`

`sqrt` takes the square root at the operand's precision; `sqrt_ctx` under a
context.

```mbti
pub fn BinaryChecked::sqrt(Self) -> Self
pub fn BinaryChecked::sqrt_ctx(Self, @binary.BinaryContext) -> Self
```

`sqrt` is `Binary::sqrt`, which returns a `DomainError` for a negative
non-zero argument, including $-\infty$, and for a signaling NaN;
$\sqrt{-0} = -0$ and a quiet NaN of either sign gives a successful NaN. `sqrt_ctx` does the same
under a context: a negative argument is a `DomainError`.

### `BinaryChecked::pow_nat`, `BinaryChecked::pown`, `BinaryChecked::pown_ctx`

These methods raise a value to an integer power.

```mbti
pub fn BinaryChecked::pow_nat(Self, UInt) -> Self
pub fn BinaryChecked::pown(Self, Int) -> Self
pub fn BinaryChecked::pown_ctx(Self, Int, @binary.BinaryContext) -> Self
```

`pow_nat(n)` calls the Luna-Flow/arithmetic trait method
`PowNatChecked::pow_nat_checked` with `ArithmeticContext::new(x.precision())`,
which `binary` maps to the binary context of that precision (`BinaryContext::new(precision=p)`) with
nearest-even rounding. `pown` returns a `DivisionByZero` error for a zero base with a negative exponent, a
`DomainError` for a signaling NaN base, zero exponent included (as does
`pow_nat`), and the rounded power otherwise, at the operand's precision. The `_ctx` forms
map the flags the same way: a `DivisionByZero` error for a zero base with a
negative exponent and a `DomainError` for a signaling NaN base.

### `BinaryChecked::rootn`, `BinaryChecked::rootn_ctx`

`rootn(n)` computes the real $n$-th root with `Binary::try_rootn_ctx`.

```mbti
pub fn BinaryChecked::rootn(Self, Int) -> Self
pub fn BinaryChecked::rootn_ctx(Self, Int, @binary.BinaryContext) -> Self
```

`rootn` uses an unbounded context at the operand's precision; `rootn_ctx` the
given context. Both report a `DomainError` for degree $0$ (for every operand, a quiet NaN and $\pm 0$ included, and never `DivisionByZero`: IEEE 754-2019 Table 9.1, "n = 0: invalid operation"), for an even root
of a negative number ($-\infty$ included) and for a signaling NaN, a
`DivisionByZero` error for $\operatorname{rootn}(\pm 0, n)$ with $n < 0$
(IEEE 754-2019 §9.2.1), and can report a `CertificationFailure`. Odd roots of negative numbers are negative:
`rootn(-8, 3)` is $-2$. The full table of special values is in
[`Binary::rootn`](binary.md#binaryrootn-binaryrootn_ctx-binarytry_rootn_ctx).

### `BinaryChecked::pow`, `BinaryChecked::pow_ctx`

`pow(y)` computes $x^{y}$ for a binary exponent with `Binary::try_pow_ctx`.

```mbti
pub fn BinaryChecked::pow(Self, Self) -> Self
pub fn BinaryChecked::pow_ctx(Self, Self, @binary.BinaryContext) -> Self
```

`pow` uses an unbounded context at the larger operand precision. Errors of the
operands come first (base, then exponent); the operation itself reports a
`DomainError` for a negative finite base with a non-integer exponent (for
example $(-2)^{0.5}$) and for a signaling NaN operand, a `DivisionByZero`
error for a zero base with a finite negative exponent ($(\pm 0)^{-1.5}$,
IEEE 754-2019 §9.2.1), and can report a `CertificationFailure`. A base of $-0$,
a negative base with an integral exponent of any size and an infinite
exponent all give the IEEE 754 values listed in
[`Binary::pow`](binary.md#binarypow-binarypow_ctx-binarytry_pow_ctx),
for example $(-1)^{\infty} = 1$ and $(-0)^{0.75} = +0$.

### `BinaryChecked::rsqrt`, `BinaryChecked::rsqrt_ctx`

$1/\sqrt{x}$, delegated to [`Binary::try_rsqrt_ctx`](binary.md#binaryrsqrt-binaryrsqrt_ctx-binarytry_rsqrt_ctx).

```mbti
pub fn BinaryChecked::rsqrt(Self) -> Self
pub fn BinaryChecked::rsqrt_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative operand ($-\infty$ included) and for a
signaling NaN; a `DivisionByZero` error for $\operatorname{rSqrt}(\pm 0)$.

### `BinaryChecked::compound`, `BinaryChecked::compound_ctx`

$(1 + x)^n$, delegated to [`Binary::try_compound_ctx`](binary.md#binarycompound-binarycompound_ctx-binarytry_compound_ctx).

```mbti
pub fn BinaryChecked::compound(Self, Int) -> Self
pub fn BinaryChecked::compound_ctx(Self, Int, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` below $-1$ ($-\infty$ included) and for a signaling NaN;
a `DivisionByZero` error for $\operatorname{compound}(-1, n)$ with $n < 0$.

### `BinaryChecked::powr`, `BinaryChecked::powr_ctx`

$x^y$ for $x \ge 0$, delegated to [`Binary::try_powr_ctx`](binary.md#binarypowr-binarypowr_ctx-binarytry_powr_ctx).

```mbti
pub fn BinaryChecked::powr(Self, Self) -> Self
pub fn BinaryChecked::powr_ctx(Self, Self, @binary.BinaryContext) -> Self
```

Errors of the operands come first (base, then exponent). The operation reports
a `DomainError` for a negative base, for a signaling NaN, and for the invalid
pairs $(\pm 0, \pm 0)$, $(+\infty, \pm 0)$ and $(1, \pm\infty)$, and a
`DivisionByZero` error for $(\pm 0, y)$ with a finite $y < 0$.

### `BinaryChecked::asinpi`, `BinaryChecked::asinpi_ctx`

$\operatorname{asin}(x)/\pi$, delegated to [`Binary::try_asinpi_ctx`](binary.md#binaryasinpi-binaryasinpi_ctx-binarytry_asinpi_ctx).

```mbti
pub fn BinaryChecked::asinpi(Self) -> Self
pub fn BinaryChecked::asinpi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for $|x| > 1$ ($\pm\infty$ included) and for a signaling NaN.

### `BinaryChecked::acospi`, `BinaryChecked::acospi_ctx`

$\operatorname{acos}(x)/\pi$, delegated to [`Binary::try_acospi_ctx`](binary.md#binaryacospi-binaryacospi_ctx-binarytry_acospi_ctx).

```mbti
pub fn BinaryChecked::acospi(Self) -> Self
pub fn BinaryChecked::acospi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: as `asinpi`.

### `BinaryChecked::atanpi`, `BinaryChecked::atanpi_ctx`

$\operatorname{atan}(x)/\pi$, delegated to [`Binary::try_atanpi_ctx`](binary.md#binaryatanpi-binaryatanpi_ctx-binarytry_atanpi_ctx).

```mbti
pub fn BinaryChecked::atanpi(Self) -> Self
pub fn BinaryChecked::atanpi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for a signaling NaN only; $\pm\infty$ gives $\pm 1/2$.

### `BinaryChecked::atan2pi`, `BinaryChecked::atan2pi_ctx`

The angle of the point $(\text{abscissa}, \text{self})$ in half-revolutions, delegated to
[`Binary::try_atan2pi_ctx`](binary.md#binaryatan2pi-binaryatan2pi_ctx-binarytry_atan2pi_ctx).

```mbti
pub fn BinaryChecked::atan2pi(Self, Self) -> Self
pub fn BinaryChecked::atan2pi_ctx(Self, Self, @binary.BinaryContext) -> Self
```

Errors are taken in the order ordinate, abscissa, operation. `atan2pi` uses
`BinaryContext::new(precision=p)` at the larger operand precision. Zero and infinite
operands give exact constants with no exception; a signaling NaN operand is a
`DomainError`.

### `BinaryChecked::hypot`, `BinaryChecked::hypot_ctx`

`hypot(y)` computes $\sqrt{x^2 + y^2}$ without intermediate overflow, with
`Binary::try_hypot_ctx`.

```mbti
pub fn BinaryChecked::hypot(Self, Self) -> Self
pub fn BinaryChecked::hypot_ctx(Self, Self, @binary.BinaryContext) -> Self
```

`hypot` uses an unbounded context at the larger operand precision. A
signaling NaN operand is a `DomainError`; `hypot` raises no other exception
(overflow and underflow are values).

```moonbit
///|
test "powers and roots" {
  let r = fn(n : Int) { @binary_checked.BinaryChecked::from_int(n) }
  inspect(show(@binary_checked.BinaryChecked::from_int(81, precision=48).sqrt()), content="9p0")
  inspect(show(r(-4).sqrt()), content="error: sqrt: invalid operation")
  inspect(show(r(3).pow_nat(10)), content="59049p0")
  inspect(show(r(0).pown(-1)), content="error: pown: division by zero")
  inspect(show(r(-8).rootn(3)), content="-1p1")
  inspect(show(r(8).rootn(0)), content="error: rootn: invalid operation")
  inspect(show(r(3).hypot(r(4))), content="5p0")
}
```

## Elementary functions

Each unary elementary function `name` has two wrapper methods. `name()` is
`bind` of `Binary::try_name_ctx` under `BinaryContext::new(precision=x.precision())`,
that is nearest-even rounding to the operand's precision with no exponent
limit; `name_ctx(ctx)` uses the given context instead. A success is the
correctly rounded value of `binary`. The flags of the step are mapped as
for `div`: the invalid operation exception (a signaling NaN operand, or an
argument outside the domain of IEEE 754-2019 Table 9.1) is a `DomainError`,
divideByZero (a pole, §9.2) is a `DivisionByZero` error, and overflow,
underflow and inexact are dropped. Besides the errors listed below, every
function can report a
`CertificationFailure` when `binary` cannot certify the rounding within its
refinement budget (see
[`binary` elementary functions](binary.md#elementary-functions)); the
`CertificationFailureDetail` names the function. The messages of the other
errors name it too: `name: invalid operation` and `name: division by zero`, so
that in a chain of steps the message says which one failed. A
quiet NaN operand gives a successful NaN.

### `BinaryChecked::exp`, `BinaryChecked::exp_ctx`

$e^x$, delegated to [`Binary::try_exp_ctx`](binary.md#binaryexp-binaryexp_ctx-binarytry_exp_ctx).

```mbti
pub fn BinaryChecked::exp(Self) -> Self
pub fn BinaryChecked::exp_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::expm1`, `BinaryChecked::expm1_ctx`

$e^x - 1$, delegated to [`Binary::try_expm1_ctx`](binary.md#binaryexpm1-binaryexpm1_ctx-binarytry_expm1_ctx).

```mbti
pub fn BinaryChecked::expm1(Self) -> Self
pub fn BinaryChecked::expm1_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::exp2m1`, `BinaryChecked::exp2m1_ctx`

$2^x - 1$, delegated to [`Binary::try_exp2m1_ctx`](binary.md#binaryexp2m1-binaryexp2m1_ctx-binarytry_exp2m1_ctx).

```mbti
pub fn BinaryChecked::exp2m1(Self) -> Self
pub fn BinaryChecked::exp2m1_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a signaling NaN is a `DomainError`; $-\infty$ gives $-1$.

### `BinaryChecked::exp10m1`, `BinaryChecked::exp10m1_ctx`

$10^x - 1$, delegated to [`Binary::try_exp10m1_ctx`](binary.md#binaryexp10m1-binaryexp10m1_ctx-binarytry_exp10m1_ctx).

```mbti
pub fn BinaryChecked::exp10m1(Self) -> Self
pub fn BinaryChecked::exp10m1_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: as `exp2m1`.

### `BinaryChecked::exp2`, `BinaryChecked::exp2_ctx`

$2^x$, delegated to [`Binary::try_exp2_ctx`](binary.md#binaryexp2-binaryexp2_ctx-binarytry_exp2_ctx).

```mbti
pub fn BinaryChecked::exp2(Self) -> Self
pub fn BinaryChecked::exp2_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::exp10`, `BinaryChecked::exp10_ctx`

$10^x$, delegated to [`Binary::try_exp10_ctx`](binary.md#binaryexp10-binaryexp10_ctx-binarytry_exp10_ctx).

```mbti
pub fn BinaryChecked::exp10(Self) -> Self
pub fn BinaryChecked::exp10_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::ln`, `BinaryChecked::ln_ctx`

$\ln x$, delegated to [`Binary::try_ln_ctx`](binary.md#binaryln-binaryln_ctx-binarytry_ln_ctx).

```mbti
pub fn BinaryChecked::ln(Self) -> Self
pub fn BinaryChecked::ln_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative argument, $-\infty$ included; a `DivisionByZero` error for $\ln(\pm 0)$.

### `BinaryChecked::log1p`, `BinaryChecked::log1p_ctx`

$\ln(1 + x)$, delegated to [`Binary::try_log1p_ctx`](binary.md#binarylog1p-binarylog1p_ctx-binarytry_log1p_ctx).

```mbti
pub fn BinaryChecked::log1p(Self) -> Self
pub fn BinaryChecked::log1p_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` below $-1$, $-\infty$ included; a `DivisionByZero` error for $\operatorname{log1p}(-1)$.

### `BinaryChecked::log2p1`, `BinaryChecked::log2p1_ctx`

$\log_2(1 + x)$, delegated to [`Binary::try_log2p1_ctx`](binary.md#binarylog2p1-binarylog2p1_ctx-binarytry_log2p1_ctx).

```mbti
pub fn BinaryChecked::log2p1(Self) -> Self
pub fn BinaryChecked::log2p1_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` below $-1$, $-\infty$ included, and for a signaling NaN; a `DivisionByZero` error for $\operatorname{log2p1}(-1)$.

### `BinaryChecked::log10p1`, `BinaryChecked::log10p1_ctx`

$\log_{10}(1 + x)$, delegated to [`Binary::try_log10p1_ctx`](binary.md#binarylog10p1-binarylog10p1_ctx-binarytry_log10p1_ctx).

```mbti
pub fn BinaryChecked::log10p1(Self) -> Self
pub fn BinaryChecked::log10p1_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: as `log2p1`.

### `BinaryChecked::log2`, `BinaryChecked::log2_ctx`

$\log_2 x$, delegated to [`Binary::try_log2_ctx`](binary.md#binarylog2-binarylog2_ctx-binarytry_log2_ctx).

```mbti
pub fn BinaryChecked::log2(Self) -> Self
pub fn BinaryChecked::log2_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative argument, $-\infty$ included; a `DivisionByZero` error for $\log_2(\pm 0)$.

### `BinaryChecked::log10`, `BinaryChecked::log10_ctx`

$\log_{10} x$, delegated to [`Binary::try_log10_ctx`](binary.md#binarylog10-binarylog10_ctx-binarytry_log10_ctx).

```mbti
pub fn BinaryChecked::log10(Self) -> Self
pub fn BinaryChecked::log10_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for a negative argument, $-\infty$ included; a `DivisionByZero` error for $\log_{10}(\pm 0)$.

### `BinaryChecked::sin`, `BinaryChecked::sin_ctx`

$\sin x$, delegated to [`Binary::try_sin_ctx`](binary.md#binarysin-binarysin_ctx-binarytry_sin_ctx).

```mbti
pub fn BinaryChecked::sin(Self) -> Self
pub fn BinaryChecked::sin_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinaryChecked::cos`, `BinaryChecked::cos_ctx`

$\cos x$, delegated to [`Binary::try_cos_ctx`](binary.md#binarycos-binarycos_ctx-binarytry_cos_ctx).

```mbti
pub fn BinaryChecked::cos(Self) -> Self
pub fn BinaryChecked::cos_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinaryChecked::tan`, `BinaryChecked::tan_ctx`

$\tan x$, delegated to [`Binary::try_tan_ctx`](binary.md#binarytan-binarytan_ctx-binarytry_tan_ctx).

```mbti
pub fn BinaryChecked::tan(Self) -> Self
pub fn BinaryChecked::tan_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinaryChecked::sinpi`, `BinaryChecked::sinpi_ctx`

$\sin(\pi x)$, delegated to [`Binary::try_sinpi_ctx`](binary.md#binarysinpi-binarysinpi_ctx-binarytry_sinpi_ctx).

```mbti
pub fn BinaryChecked::sinpi(Self) -> Self
pub fn BinaryChecked::sinpi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinaryChecked::cospi`, `BinaryChecked::cospi_ctx`

$\cos(\pi x)$, delegated to [`Binary::try_cospi_ctx`](binary.md#binarycospi-binarycospi_ctx-binarytry_cospi_ctx).

```mbti
pub fn BinaryChecked::cospi(Self) -> Self
pub fn BinaryChecked::cospi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument.

### `BinaryChecked::tanpi`, `BinaryChecked::tanpi_ctx`

$\tan(\pi x)$, delegated to [`Binary::try_tanpi_ctx`](binary.md#binarytanpi-binarytanpi_ctx-binarytry_tanpi_ctx).

```mbti
pub fn BinaryChecked::tanpi(Self) -> Self
pub fn BinaryChecked::tanpi_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for an infinite argument; a `DivisionByZero` error at half-integers, the poles of §9.2.1.

### `BinaryChecked::asin`, `BinaryChecked::asin_ctx`

$\arcsin x$, delegated to [`Binary::try_asin_ctx`](binary.md#binaryasin-binaryasin_ctx-binarytry_asin_ctx).

```mbti
pub fn BinaryChecked::asin(Self) -> Self
pub fn BinaryChecked::asin_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` outside $[-1, 1]$, infinities included.

### `BinaryChecked::acos`, `BinaryChecked::acos_ctx`

$\arccos x$, delegated to [`Binary::try_acos_ctx`](binary.md#binaryacos-binaryacos_ctx-binarytry_acos_ctx).

```mbti
pub fn BinaryChecked::acos(Self) -> Self
pub fn BinaryChecked::acos_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` outside $[-1, 1]$, infinities included.

### `BinaryChecked::atan`, `BinaryChecked::atan_ctx`

$\arctan x$, delegated to [`Binary::try_atan_ctx`](binary.md#binaryatan-binaryatan_ctx-binarytry_atan_ctx).

```mbti
pub fn BinaryChecked::atan(Self) -> Self
pub fn BinaryChecked::atan_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::sinh`, `BinaryChecked::sinh_ctx`

$\sinh x$, delegated to [`Binary::try_sinh_ctx`](binary.md#binarysinh-binarysinh_ctx-binarytry_sinh_ctx).

```mbti
pub fn BinaryChecked::sinh(Self) -> Self
pub fn BinaryChecked::sinh_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::cosh`, `BinaryChecked::cosh_ctx`

$\cosh x$, delegated to [`Binary::try_cosh_ctx`](binary.md#binarycosh-binarycosh_ctx-binarytry_cosh_ctx).

```mbti
pub fn BinaryChecked::cosh(Self) -> Self
pub fn BinaryChecked::cosh_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::tanh`, `BinaryChecked::tanh_ctx`

$\tanh x$, delegated to [`Binary::try_tanh_ctx`](binary.md#binarytanh-binarytanh_ctx-binarytry_tanh_ctx).

```mbti
pub fn BinaryChecked::tanh(Self) -> Self
pub fn BinaryChecked::tanh_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::asinh`, `BinaryChecked::asinh_ctx`

$\operatorname{asinh} x$, delegated to [`Binary::try_asinh_ctx`](binary.md#binaryasinh-binaryasinh_ctx-binarytry_asinh_ctx).

```mbti
pub fn BinaryChecked::asinh(Self) -> Self
pub fn BinaryChecked::asinh_ctx(Self, @binary.BinaryContext) -> Self
```

### `BinaryChecked::acosh`, `BinaryChecked::acosh_ctx`

$\operatorname{acosh} x$, delegated to [`Binary::try_acosh_ctx`](binary.md#binaryacosh-binaryacosh_ctx-binarytry_acosh_ctx).

```mbti
pub fn BinaryChecked::acosh(Self) -> Self
pub fn BinaryChecked::acosh_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` below $1$.

### `BinaryChecked::atanh`, `BinaryChecked::atanh_ctx`

$\operatorname{atanh} x$, delegated to [`Binary::try_atanh_ctx`](binary.md#binaryatanh-binaryatanh_ctx-binarytry_atanh_ctx).

```mbti
pub fn BinaryChecked::atanh(Self) -> Self
pub fn BinaryChecked::atanh_ctx(Self, @binary.BinaryContext) -> Self
```

Errors: a `DomainError` for $|x| > 1$; a `DivisionByZero` error for $\operatorname{atanh}(\pm 1)$.

### `BinaryChecked::atan2`, `BinaryChecked::atan2_ctx`

The angle of the point $(\text{abscissa}, \text{self})$, delegated to
[`Binary::try_atan2_ctx`](binary.md#binaryatan2-binaryatan2_ctx-binarytry_atan2_ctx).

```mbti
pub fn BinaryChecked::atan2(Self, Self) -> Self
pub fn BinaryChecked::atan2_ctx(Self, Self, @binary.BinaryContext) -> Self
```

Errors are taken in the order ordinate, abscissa, operation. `atan2` uses
`BinaryContext::new(precision=p)` at the larger operand precision. Signed zeros
follow IEEE 754: `atan2` of $(-0, -0)$ is $-\pi$ and of $(-0, +0)$ is $-0$.
A signaling NaN operand is a `DomainError`; `atan2` raises no other
exception.

```moonbit
///|
test "elementary functions" {
  let r = fn(n : Int) { @binary_checked.BinaryChecked::from_int(n) }
  inspect(show(r(2).ln()), content="6243314768165359p-53")
  inspect(
    show(r(2).ln_ctx(@binary.BinaryContext::new(precision=24))),
    content="1453635p-21",
  )
  inspect(show(r(0).ln()), content="error: ln: division by zero")
  inspect(show(r(-4).ln()), content="error: ln: invalid operation")
  inspect(show(r(2).asin()), content="error: asin: invalid operation")
  inspect(show(r(0).exp().ln()), content="0")
}
```

## Trait implementations

### `Add`, `Sub`, `Mul`, `Div` and `Neg` for `BinaryChecked`

The operators `+`, `-`, `*`, `/` and unary `-` call `add`, `sub`, `mul`, `div`
and `neg`.

```mbti
pub impl Add for BinaryChecked
pub impl Sub for BinaryChecked
pub impl Mul for BinaryChecked
pub impl Div for BinaryChecked
pub impl Neg for BinaryChecked
```

So `/` on wrappers reports division by zero, while `/` on plain `Binary`
values returns an infinity.

## Deprecated

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/binary_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/binary",
}

// Values

// Errors

// Types and methods
pub struct BinaryChecked {
  // private fields
}
pub fn BinaryChecked::abs(Self) -> Self
pub fn BinaryChecked::acos(Self) -> Self
pub fn BinaryChecked::acos_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::acosh(Self) -> Self
pub fn BinaryChecked::acosh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::acospi(Self) -> Self
pub fn BinaryChecked::acospi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::add(Self, Self) -> Self
pub fn BinaryChecked::add_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::asin(Self) -> Self
pub fn BinaryChecked::asin_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::asinh(Self) -> Self
pub fn BinaryChecked::asinh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::asinpi(Self) -> Self
pub fn BinaryChecked::asinpi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::atan(Self) -> Self
pub fn BinaryChecked::atan2(Self, Self) -> Self
pub fn BinaryChecked::atan2_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::atan2pi(Self, Self) -> Self
pub fn BinaryChecked::atan2pi_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::atan_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::atanh(Self) -> Self
pub fn BinaryChecked::atanh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::atanpi(Self) -> Self
pub fn BinaryChecked::atanpi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::bind(Self, (@binary.Binary) -> Self) -> Self
pub fn BinaryChecked::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinaryChecked::compound(Self, Int32) -> Self
pub fn BinaryChecked::compound_ctx(Self, Int32, @binary.BinaryContext) -> Self
pub fn BinaryChecked::cos(Self) -> Self
pub fn BinaryChecked::cos_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::cosh(Self) -> Self
pub fn BinaryChecked::cosh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::cospi(Self) -> Self
pub fn BinaryChecked::cospi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::div(Self, Self) -> Self
pub fn BinaryChecked::div_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::err(@arithmetic.ArithmeticError) -> Self
pub fn BinaryChecked::error(Self) -> @arithmetic.ArithmeticError?
pub fn BinaryChecked::exp(Self) -> Self
pub fn BinaryChecked::exp10(Self) -> Self
pub fn BinaryChecked::exp10_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::exp10m1(Self) -> Self
pub fn BinaryChecked::exp10m1_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::exp2(Self) -> Self
pub fn BinaryChecked::exp2_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::exp2m1(Self) -> Self
pub fn BinaryChecked::exp2m1_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::exp_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::expm1(Self) -> Self
pub fn BinaryChecked::expm1_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::from_coefficient(@binary.BinCoeff, precision? : Int32, negative? : Bool) -> Self
pub fn BinaryChecked::from_double(Double, precision? : Int32) -> Self
pub fn BinaryChecked::from_float(Float, precision? : Int32) -> Self
pub fn BinaryChecked::from_int(Int32, precision? : Int32) -> Self
pub fn BinaryChecked::from_result(Result[@binary.Binary, @arithmetic.ArithmeticError]) -> Self
pub fn BinaryChecked::hypot(Self, Self) -> Self
pub fn BinaryChecked::hypot_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::is_err(Self) -> Bool
pub fn BinaryChecked::is_ok(Self) -> Bool
pub fn BinaryChecked::ln(Self) -> Self
pub fn BinaryChecked::ln_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::log10(Self) -> Self
pub fn BinaryChecked::log10_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::log10p1(Self) -> Self
pub fn BinaryChecked::log10p1_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::log1p(Self) -> Self
pub fn BinaryChecked::log1p_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::log2(Self) -> Self
pub fn BinaryChecked::log2_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::log2p1(Self) -> Self
pub fn BinaryChecked::log2p1_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::map(Self, (@binary.Binary) -> @binary.Binary) -> Self
pub fn BinaryChecked::max_num(Self, Self) -> Self
pub fn BinaryChecked::min_num(Self, Self) -> Self
pub fn BinaryChecked::mul(Self, Self) -> Self
pub fn BinaryChecked::mul_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::neg(Self) -> Self
pub fn BinaryChecked::normalized(Self) -> Self
pub fn BinaryChecked::ok(@binary.Binary) -> Self
pub fn BinaryChecked::pow(Self, Self) -> Self
pub fn BinaryChecked::pow_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::pow_nat(Self, UInt32) -> Self
pub fn BinaryChecked::pown(Self, Int32) -> Self
pub fn BinaryChecked::pown_ctx(Self, Int32, @binary.BinaryContext) -> Self
pub fn BinaryChecked::powr(Self, Self) -> Self
pub fn BinaryChecked::powr_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::result(Self) -> Result[@binary.Binary, @arithmetic.ArithmeticError]
pub fn BinaryChecked::rootn(Self, Int32) -> Self
pub fn BinaryChecked::rootn_ctx(Self, Int32, @binary.BinaryContext) -> Self
pub fn BinaryChecked::rsqrt(Self) -> Self
pub fn BinaryChecked::rsqrt_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sin(Self) -> Self
pub fn BinaryChecked::sin_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sinh(Self) -> Self
pub fn BinaryChecked::sinh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sinpi(Self) -> Self
pub fn BinaryChecked::sinpi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sqrt(Self) -> Self
pub fn BinaryChecked::sqrt_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::sub(Self, Self) -> Self
pub fn BinaryChecked::sub_ctx(Self, Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::tan(Self) -> Self
pub fn BinaryChecked::tan_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::tanh(Self) -> Self
pub fn BinaryChecked::tanh_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::tanpi(Self) -> Self
pub fn BinaryChecked::tanpi_ctx(Self, @binary.BinaryContext) -> Self
pub fn BinaryChecked::ulp(Self) -> Self
pub fn BinaryChecked::with_precision(Self, Int32, @binary.BinaryRoundingMode) -> Self
pub impl Add for BinaryChecked
pub impl Div for BinaryChecked
pub impl Mul for BinaryChecked
pub impl Neg for BinaryChecked
pub impl Sub for BinaryChecked

// Type aliases

// Traits
```
<!-- generated-api-end -->
