# `decimal_gda_checked` API

`decimal_gda_checked` provides `GdaDecimalChecked`, a pipeline over the General
Decimal Arithmetic (GDA) operations of [`decimal_gda`](decimal_gda.md). It holds
exactly one `GdaOutcome[Decimal]`: the current defined value, the next context
(whose sticky `status` accumulates every signal raised so far), the signals
raised by the latest operation, and, if a trap fired, the trapped signal. An
operation on a completed state runs the GDA operation with the stored context;
an operation on a trapped state does nothing. `resume_defined()` is the only way
to continue after a trap. The package never produces an `ArithmeticError`. The
[tutorial](../tutorial/decimal_gda_checked.md) walks through traps and
recovery; the [design page](../design/decimal_gda_checked.md) models the
pipeline as a state monad with an absorbing trap and proves the sticky-status
laws.

The examples list GDA flags with this helper:

```moonbit
///|
fn gda_flags(f : @decimal_gda.GdaFlags) -> String {
  let named = [
    ("inexact", f.inexact),
    ("rounded", f.rounded),
    ("invalid_operation", f.invalid_operation),
    ("division_by_zero", f.division_by_zero),
    ("overflow", f.overflow),
    ("underflow", f.underflow),
    ("conversion_syntax", f.conversion_syntax),
    ("invalid_context", f.invalid_context),
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

The signals of the rounding are raised, merged into the status and checked
against the traps, so construction itself can trap.

### `GdaDecimalChecked::parse`

`parse(source, context)` is the GDA *to-number* conversion of a string.

```mbti
pub fn GdaDecimalChecked::parse(String, @decimal_gda.GdaContext) -> Self
```

An invalid string gives NaN with `conversion_syntax`; because GDA treats
conversion syntax as an invalid-operation condition, a context that traps
`InvalidOperation` (such as `GdaContext::default()`) traps it.

## Observation

### `outcome`, `value`, `context`, `raised`, `status`

These methods return the wrapped outcome and its components.

```mbti
pub fn GdaDecimalChecked::outcome(Self) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
pub fn GdaDecimalChecked::value(Self) -> @decimal_gda.Decimal
pub fn GdaDecimalChecked::context(Self) -> @decimal_gda.GdaContext
pub fn GdaDecimalChecked::raised(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::status(Self) -> @decimal_gda.GdaFlags
```

`value()` is the defined result, also when trapped. `context()` is the next
context, including its updated status and its traps. `raised()` holds the
signals of the latest operation only. `status()` is `context().status()`, the
sticky union of everything raised since the context's status was last cleared;
whenever any invalid-operation condition (`conversion_syntax`,
`division_impossible`, `division_undefined`, `invalid_context`) is raised, the
status also gets `invalid_operation`.

### `is_trapped`, `trapped_signal`

These methods report whether a trap fired and which signal it was.

```mbti
pub fn GdaDecimalChecked::is_trapped(Self) -> Bool
pub fn GdaDecimalChecked::trapped_signal(Self) -> @decimal_gda.GdaSignal?
```

When several raised signals are trapped at once, the reported one is the first
in the priority order `InvalidOperation`, `DivisionByZero`,
`DivisionUndefined`, `DivisionImpossible`, `InvalidContext`,
`ConversionSyntax`, `Overflow`, `Underflow`, `Subnormal`, `Inexact`, `Rounded`,
`Clamped`, `LostDigits`.

## Recovery

### `GdaDecimalChecked::resume_defined`

`resume_defined()` continues a trapped pipeline with its defined result.

```mbti
pub fn GdaDecimalChecked::resume_defined(Self) -> Self
```

On `Trapped(signal, value, context, raised)` it returns
`Completed(value, context, GdaFlags::none())`: the value and the context (with
its status, which already contains the trapped signal) are kept, the trap
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
  let trapped = @decimal_gda_checked.GdaDecimalChecked::parse("1.234567", ctx).divide(
    @decimal_gda.Decimal::zero(),
  )
  inspect(trapped.is_trapped(), content="true")
  inspect(
    trapped.trapped_signal() == Some(@decimal_gda.GdaSignal::DivisionByZero),
    content="true",
  )
  inspect(trapped.value().to_string(), content="inf")
  inspect(gda_flags(trapped.raised()), content="division_by_zero")
  inspect(gda_flags(trapped.status()), content="inexact,rounded,division_by_zero")
  inspect(trapped.add(one).is_trapped(), content="true")
  let resumed = trapped.resume_defined()
  inspect(gda_flags(resumed.raised()), content="")
  let next = resumed.minus()
  inspect(next.value().to_string(), content="-inf")
  inspect(gda_flags(next.status()), content="inexact,rounded,division_by_zero")
}
```

## Operations

### `apply`, `plus`, `minus`, `abs`, `add`, `subtract`, `multiply`, `divide`, `fma`, `sqrt`, `exp`, `ln`, `log10`, `power`, `quantize`, `remainder`, `reduce`, `next_minus`, `next_plus`, `next_toward`

These methods apply the `decimal_gda` operation of the same name to the current
value under the stored context.

```mbti
pub fn GdaDecimalChecked::apply(Self) -> Self
pub fn GdaDecimalChecked::plus(Self) -> Self
pub fn GdaDecimalChecked::minus(Self) -> Self
pub fn GdaDecimalChecked::abs(Self) -> Self
pub fn GdaDecimalChecked::add(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::subtract(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::multiply(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::divide(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::fma(Self, @decimal_gda.Decimal, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::sqrt(Self) -> Self
pub fn GdaDecimalChecked::exp(Self) -> Self
pub fn GdaDecimalChecked::ln(Self) -> Self
pub fn GdaDecimalChecked::log10(Self) -> Self
pub fn GdaDecimalChecked::power(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::quantize(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::remainder(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::reduce(Self) -> Self
pub fn GdaDecimalChecked::next_minus(Self) -> Self
pub fn GdaDecimalChecked::next_plus(Self) -> Self
pub fn GdaDecimalChecked::next_toward(Self, @decimal_gda.Decimal) -> Self
```

On `Completed(v, c, _)` the method returns the outcome of
`@decimal_gda.op(v, …, c)`; on `Trapped` it returns the state unchanged. The
second operand (`other`, `multiplier`, `addend`, `exponent`, `quantum`,
`divisor`, `target`) is a plain `Decimal`. The GDA operation computes the
result under `c`'s precision, rounding, exponent limits, clamping and extended
mode; if it raises no signal the context is passed on unchanged with empty
`raised`; otherwise the raised signals are merged into the status of the next
context and, if one of them is enabled in `c.traps()`, the outcome is
`Trapped`. The mathematical functions `exp`, `ln`, `log10` and `power` need
precision and exponent limits within $\pm 999\,999$; otherwise they return NaN
with `invalid_context`.

```moonbit
///|
test "sticky status across operations" {
  let ctx = @decimal_gda.GdaContext::new(precision=5)
  let parsed = @decimal_gda_checked.GdaDecimalChecked::parse("1.234567", ctx)
  inspect(parsed.value().to_string(), content="1.2346")
  inspect(gda_flags(parsed.raised()), content="inexact,rounded")
  let added = parsed.add(@decimal_gda.Decimal::zero())
  inspect(gda_flags(added.raised()), content="")
  inspect(gda_flags(added.status()), content="inexact,rounded")
  let e = @decimal_gda_checked.GdaDecimalChecked::parse(
    "2",
    @decimal_gda.GdaContext::decimal64(),
  ).exp()
  inspect(e.value().to_string(), content="7.389056098930650")
  let q = parsed.quantize(@decimal_gda.Decimal::from_string("0.01").unwrap())
  inspect(q.value().to_string(), content="1.23")
}
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
pub fn GdaDecimalChecked::add(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::apply(Self) -> Self
pub fn GdaDecimalChecked::context(Self) -> @decimal_gda.GdaContext
pub fn GdaDecimalChecked::divide(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::exp(Self) -> Self
pub fn GdaDecimalChecked::fma(Self, @decimal_gda.Decimal, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::from_decimal(@decimal_gda.Decimal, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::from_outcome(@decimal_gda.GdaOutcome[@decimal_gda.Decimal]) -> Self
pub fn GdaDecimalChecked::is_trapped(Self) -> Bool
pub fn GdaDecimalChecked::ln(Self) -> Self
pub fn GdaDecimalChecked::log10(Self) -> Self
pub fn GdaDecimalChecked::minus(Self) -> Self
pub fn GdaDecimalChecked::multiply(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::next_minus(Self) -> Self
pub fn GdaDecimalChecked::next_plus(Self) -> Self
pub fn GdaDecimalChecked::next_toward(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::outcome(Self) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
pub fn GdaDecimalChecked::parse(String, @decimal_gda.GdaContext) -> Self
pub fn GdaDecimalChecked::plus(Self) -> Self
pub fn GdaDecimalChecked::power(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::quantize(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::raised(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::reduce(Self) -> Self
pub fn GdaDecimalChecked::remainder(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::resume_defined(Self) -> Self
pub fn GdaDecimalChecked::sqrt(Self) -> Self
pub fn GdaDecimalChecked::status(Self) -> @decimal_gda.GdaFlags
pub fn GdaDecimalChecked::subtract(Self, @decimal_gda.Decimal) -> Self
pub fn GdaDecimalChecked::trapped_signal(Self) -> @decimal_gda.GdaSignal?
pub fn GdaDecimalChecked::value(Self) -> @decimal_gda.Decimal

// Type aliases

// Traits
```
<!-- generated-api-end -->
