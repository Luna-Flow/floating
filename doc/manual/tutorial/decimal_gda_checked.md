# `decimal_gda_checked` tutorial

This tutorial shows how to run a General Decimal Arithmetic (GDA) calculation
as a pipeline that honours GDA traps: you choose a `GdaContext` with the traps
your application needs, start a `GdaDecimalChecked`, chain operations, detect
the step that trapped, inspect the sticky status, and decide explicitly whether
to continue. This is the model of Python's `decimal` module and of the GDA test
suites: status flags are sticky, and an enabled trap stops the computation.
The operations come from [`decimal_gda`](decimal_gda.md); the
[design page](../design/decimal_gda_checked.md) proves the status and trap laws;
the [API reference](../api/decimal_gda_checked.md) lists every method.

## Quick start

```sh
moon add Luna-Flow/floating@0.8.0
```

```text
import {
  "Luna-Flow/floating/decimal_gda",
  "Luna-Flow/floating/decimal_gda_checked",
}
```

Divide under the GDA *basic* context, which traps division by zero:

```moonbit
///|
test "quick start: a trapped division" {
  let ctx = @decimal_gda.GdaContext::default()
  let r = @decimal_gda_checked.GdaDecimalChecked::parse("1", ctx).divide(
    @decimal_gda.Decimal::zero(),
  )
  inspect(r.is_trapped(), content="true")
  inspect(
    r.trapped_signal() == Some(@decimal_gda.GdaSignal::DivisionByZero),
    content="true",
  )
}
```

## Everyday tasks

The examples list flags with this helper:

```moonbit
///|
fn gda_flags(f : @decimal_gda.GdaFlags) -> String {
  let named = [
    ("inexact", f.inexact),
    ("rounded", f.rounded),
    ("invalid_operation", f.invalid_operation),
    ("division_by_zero", f.division_by_zero),
    ("overflow", f.overflow),
    ("conversion_syntax", f.conversion_syntax),
    ("invalid_context", f.invalid_context),
  ]
  [ for p in named if p.1 => p.0 ].join(",")
}
```

### Choose the traps

A `GdaContext` carries a trap set. The predefined contexts differ:
`GdaContext::default()` (the GDA basic context: precision 9, `HalfUp`) traps
`DivisionByZero`, `InvalidOperation`, `Overflow`, `Underflow` and `Clamped`;
`decimal32()`, `decimal64()`, `decimal128()` and `new(...)` trap nothing. Add
or remove traps with `trap`:

```moonbit
///|
test "trap inexact results" {
  let exact_only = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::Inexact,
  )
  let ok = @decimal_gda_checked.GdaDecimalChecked::parse("10", exact_only).divide(
    @decimal_gda.Decimal::from_int(4),
  )
  inspect(ok.is_trapped(), content="false")
  inspect(ok.value().to_string(), content="2.5")
  let stopped = @decimal_gda_checked.GdaDecimalChecked::parse("10", exact_only).divide(
    @decimal_gda.Decimal::from_int(3),
  )
  inspect(stopped.is_trapped(), content="true")
  inspect(
    stopped.trapped_signal() == Some(@decimal_gda.GdaSignal::Inexact),
    content="true",
  )
}
```

### Read the sticky status

`raised()` holds the signals of the latest operation, `status()` every signal
since the context was created:

```moonbit
///|
test "status is sticky" {
  let ctx = @decimal_gda.GdaContext::new(precision=5)
  let r = @decimal_gda_checked.GdaDecimalChecked::parse("1.234567", ctx)
    .add(@decimal_gda.Decimal::one())
    .multiply(@decimal_gda.Decimal::from_int(2))
  inspect(r.value().to_string(), content="4.4692")
  inspect(gda_flags(r.raised()), content="")
  inspect(gda_flags(r.status()), content="inexact,rounded")
}
```

### Nothing runs after a trap

Once trapped, every further operation returns the pipeline unchanged; the
value is the defined result of the trapped step:

```moonbit
///|
test "short circuit after a trap" {
  let ctx = @decimal_gda.GdaContext::default()
  let r = @decimal_gda_checked.GdaDecimalChecked::parse("1", ctx)
    .divide(@decimal_gda.Decimal::zero())
    .add(@decimal_gda.Decimal::one())
    .multiply(@decimal_gda.Decimal::from_int(5))
  inspect(r.is_trapped(), content="true")
  inspect(r.value().to_string(), content="inf")
}
```

### Resume deliberately

`resume_defined()` accepts the defined result and continues. The status still
records the trapped signal, so the decision is visible afterwards:

```moonbit
///|
test "resume with the defined result" {
  let ctx = @decimal_gda.GdaContext::default()
  let trapped = @decimal_gda_checked.GdaDecimalChecked::parse("1", ctx).divide(
    @decimal_gda.Decimal::zero(),
  )
  let resumed = trapped.resume_defined().minus()
  inspect(resumed.is_trapped(), content="false")
  inspect(resumed.value().to_string(), content="-inf")
  inspect(gda_flags(resumed.status()), content="division_by_zero")
}
```

The traps are still enabled after resuming: dividing by zero again traps
again.

## Going further

### Syntax errors are invalid operations

GDA classifies conversion syntax, impossible and undefined divisions and invalid
contexts as *invalid-operation conditions*. A context that traps
`InvalidOperation` therefore stops on a malformed string, and the status gains
`invalid_operation` next to the specific condition:

```moonbit
///|
test "a malformed literal" {
  let r = @decimal_gda_checked.GdaDecimalChecked::parse(
    "12,5",
    @decimal_gda.GdaContext::default(),
  )
  inspect(r.is_trapped(), content="true")
  inspect(
    r.trapped_signal() == Some(@decimal_gda.GdaSignal::InvalidOperation),
    content="true",
  )
  inspect(gda_flags(r.status()), content="invalid_operation,conversion_syntax")
}
```

### Mathematical functions need bounded contexts

`exp`, `ln`, `log10` and `power` follow the GDA restriction to precision and
exponent limits within $\pm 999\,999$. The interchange contexts satisfy it;
`GdaContext::new` with its default unbounded range does not, and the functions
return NaN with `invalid_context` (which traps under `InvalidOperation`):

```moonbit
///|
test "exp needs a bounded context" {
  let good = @decimal_gda_checked.GdaDecimalChecked::parse(
    "2",
    @decimal_gda.GdaContext::decimal64(),
  ).exp()
  inspect(good.value().to_string(), content="7.389056098930650")
  let bad = @decimal_gda_checked.GdaDecimalChecked::parse(
    "2",
    @decimal_gda.GdaContext::new(precision=16),
  ).exp()
  inspect(bad.value().to_string(), content="nan")
  inspect(gda_flags(bad.raised()), content="invalid_context")
}
```

### Combine with the plain GDA functions

Any `decimal_gda` operation returns a `GdaOutcome`. When the pipeline has no
method for it, run it on `value()` and `context()` and wrap the outcome:

```moonbit
///|
test "use an operation without a pipeline method" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let start = @decimal_gda_checked.GdaDecimalChecked::parse("7.5", ctx)
  let rounded = @decimal_gda_checked.GdaDecimalChecked::from_outcome(
    @decimal_gda.to_integral_value(start.value(), start.context()),
  )
  inspect(rounded.value().to_string(), content="8")
}
```

Do this only on a pipeline that is not trapped; `from_outcome` does not check
the previous state.

## Common pitfalls

- **`default()` traps, `new()` does not.** Choose the context deliberately.
- **`raised()` versus `status()`.** The first is the latest step, the second
  the sticky history.
- **`resume_defined` keeps the status and the traps.** It clears only the
  trap marker and `raised()`. Clear the status with
  `GdaContext::clear_status` on a context and start a new pipeline if needed.
- **No errors.** Traps are not converted to `ArithmeticError`; check
  `is_trapped()`.
- **Two decimal packages.** `decimal_gda.Decimal` is not
  `decimal.Decimal`; IEEE-style flag accumulation without traps is
  [`decimal_checked`](decimal_checked.md).

## Next steps

- [`decimal_gda_checked` design](../design/decimal_gda_checked.md): sticky
  status as a monoid, the trap predicate and the short-circuit proof.
- [`decimal_gda_checked` API](../api/decimal_gda_checked.md): every method.
- [`decimal_gda` tutorial](decimal_gda.md): contexts, rounding modes and the
  full GDA operation set.
