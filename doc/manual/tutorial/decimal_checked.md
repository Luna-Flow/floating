# decimal_checked tutorial

This tutorial shows how to run an IEEE decimal calculation as one pipeline that
remembers every exceptional condition: you fix a `DecimalContext`, start a
`DecimalChecked` from a string or number, apply operations, and at the end read
the value together with the union of all flags raised on the way. The typical
use is an auditable calculation (money, measurements) where "was anything
rounded?" or "did anything overflow?" must be answered for the whole
computation, not for the last step. Arithmetic comes from
[`decimal`](decimal.md); the [design page](../design/decimal_checked.md) gives
the algebra of flag accumulation; the [API reference](../api/decimal_checked.md)
lists every method.

| I want to | Use |
| --- | --- |
| start a pipeline from text or a number | [`DecimalChecked::parse`, `from_int`](#audit-a-price-calculation) |
| know whether any step rounded | [`flags()`](#find-out-that-an-earlier-step-rounded) |
| see what only the last step did | [`raised()`](#audit-a-price-calculation) |
| continue after a division by zero | [flagged values](#keep-going-after-a-division-by-zero) |
| start a new audit period | [`clear_flags`](#start-a-new-audit-period) |
| call `ln`, `exp` or `power` in a pipeline | [a bounded context](#elementary-functions-need-a-bounded-context) |
| use an `ArithmeticContext` | [`from_arithmetic_context`](#start-from-a-luna-flowarithmetic-context) |
| hand the result to the contextual traits | [`result()`](#hand-the-result-to-the-contextual-traits) |

## Quick start

Add `floating` to your module:

```bash
moon add Luna-Flow/floating@0.8.0
```

and import both packages in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/decimal_checked",
}
```

Divide 10 by 4 in decimal64 and check that the result is exact:

```moonbit
///|
test "quick start: an exact division" {
  let ctx = @decimal.DecimalContext::decimal64()
  let r = @decimal_checked.DecimalChecked::from_int(10, ctx).div(
    @decimal.Decimal::from_int(4),
  )
  inspect(r.value().to_string(), content="2.5")
  inspect(r.flags().inexact, content="false")
}
```

## Everyday tasks

The examples list flags with this helper:

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

### Audit a price calculation

Compute a price with tax, rounded to cents. `raised()` describes the last step
and `flags()` the whole pipeline:

```moonbit
///|
test "price with tax" {
  let ctx = @decimal.DecimalContext::decimal64()
  let gross = @decimal_checked.DecimalChecked::parse("19.99", ctx)
    .mul(@decimal.Decimal::from_string("1.0825").unwrap())
    .quantize(@decimal.Decimal::from_string("0.01").unwrap())
  inspect(gross.value().to_string(), content="21.64")
  inspect(flags(gross.raised()), content="inexact,rounded")
  inspect(flags(gross.flags()), content="inexact,rounded")
}
```

The multiplication is exact ($19.99 \times 1.0825 = 21.639175$); only the
quantization to cents rounds, and the pipeline records that.

### Find out that an earlier step rounded

Flags of earlier steps stay in `flags()` even when later steps are exact:

```moonbit
///|
test "an early rounding is remembered" {
  let ctx = @decimal.DecimalContext::new(precision=5, e_min=-99, e_max=99)
  let r = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
    .add(@decimal.Decimal::from_int(1))
    .mul(@decimal.Decimal::from_int(2))
  inspect(r.value().to_string(), content="4.4692")
  inspect(flags(r.raised()), content="")
  inspect(flags(r.flags()), content="inexact,rounded")
}
```

### Keep going after a division by zero

IEEE decimal arithmetic defines a result for every operation. Dividing by zero
gives an infinity and the `division_by_zero` flag; the pipeline continues and
the flag is kept:

```moonbit
///|
test "division by zero is a flagged value" {
  let ctx = @decimal.DecimalContext::decimal64()
  let r = @decimal_checked.DecimalChecked::from_int(1, ctx)
    .div(@decimal.Decimal::zero())
    .add(@decimal.Decimal::from_int(5))
  inspect(r.value().to_string(), content="inf")
  inspect(flags(r.flags()), content="division_by_zero")
  inspect(r.is_ok(), content="true")
}
```

Decide at the end what the flags mean for your application, for example with
`DecimalFlags::has_error`, which is true when any of `invalid_operation`,
`conversion_syntax`, `division_by_zero`, `division_impossible`,
`division_undefined` or `invalid_context` is set.

### Start a new audit period

`clear_flags` resets both the raised and the accumulated flags without
touching the value:

```moonbit
///|
test "clear flags between phases" {
  let ctx = @decimal.DecimalContext::decimal64()
  let phase1 = @decimal_checked.DecimalChecked::from_int(2, ctx).div(
    @decimal.Decimal::from_int(3),
  )
  inspect(flags(phase1.flags()), content="inexact,rounded")
  let phase2 = phase1.clear_flags().mul(@decimal.Decimal::from_int(10))
  inspect(phase2.value().to_string(), content="6.666666666666667")
  inspect(flags(phase2.flags()), content="")
}
```

Multiplying the 16-digit quotient by ten is exact, so the second phase reports
no flags although the first one rounded.

## Going further

### Elementary functions need a bounded context

Mathematical functions (`exp`, `ln`, `power`, the trigonometric family, …)
follow the General Decimal Arithmetic restriction to precision and exponent
limits within $\pm 999\,999$. Use one of the interchange contexts or explicit
bounds; with the default unbounded range they return NaN with
`invalid_context`:

```moonbit
///|
test "a bounded context for ln" {
  let good = @decimal_checked.DecimalChecked::from_int(
    10,
    @decimal.DecimalContext::decimal128(),
  ).ln()
  inspect(good.value().to_string(), content="2.302585092994045684017991454684364")
  let bad = @decimal_checked.DecimalChecked::from_int(
    10,
    @decimal.DecimalContext::new(precision=34),
  ).ln()
  inspect(flags(bad.raised()), content="invalid_context")
}
```

### Start from a Luna-Flow/arithmetic context

Code that is generic over Luna-Flow/arithmetic carries an
`ArithmeticContext`. `DecimalContext::from_arithmetic_context` maps its
precision, rounding direction, exponent bounds and clamp flag; the predefined
`ArithmeticContext::decimal64()` maps to the same context as
`DecimalContext::decimal64()`:

```moonbit
///|
test "from an arithmetic context" {
  let ctx = @decimal.DecimalContext::from_arithmetic_context(
    @lf_arith.ArithmeticContext::decimal64(),
  )
  inspect(ctx == @decimal.DecimalContext::decimal64(), content="true")
  let r = @decimal_checked.DecimalChecked::from_int(2, ctx).sqrt()
  inspect(r.value().to_string(), content="1.414213562373095")
}
```

### Hand the result to the contextual traits

`result()` returns `Ok((value, flags))` or the recorded error. The
`AddContextual`, `SqrtContextual`, … implementations of `Decimal` in
Luna-Flow/arithmetic report diagnostics instead of flags; the six shared
conditions (`inexact`, `rounded`, `overflow`, `underflow`, `subnormal`,
`clamped`) can be carried over field by field:

```moonbit
///|
fn diagnostics(f : @decimal.DecimalFlags) -> @lf_arith.ArithmeticDiagnostics {
  @lf_arith.ArithmeticDiagnostics::new(
    inexact=f.inexact,
    rounded=f.rounded,
    overflow=f.overflow,
    underflow=f.underflow,
    subnormal=f.subnormal,
    clamped=f.clamped,
  )
}

///|
test "accumulated flags become arithmetic diagnostics" {
  let ctx = @decimal.DecimalContext::decimal64()
  match @decimal_checked.DecimalChecked::from_int(1, ctx).div(@decimal.Decimal::from_int(3)).result() {
    Ok((value, f)) => {
      let outcome = @lf_arith.ArithmeticOutcome::with_diagnostics(value, diagnostics(f))
      inspect(outcome.diagnostics.inexact, content="true")
    }
    Err(e) => fail(e.message)
  }
}
```

The [design page](../design/decimal_checked.md#from-flags-to-arithmetic-diagnostics)
shows why converting the accumulated flags once gives the same diagnostics as
combining the per-step diagnostics.

## Common pitfalls

- **`raised()` is not the whole story.** It describes the latest step only;
  audit with `flags()`.
- **Exceptional results are not errors.** NaN, infinities and rounded values
  are successes with flags. `is_err()` is true only for certification
  failures of elementary functions.
- **Unbounded contexts disable the mathematical functions.** See above; this
  also applies to contexts built from an `ArithmeticContext` without
  `e_min` / `e_max`.
- **Binary sources.** `from_double(0.1, …)` converts the binary value of
  `0.1` rounded to 17 digits, not one tenth and not the exact binary value
  (in decimal128 it is `0.10000000000000001`); parse the string `"0.1"`
  instead.
- **`remainder` is the IEEE remainder.** It rounds the quotient to the
  nearest integer, so `1` remainder `0.6` is `-0.2`, not `0.4`.
- **`atan2` with an infinite operand aborts.** Check `is_infinite()` first.
  Tracked in [#92](https://github.com/Luna-Flow/floating/issues/92); a fix is proposed in [#98](https://github.com/Luna-Flow/floating/pull/98).
- **Operands are plain `Decimal` values.** They are not rounded to the
  context before the operation; the operation rounds the result.
- **`clear_flags` also works after an error,** but the error stays.

## Next steps

- [`decimal_checked` design](../design/decimal_checked.md): the state model,
  the flag monoid and the short-circuit rule.
- [`decimal_checked` API](../api/decimal_checked.md): every method.
- [`decimal` tutorial](decimal.md): contexts, rounding modes and interchange
  formats.
- [`decimal_gda_checked` tutorial](decimal_gda_checked.md): the same idea for
  General Decimal Arithmetic with sticky status and traps.
