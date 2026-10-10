# decimal_gda tutorial

This tutorial teaches you to compute with `decimal_gda`, the package that
implements Cowlishaw's General Decimal Arithmetic (GDA): decimal numbers that
keep their trailing zeros, a context that fixes precision, rounding and
exponent limits, sticky status that records what happened, and traps that stop
a calculation while still handing you the defined result. By the end you can
thread a context through a calculation, round money, handle traps, overflow and
underflow, call the elementary functions and pick the right comparison. The
mathematics behind each rule is on the [design page](../design/decimal_gda.md);
every public name is on the [API page](../api/decimal_gda.md).

| I want to | Use |
| --- | --- |
| Read a number under a context | [`parse`](#quick-start) |
| Carry status from one operation to the next | [`next_context()`](#thread-the-context-through-a-calculation) |
| Round an amount to cents | [`quantize`](#keep-and-set-the-quantum) |
| Stop on a condition but keep the result | [`GdaContext::trap`](#handle-a-trap-without-losing-the-result) |
| Control overflow and underflow | [exponent limits and rounding modes](#respect-the-exponent-range) |
| Compute `exp`, `ln`, `log10`, `sqrt` or `power` | [elementary functions](#call-the-elementary-functions) |
| Compare numbers or representations | [`compare`, `compare_total`](#compare-and-print) |
| Chain many operations without manual threading | [`decimal_gda_checked`](#long-chains-with-decimal_gda_checked) |
| Encode decimal32/64/128 bit patterns | [`GdaInterchange`](#interchange-encodings) |

## Quick start

Add the module:

```bash
moon add Luna-Flow/floating@0.8.0
```

Import the package in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal_gda",
}
```

Every GDA operation takes its operands and a `GdaContext` and returns a
`GdaOutcome`: the result, the context to use next, and the conditions this
operation raised.

```moonbit
///|
test "quick start: one third in nine digits" {
  let ctx = @decimal_gda.context(precision=9).unwrap()
  let one = @decimal_gda.parse("1", ctx)
  let three = @decimal_gda.Decimal::from_string("3").unwrap()
  let third = @decimal_gda.divide(one.value(), three, one.next_context())
  inspect(third.value(), content="0.333333333")
  inspect(third.raised().contains(Inexact), content="true")
  inspect(third.next_context().status().contains(Rounded), content="true")
}
```

`raised()` describes this one operation. `next_context().status()` is sticky:
it collects every condition since the context was created or cleared.

## Everyday tasks

### Thread the context through a calculation

Status accumulates only when you pass each outcome's `next_context()` to the
next operation. The context you started with never changes, because a context
is a value, not a mutable object.

```moonbit
///|
test "sticky status follows the threaded context" {
  let start = @decimal_gda.context(precision=5).unwrap()
  let two = @decimal_gda.Decimal::from_string("2").unwrap()
  let three = @decimal_gda.Decimal::from_string("3").unwrap()
  let q = @decimal_gda.divide(two, three, start) // inexact
  let tiny = @decimal_gda.Decimal::from_string("0.00001").unwrap()
  let s = @decimal_gda.add(q.value(), tiny, q.next_context()) // exact
  inspect(s.value(), content="0.66668")
  inspect(s.raised().contains(Inexact), content="false")
  inspect(s.next_context().status().contains(Inexact), content="true")
  inspect(start.status().contains(Inexact), content="false")
  // Start a new observation window and keep the trap settings.
  let fresh = s.next_context().clear_status()
  inspect(fresh.status() == @decimal_gda.GdaFlags::none(), content="true")
}
```

### Keep and set the quantum

A GDA number is a coefficient and an exponent, so `2.50` and `2.5` are equal
numbers with different exponents (different *quanta*). Arithmetic keeps the
exponent that the exact result calls for, and `quantize` sets it explicitly.
That is how you round an amount to cents:

```moonbit
///|
test "round to cents with quantize" {
  let even = @decimal_gda.GdaContext::decimal64() // HalfEven
  let half_up = @decimal_gda.context(precision=16, rounding=HalfUp).unwrap()
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

`reduce` goes the other way: it removes trailing zeros, so `reduce(7.50)` is
`7.5`. Use it only when you really want the shortest cohort member.

### Handle a trap without losing the result

Enable a trap by deriving a new context with `trap`. A trapped operation
returns `Trapped(signal, value, next_context, raised)`: the GDA-defined result
is still there, and the sticky status is still updated.

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
      inspect(next.status().contains(DivisionByZero), content="true")
    }
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
}
```

An `InvalidOperation` trap also catches the four detailed invalid conditions
(`ConversionSyntax`, `DivisionImpossible`, `DivisionUndefined`,
`InvalidContext`). The basic context enables it, so a malformed literal traps:

```moonbit
///|
test "the InvalidOperation trap covers conversion syntax" {
  let basic = @decimal_gda.GdaContext::basic()
  let out = @decimal_gda.parse("1.2.3", basic)
  match out {
    @decimal_gda.GdaOutcome::Trapped(signal, value, _, raised) => {
      inspect(signal == InvalidOperation, content="true")
      inspect(value, content="nan")
      inspect(raised.conversion_syntax, content="true")
    }
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
}
```

When one operation raises several trapped conditions, the package reports one
of them by a fixed precedence (listed in the [API page](../api/decimal_gda.md#trap-selection)),
so you never have to invent your own order.

### Respect the exponent range

A context bounds the adjusted exponent to `[e_min, e_max]`. Beyond `e_max` the
result overflows; what it overflows *to* depends on the rounding mode. Below
`e_min` the result becomes subnormal and loses digits:

```moonbit
///|
test "overflow and underflow in decimal32" {
  let d32 = @decimal_gda.GdaContext::decimal32() // p=7, e_max=96, HalfEven
  let down = @decimal_gda.context(
    precision=7,
    rounding=Down,
    e_min=-95,
    e_max=96,
    clamp=true,
  ).unwrap()
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
even, whatever the context's rounding mode says. `power` with a non-integer
exponent is also correctly rounded, but under the context's own rounding mode.
As the GDA specification requires, `exp`, `ln`, `log10` and non-integer `power`
only accept contexts with precision, `e_max` and `-e_min` at most 999,999; the
decimal32/64/128 presets qualify, but the defaults of `GdaContext::new` and
`context` (exponent range ±999,999,999) do not:

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
  let floor3 = @decimal_gda.context(
    precision=3,
    rounding=Floor,
    e_min=-999_999,
    e_max=999_999,
  ).unwrap()
  let three_halves = @decimal_gda.Decimal::from_string("1.5").unwrap()
  inspect(@decimal_gda.exp(one, floor3).value(), content="2.72") // still half-even
  inspect(@decimal_gda.power(two, three_halves, floor3).value(), content="2.82") // floor
}
```

### Compare and print

`compare` is numeric and returns a decimal (`-1`, `0`, `1`, or NaN when an
operand is NaN). `compare_total` orders representations, so it tells `2.50`
from `2.5`. Printing a value gives its scientific string; `class_name` names
its class:

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
  let (eng, _) = @decimal_gda.Decimal::to_eng_string(
    "123E+5",
    @decimal_gda.DecimalContext::new().unwrap(),
  )
  inspect(eng, content="12.3E+6")
}
```

## Going further

### Long chains with `decimal_gda_checked`

Manual threading is clearest at boundaries. For a long linear pipeline,
[`decimal_gda_checked`](decimal_gda_checked.md) keeps one outcome, threads the
sticky context for you and stops after the first trap:

```moonbit
///|
test "a checked GDA pipeline" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse("2", ctx)
    .sqrt()
    .multiply(@decimal_gda.Decimal::from_string("10").unwrap())
  inspect(checked.value(), content="14.14213562373095")
  inspect(checked.is_trapped(), content="false")
  inspect(checked.status().contains(Inexact), content="true")
}
```

### Generic code through `Luna-Flow/arithmetic`

`Decimal` implements the contextual traits of
[`Luna-Flow/arithmetic`](https://lunaflow.cn/en/arithmetic/), so code written
against `AddContextual`, `DivContextual`, `SqrtContextual` and friends runs on
it. These adapters use the five IEEE-style rounding modes of
`ArithmeticContext`, report errors as `Err`, and know nothing about traps:

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

`GdaContext::basic()` is the GDA *basic default context*: precision 9,
`HalfUp`, `extended=false`, with the `DivisionByZero`, `InvalidOperation`,
`Overflow`, `Underflow` and `Clamped` traps enabled. A non-extended context
rounds operands that are longer than the precision before using them and
reports `LostDigits` when that loses information:

```moonbit
///|
test "subset arithmetic rounds long operands" {
  let basic = @decimal_gda.GdaContext::basic()
  let long = @decimal_gda.Decimal::from_string("1234567891").unwrap()
  let zero = @decimal_gda.Decimal::zero()
  let out = @decimal_gda.add(long, zero, basic)
  inspect(out.value(), content="1.23456789E+9")
  inspect(out.raised().contains(LostDigits), content="true")
}
```

### Interchange encodings

`GdaInterchange` holds a decimal32, decimal64 or decimal128 bit pattern in the
densely packed decimal (DPD) encoding, written as `#` and hexadecimal digits:

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

- **Reusing the original context.** Status only accumulates if you pass
  `next_context()` on. A trap set or status you put on a context also travels
  with every context derived from it.
- **Treating `Trapped` as "no value".** A trap changes the variant, not the
  result; read the value with `value()` before you decide to stop.
- **Expecting constructors to keep zeros.** `Decimal::from_int(100)` and
  `Decimal::make` remove trailing zeros, so `from_int(100)` prints `1E+2`. Use
  `Decimal::from_string("100")` or `parse` when the quantum matters.
- **Using the operators for GDA work.** `+`, `-`, `*` and `/` take no context:
  they round half-even to the larger operand precision (`*` is exact), never
  signal, and `+` and `/` return the shortest cohort member. Use the package
  functions whenever GDA results, flags or traps matter.
- **Equality and NaN.** `==` and `compare` put every NaN equal to every other
  NaN and above every number (a total preorder, so sorting never aborts). Use
  `compare` (the package function), `compare_signal`, or
  `Decimal::compare_checked` when NaN must stay unordered.
- **Mixing the two decimal packages.** `@decimal_gda.Decimal` and
  `@decimal.Decimal` are different types with different contracts; cross
  between them through strings or interchange bits.
- **Expecting `exp`, `ln`, `log10` or `sqrt` to follow the context rounding.**
  They always round half to even; only `power` follows the context.
- **Calling `exp`, `ln`, `log10` or non-integer `power` with a default
  context.** `GdaContext::new()` and `context()` allow exponents up to
  ±999,999,999, which is outside the range these functions are defined for, so
  they return NaN and raise `InvalidContext` (an `InvalidOperation`). Use a
  preset or pass `e_min=-999_999, e_max=999_999`. The same holds for an
  `ArithmeticContext` without `e_min` and `e_max`: no bounds are filled in for
  you, and `exp_contextual` returns `Err(unsupported)` with an
  `invalid context:` message naming the missing bounds.

## Next steps

- [Design](../design/decimal_gda.md): the arithmetic model, ideal exponents,
  rounding functions, the signal and trap state machine, and how the
  elementary functions are certified.
- [API reference](../api/decimal_gda.md): every type, function and method.
- [Conformance](../conformance/decimal_gda.md) and
  [performance](../performance/decimal_gda.md): the pinned test-suite result and
  how to measure speed.
- [`decimal_gda_checked` tutorial](decimal_gda_checked.md): trap
  short-circuiting and recovery in pipelines.
- [`decimal` tutorial](decimal.md): the IEEE 754 decimal model with
  per-operation flags.
