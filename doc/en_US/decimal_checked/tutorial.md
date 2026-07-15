# `decimal_checked` Tutorial

`DecimalChecked` is a closed IEEE decimal pipeline. It stores the current
defined `Decimal`, one IEEE `DecimalContext`, flags raised by the latest step,
flags accumulated across all steps, and an optional certification error.

## Accumulate IEEE Flags

```moonbit check
///|
test "IEEE checked decimal pipeline" {
  let context = @decimal.DecimalContext::new(precision=3)
  let checked = @decimal_checked.DecimalChecked::parse("1.2345", context)
    .add(@decimal.Decimal::one())
  inspect(checked.value().to_string(), content="2.23")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::Inexact),
    content="true",
  )
  inspect(
    checked.flags().contains(@decimal.DecimalSignal::Rounded),
    content="true",
  )
}
```

`raised()` describes only the last operation. `flags()` is the combined history.
`outcome()` returns the current value with the combined flags.

## Keep Defined Exceptional Results

IEEE conditions usually retain a numerical result:

```moonbit check
///|
test "IEEE checked defined result" {
  let checked = @decimal_checked.DecimalChecked::from_int(
    1,
    @decimal.DecimalContext::decimal64(),
  ).div(@decimal.Decimal::zero())
  inspect(checked.value().is_infinite(), content="true")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::DivisionByZero),
    content="true",
  )
  inspect(checked.is_ok(), content="true")
}
```

`is_ok()` means that no `ArithmeticError` stopped the pipeline. It does not mean
that IEEE flags are empty. Certification failures from elementary `try_*`
operations enter `error()` and short-circuit later steps; rounded, inexact,
overflow, or division-by-zero conditions remain value-plus-flags outcomes.

## Reset A Status Window

`clear_flags()` keeps the current value and context but clears both latest and
accumulated flags. Use it after an application has recorded one calculation
phase.

`with_context(new_context)` reapplies the current value under the new IEEE
context and records any resulting flags. It is an observable calculation step,
not a metadata-only setter.

## Do Not Merge Independent Pipelines

Binary methods accept a plain `Decimal`. This avoids inventing a rule for
merging two contexts and two flag histories.

```moonbit nocheck
let right = @decimal.Decimal::from_string("2.5").unwrap()
let result = checked.mul(right)
```

If two independent checked calculations must be combined, first decide at the
application boundary which context and flag-merging policy is correct.

## Recommended Practice

1. Inspect `raised()` for step-local policy and `flags()` for end-to-end policy.
2. Treat `is_ok()` and `flags().has_error()` as different questions.
3. Clear flags only after the previous status window has been consumed.
4. Use `result()` at the outer boundary when certification failure must be
   returned to the caller.
5. Use `decimal_gda_checked` instead when sticky GDA status and traps are
   required.

See [Design](./design.md) for the transition model and
[`decimal` tutorial](../decimal/tutorial.md) for raw context operations.
