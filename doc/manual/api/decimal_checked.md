# decimal_checked API

## Purpose

`decimal_checked` provides `DecimalChecked`, an immutable pipeline state for
IEEE 754 decimal arithmetic with [`decimal`](decimal.md). It stores the
current value, one `DecimalContext`, the flags raised by the latest step, the
flags accumulated over all steps, and an optional `ArithmeticError`. Each
operation applies the matching `Decimal::*_ctx` operation under the stored
context. IEEE exceptional results (infinities, NaNs, rounded values) remain
values and only set flags; only failure to certify an elementary function records
an error and stops the pipeline. The
[tutorial](../tutorial/decimal_checked.md) shows typical pipelines; the
[design page](../design/decimal_checked.md) models the state as a writer monad
over the flag monoid and proves that the accumulated flags are the union of the
per-step flags.

## Importing

Add both packages to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/decimal_checked",
}
```

The examples use the aliases `@decimal_checked.` and `@decimal.`, and list
flags with this helper:

```moonbit
///|
fn flags(f : @decimal.DecimalFlags) -> String {
  let named = [
    ("inexact", f.inexact()),
    ("invalid_operation", f.invalid_operation()),
    ("division_by_zero", f.division_by_zero()),
    ("overflow", f.overflow()),
    ("underflow", f.underflow()),
    ("not_computed", f.not_computed()),
  ]
  [ for p in named if p.1 => p.0 ].join(",")
}
```

## The state type

### `DecimalChecked`

`DecimalChecked` stores the state of an IEEE decimal pipeline.

```mbti
pub struct DecimalChecked {
  // private fields
}
```

Write a state as $\sigma = (v, c, r, F, \varepsilon)$: value $v$, context $c$,
raised flags $r$ of the latest step, accumulated flags $F$, and error
$\varepsilon$ (absent or one `ArithmeticError`). Every operation returns a new
state; nothing is mutated.

## Construction

### `DecimalChecked::from_decimal`

`from_decimal(value, context)` rounds a value into the context.

```mbti
pub fn DecimalChecked::from_decimal(@decimal.Decimal, @decimal.DecimalContext) -> Self
```

It applies `Decimal::apply_ctx`, which rounds the value to the context's
precision and exponent range, and records the resulting flags as both raised
and accumulated.

### `DecimalChecked::parse`

`parse(source, context)` converts a decimal string under the context.

```mbti
pub fn DecimalChecked::parse(String, @decimal.DecimalContext) -> Self
```

It uses `Decimal::from_string_ctx`. Extra digits are rounded (`inexact`);
an invalid string gives a NaN value with `invalid_operation` raised,
not an error.

### `DecimalChecked::from_int`, `from_bigint`, `from_double`, `from_float`

Convert a MoonBit number into the pipeline.

```mbti
pub fn DecimalChecked::from_int(Int32, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
```

`from_int` and `from_bigint` parse the integer's decimal string, so an integer
longer than the precision is rounded with flags. `from_double` first converts
the binary value to a decimal of 17 significant digits and `from_float` to 9
digits (enough to identify the binary value), then rounds into the context with
`from_decimal`. So `from_double(0.1, decimal64)` is `0.1000000000000000` with
`inexact` raised.

This is a conversion in two roundings, not the correctly rounded value of the
binary number. With a context precision above 17 (decimal128) the result keeps
only 17 digits: `from_double(0.1, decimal128)` is `0.10000000000000001`, not
the exact `0.1000000000000000055511151231257827`, and its flags describe only
the second rounding. With a precision below 17 the half modes can round twice
(a 17-digit midpoint created by the first rounding). For the exact binary
value use `from_decimal(Decimal::from_double(x, precision=p), context)` with
`p = 767`, which holds every `Double` exactly.

```moonbit
///|
test "construction records conversion flags" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let parsed = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
  inspect(parsed.value().to_string(), content="1.2346")
  inspect(flags(parsed.raised()), content="inexact")
  let bad = @decimal_checked.DecimalChecked::parse("abc", ctx)
  inspect(bad.value().to_string(), content="nan")
  inspect(bad.is_ok(), content="true")
  inspect(
    flags(bad.raised()).contains("invalid_operation"),
    content="true",
  )
  let tenth = @decimal_checked.DecimalChecked::from_double(
    0.1,
    @decimal.DecimalContext::decimal64(),
  )
  inspect(tenth.value().to_string(), content="0.1000000000000000")
}
```

## Observation

### `DecimalChecked::value`, `context`, `raised`, `flags`

Read the components of the state.

```mbti
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
```

`raised()` is $r$, the flags of the latest successful step only. `flags()` is
$F$, the bitwise OR of the flags of every successful step since construction
or the last `clear_flags`. After an error, `value` keeps the value reached
before the failing step. So do `raised` and `flags` for a method without a
pipeline operand. A method with pipeline operands (the binary methods and
`fma`) also takes their flags: `flags` gains theirs, and `raised` is theirs when
an operand holds the error, otherwise the earlier `raised` joined with theirs.

### `DecimalChecked::result`

`result` returns the value with the accumulated flags, or the error.

```mbti
pub fn DecimalChecked::result(Self) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @arithmetic.ArithmeticError]
```

`result()` returns $\mathrm{Err}(\varepsilon)$ when an error is recorded and
$\mathrm{Ok}((v, F))$ otherwise. It is the only method that returns the value
with accumulated flags; `value()` and `flags()` remain available after an
error, and there is no separate `outcome()`.

### `DecimalChecked::is_ok`, `is_err`, `error`

Test for and read the recorded error.

```mbti
pub fn DecimalChecked::is_ok(Self) -> Bool
pub fn DecimalChecked::is_err(Self) -> Bool
pub fn DecimalChecked::error(Self) -> @arithmetic.ArithmeticError?
```

## Controlling the state

### `DecimalChecked::clear_flags`

`clear_flags()` resets both $r$ and $F$ to the empty flag set.

```mbti
pub fn DecimalChecked::clear_flags(Self) -> Self
```

The value, context and error stay unchanged. The method also applies to a
state with an error.

### `DecimalChecked::with_context`

Switch to a new context and round the current value into it.

```mbti
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self
```

`with_context(context)` reapplies the value with `apply_ctx` under the new context; the new flags
become $r$ and are ORed into $F$. On a state with an error it returns the state
unchanged.

### `DecimalChecked::apply`

`apply()` rounds the current value into the stored context and records its flags.

```mbti
pub fn DecimalChecked::apply(Self) -> Self
```

```moonbit
///|
test "raised versus accumulated flags" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let start = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
  let step = start.add(@decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::from_int(1), ctx))
  inspect(flags(step.raised()), content="")
  inspect(flags(step.flags()), content="inexact")
  let infinite = step.div(@decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::zero(), ctx))
  inspect(infinite.value().to_string(), content="inf")
  inspect(flags(infinite.raised()), content="division_by_zero")
  inspect(flags(infinite.flags()), content="inexact,division_by_zero")
  inspect(flags(infinite.clear_flags().flags()), content="")
  let wider = @decimal_checked.DecimalChecked::parse(
    "1.234567",
    @decimal.DecimalContext::decimal64(),
  ).with_context(ctx)
  inspect(wider.value().to_string(), content="1.2346")
}
```

## Operations that cannot fail

### `DecimalChecked::abs`, `add`, `sub`, `mul`, `div`, `fma`, `sqrt`, `quantize`, `quantum`, `remainder`, `minimum_number`, `maximum_number`, `next_down`, `next_up`

These methods apply the corresponding IEEE decimal operation to the current
value, and to the pipeline operands of the methods that take them, under the
stored context of the left pipeline. A right operand is a `DecimalChecked`: an error of the left pipeline stays,
an error of the right one is taken before the operation runs (the value of the
left pipeline is kept), and the conditions of the right pipeline join
`raised` and `flags`.

`DecimalChecked::from_decimal(x, ctx)` lifts a plain value by applying the context. A
signaling NaN is quieted and raises `invalid_operation` during this lift. To
use the operand exactly, as IEEE 754-2019 5.1 does (operands exact, one
rounding of the result), lift it in a context wide enough to hold it, for
example `decimal128`; lifting it in the context of the left pipeline rounds it
first and then the result, two roundings. At three digits, half-even,
`1.00 + 0.24500001` is `1.25` with the operand lifted in a wide context, and
`1.24` with the operand lifted at three digits (it becomes `0.245` with
`inexact`, and `1.00 + 0.245` is a tie that rounds to even); each is right for
what was asked.

```mbti
pub fn DecimalChecked::abs(Self) -> Self
pub fn DecimalChecked::add(Self, Self) -> Self
pub fn DecimalChecked::sub(Self, Self) -> Self
pub fn DecimalChecked::mul(Self, Self) -> Self
pub fn DecimalChecked::div(Self, Self) -> Self
pub fn DecimalChecked::fma(Self, Self, Self) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::quantize(Self, Self) -> Self
pub fn DecimalChecked::quantum(Self) -> Self
pub fn DecimalChecked::remainder(Self, Self) -> Self
pub fn DecimalChecked::minimum_number(Self, Self) -> Self
pub fn DecimalChecked::maximum_number(Self, Self) -> Self
pub fn DecimalChecked::next_down(Self) -> Self
pub fn DecimalChecked::next_up(Self) -> Self
```

| Method | Delegates to | Result |
| --- | --- | --- |
| `abs` | `abs_ctx` | $\lvert v\rvert$ rounded into the context |
| `add`, `sub`, `mul`, `div` | `add_ctx`, … | $v \circ y$ correctly rounded |
| `fma(m, a)` | `fma_ctx` | $v \cdot m + a$ with one rounding |
| `sqrt` | `sqrt_ctx` | $\sqrt{v}$ correctly rounded |
| `quantize(q)` | `quantize_ctx` | $v$ rounded to the exponent of `q` |
| `quantum()` | `quantum_ctx` | the number $10^q$ for the exponent $q$ of $v$ (IEEE 754-2019 5.3.2) |
| `remainder(d)` | `remainder_ctx` | IEEE remainder $v - d \cdot n$, $n$ = $v/d$ rounded to nearest, ties to even |
| `minimum_number`, `maximum_number` | `minimum_number_ctx`, `maximum_number_ctx` | IEEE 754-2019 9.6 `minimumNumber`/`maximumNumber`: a quiet NaN loses to a number; a signaling NaN gives the number and raises `invalid_operation` |
| `next_down`, `next_up` | `next_down_ctx`, `next_up_ctx` | adjacent representable value |

The General Decimal Arithmetic `min` and `max` operations are in
`decimal_gda`, not this IEEE wrapper.

An operation on a state with an error returns it unchanged. Otherwise the
context operation produces $(v', r') = \mathrm{op}(v, c)$ and the new state is
$(v', c, r', F \lor r', \text{none})$ for a method without a pipeline operand.
For the binary methods and `fma`, whose operands have raised flags $r_o$ and
accumulated flags $F_o$ (joined over the operands of `fma`), it is
$(v', c, r' \lor r_o, F \lor r' \lor F_o, \text{none})$. An invalid operation returns NaN
with `invalid_operation`; division by zero returns an infinity with
`division_by_zero`; overflow returns an infinity or the largest finite value
with `overflow` and `inexact`, as in IEEE 754 decimal arithmetic.

```moonbit
///|
test "exceptional results are values" {
  let ctx = @decimal.DecimalContext::decimal64()
  let negative = @decimal_checked.DecimalChecked::from_int(-1, ctx).sqrt()
  inspect(negative.value().to_string(), content="nan")
  inspect(flags(negative.raised()), content="invalid_operation")
  inspect(negative.is_ok(), content="true")
  let big = @decimal_checked.DecimalChecked::parse("9e384", ctx).mul(
    @decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::from_int(10), ctx),
  )
  inspect(big.value().to_string(), content="inf")
  inspect(flags(big.raised()), content="inexact,overflow")
  let cents = @decimal_checked.DecimalChecked::parse("2.675", ctx).quantize(
    @decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::from_string("0.01").unwrap(), ctx),
  )
  inspect(cents.value().to_string(), content="2.68")
}
```

## Operations that can record an error

### `DecimalChecked::exp`, `exp2`, `exp10`, `expm1`, `exp2m1`, `exp10m1`, `ln`, `log2`, `log10`, `log1p`, `log2p1`, `log10p1`, `rsqrt`, `compound`, `powr`, `pow`, `pown`, `rootn`, `hypot`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `asinpi`, `acospi`, `atanpi`, `atan2pi`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`

Apply the certified `Decimal::try_*_ctx` function with the same name.

```mbti
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::exp2(Self) -> Self
pub fn DecimalChecked::exp10(Self) -> Self
pub fn DecimalChecked::expm1(Self) -> Self
pub fn DecimalChecked::exp2m1(Self) -> Self
pub fn DecimalChecked::exp10m1(Self) -> Self
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log2(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
pub fn DecimalChecked::log1p(Self) -> Self
pub fn DecimalChecked::log2p1(Self) -> Self
pub fn DecimalChecked::log10p1(Self) -> Self
pub fn DecimalChecked::rsqrt(Self) -> Self
pub fn DecimalChecked::compound(Self, Int32) -> Self
pub fn DecimalChecked::powr(Self, Self) -> Self
pub fn DecimalChecked::pow(Self, Self) -> Self
pub fn DecimalChecked::pown(Self, Int32) -> Self
pub fn DecimalChecked::rootn(Self, Int32) -> Self
pub fn DecimalChecked::hypot(Self, Self) -> Self
pub fn DecimalChecked::sin(Self) -> Self
pub fn DecimalChecked::cos(Self) -> Self
pub fn DecimalChecked::tan(Self) -> Self
pub fn DecimalChecked::sinpi(Self) -> Self
pub fn DecimalChecked::cospi(Self) -> Self
pub fn DecimalChecked::tanpi(Self) -> Self
pub fn DecimalChecked::asin(Self) -> Self
pub fn DecimalChecked::acos(Self) -> Self
pub fn DecimalChecked::atan(Self) -> Self
pub fn DecimalChecked::atan2(Self, Self) -> Self
pub fn DecimalChecked::asinpi(Self) -> Self
pub fn DecimalChecked::acospi(Self) -> Self
pub fn DecimalChecked::atanpi(Self) -> Self
pub fn DecimalChecked::atan2pi(Self, Self) -> Self
pub fn DecimalChecked::sinh(Self) -> Self
pub fn DecimalChecked::cosh(Self) -> Self
pub fn DecimalChecked::tanh(Self) -> Self
pub fn DecimalChecked::asinh(Self) -> Self
pub fn DecimalChecked::acosh(Self) -> Self
pub fn DecimalChecked::atanh(Self) -> Self
```

The results follow `decimal`, including its exact result for some non-integral
powers before refinement; see [elementary functions](decimal.md#elementary-functions).
For example, $0.0016^{0.25} = 0.2$ is exact. `atan2` with zero or infinite
operands returns IEEE values; an `atan2` of $+\infty$ and 1 returns $\pi/2$,
inexact.
Domain violations also return IEEE values with flags: `ln` of a negative
number returns NaN with `invalid_operation`, and `tanpi(0.5)` returns an
infinity with `division_by_zero`.

These methods record an error only when `try_*_ctx` returns `Err` with a
`CertificationFailure`, meaning the correctly rounded result could not be
certified within the refinement budget. In that case the new state is
$(v, c, r, F, \mathrm{Some}(e))$; the value and flags from before the step
remain. For `powr`, `pow`, `hypot`, `atan2` and `atan2pi`, which take a
pipeline operand, the flags of the operand still join `raised` and `flags` as
described under Observation.

> [!IMPORTANT]
> As an implementation limit (`DEC_MAX_MATH` in decNumber, required by the
> decTest suite and permitted by the GDA Invalid context condition), these
> operations require, by default, context precision and exponent limits within
> 999,999. A
> context with `e_max` above 999,999, or with precision of 1,000 digits or more
> and no explicit `e_max`, returns NaN with `not_computed`; the `try_` forms
> return `Err` with a certification failure.
> Use `decimal32()`, `decimal64()`, `decimal128()` or an explicit `e_max` no
> greater than 999,999. `pow` and `pown` with an integral exponent, and `pow`
> with exponent `0.5`, are not restricted in `e_max`, but like the others they
> are held to the context's `elementary_precision_limit` (999,999 digits by
> default; `with_elementary_precision_limit(None)` removes it).

```moonbit
///|
test "elementary functions under a bounded context" {
  let ctx = @decimal.DecimalContext::decimal64()
  let ln2 = @decimal_checked.DecimalChecked::from_int(2, ctx).ln()
  inspect(ln2.value().to_string(), content="0.6931471805599453")
  inspect(flags(ln2.raised()), content="inexact")
  let unbounded = @decimal_checked.DecimalChecked::from_int(
    2,
    @decimal.DecimalContext::new(precision=16, e_max=999_999_999),
  ).ln()
  // a context beyond the kernels is the error of the certification-failure kind
  inspect(unbounded.error().unwrap().is_certification_failure(), content="true")
  inspect(unbounded.error().unwrap().is_domain_error(), content="false")
  let pole = @decimal_checked.DecimalChecked::parse("0.5", ctx).tanpi()
  inspect(flags(pole.raised()), content="division_by_zero")
}
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/decimal",
  "moonbitlang/core/bigint",
}

// Values

// Errors

// Types and methods
pub struct DecimalChecked {
  // private fields
}
pub fn DecimalChecked::abs(Self) -> Self
pub fn DecimalChecked::acos(Self) -> Self
pub fn DecimalChecked::acosh(Self) -> Self
pub fn DecimalChecked::acospi(Self) -> Self
pub fn DecimalChecked::add(Self, Self) -> Self
pub fn DecimalChecked::apply(Self) -> Self
pub fn DecimalChecked::asin(Self) -> Self
pub fn DecimalChecked::asinh(Self) -> Self
pub fn DecimalChecked::asinpi(Self) -> Self
pub fn DecimalChecked::atan(Self) -> Self
pub fn DecimalChecked::atan2(Self, Self) -> Self
pub fn DecimalChecked::atan2pi(Self, Self) -> Self
pub fn DecimalChecked::atanh(Self) -> Self
pub fn DecimalChecked::atanpi(Self) -> Self
pub fn DecimalChecked::clear_flags(Self) -> Self
pub fn DecimalChecked::compound(Self, Int32) -> Self
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::cos(Self) -> Self
pub fn DecimalChecked::cosh(Self) -> Self
pub fn DecimalChecked::cospi(Self) -> Self
pub fn DecimalChecked::div(Self, Self) -> Self
pub fn DecimalChecked::error(Self) -> @arithmetic.ArithmeticError?
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::exp10(Self) -> Self
pub fn DecimalChecked::exp10m1(Self) -> Self
pub fn DecimalChecked::exp2(Self) -> Self
pub fn DecimalChecked::exp2m1(Self) -> Self
pub fn DecimalChecked::expm1(Self) -> Self
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::fma(Self, Self, Self) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_decimal(@decimal.Decimal, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_int(Int32, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::hypot(Self, Self) -> Self
pub fn DecimalChecked::is_err(Self) -> Bool
pub fn DecimalChecked::is_ok(Self) -> Bool
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
pub fn DecimalChecked::log10p1(Self) -> Self
pub fn DecimalChecked::log1p(Self) -> Self
pub fn DecimalChecked::log2(Self) -> Self
pub fn DecimalChecked::log2p1(Self) -> Self
pub fn DecimalChecked::maximum_number(Self, Self) -> Self
pub fn DecimalChecked::minimum_number(Self, Self) -> Self
pub fn DecimalChecked::mul(Self, Self) -> Self
pub fn DecimalChecked::next_down(Self) -> Self
pub fn DecimalChecked::next_up(Self) -> Self
pub fn DecimalChecked::parse(String, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::pow(Self, Self) -> Self
pub fn DecimalChecked::pown(Self, Int32) -> Self
pub fn DecimalChecked::powr(Self, Self) -> Self
pub fn DecimalChecked::quantize(Self, Self) -> Self
pub fn DecimalChecked::quantum(Self) -> Self
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::remainder(Self, Self) -> Self
pub fn DecimalChecked::result(Self) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @arithmetic.ArithmeticError]
pub fn DecimalChecked::rootn(Self, Int32) -> Self
pub fn DecimalChecked::rsqrt(Self) -> Self
pub fn DecimalChecked::sin(Self) -> Self
pub fn DecimalChecked::sinh(Self) -> Self
pub fn DecimalChecked::sinpi(Self) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::sub(Self, Self) -> Self
pub fn DecimalChecked::tan(Self) -> Self
pub fn DecimalChecked::tanh(Self) -> Self
pub fn DecimalChecked::tanpi(Self) -> Self
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
