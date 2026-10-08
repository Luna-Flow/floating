# decimal_checked API

## Purpose

`decimal_checked` provides `DecimalChecked`, an immutable pipeline state for
IEEE 754 decimal arithmetic with [`decimal`](decimal.md). The state holds the
current value, one `DecimalContext`, the flags raised by the latest step, the
flags accumulated over all steps, and an optional `ArithmeticError`. Each
operation applies the matching `Decimal::*_ctx` operation under the stored
context. IEEE exceptional results (infinities, NaNs, rounded values) remain
values and only set flags; an error is recorded only when an elementary
function cannot certify its result, and it stops the pipeline. The
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
    ("inexact", f.inexact),
    ("rounded", f.rounded),
    ("invalid_operation", f.invalid_operation),
    ("division_by_zero", f.division_by_zero),
    ("overflow", f.overflow),
    ("underflow", f.underflow),
    ("subnormal", f.subnormal),
    ("conversion_syntax", f.conversion_syntax),
    ("invalid_context", f.invalid_context),
  ]
  [ for p in named if p.1 => p.0 ].join(",")
}
```

## The state type

### `DecimalChecked`

`DecimalChecked` is the state of an IEEE decimal pipeline.

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

### `DecimalChecked::from_outcome`

`from_outcome(value, context, flags)` starts a pipeline from a value and the
flags that produced it.

```mbti
pub fn DecimalChecked::from_outcome(@decimal.Decimal, @decimal.DecimalContext, @decimal.DecimalFlags) -> Self
```

The result is $(\textit{value}, c', \textit{flags}, \textit{flags},
\text{none})$ with $c' = \textit{context}.\texttt{ieee754()}$ (on the current
branch `ieee754()` returns the context unchanged). The value is *not*
re-rounded; use it with the `(value, flags)` pair returned by a
`Decimal::*_ctx` call.

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

It uses `Decimal::from_string_ctx`. Extra digits are rounded (`inexact`,
`rounded`); an invalid string gives a NaN value with `conversion_syntax` raised,
not an error.

### `DecimalChecked::from_int`, `from_bigint`, `from_double`, `from_float`

These constructors convert a MoonBit number.

```mbti
pub fn DecimalChecked::from_int(Int, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
```

`from_int` and `from_bigint` parse the integer's decimal string, so integers
longer than the precision are rounded with flags. `from_double` first converts
the binary value to a decimal of 17 significant digits and `from_float` to 9
digits (enough to identify the binary value), then rounds into the context with
`from_decimal`. So `from_double(0.1, decimal64)` is `0.1000000000000000` with
`inexact` and `rounded` raised.

This is a conversion in two roundings, not the correctly rounded value of the
binary number. With a context precision above 17 (decimal128) the result keeps
only 17 digits: `from_double(0.1, decimal128)` is `0.10000000000000001`, not
the exact `0.1000000000000000055511151231257827`, and its flags describe only
the second rounding. With a precision below 17 the half modes can round twice
(a 17-digit midpoint created by the first rounding). For the exact binary
value use `from_decimal(Decimal::from_double(x, precision=p), context)` with
`p` at least the context precision plus one, or with `p = 767`, which holds
every `Double` exactly.

```moonbit
///|
test "construction records conversion flags" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let parsed = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
  inspect(parsed.value().to_string(), content="1.2346")
  inspect(flags(parsed.raised()), content="inexact,rounded")
  let bad = @decimal_checked.DecimalChecked::parse("abc", ctx)
  inspect(bad.value().to_string(), content="nan")
  inspect(bad.is_ok(), content="true")
  inspect(
    flags(bad.raised()).contains("conversion_syntax"),
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

These accessors return the components of the state.

```mbti
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
```

`raised()` is $r$, the flags of the latest successful step only. `flags()` is
$F$, the bitwise OR of the flags of every successful step since construction
or the last `clear_flags`. After an error, `value`, `raised` and `flags` keep
the state reached before the failing step.

### `DecimalChecked::outcome`, `result`

These methods return the value with the accumulated flags.

```mbti
pub fn DecimalChecked::outcome(Self) -> (@decimal.Decimal, @decimal.DecimalFlags)
pub fn DecimalChecked::result(Self) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @arithmetic.ArithmeticError]
```

`outcome()` is $(v, F)$ regardless of the error; `result()` is
$\mathrm{Err}(\varepsilon)$ when an error is recorded and
$\mathrm{Ok}((v, F))$ otherwise.

### `DecimalChecked::is_ok`, `is_err`, `error`

These methods test for and return the recorded error.

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

Value, context and error are kept. It also applies to a state with an error.

### `DecimalChecked::with_context`

`with_context(context)` switches to a new context and rounds the current value
into it.

```mbti
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self
```

The value is re-applied with `apply_ctx` under the new context; the new flags
become $r$ and are ORed into $F$. On a state with an error it returns the state
unchanged.

### `DecimalChecked::apply`

`apply()` rounds the current value into the stored context and records the
flags.

```mbti
pub fn DecimalChecked::apply(Self) -> Self
```

```moonbit
///|
test "raised versus accumulated flags" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let start = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
  let step = start.add(@decimal.Decimal::from_int(1))
  inspect(flags(step.raised()), content="")
  inspect(flags(step.flags()), content="inexact,rounded")
  let infinite = step.div(@decimal.Decimal::zero())
  inspect(infinite.value().to_string(), content="inf")
  inspect(flags(infinite.raised()), content="division_by_zero")
  inspect(flags(infinite.flags()), content="inexact,rounded,division_by_zero")
  inspect(flags(infinite.clear_flags().flags()), content="")
  let wider = @decimal_checked.DecimalChecked::parse(
    "1.234567",
    @decimal.DecimalContext::decimal64(),
  ).with_context(ctx)
  inspect(wider.value().to_string(), content="1.2346")
}
```

## Operations that cannot fail

### `DecimalChecked::plus`, `minus`, `abs`, `add`, `sub`, `mul`, `div`, `fma`, `sqrt`, `quantize`, `remainder`, `reduce`, `min`, `max`, `next_minus`, `next_plus`, `next_toward`

These methods apply the IEEE decimal operation of the same meaning to the
current value and a plain `Decimal` operand under the stored context.

```mbti
pub fn DecimalChecked::plus(Self) -> Self
pub fn DecimalChecked::minus(Self) -> Self
pub fn DecimalChecked::abs(Self) -> Self
pub fn DecimalChecked::add(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::sub(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::mul(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::div(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::fma(Self, @decimal.Decimal, @decimal.Decimal) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::quantize(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::remainder(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::reduce(Self) -> Self
pub fn DecimalChecked::min(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::max(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::next_minus(Self) -> Self
pub fn DecimalChecked::next_plus(Self) -> Self
pub fn DecimalChecked::next_toward(Self, @decimal.Decimal) -> Self
```

| Method | Delegates to | Result |
| --- | --- | --- |
| `plus`, `minus`, `abs` | `plus_ctx`, `minus_ctx`, `abs_ctx` | $+v$, $-v$, $\lvert v\rvert$ rounded into the context |
| `add`, `sub`, `mul`, `div` | `add_ctx`, … | $v \circ y$ correctly rounded |
| `fma(m, a)` | `fma_ctx` | $v \cdot m + a$ with one rounding |
| `sqrt` | `sqrt_ctx` | $\sqrt{v}$ correctly rounded |
| `quantize(q)` | `quantize` | $v$ rounded to the exponent of `q` |
| `remainder(d)` | `remainder_ctx` | IEEE remainder $v - d \cdot n$, $n$ = $v/d$ rounded to nearest, ties to even |
| `reduce` | `reduce_ctx` | $v$ with trailing zeros removed |
| `min`, `max` | `min_ctx`, `max_ctx` | General Decimal Arithmetic `min`/`max`: a quiet NaN loses to a number (IEEE 754-2008 minNum/maxNum, not the 2019 `minimum`) |
| `next_minus`, `next_plus`, `next_toward(t)` | same names | adjacent representable value |

If an error is recorded, each method returns the state unchanged. Otherwise
the step $(v', r') = \mathrm{op}(v, c)$ gives the new state $(v', c, r',
F \lor r', \text{none})$. Invalid operations produce NaN with
`invalid_operation`, division by zero produces an infinity with
`division_by_zero`, overflow produces an infinity or the largest finite number
with `overflow`, `inexact` and `rounded`, as in IEEE 754 decimal arithmetic.

```moonbit
///|
test "exceptional results are values" {
  let ctx = @decimal.DecimalContext::decimal64()
  let negative = @decimal_checked.DecimalChecked::from_int(-1, ctx).sqrt()
  inspect(negative.value().to_string(), content="nan")
  inspect(flags(negative.raised()), content="invalid_operation")
  inspect(negative.is_ok(), content="true")
  let big = @decimal_checked.DecimalChecked::parse("9e384", ctx).mul(
    @decimal.Decimal::from_int(10),
  )
  inspect(big.value().to_string(), content="inf")
  inspect(flags(big.raised()), content="inexact,rounded,overflow")
  let cents = @decimal_checked.DecimalChecked::parse("2.675", ctx).quantize(
    @decimal.Decimal::from_string("0.01").unwrap(),
  )
  inspect(cents.value().to_string(), content="2.68")
}
```

## Operations that can record an error

### `DecimalChecked::exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `power`, `pown`, `rootn`, `hypot`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`

These methods apply the certified `Decimal::try_*_ctx` functions of the same
name.

```mbti
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::exp2(Self) -> Self
pub fn DecimalChecked::exp10(Self) -> Self
pub fn DecimalChecked::expm1(Self) -> Self
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log2(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
pub fn DecimalChecked::log1p(Self) -> Self
pub fn DecimalChecked::power(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::pown(Self, Int) -> Self
pub fn DecimalChecked::rootn(Self, Int) -> Self
pub fn DecimalChecked::hypot(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::sin(Self) -> Self
pub fn DecimalChecked::cos(Self) -> Self
pub fn DecimalChecked::tan(Self) -> Self
pub fn DecimalChecked::sinpi(Self) -> Self
pub fn DecimalChecked::cospi(Self) -> Self
pub fn DecimalChecked::tanpi(Self) -> Self
pub fn DecimalChecked::asin(Self) -> Self
pub fn DecimalChecked::acos(Self) -> Self
pub fn DecimalChecked::atan(Self) -> Self
pub fn DecimalChecked::atan2(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::sinh(Self) -> Self
pub fn DecimalChecked::cosh(Self) -> Self
pub fn DecimalChecked::tanh(Self) -> Self
pub fn DecimalChecked::asinh(Self) -> Self
pub fn DecimalChecked::acosh(Self) -> Self
pub fn DecimalChecked::atanh(Self) -> Self
```

The results are those of `decimal`, including its documented exceptions to
correct rounding (undetected exact results, integer powers, results near the
underflow threshold; see the
[decimal API](decimal.md#elementary-functions)). Domain violations are IEEE
values with flags (`ln` of a negative number is NaN with `invalid_operation`,
`tanpi(0.5)` is an infinity with `division_by_zero`). An error is recorded only
when `try_*_ctx` returns `Err`, which these functions do for a
`CertificationFailure` (the correctly rounded result could not be certified
within the refinement budget). On error the new state is
$(v, c, r, F, \mathrm{Some}(e))$: the value and flags before the step are kept.

> [!WARNING]
> `atan2` aborts the program, instead of recording an error, when the current
> value or the abscissa is an infinity, because `Decimal::try_atan2_ctx` does.
> Check `value().is_infinite()` and the operand first.

> [!IMPORTANT]
> Following the General Decimal Arithmetic rules for the mathematical
> functions, these operations require a context with precision and exponent
> limits within $\pm 999\,999$. The default `DecimalContext::new` range
> ($\pm 999\,999\,999$), and any context built by `from_arithmetic_context`
> from an `ArithmeticContext` without exponent bounds, makes them return NaN
> with `invalid_context`. Use `decimal32()`, `decimal64()`, `decimal128()` or
> explicit `e_min` / `e_max`. `power` and `pown` with an integral exponent,
> and `power` with the exponent `0.5`, are not restricted.

```moonbit
///|
test "elementary functions under a bounded context" {
  let ctx = @decimal.DecimalContext::decimal64()
  let ln2 = @decimal_checked.DecimalChecked::from_int(2, ctx).ln()
  inspect(ln2.value().to_string(), content="0.6931471805599453")
  inspect(flags(ln2.raised()), content="inexact,rounded")
  let unbounded = @decimal_checked.DecimalChecked::from_int(
    2,
    @decimal.DecimalContext::new(precision=16),
  ).ln()
  inspect(unbounded.value().to_string(), content="nan")
  inspect(flags(unbounded.raised()), content="invalid_context")
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
pub fn DecimalChecked::add(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::apply(Self) -> Self
pub fn DecimalChecked::asin(Self) -> Self
pub fn DecimalChecked::asinh(Self) -> Self
pub fn DecimalChecked::atan(Self) -> Self
pub fn DecimalChecked::atan2(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::atanh(Self) -> Self
pub fn DecimalChecked::clear_flags(Self) -> Self
pub fn DecimalChecked::context(Self) -> @decimal.DecimalContext
pub fn DecimalChecked::cos(Self) -> Self
pub fn DecimalChecked::cosh(Self) -> Self
pub fn DecimalChecked::cospi(Self) -> Self
pub fn DecimalChecked::div(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::error(Self) -> @arithmetic.ArithmeticError?
pub fn DecimalChecked::exp(Self) -> Self
pub fn DecimalChecked::exp10(Self) -> Self
pub fn DecimalChecked::exp2(Self) -> Self
pub fn DecimalChecked::expm1(Self) -> Self
pub fn DecimalChecked::flags(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::fma(Self, @decimal.Decimal, @decimal.Decimal) -> Self
pub fn DecimalChecked::from_bigint(@bigint.BigInt, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_decimal(@decimal.Decimal, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_double(Double, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_float(Float, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_int(Int, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::from_outcome(@decimal.Decimal, @decimal.DecimalContext, @decimal.DecimalFlags) -> Self
pub fn DecimalChecked::hypot(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::is_err(Self) -> Bool
pub fn DecimalChecked::is_ok(Self) -> Bool
pub fn DecimalChecked::ln(Self) -> Self
pub fn DecimalChecked::log10(Self) -> Self
pub fn DecimalChecked::log1p(Self) -> Self
pub fn DecimalChecked::log2(Self) -> Self
pub fn DecimalChecked::max(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::min(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::minus(Self) -> Self
pub fn DecimalChecked::mul(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::next_minus(Self) -> Self
pub fn DecimalChecked::next_plus(Self) -> Self
pub fn DecimalChecked::next_toward(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::outcome(Self) -> (@decimal.Decimal, @decimal.DecimalFlags)
pub fn DecimalChecked::parse(String, @decimal.DecimalContext) -> Self
pub fn DecimalChecked::plus(Self) -> Self
pub fn DecimalChecked::power(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::pown(Self, Int) -> Self
pub fn DecimalChecked::quantize(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::raised(Self) -> @decimal.DecimalFlags
pub fn DecimalChecked::reduce(Self) -> Self
pub fn DecimalChecked::remainder(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::result(Self) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @arithmetic.ArithmeticError]
pub fn DecimalChecked::rootn(Self, Int) -> Self
pub fn DecimalChecked::sin(Self) -> Self
pub fn DecimalChecked::sinh(Self) -> Self
pub fn DecimalChecked::sinpi(Self) -> Self
pub fn DecimalChecked::sqrt(Self) -> Self
pub fn DecimalChecked::sub(Self, @decimal.Decimal) -> Self
pub fn DecimalChecked::tan(Self) -> Self
pub fn DecimalChecked::tanh(Self) -> Self
pub fn DecimalChecked::tanpi(Self) -> Self
pub fn DecimalChecked::value(Self) -> @decimal.Decimal
pub fn DecimalChecked::with_context(Self, @decimal.DecimalContext) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
