# decimal_gda tutorial

Use `decimal_gda` to parse decimal input, carry a context through calculations,
round amounts, inspect conditions and preserve trailing zeros. A context sets
the precision, rounding algorithm and exponent limits; its flags record the
conditions raised by each operation, and its traps can stop an operation while
returning its defined result. The [design page](../design/decimal_gda.md)
explains the arithmetic rules, and the [API page](../api/decimal_gda.md) lists
every public name.

| I want to | Use |
| --- | --- |
| Read a number under a context | [`parse`](#quick-start) |
| Carry flags from one operation to the next | [`next_context()`](#thread-the-context-through-a-calculation) |
| Round an amount to cents | [`quantize`](#keep-and-set-the-quantum) |
| Stop on a condition but keep the result | [`GdaContext::trap`](#handle-a-trap-without-losing-the-result) |
| Control overflow and underflow | [exponent limits and rounding algorithms](#respect-the-exponent-range) |
| Compute `exp`, `ln`, `log10`, `sqrt` or `power` | [elementary functions](#call-the-elementary-functions) |
| Compare numbers or representations | [`compare`, `compare_total`](#compare-and-print) |
| Chain many operations without manual threading | [`decimal_gda_checked`](#long-chains-with-decimal_gda_checked) |
| Encode decimal32/64/128 bit patterns | [`GdaInterchange`](#interchange-encodings) |

## Quick start

Add the module to your project:

```bash
moon add Luna-Flow/floating@0.11.0
```

Import the package in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal_gda",
}
```

Pass the operands and a `GdaContext` to a GDA operation. It returns a
`GdaOutcome` containing the result, the next context and the conditions raised
by that operation.

```moonbit
///|
test "quick start: one third in nine digits" {
  let ctx = @decimal_gda.GdaContext::new(precision=9)
  let one = @decimal_gda.to_number("1", ctx)
  let three = @decimal_gda.Decimal::from_string("3").unwrap()
  let third = @decimal_gda.divide(one.value(), three, one.next_context())
  inspect(third.value(), content="0.333333333")
  inspect(third.raised().contains(Inexact), content="true")
  inspect(third.next_context().flags().contains(Rounded), content="true")
}
```

`raised()` reports the conditions from this operation. The flags in
`next_context()` accumulate every condition raised since the context was created
or its flags were cleared.

## Everyday tasks

### Thread the context through a calculation

Pass each outcome's `next_context()` to the next operation to accumulate flags.
The starting context remains unchanged because a context is a value.

```moonbit
///|
test "sticky flags follows the threaded context" {
  let start = @decimal_gda.GdaContext::new(precision=5)
  let two = @decimal_gda.Decimal::from_string("2").unwrap()
  let three = @decimal_gda.Decimal::from_string("3").unwrap()
  let q = @decimal_gda.divide(two, three, start) // inexact
  let tiny = @decimal_gda.Decimal::from_string("0.00001").unwrap()
  let s = @decimal_gda.add(q.value(), tiny, q.next_context()) // exact
  inspect(s.value(), content="0.66668")
  inspect(s.raised().contains(Inexact), content="false")
  inspect(s.next_context().flags().contains(Inexact), content="true")
  inspect(start.flags().contains(Inexact), content="false")
  // Start a new observation window and keep the trap settings.
  let fresh = s.next_context().clear_flags()
  inspect(fresh.flags() == @decimal_gda.GdaFlags::new(), content="true")
}
```

### Keep and set the quantum

A GDA number has a coefficient and an exponent. The quantum is $10^q$, where
$q$ is that exponent, so `2.50` and `2.5` have the same value but different
quanta. Arithmetic chooses the exponent required by the exact result, while
`quantize` sets a target exponent. Use it to round an amount to cents:

```moonbit
///|
test "round to cents with quantize" {
  let even = @decimal_gda.GdaContext::decimal64() // HalfEven
  let half_up = @decimal_gda.GdaContext::new(precision=16, rounding=HalfUp)
  let price = @decimal_gda.Decimal::from_string("2.50").unwrap()
  let qty = @decimal_gda.Decimal::from_string("3").unwrap()
  inspect(@decimal_gda.multiply(price, qty, even).value(), content="7.50")
  let cents = @decimal_gda.Decimal::from_string("0.01").unwrap()
  let x = @decimal_gda.Decimal::from_string("2.345").unwrap()
  let banker = @decimal_gda.quantize(x, cents, even)
  let school = @decimal_gda.quantize(x, cents, half_up)
  inspect(banker.value(), content="2.34")
  inspect(school.value(), content="2.35")
  inspect(banker.raised().contains(Inexact), content="true")
  // A quantum that needs more digits than the precision is invalid.
  let tiny = @decimal_gda.Decimal::from_string("1E-20").unwrap()
  let bad = @decimal_gda.quantize(x, tiny, even)
  inspect(bad.value(), content="nan")
  inspect(bad.raised().contains(InvalidOperation), content="true")
}
```

`reduce` removes trailing zeros, so `reduce(7.50)` is `7.5`. Use it when you
want the shortest representation in the same cohort.

### Handle a trap without losing the result

Call `trap` on a context to enable a trap. A trapped operation returns
`Trapped(signal, value, next_context, raised)`. The result specified by GDA
remains available as `value`, and `next_context` contains the updated flags.

```moonbit
///|
test "a trapped division keeps its defined result" {
  let ctx = @decimal_gda.GdaContext::decimal64().trap(DivisionByZero)
  let one = @decimal_gda.Decimal::one()
  let zero = @decimal_gda.Decimal::zero()
  match @decimal_gda.divide(one, zero, ctx) {
    @decimal_gda.GdaOutcome::Trapped(signal, value, next, raised) => {
      inspect(signal == DivisionByZero, content="true")
      inspect(value, content="inf")
      inspect(raised.contains(DivisionByZero), content="true")
      inspect(next.flags().contains(DivisionByZero), content="true")
    }
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
}
```

An `InvalidOperation` trap also covers conversion syntax, division impossible,
division undefined and invalid context. These four detailed conditions appear
as flags in the outcome, not as signals. Only the specification's nine signals
can be trapped. `GdaContext::basic_default()` enables `InvalidOperation`, so a
malformed literal traps:

```moonbit
///|
test "the InvalidOperation trap covers conversion syntax" {
  let basic = @decimal_gda.GdaContext::basic_default()
  let out = @decimal_gda.to_number("1.2.3", basic)
  match out {
    @decimal_gda.GdaOutcome::Trapped(signal, value, _, raised) => {
      inspect(signal == InvalidOperation, content="true")
      inspect(value, content="nan")
      inspect(raised.conversion_syntax(), content="true")
    }
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
}
```

When an operation raises several trapped conditions, the package reports one
according to a fixed precedence. The [API page](../api/decimal_gda.md#trap-selection)
lists that precedence.

### Respect the exponent range

The context bounds the adjusted exponent to `[e_min, e_max]`. A result above
`e_max` overflows; its rounding algorithm determines what the result becomes.
A result below `e_min` becomes subnormal and loses digits:

```moonbit
///|
test "overflow and underflow in decimal32" {
  let d32 = @decimal_gda.GdaContext::decimal32() // p=7, e_max=96, HalfEven
  let down = @decimal_gda.GdaContext::new(
    precision=7,
    rounding=Down,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
  let big = @decimal_gda.Decimal::from_string("9E+96").unwrap()
  let ten = @decimal_gda.Decimal::from_string("10").unwrap()
  inspect(@decimal_gda.multiply(big, ten, d32).value(), content="inf")
  inspect(@decimal_gda.multiply(big, ten, down).value(), content="9.999999E+96")
  let small = @decimal_gda.Decimal::from_string("1.234567E-95").unwrap()
  let thousand = @decimal_gda.Decimal::from_string("1000").unwrap()
  let sub = @decimal_gda.divide(small, thousand, d32)
  inspect(sub.value(), content="1.235E-98")
  inspect(sub.raised().contains(Subnormal), content="true")
  inspect(sub.raised().contains(Underflow), content="true")
}
```
### Call the elementary functions

`sqrt`, `exp`, `ln` and `log10` are correctly rounded and always round half to
even, whatever the context's rounding algorithm says. `power` with a non-integer
exponent is also correctly rounded, but under the context's own rounding
algorithm. `exp`, `ln`, `log10` and non-integer `power` only accept contexts with
precision, `e_max` and `-e_min` at most 999,999 (decNumber's limit, which the
decTest suite requires and GDA's Invalid context condition permits; the
operation text of the specification states no such bound); the
decimal32/64/128 presets qualify, but the defaults of `GdaContext::new` and
`context` (exponent range ±999,999,999) do not:

GDA 1.70, page 30 (exp) and page 31 (ln, log10), allows an inexact result to be
up to 1 ulp from the correctly rounded result; this package returns the correctly
rounded result. GDA 1.70, page 39 (square-root), specifies half-even rounding for
an inexact square root, and this package also returns the correctly rounded result.
GDA 1.70, page 35 (power), allows up to 1 ulp of error for a non-integer
exponent; this package returns the correctly rounded result.

```moonbit
///|
test "elementary functions" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let one = @decimal_gda.Decimal::one()
  let two = @decimal_gda.Decimal::from_string("2").unwrap()
  let ten = @decimal_gda.Decimal::from_string("10").unwrap()
  inspect(@decimal_gda.exp(one, ctx).value(), content="2.718281828459045")
  inspect(@decimal_gda.ln(ten, ctx).value(), content="2.302585092994046")
  inspect(@decimal_gda.log10(two, ctx).value(), content="0.3010299956639812")
  inspect(@decimal_gda.sqrt(two, ctx).value(), content="1.414213562373095")
  // exp, ln, log10 and non-integer power need |e_min|, e_max <= 999999.
  let floor3 = @decimal_gda.GdaContext::new(
    precision=3,
    rounding=Floor,
    e_min=-999_999,
    e_max=999_999,
  )
  let three_halves = @decimal_gda.Decimal::from_string("1.5").unwrap()
  inspect(@decimal_gda.exp(one, floor3).value(), content="2.72") // still half-even
  inspect(@decimal_gda.power(two, three_halves, floor3).value(), content="2.82") // floor
}
```

Here, certification means that the package decides the rounding result before
returning it. Each function
refines its enclosure at most twelve times by default. For an argument close
to a rounding boundary, `ctx.with_refinement_limit(Some(24))` allows 24 steps;
`with_refinement_limit(None)` removes the count, so the working precision
stops at a resource bound of at least 8,000,000 bits. Read the current setting
with `refinement_limit()`.

### Compare and print

Use `compare` for numerical order: it returns a decimal containing `-1`, `0`,
or `1`, and returns NaN when an operand is NaN. Use `compare_total` when the
representation matters; it orders `2.50` before `2.5`. Printing a value uses
scientific notation, while `class_name` returns its class name:

```moonbit
///|
test "comparisons and text" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let a = @decimal_gda.Decimal::from_string("2.50").unwrap()
  let b = @decimal_gda.Decimal::from_string("2.5").unwrap()
  inspect(@decimal_gda.compare(a, b, ctx).value(), content="0")
  inspect(@decimal_gda.compare_total(a, b, ctx).value(), content="-1")
  let nan = @decimal_gda.Decimal::nan()
  inspect(@decimal_gda.compare(a, nan, ctx).value(), content="nan")
  inspect(
    @decimal_gda.compare_signal(a, nan, ctx).raised().contains(InvalidOperation),
    content="true",
  )
  let big = @decimal_gda.Decimal::from_string("123E+5").unwrap()
  inspect(big, content="1.23E+7")
  inspect(@decimal_gda.class_name(big, ctx).value(), content="+Normal")
  inspect(big.to_eng_string(), content="12.3E+6")
}
```
## Going further

### Long chains with `decimal_gda_checked`

Manual context threading is clearest at calculation boundaries. For a long
linear pipeline, use [`decimal_gda_checked`](decimal_gda_checked.md): it keeps
one outcome, threads the flags and context through each operation, and stops
after the first trap:

```moonbit
///|
test "a checked GDA pipeline" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let ten = @decimal_gda_checked.GdaDecimalChecked::to_number("10", ctx)
  let checked = @decimal_gda_checked.GdaDecimalChecked::to_number("2", ctx)
    .sqrt()
    .multiply(ten)
  inspect(checked.value(), content="14.14213562373095")
  inspect(checked.is_err(), content="false")
  inspect(checked.flags().contains(Inexact), content="true")
}
```

### Generic code through `Luna-Flow/arithmetic`

`Decimal` implements the contextual traits of
[`Luna-Flow/arithmetic`](https://lunaflow.cn/en/arithmetic/). Generic code that
uses traits such as `AddContextual`, `DivContextual` and `SqrtContextual` can
therefore use `Decimal`. These adapters use the five IEEE-style rounding
algorithms of `ArithmeticContext`, return errors as `Err`, and do not support
traps:

```moonbit
///|
fn[T : @lf_arith.AddContextual] sum3(
  a : T,
  b : T,
  c : T,
  ctx : @lf_arith.ArithmeticContext,
) -> Result[T, @lf_arith.ArithmeticError] {
  match @lf_arith.AddContextual::add_contextual(a, b, ctx) {
    Ok(ab) =>
      @lf_arith.AddContextual::add_contextual(ab.value, c, ctx).map(o => o.value)
    Err(error) => Err(error)
  }
}

///|
test "generic contextual addition" {
  let ctx = @lf_arith.ArithmeticContext::new(3)
  let x = @decimal_gda.Decimal::from_string("1.25").unwrap()
  inspect(sum3(x, x, x, ctx).unwrap(), content="3.75")
}
```

### Subset arithmetic and lost digits

`GdaContext::basic_default()` is the GDA basic default context: precision 9,
`HalfUp`, `extended=false`, and traps for `DivisionByZero`,
`InvalidOperation`, `Overflow`, `Underflow` and `Clamped`. A non-extended
context rounds an operand with more digits than the precision before using it
and raises `LostDigits` when that rounding loses information:

```moonbit
///|
test "subset arithmetic rounds long operands" {
  let basic = @decimal_gda.GdaContext::basic_default()
  let long = @decimal_gda.Decimal::from_string("1234567891").unwrap()
  let zero = @decimal_gda.Decimal::zero()
  let out = @decimal_gda.add(long, zero, basic)
  inspect(out.value(), content="1.23456789E+9")
  inspect(out.raised().contains(LostDigits), content="true")
}
```

### Interchange encodings

`GdaInterchange` represents a decimal32, decimal64 or decimal128 bit pattern
in densely packed decimal (DPD) encoding. The pattern is written as `#`
followed by hexadecimal digits:

```moonbit
///|
test "decimal64 interchange round trip" {
  let x = @decimal_gda.Decimal::from_string("-7.50").unwrap()
  let (bits, _) = @decimal_gda.GdaInterchange::from_decimal(x, Decimal64)
  inspect(bits.to_hex(), content="#A2300000000003D0")
  inspect(bits.to_decimal(), content="-7.50")
}
```
## Common pitfalls

- **Reusing the original context.** Flags accumulate only when you pass each
  outcome's `next_context()` to the next operation. Trap settings and flags also
  travel with contexts derived from the original.
- **Treating `Trapped` as "no value".** A trap changes the outcome variant, not
  the result. Read `value()` before deciding whether to stop.
- **Expecting constructors to keep zeros.** `Decimal::from_int(100)` and
  `Decimal::make` remove trailing zeros, so `from_int(100)` prints `1E+2`. Use
  `Decimal::from_string("100")` or `parse` when the quantum matters.
- **Using the operators for GDA work.** `+`, `-`, `*` and `/` take no context.
  They use a private context with larger operand precision, half-even rounding,
  no clamp and no traps. They round to that private precision and return the GDA
  cohort member: `1.10 + 3.50` is `4.60`. Use the package functions when GDA
  results, flags or traps matter.
- **Equality and NaN.** `==` and `compare` put every NaN equal to every other
  NaN and above every finite number. Use the package `compare`,
  `compare_signal`, or `Decimal::compare_checked` when NaN must remain
  unordered.
- **Mixing the two decimal packages.** `@decimal_gda.Decimal` and
  `@decimal.Decimal` have different contracts and types. Convert between them
  through strings or interchange bits.
- **Expecting elementary functions to follow the context rounding.** `exp`,
  `ln`, `log10` and `sqrt` round half to even; only `power` follows the
  context's rounding algorithm. The [elementary-functions task](#call-the-elementary-functions)
  gives the required context range.
- **Using a default context for elementary functions.** The default exponent
  range is $-999{,}999{,}999$ to $999{,}999{,}999$, outside the implementation
  limit for these operations. They return NaN and raise `InvalidContext` (an
  `InvalidOperation`). Use a preset or set the bounds described in [the
  elementary-functions task](#call-the-elementary-functions). The same applies
  to an `ArithmeticContext` without `e_min` and `e_max`: no bounds are filled in,
  and `exp_contextual` returns `Err(unsupported)` with an `invalid context:`
  message naming the missing bounds.

## Next steps

- [Design](../design/decimal_gda.md): the arithmetic model, ideal exponents,
  rounding functions, the signal and trap state machine, and the certification
  method for elementary functions.
- [API reference](../api/decimal_gda.md): every type, function and method.
- [Conformance](../conformance/decimal_gda.md) and
  [performance](../performance/decimal_gda.md): the pinned test-suite result and
  how to measure speed.
- [`decimal_gda_checked` tutorial](decimal_gda_checked.md): trap
  short-circuiting and recovery in pipelines.
- [`decimal` tutorial](decimal.md): the IEEE 754 decimal model with
  per-operation flags.
