# decimal tutorial

This tutorial shows how to compute with decimal numbers that behave the way
people write them: `0.1 + 0.2` is exactly `0.3`, `12.30` remembers that it
has two decimal places, and every rounding is chosen by you and reported back
to you. You will parse and format values, compute under a context and read
its flags, round money with `quantize`, exchange decimal64 bits, and call
certified elementary functions. The mathematics behind each step is in
the [decimal design](../design/decimal.md); every function is specified in the
[decimal API](../api/decimal.md).

| I want to | Use |
| --- | --- |
| parse an amount and keep its decimal places | [`Decimal::from_string`](#parse-amounts-and-keep-their-scale) |
| compute with a fixed precision and see what was rounded | [`*_ctx` operations and `DecimalFlags`](#compute-under-a-context-and-keep-the-flags) |
| round money to cents, half-even or half-up | [`quantize`](#round-money-with-quantize) |
| get a guaranteed lower and upper bound | [directed rounding](#bound-a-result-from-both-sides) |
| read or write decimal64 bits (DPD or BID) | [`DecimalInterchange`](#exchange-decimal64-bits) |
| take a logarithm or an exponential | [`ln_ctx`, `try_ln_ctx`](#call-an-elementary-function) |
| run generic `Ring` code on decimals | [the algebra traits](#generic-code-over-the-algebra-traits) |
| sort stored values deterministically | [`compare_total`](#a-deterministic-order-for-storage) |
| accumulate flags over a long pipeline | [`decimal_checked`](decimal_checked.md) |

## Quick start

Add `floating` to your module:

```bash
moon add Luna-Flow/floating@0.8.0
```

and import the package in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal",
}
```

The smallest useful program adds two decimal fractions that a `Double` cannot
represent:

```moonbit
///|
test "decimal quick start" {
  let a = @decimal.Decimal::from_string("0.1").unwrap()
  let b = @decimal.Decimal::from_string("0.2").unwrap()
  inspect(a + b, content="0.3")
  inspect(0.1 + 0.2 == 0.3, content="false")
}
```

`0.1` is $1/10$, and no power of two is divisible by 5, so binary floating
point can only approximate it; decimal floating point stores it exactly.

## Everyday tasks

### Parse amounts and keep their scale

Parsing keeps the exponent of the text. Two values can be equal and still
carry different information:

```moonbit
///|
test "decimal parsing keeps the quantum" {
  let price = @decimal.Decimal::from_string("12.30").unwrap()
  let same = @decimal.Decimal::from_string("12.3").unwrap()
  inspect(price == same, content="true")
  inspect(price.quantum(), content="-2")
  inspect(same.quantum(), content="-1")
  inspect(price.same_quantum(same), content="false")
  inspect(price.normalized(), content="12.3")
}
```

`12.30` and `12.3` are two members of the same *cohort*: numerically equal,
written with different exponents. `normalized()` picks the shortest member.
Do not call it on amounts whose number of decimal places matters; call it
when you want a canonical key.

Integers are built reduced: `Decimal::from_int(1000)` is stored as $1 \times
10^{3}$ and prints as `1E+3`. Parse `"1000"` when you want the four digits.

### Compute under a context and keep the flags

A `DecimalContext` fixes the precision, rounding mode and exponent range.
Each `*_ctx` operation returns the result and the flags it raised. Combine the
flags as you go:

```moonbit
///|
test "decimal64 pipeline with flags" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let (total, f1) = d("100").div_ctx(d("3"), ctx)
  let (scaled, f2) = total.mul_ctx(d("3"), ctx)
  let flags = f1.combine(f2)
  inspect(total, content="33.33333333333333")
  inspect(scaled, content="99.99999999999999")
  inspect(flags.inexact, content="true")
  inspect(flags.has_error(), content="false")
}
```

`inexact` tells you that $100/3 \cdot 3$ was not computed exactly; it is not
an error, so `has_error()` stays false. `has_error()` reports invalid
operations, unparsable text, division by zero, impossible divisions and
invalid contexts.
Check the individual flags (`overflow`, `underflow`, `inexact`) when your
application cares about them.

### Round money with `quantize`

`quantize` gives a value the exponent of a template value. Choose the rounding
mode in the context; commercial rounding is `HalfUp`, which the shared
`RoundingMode` enum does not have, so pass `decimal_rounding`:

```moonbit
///|
test "decimal round to cents" {
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let cents = d("0.01")
  let bankers = @decimal.DecimalContext::decimal64()
  let commercial = @decimal.DecimalContext::new(
    precision=16,
    e_min=-383,
    e_max=384,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
  ).unwrap()
  inspect(d("2.345").quantize(cents, bankers).0, content="2.34")
  inspect(d("2.345").quantize(cents, commercial).0, content="2.35")
  inspect(d("7").quantize(cents, bankers).0, content="7.00")
}
```

Half-even ("banker's") rounding sends the tie `2.345` to the even last digit
`4`; half-up sends it away from zero. `quantize` never silently picks another
exponent: if the result would need more digits than the precision, you get NaN
with `invalid_operation`.

### Bound a result from both sides

Directed rounding gives guaranteed bounds. Rounding the same quotient toward
$-\infty$ and toward $+\infty$ brackets the exact value:

```moonbit
///|
test "decimal directed rounding brackets the exact quotient" {
  let ctx = @decimal.DecimalContext::decimal32()
  let one = @decimal.Decimal::one()
  let seven = @decimal.Decimal::from_int(7)
  let down = ctx.with_rounding(@def.RoundingMode::TowardNegative)
  let up = ctx.with_rounding(@def.RoundingMode::TowardPositive)
  inspect(one.div_ctx(seven, down).0, content="0.1428571")
  inspect(one.div_ctx(seven, up).0, content="0.1428572")
}
```

The two results are adjacent decimal32 values, and $1/7$ lies strictly
between them.

### Exchange decimal64 bits

Interchange formats are what databases, files and other languages exchange.
Encode in the encoding your peer expects, and decode with the same one:

```moonbit
///|
test "decimal64 DPD and BID round trip" {
  let fmt = @decimal.DecimalInterchangeFormat::Decimal64
  let price = @decimal.Decimal::from_string("19.99").unwrap()
  let (bits, flags) = @decimal.DecimalInterchange::from_decimal_with_encoding(
    price,
    fmt,
    @decimal.DecimalInterchangeEncoding::BID,
  )
  inspect(bits.to_hex(), content="#31800000000007CF")
  inspect(flags.has_error(), content="false")
  inspect(bits.to_decimal(), content="19.99")
  let (dpd, _) = price.to_interchange_hex(fmt)
  inspect(dpd, content="#22300000000004FF")
}
```

Both encodings keep the exponent, so `19.99` comes back with two decimal
places. Bits you did not produce yourself may be non-canonical; keep them in a
`DecimalInterchange` and call `canonical()` before comparing bit patterns.

### Call an elementary function

Logarithms, exponentials, powers and trigonometric functions are certified:
the result is the correctly rounded value in every rounding mode, or an
explicit failure. They need a context with a bounded exponent range, such as a
format preset:

```moonbit
///|
test "decimal certified logarithm" {
  let ctx = @decimal.DecimalContext::decimal64()
  let two = @decimal.Decimal::from_int(2)
  match two.try_ln_ctx(ctx) {
    Ok((value, flags)) => {
      inspect(value, content="0.6931471805599453")
      inspect(flags.inexact, content="true")
    }
    Err(e) => fail("not certified: \{e.is_certification_failure()}")
  }
  inspect(@decimal.Decimal::from_int(1000).log10_ctx(ctx).0, content="3")
}
```

`try_ln_ctx` returns `Err` only if the result could not be certified within
the refinement budget; `ln_ctx` turns that case into NaN with
`invalid_operation`. Exact results such as $\log_{10} 1000 = 3$ come back
without `inexact`.

## Going further

### Generic code over the algebra traits

`Decimal` implements `Ring` from [luna-generic](https://lunaflow.cn/en/luna-generic/)
through its plain operators, so generic code runs on it unchanged:

```moonbit
///|
fn[T : @lf_alg.Ring] dot(xs : Array[T], ys : Array[T]) -> T {
  let mut acc : T = @lf_alg.Zero::zero()
  for i in 0..<xs.length() {
    acc = acc + xs[i] * ys[i]
  }
  acc
}

///|
test "decimal in generic ring code" {
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(dot([d("1.5"), d("2.25")], [d("4"), d("0.2")]), content="6.45")
}
```

The plain operators have no context: `*` is exact, `+` rounds to the larger
operand precision (34 digits by default) and returns the shortest cohort
member. Code that needs a precision, an exponent range or flags should take a
`DecimalContext` and call the `*_ctx` operations.

### The shared contextual traits

Code written against [`Luna-Flow/arithmetic`](https://lunaflow.cn/en/arithmetic/)
uses `ArithmeticContext` and gets an `ArithmeticOutcome` with diagnostics:

```moonbit
///|
test "decimal through the contextual traits" {
  let ctx = @lf_arith.ArithmeticContext::new(5)
  let x = @decimal.Decimal::from_int(2)
  match x.div_contextual(@decimal.Decimal::from_int(3), ctx) {
    Ok(outcome) => {
      inspect(outcome.value, content="0.66667")
      inspect(outcome.diagnostics.inexact, content="true")
    }
    Err(_) => fail("unexpected error")
  }
  inspect(x.div_contextual(@decimal.Decimal::zero(), ctx) is Err(_), content="true")
}
```

Errors (`invalid_operation`, `division_by_zero`, …) become `Err`; inexactness
and range events become diagnostics.

### Pipelines, GDA status and intervals

- [`decimal_checked`](decimal_checked.md) wraps a value, its context and its
  accumulated flags, so a long pipeline does not need explicit `combine`
  calls.
- [`decimal_gda`](decimal_gda.md) implements the General Decimal Arithmetic
  model with sticky status and traps. Its values are a separate type; use it
  when you need `.decTest` behaviour, not IEEE per-operation flags.
- To enclose a decimal value in a binary interval, convert it twice with
  `to_bin_float(mode=TowardNegative)` and `to_bin_float(mode=TowardPositive)`
  and build a [`ball_float`](ball_float.md) ball from both bounds.

### A deterministic order for storage

`compare_total` orders every representation, including cohorts, signed zeros
and NaNs, so it is the right key for sorting stored values or deduplicating
bit-exact records:

```moonbit
///|
test "decimal total order separates cohorts" {
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let xs = [d("1.0"), d("-0"), d("1.00"), d("NaN"), d("0")]
  xs.sort_by(fn(a, b) { a.compare_total(b) })
  inspect(xs.map(fn(x) { x.to_string() }).join(" "), content="-0 0 1.00 1.0 nan")
}
```

## Common pitfalls

- **Elementary functions need a bounded context.** `DecimalContext::new()`
  has the exponent range $\pm 999\,999\,999$, which is outside what the
  elementary functions accept; they return NaN with `invalid_context`. Use
  `decimal32()`/`decimal64()`/`decimal128()` or pass `e_min`/`e_max` within
  $\pm 999\,999$.
- **Operators are not context operations.** `*` never rounds, so repeated
  products grow without bound; `/` rounds half-even to the operand precision
  and applies no exponent range. Use `mul_ctx` and `div_ctx` when the result
  must be bounded, rounded in another mode, or reported through flags.
- **`==` is not IEEE equality.** `Eq` and `compare` treat every NaN as equal
  to every NaN and greater than every number, so sorting works. Use
  `compare_checked` or `is_nan` when a NaN must be unordered.
- **`has_error()` is narrow.** It ignores `inexact`, `overflow` and
  `underflow`. Check those flags yourself when they matter, for example
  `overflow` after a long product.
- **The checked powers convert the exponent at context precision.**
  `pow_int_checked` and `pow_nat_checked` turn the integer exponent into a
  `Decimal` with the context precision, so an exponent with more digits than
  the precision is rounded before the power is taken. Keep $|n| < 10^{p}$ or
  call `pown_ctx`, which converts the exponent exactly.
- **`with_rounding` cannot choose `HalfUp`, `HalfDown` or `ZeroFiveUp`.**
  Build the context with `DecimalContext::new(decimal_rounding=...)`.
- **Binary conversions lose decimal meaning.** `from_double(0.1)` is the exact
  binary value `0.1000000000000000055511151231257827` (rounded to 34 digits),
  not `0.1`; parse text instead.

## Next steps

- [decimal API](../api/decimal.md): every type and function with its exact
  semantics.
- [decimal design](../design/decimal.md): formats, cohorts, encodings,
  rounding, error bounds and certification.
- [decimal conformance](../conformance/decimal.md) and
  [decimal performance](../performance/decimal.md): the finite evidence and
  the measurement method.
- [`decimal_checked` tutorial](decimal_checked.md) and
  [`decimal_gda` tutorial](decimal_gda.md) for pipelines and GDA status.
