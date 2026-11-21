# Getting started

This guide takes you from an empty MoonBit project to correct first results
with `Luna-Flow/floating`: choosing a package, installing it, building values,
choosing how precision and failures are reported, and reading the results.
Every example compiles against the current branch.

## Choose a numeric domain

Choose the package by the semantics your program needs, not by how its input
is spelled.

| You need | Package | Main type | Results |
| --- | --- | --- | --- |
| arbitrary-precision binary values, IEEE 754 binary formats | `binary` | `Binary` | value, or `(value, BinaryFlags)` under a `BinaryContext` |
| IEEE 754 decimal arithmetic and decimal32/64/128 interchange | `decimal` | `Decimal` | value, or `(value, DecimalFlags)` under a `DecimalContext` |
| General Decimal Arithmetic with sticky status and traps | `decimal_gda` | `Decimal` | `GdaOutcome[Decimal]` with the next `GdaContext` |
| certified enclosures of real results (IEEE 1788) | `interval` | `Interval`, `DecoratedInterval` | an interval, or `(interval, IntervalFlags)` under an `IntervalContext` |
| a binary pipeline that stops at the first error | `binary_checked` | `BinaryChecked` | `Result[Binary, ArithmeticError]` inside a wrapper |
| an IEEE decimal pipeline that accumulates flags | `decimal_checked` | `DecimalChecked` | defined value plus latest and accumulated `DecimalFlags` |
| a GDA pipeline that stops at a trap | `decimal_gda_checked` | `GdaDecimalChecked` | one threaded `GdaOutcome[Decimal]` |
| an interval pipeline that stops at the first error | `interval_checked` | `IntervalChecked` | `Result[Interval, ArithmeticError]` inside a wrapper |
| comparing values across packages | `semantic` | `SemanticScalar`, `SemanticInterval` | exact rationals, deliberately dropping metadata |

`def` holds the small vocabulary all of them share (`Sign`, `PartialOrder`,
the `Floating` trait and re-exported `arithmetic` types). `numeric_expr` and
`frontend/*` are for parser and conformance tooling; `internal/*`, `cli/*`,
`consistency`, `doc_examples` and `bench/*` are repository infrastructure, not
application dependencies. The [manual overview](./index.md) lists every
package.

## Install and import

You need the MoonBit toolchain 0.10.20 or later (`moonc` ≥ 0.10.20). Add the module,
and `Luna-Flow/arithmetic` if you name its rounding modes or contexts
yourself:

```bash
moon add Luna-Flow/floating@0.11.0
moon add Luna-Flow/arithmetic
```

> [!NOTE]
> The manual describes the current branch. Operations listed under
> "Unreleased" in the changelog (for example `Binary::fma_ctx`,
> `remainder_ctx`, `next_up_ctx` and decimal string formatting) are not in a
> published release yet.

Import only the packages you use in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/arithmetic" @lf_arith,
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/interval",
}
```

Imports name packages, not files: each directory with a `moon.pkg` is one
package, and its files share one namespace. By convention the manual imports
`Luna-Flow/arithmetic` as `@lf_arith` and `Luna-Flow/luna-generic` as
`@lf_alg`.

## Build values

A `Binary` is an exact dyadic number $c \cdot 2^e$ with a precision; a
`Decimal` is $c \cdot 10^q$ and remembers the exponent $q$ of its literal; an
`Interval` is an interval with binary endpoints.

```moonbit
///|
test "first values" {
  // 3 * 2^-1 at 53 bits of precision.
  let binary = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(3UL),
    -1,
    53,
  )
  inspect(binary, content="3p-1")
  inspect(binary.to_shortest_string(), content="1.5")
  // Parsing keeps significant trailing zeros.
  let price = @decimal.Decimal::from_string("12.3400").unwrap()
  inspect(price, content="12.3400")
  inspect(price.exponent10(), content="-4")
  // Every real number from 1 through 2.
  let interval = @interval.Interval::from_bounds(
    @binary.Binary::from_int(1),
    @binary.Binary::from_int(2),
  )
  inspect(interval.is_member(binary), content="true")
}
```

`Binary` prints in the exact form `<coefficient>p<exponent>`; use
`to_shortest_string` or `to_decimal_string_ctx` for decimal text. Call
`normalized()` on a decimal only when you want to drop its cohort.

Other constructors: `Binary::from_int`, `from_double`, `from_string` and
`from_string_ctx` (correctly rounded decimal parsing), `from_hex`;
`Decimal::from_int`, `from_string` and `from_string_ctx`; `Interval::from_int`,
`from_double`, `exact` and `from_bounds`. Constructors take an optional
`precision`; `Interval::from_int` defaults to 53 bits, as the other
constructors.

## Choose a context

The plain operators (`+`, `-`, `*`, `/` and `add`, `mul`, …) work at the
operands' precision with round-to-nearest-even and an effectively unbounded
exponent range, and they discard status. When precision, exponent range,
rounding direction, tininess or the status flags are part of your result, use
the `*_ctx` form with an explicit context:

```moonbit
///|
test "contextual arithmetic" {
  let ctx = @binary.BinaryContext::binary64()
  let (third, flags) = @binary.Binary::from_int(1).div_ctx(
    @binary.Binary::from_int(3),
    ctx,
  )
  inspect(third.to_shortest_string(), content="0.3333333333333333")
  inspect(flags.inexact(), content="true")
  // The same quotient rounded upward lands one ulp higher.
  let up = @binary.BinaryContext::binary64(rounding=RoundTowardPositive)
  let (high, _) = @binary.Binary::from_int(1).div_ctx(
    @binary.Binary::from_int(3),
    up,
  )
  inspect(high.sub(third) == third.ulp(), content="true")
  let decimal_ctx = @decimal.DecimalContext::decimal64()
  let (q, decimal_flags) = @decimal.Decimal::from_int(1).div_ctx(
    @decimal.Decimal::from_int(3),
    decimal_ctx,
  )
  inspect(q, content="0.3333333333333333")
  inspect(decimal_flags.inexact(), content="true")
}
```

Contexts are immutable values; nothing in the library reads a global rounding
mode. IEEE contexts return the flags of one operation, which you `combine`
yourself. A GDA context instead travels with the result: every `GdaOutcome`
returns the next context, whose status accumulates the flags.

## Choose a failure model

The library exposes several failure channels on purpose. Pick the one that
matches what your caller must observe:

- `Option` from simple constructors such as `Decimal::from_string`, when bad
  input needs no diagnostic.
- `Result[T, ArithmeticError]` from checked operations (`div_checked`,
  `sqrt`, `compare_checked`, `from_string`, the `try_*_ctx` elementary
  functions).
- `BinaryFlags`, `DecimalFlags` and `IntervalFlags` beside a defined result.
- `GdaOutcome[T]`, which keeps the GDA-defined result even when a trap fires.
- The pipeline wrappers: `BinaryChecked` and `IntervalChecked` stop at the
  first error; `DecimalChecked` keeps defined NaN and infinity results and
  accumulates flags; `GdaDecimalChecked` stops at a trap and keeps its
  outcome.
- Empty, Entire and NaI, which are interval values, not errors.

```moonbit
///|
test "pipelines" {
  let failed = @binary_checked.BinaryChecked::from_int(-4).sqrt()
  inspect(failed.is_err(), content="true")
  let ctx = @decimal.DecimalContext::decimal64()
  let three = @decimal_checked.DecimalChecked::from_int(3, ctx)
  let total = @decimal_checked.DecimalChecked::parse("1", ctx)
    .div(three)
    .mul(three)
  inspect(total.value(), content="0.9999999999999999")
  // Accumulated over the pipeline versus raised by the last step.
  inspect(total.flags().inexact(), content="true")
  inspect(total.raised().inexact(), content="false")
}
```

Do not fold these channels into one exception type or one `Result`: that
erases semantics the standards make observable.

## Read results correctly

- Signed zero, infinities, quiet and signaling NaN, and NaN payloads are
  observable on scalars.
- `compare`, `<` and sorting use a total preorder in which every NaN is equal
  to every other NaN and above every number, and $-0 = +0$. For IEEE
  semantics use `compare_checked`, the quiet and signaling predicates of
  `binary`, or the `total_order*` functions.
- `==` agrees with `compare` in the number types: on `Binary` it ignores the
  sign of a zero and the precision (`-0 == +0`) and treats two NaNs as equal, on
  `Decimal` it compares values, and on `Interval` it compares the bounds by
  value (two empty intervals are equal). `a.identical(b)` compares every field
  of a `Binary`. See [numeric semantics](./numeric_semantics.md).
- An `Interval` has containment and set relations (`contains`, `subset`,
  `definitely_lt`, …), not a scalar order. A result is correct when it encloses
  the exact result; tightness is a separate quality.
- `SemanticScalar` compares mathematical values across packages and drops
  precision, exponent, signed zero, payloads, decorations and flags.

## Continue reading

- [Numeric semantics](./numeric_semantics.md) defines rounding, ulp, flags,
  exponent, signed zero, NaN and enclosures with their derivations.
- [Architecture](./architecture.md) explains the package layers and the
  certified elementary functions.
- [Verification](./verification.md) lists the gates and the exact scope of each
  conformance claim.
- Each package has a tutorial, an API reference and a design page; start with
  the [`binary` tutorial](./tutorial/binary.md), the
  [`decimal` tutorial](./tutorial/decimal.md) or the
  [`interval` tutorial](./tutorial/interval.md).
