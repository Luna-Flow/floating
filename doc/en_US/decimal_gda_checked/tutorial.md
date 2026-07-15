# `decimal_gda_checked` Tutorial

`GdaDecimalChecked` stores exactly one GDA outcome and threads its sticky
context through a linear calculation. It is the recommended composition layer
when a trap should stop later operations until recovery is explicit.

## Thread Sticky Status

```moonbit check
///|
test "GDA checked sticky pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "1.2345",
    @decimal_gda.GdaContext::new(precision=3),
  ).add(@decimal_gda.Decimal::one())
  inspect(
    checked.status().contains(@decimal_gda.GdaSignal::Rounded),
    content="true",
  )
}
```

`raised()` describes the latest operation. `status()` comes from the next
context and includes all previously threaded conditions. `outcome()` exposes
the complete `Completed` or `Trapped` state.

## Stop At A Trap

```moonbit check
///|
test "GDA checked trap short-circuit" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  inspect(trapped.is_trapped(), content="true")
  inspect(trapped.value().is_infinite(), content="true")
  inspect(trapped.trapped_signal() is Some(_), content="true")
  inspect(trapped.add(@decimal_gda.Decimal::one()).is_trapped(), content="true")
}
```

The value remains the GDA-defined infinity. Later operations are identity
transitions while the outcome is trapped, so no calculation accidentally runs
past the configured control boundary.

## Resume Only By Policy

```moonbit check
///|
test "GDA checked explicit recovery" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  let resumed = trapped.resume_defined()
  inspect(resumed.is_trapped(), content="false")
  inspect(resumed.value().is_infinite(), content="true")
}
```

`resume_defined()` retains the defined value and sticky context, clears the
current-step raised observation, and returns a completed pipeline. Call it only
after the application has logged/handled the trap and decided that continuing
from the defined result is valid.

## Keep Binary Operands Plain

Methods such as `add`, `multiply`, and `quantize` accept a plain GDA `Decimal`.
This prevents implicit merging of two independent sticky contexts. If two
pipelines meet, select the controlling context and status policy outside the
wrapper.

## Recommended Practice

1. Check `is_trapped()` or `trapped_signal()` at business control boundaries.
2. Record `raised()`, `status()`, and the defined value before recovery.
3. Never use `resume_defined()` merely to make a pipeline continue.
4. Use raw `decimal_gda` outcomes when trap handling branches into several
   application actions; use this wrapper for linear composition.

See [Design](./design.md) and the raw
[`decimal_gda` tutorial](../decimal_gda/tutorial.md).
