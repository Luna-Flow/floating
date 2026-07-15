# `decimal_gda` Tutorial

Use `decimal_gda` when a calculation must follow General Decimal Arithmetic
rounding, sticky status, defined trap results, and trap precedence. Use
[`decimal`](../decimal/tutorial.md) instead for the IEEE `(value, flags)` model,
DPD/BID interchange, or the broader 0.7.0 elementary-function surface.

## The One Rule To Remember

Every operation returns a `GdaOutcome`. Thread `next_context()` into the next
operation when status must accumulate.

```text
old context -> operation -> value + raised flags + next context (+ optional trap)
```

`raised()` describes the current operation. `next_context().status()` is sticky
and describes the full threaded calculation so far.

## Parse And Calculate

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let divided = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(divided.value().to_string(), content="6.1700")
```

The parse result preserves the input cohort. Division receives the context
returned by parsing, so any parse condition remains in the sticky status.

## Read Raised And Sticky Status

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
inspect(
  outcome.raised().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
inspect(
  outcome.next_context().status().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
```

Use `clear_status()` to start a new observation window while retaining traps.
Use `reset()` only when both status and trap configuration should return to
defaults.

## Configure And Handle A Trap

Trap sets are immutable. Enabling a trap creates a new context.

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let outcome = @decimal_gda.divide(
  @decimal_gda.Decimal::one(),
  @decimal_gda.Decimal::zero(),
  context,
)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected a trap")
}
```

The defined infinity remains available. The trap changes control flow; it does
not replace the GDA result with a generic error. When several enabled signals
are raised, inspect `trapped_signal()`/the `Trapped` case rather than inventing
an application-side precedence order.

## Validate Dynamic Contexts

Use `try_new` for configuration or user input:

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

This keeps invalid precision or reversed exponent bounds in the normal error
channel instead of aborting.

## Quantize And Preserve Cohorts

Use GDA `quantize` when the result exponent is prescribed:

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let value = @decimal_gda.Decimal::from_string("12.3456").unwrap()
let cents = @decimal_gda.Decimal::from_string("0.00").unwrap()
let outcome = @decimal_gda.quantize(value, cents, context)
inspect(outcome.value().quantum(), content="-2")
```

Thread `outcome.next_context()` after observing Rounded/Inexact or an invalid
quantize request. Call `reduce` only when canonical cohort form is intended.

## Use Mathematical Functions

The GDA surface intentionally exposes only the standard-facing mathematical
family implemented by the package: square root, power, `exp`, `ln`, and
`log10`.

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let nine = @decimal_gda.Decimal::from_int(9)
let root = @decimal_gda.sqrt(nine, context)
inspect(root.value().to_string(), content="3")
```

Trigonometric, hyperbolic, inverse, `atan2`, `hypot`, and pi-scaled operations
belong to the IEEE decimal/binary and interval surfaces, not to this GDA adapter.

## Choose The Right Comparison

- `compare` performs quiet numerical comparison and returns a decimal
  comparison value.
- `compare_signal` applies signaling comparison behavior.
- `compare_total` orders complete representations, including NaNs and cohorts.
- `compare_total_magnitude` applies total order to magnitudes.
- `same_quantum` tests cohort exponent compatibility.

Use total comparison for deterministic sorting or protocol canonicalization;
do not substitute it for ordinary numerical equality.

## Use The Checked Pipeline For Long Chains

Manual context threading is clearest at integration boundaries. For a long
linear pipeline, `decimal_gda_checked` retains one `GdaOutcome`, threads sticky
status, and stops automatically after a trap:

```moonbit check
///|
test "GDA checked pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "9",
    @decimal_gda.GdaContext::decimal64(),
  ).sqrt()
  inspect(checked.value().to_string(), content="3")
  inspect(checked.is_trapped(), content="false")
}
```

Use `resume_defined()` only after the application has explicitly decided that
continuing from a trapped operation's defined result is valid.

## Common Mistakes

- Reusing the original context when sticky status should accumulate.
- Treating `Trapped` as “no value.”
- Combining `GdaFlags` manually and assuming a context status changed.
- Mixing `decimal.Decimal` and `decimal_gda.Decimal` as if they were aliases.
- Using `decimal_checked` for a GDA pipeline; it deliberately implements the
  different IEEE flag model.
- Depending on coefficient thresholds or cache behavior; neither is public API.

## Recommended Practice

1. Construct or validate one context at the calculation boundary.
2. Thread every returned `next_context()` in manual workflows.
3. Inspect both current `raised` flags and sticky `status` at control boundaries.
4. Match `Trapped` explicitly and record the defined result before deciding to
   resume or stop.
5. Use `decimal_gda_checked` for linear composition, but return to raw outcomes
   where branching trap policy is application-specific.

## Next Reading

- [Design](./design.md) explains the state transition, kernel isolation, and
  switching boundaries.
- [API reference](./api.md) lists the complete legal scalar surface.
- [Conformance](./conformance.md) defines the pinned GDA corpus claim.
- [`decimal_gda_checked` tutorial](../decimal_gda_checked/tutorial.md) covers
  trap short-circuit and recovery in detail.
