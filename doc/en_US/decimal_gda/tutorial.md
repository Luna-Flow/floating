# `decimal_gda` Tutorial

Use this package when a calculation must follow General Decimal Arithmetic
rounding, sticky status, and trap behavior. Use `decimal` instead for the IEEE
`(value, flags)` model.

## Parse And Calculate

Create a context, parse through it, and thread the returned context:

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let result = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(result.value().to_string(), content="6.1700")
```

`result.raised()` contains only conditions from division.
`result.next_context().status()` contains conditions from parsing and division.

## Observe Raised And Sticky Status

Query a condition explicitly:

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
let rounded = outcome.raised().contains(@decimal_gda.GdaSignal::Rounded)
let sticky = outcome.next_context().status().contains(
  @decimal_gda.GdaSignal::Rounded,
)
inspect((rounded, sticky), content="(true, true)")
```

Call `clear_status()` to begin a new status window while retaining traps. Call
`reset()` only when both status and traps should return to defaults.

## Configure A Trap

Trap sets are immutable. Enable one signal on a context:

```moonbit nocheck
let trapped_context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let one = @decimal_gda.Decimal::one()
let zero = @decimal_gda.Decimal::zero()
let outcome = @decimal_gda.divide(one, zero, trapped_context)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected trap")
}
```

The defined infinity remains available. The trap changes control information;
it does not erase the numerical result.

## Use Checked Context Construction

Use `try_new` when context parameters come from configuration or user input:

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

This avoids aborting on non-positive precision or reversed exponent bounds.

## Choose The Right Comparison

- `compare` performs quiet numeric comparison and returns a decimal comparison
  value.
- `compare_signal` uses signaling comparison behavior.
- `compare_total` orders complete representations, including NaNs and cohorts.
- `compare_total_magnitude` applies total ordering to magnitudes.

Use total comparison for deterministic sorting or protocol canonicalization;
do not substitute it for ordinary numerical equality.

## Avoid Common Mistakes

- Do not reuse the original context if sticky status should accumulate.
- Do not treat `Trapped` as “no value”; inspect its defined result.
- Do not combine `GdaFlags` manually and then assume a context status changed;
  thread `next_context()`.
- Do not import `decimal` and `decimal_gda` values interchangeably.
- Do not use the checked wrappers when the required contract is GDA signals and
  traps; they preserve `ArithmeticError`, not GDA state.

