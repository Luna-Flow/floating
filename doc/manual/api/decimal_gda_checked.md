# decimal_gda_checked API

## Purpose

`decimal_gda_checked` provides `GdaDecimalChecked`, a pipeline over the General
Decimal Arithmetic (GDA) operations of [`decimal_gda`](decimal_gda.md). It holds
exactly one `GdaOutcome[Decimal]`: the current defined value, the next context
(whose sticky `flags` accumulates every signal raised so far), the signals
raised by the latest operation, and, if a trap fired, the trapped signal. An
operation on a completed state runs the GDA operation with the stored context;
an operation on a trapped state does nothing. `resume_defined()` is the only way
to continue after a trap. The right operand of a binary operation is a pipeline
too: its conditions join the result and its trap short-circuits (see
[Operations](#operations)). The package never produces an `ArithmeticError`. The
[tutorial](../tutorial/decimal_gda_checked.md) walks through traps and
recovery; the [design page](../design/decimal_gda_checked.md) models the
pipeline as a state monad with an absorbing trap and proves the sticky-flags
laws.

## Importing

Add both packages to your `moon.pkg`; the pipeline takes `decimal_gda`
values and contexts:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal_gda",
  "Luna-Flow/floating/decimal_gda_checked",
}
```

The examples call the packages through the aliases `@decimal_gda.` and
`@decimal_gda_checked.`, and list GDA flags with this helper:

```moonbit
///|
fn gda_flags(f : @decimal_gda.GdaFlags) -> String {
  let named = [
    ("inexact", f.inexact()),
    ("rounded", f.rounded()),
    ("invalid_operation", f.invalid_operation()),
    ("division_by_zero", f.division_by_zero()),
    ("overflow", f.overflow()),
    ("underflow", f.underflow()),
    ("conversion_syntax", f.conversion_syntax()),
    ("invalid_context", f.invalid_context()),
  ]
  [ for p in named if p.1 => p.0 ].join(",")
}
```

## The state type

### `GdaDecimalChecked`

`GdaDecimalChecked` wraps one `GdaOutcome[@decimal_gda.Decimal]`.

```mbti
pub struct GdaDecimalChecked {
  // private fields
}
```

The outcome is either `Completed(value, next_context, raised)` or
`Trapped(signal, value, next_context, raised)`; see `GdaOutcome` in the
[`decimal_gda` API](decimal_gda.md).

## Construction

### `GdaDecimalChecked::from_outcome`

`from_outcome(outcome)` wraps the outcome of any `decimal_gda` operation.

```mbti
pub fn GdaDecimalChecked::from_outcome(@decimal_gda.GdaOutcome[@decimal_gda.Decimal]) -> Self
```

A `Trapped` outcome gives a trapped pipeline.

### `GdaDecimalChecked::from_decimal`

`from_decimal(value, context)` rounds a value into the context with the GDA
`apply` operation (the *plus*-like conversion to the context).

```mbti
pub fn GdaDecimalChecked::from_decimal(@decimal_gda.Decimal, @decimal_gda.GdaContext) -> Self
```

The signals of the rounding are raised, merged into the flags and checked
against the traps, so construction itself can trap.

### `GdaDecimalChecked::to_number`

`to_number(source, context)` is the GDA *to-number* conversion of a string.

```mbti
pub fn GdaDecimalChecked::to_number(String, @decimal_gda.GdaContext) -> Self
```

An invalid string gives NaN with `conversion_syntax`; because GDA treats
conversion syntax as an invalid-operation condition, a context that traps
`InvalidOperation` (such as `GdaContext::basic_default()`) traps it.

## Observation

### `GdaDecimalChecked::outcome`, `GdaDecimalChecked::value`, `GdaDecimalChecked::context`, `GdaDecimalChecked::raised`, `GdaDecimalChecked::flags`

These methods return the wrapped outcome and its components.

```mbti
pub fn GdaDecimalChecked::outcome(Self) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
pub fn GdaDecimalChecked::value(Self) -> @decimal_gda.Decimal
pub fn GdaDecimalChecked::context(Self) -> @decimal_gda.GdaContext
pub fn GdaDecimalChecked::raised(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::flags(Self) -> @decimal_gda.GdaFlags
```

`value()` is the defined result, also when trapped. `context()` is the next
context, including its updated flags and its traps. `raised()` holds the
signals of the latest operation only. `flags()` is `context().flags()`, the
sticky union of everything raised since the context's flags was last cleared;
whenever any invalid-operation condition (`conversion_syntax`,
`division_impossible`, `division_undefined`, `invalid_context`) is raised, the
flags also gets `invalid_operation`.

### `GdaDecimalChecked::error`, `GdaDecimalChecked::result`, `GdaDecimalChecked::is_ok`, `GdaDecimalChecked::is_err`

These report whether a trap fired and which signal it was.

```mbti
pub fn GdaDecimalChecked::error(Self) -> @decimal_gda.GdaSignal?
pub fn GdaDecimalChecked::result(Self) -> Result[@decimal_gda.Decimal, @decimal_gda.GdaSignal]
pub fn GdaDecimalChecked::is_ok(Self) -> Bool
pub fn GdaDecimalChecked::is_err(Self) -> Bool
```

`error()` is the trapped signal or `None`; `result()` is `Ok(value)` for a
completed pipeline and `Err(signal)` for a trapped one (`value()` still gives
the defined result of a trapped pipeline). The error type is `GdaSignal`, not
`ArithmeticError`: a trap is the failure channel of this tier, and the signal
says which of the nine signals it was. These are the names `DecimalChecked`
uses. When several raised signals are trapped at once, the reported one is the
first in the priority order `InvalidOperation`, `DivisionByZero`, `Overflow`,
`Underflow`, `Subnormal`, `Inexact`, `Rounded`, `Clamped`, `LostDigits`.

## Recovery

### `GdaDecimalChecked::resume_defined`

`resume_defined()` continues a trapped pipeline with its defined result.

```mbti
pub fn GdaDecimalChecked::resume_defined(Self) -> Self
```

On `Trapped(signal, value, context, raised)` it returns
`Completed(value, context, GdaFlags::new())`: the value and the context (with
its flags, which already contains the trapped signal) are kept, the trap
marker and the latest-step flags are dropped. On a completed pipeline it does
nothing. Traps stay enabled in the context, so the same condition traps again
if it recurs.

```moonbit
///|
test "a trap stops the pipeline until it is resumed" {
  let ctx = @decimal_gda.GdaContext::new(precision=5).trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let one = @decimal_gda.Decimal::one()
  let d = fn(v : @decimal_gda.Decimal) {
    @decimal_gda_checked.GdaDecimalChecked::from_decimal(v, ctx)
  }
  let trapped = @decimal_gda_checked.GdaDecimalChecked::to_number("1.234567", ctx).divide(
    d(@decimal_gda.Decimal::zero()),
  )
  inspect(trapped.is_err(), content="true")
  inspect(
    trapped.error() == Some(@decimal_gda.GdaSignal::DivisionByZero),
    content="true",
  )
  inspect(trapped.value().to_string(), content="inf")
  inspect(gda_flags(trapped.raised()), content="division_by_zero")
  inspect(gda_flags(trapped.flags()), content="inexact,rounded,division_by_zero")
  inspect(trapped.add(d(one)).is_err(), content="true")
  let resumed = trapped.resume_defined()
  inspect(gda_flags(resumed.raised()), content="")
  let next = resumed.minus()
  inspect(next.value().to_string(), content="-inf")
  inspect(gda_flags(next.flags()), content="inexact,rounded,division_by_zero")
}
```

## Operations

Every operation method applies the `decimal_gda` function of the same name to
the current value under the stored context; `remainder` is the GDA
`remainder` (truncating) and `remainder_near` the nearest one.

On `Completed(v, c, _)` the method returns the outcome of
`@decimal_gda.op(v, …, c)`; on `Trapped` it returns the state unchanged. The
other operands (`other`, `multiplier`, `addend`, `exponent`, `quantum`,
`divisor`, `target`, `count`) are pipelines too, so that the conditions of the
pipeline that produced them are not lost. Rules for a binary operation `a.op(b)`:
1. If `a` is trapped, the result is `a`.
2. Otherwise, if `b` is trapped, no operation runs: the result keeps the value and
   the context of `a`, the conditions of `b` join `raised` and the flags, and the
   trap of `b` is the trap of the result.
3. Otherwise the operation runs under the context of `a`, and the conditions
   that `b` raised join `raised` of the result and the flags of its context. The
   traps of `a` are not tested against the conditions of `b`: `b` decided its own.

`fma` applies the same rules to its two operands. The GDA operation computes the
result under `c`'s precision, rounding, exponent limits, clamping and extended
mode; if it raises no signal the context is passed on unchanged with empty
`raised`; otherwise the raised signals are merged into the flags of the next
context and, if one of them is enabled in `c.traps()`, the outcome is
`Trapped`. The mathematical functions `exp`, `ln`, `log10` and `power` with a
non-integer exponent need precision and exponent limits within
$\pm 999\,999$; otherwise they return NaN with `invalid_context`, which an
`InvalidOperation` trap catches.

The operations that return a number are all here: `apply`, `plus`, `minus`,
`abs`, `add`, `subtract`, `multiply`, `divide`, `divide_integer`, `fma`,
`remainder`, `remainder_near`, `power`, `sqrt`, `exp`, `ln`, `log10`, `quantize`,
`rescale`, `reduce`, `round_to_integral_exact`, `round_to_integral_value`,
`scaleb`, `shift`, `rotate`, `logb`, `logical_and`, `logical_or`, `logical_xor`,
`logical_invert`, `next_minus`, `next_plus`, `next_toward`, `compare`,
`compare_signal`, `max`, `min`, `max_magnitude` and `min_magnitude`. The
functions of `decimal_gda` that return a string, a boolean or an integer
(`class_name`, `is_normal`, `is_subnormal`, `compare_total`,
`compare_total_magnitude`) and the `try_` forms are called on `value()` and
`context()`.

```moonbit
///|
test "sticky flags across operations" {
  let ctx = @decimal_gda.GdaContext::new(precision=5)
  let parsed = @decimal_gda_checked.GdaDecimalChecked::to_number("1.234567", ctx)
  inspect(parsed.value().to_string(), content="1.2346")
  inspect(gda_flags(parsed.raised()), content="inexact,rounded")
  let d = fn(v : @decimal_gda.Decimal) {
    @decimal_gda_checked.GdaDecimalChecked::from_decimal(v, ctx)
  }
  let added = parsed.add(d(@decimal_gda.Decimal::zero()))
  inspect(gda_flags(added.raised()), content="")
  inspect(gda_flags(added.flags()), content="inexact,rounded")
  let e = @decimal_gda_checked.GdaDecimalChecked::to_number(
    "2",
    @decimal_gda.GdaContext::decimal64(),
  ).exp()
  inspect(e.value().to_string(), content="7.389056098930650")
  let q = parsed.quantize(d(@decimal_gda.Decimal::from_string("0.01").unwrap()))
  inspect(q.value().to_string(), content="1.23")
}
```

### `GdaDecimalChecked::apply`, `GdaDecimalChecked::plus`, `GdaDecimalChecked::minus`, `GdaDecimalChecked::abs`

These round or change the sign of the current value: `apply` is the GDA
conversion to the context, `plus` is $0 + x$, `minus` is $0 - x$ and `abs` is
$|x|$.

```mbti
pub fn GdaDecimalChecked::apply(Self) -> Self
pub fn GdaDecimalChecked::plus(Self) -> Self
pub fn GdaDecimalChecked::minus(Self) -> Self
pub fn GdaDecimalChecked::abs(Self) -> Self
```

### `GdaDecimalChecked::add`, `GdaDecimalChecked::subtract`, `GdaDecimalChecked::multiply`, `GdaDecimalChecked::divide`, `GdaDecimalChecked::fma`

These combine the current value with the pipelines `b` and `c`; `fma(b, c)` is
$v \times b + c$ with one rounding.

```mbti
pub fn GdaDecimalChecked::add(Self, Self) -> Self
pub fn GdaDecimalChecked::subtract(Self, Self) -> Self
pub fn GdaDecimalChecked::multiply(Self, Self) -> Self
pub fn GdaDecimalChecked::divide(Self, Self) -> Self
pub fn GdaDecimalChecked::fma(Self, Self, Self) -> Self
```

### `GdaDecimalChecked::sqrt`, `GdaDecimalChecked::exp`, `GdaDecimalChecked::ln`, `GdaDecimalChecked::log10`, `GdaDecimalChecked::power`

These are the GDA elementary functions of the current value; `power(y)` is
$v^y$.

```mbti
pub fn GdaDecimalChecked::sqrt(Self) -> Self
pub fn GdaDecimalChecked::exp(Self) -> Self
pub fn GdaDecimalChecked::ln(Self) -> Self
pub fn GdaDecimalChecked::log10(Self) -> Self
pub fn GdaDecimalChecked::power(Self, Self) -> Self
```

### `GdaDecimalChecked::quantize`, `GdaDecimalChecked::remainder`, `GdaDecimalChecked::reduce`

These set the exponent, take a remainder or remove trailing zeros. The other
operations of the list above have the shape of these: one pipeline for a unary
one and `(Self, Self) -> Self` for a binary one.

```mbti
pub fn GdaDecimalChecked::quantize(Self, Self) -> Self
pub fn GdaDecimalChecked::remainder(Self, Self) -> Self
pub fn GdaDecimalChecked::reduce(Self) -> Self
```

### `GdaDecimalChecked::next_minus`, `GdaDecimalChecked::next_plus`, `GdaDecimalChecked::next_toward`

These step to an adjacent representable value.

```mbti
pub fn GdaDecimalChecked::next_minus(Self) -> Self
pub fn GdaDecimalChecked::next_plus(Self) -> Self
pub fn GdaDecimalChecked::next_toward(Self, Self) -> Self
```

## Complete public interface

The following snapshot is the complete generated interface of the package.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda_checked"

import {
  "Luna-Flow/floating/decimal_gda",
}

// Values

// Errors

// Types and methods
pub struct GdaDecimalChecked {
  // private fields
}
pub fn GdaDecimalChecked::abs(Self) -> Self
pub fn GdaDecimalChecked::add(Self, Self) -> Self
pub fn GdaDecimalChecked::apply(Self) -> Self
pub fn GdaDecimalChecked::compare(Self, Self) -> Self
pub fn GdaDecimalChecked::compare_signal(Self, Self) -> Self
pub fn GdaDecimalChecked::context(Self) -> @decimal_gda.GdaContext
pub fn GdaDecimalChecked::divide(Self, Self) -> Self
pub fn GdaDecimalChecked::divide_integer(Self, Self) -> Self
pub fn GdaDecimalChecked::error(Self) -> @decimal_gda.GdaSignal?
pub fn GdaDecimalChecked::exp(Self) -> Self
pub fn GdaDecimalChecked::flags(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::fma(Self, Self, Self) -> Self
pub fn GdaDecimalChecked::from_decimal(@decimal_gda.Decimal, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::from_outcome(@decimal_gda.GdaOutcome[@decimal_gda.Decimal]) -> Self
pub fn GdaDecimalChecked::is_err(Self) -> Bool
pub fn GdaDecimalChecked::is_ok(Self) -> Bool
pub fn GdaDecimalChecked::ln(Self) -> Self
pub fn GdaDecimalChecked::log10(Self) -> Self
pub fn GdaDecimalChecked::logb(Self) -> Self
pub fn GdaDecimalChecked::logical_and(Self, Self) -> Self
pub fn GdaDecimalChecked::logical_invert(Self) -> Self
pub fn GdaDecimalChecked::logical_or(Self, Self) -> Self
pub fn GdaDecimalChecked::logical_xor(Self, Self) -> Self
pub fn GdaDecimalChecked::max(Self, Self) -> Self
pub fn GdaDecimalChecked::max_magnitude(Self, Self) -> Self
pub fn GdaDecimalChecked::min(Self, Self) -> Self
pub fn GdaDecimalChecked::min_magnitude(Self, Self) -> Self
pub fn GdaDecimalChecked::minus(Self) -> Self
pub fn GdaDecimalChecked::multiply(Self, Self) -> Self
pub fn GdaDecimalChecked::next_minus(Self) -> Self
pub fn GdaDecimalChecked::next_plus(Self) -> Self
pub fn GdaDecimalChecked::next_toward(Self, Self) -> Self
pub fn GdaDecimalChecked::outcome(Self) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
pub fn GdaDecimalChecked::plus(Self) -> Self
pub fn GdaDecimalChecked::power(Self, Self) -> Self
pub fn GdaDecimalChecked::quantize(Self, Self) -> Self
pub fn GdaDecimalChecked::raised(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::reduce(Self) -> Self
pub fn GdaDecimalChecked::remainder(Self, Self) -> Self
pub fn GdaDecimalChecked::remainder_near(Self, Self) -> Self
pub fn GdaDecimalChecked::rescale(Self, Self) -> Self
pub fn GdaDecimalChecked::result(Self) -> Result[@decimal_gda.Decimal, @decimal_gda.GdaSignal]
pub fn GdaDecimalChecked::resume_defined(Self) -> Self
pub fn GdaDecimalChecked::rotate(Self, Self) -> Self
pub fn GdaDecimalChecked::round_to_integral_exact(Self) -> Self
pub fn GdaDecimalChecked::round_to_integral_value(Self) -> Self
pub fn GdaDecimalChecked::scaleb(Self, Self) -> Self
pub fn GdaDecimalChecked::shift(Self, Self) -> Self
pub fn GdaDecimalChecked::sqrt(Self) -> Self
pub fn GdaDecimalChecked::subtract(Self, Self) -> Self
pub fn GdaDecimalChecked::to_number(String, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::value(Self) -> @decimal_gda.Decimal

// Type aliases

// Traits
```
<!-- generated-api-end -->
