# def tutorial

The goal of this tutorial is to write code that works with every number type
of `floating` at once: you inspect values through the `Floating` trait, test
their class with the generic predicates, read IEEE comparison results as
`PartialOrder`, and reuse the arithmetic context and error types that `def`
re-exports. `def` itself does no arithmetic; the concrete packages
([`bin_float`](bin_float.md), [`decimal`](decimal.md),
[`decimal_gda`](decimal_gda.md), [`ball_float`](ball_float.md)) do. The laws
behind the trait are in the [design page](../design/def.md).

| I want to | Use |
| --- | --- |
| ask any value for its class, sign or precision | [`Floating`](#write-one-function-for-every-representation) |
| test for NaN, infinity or zero generically | [`is_nan`, `is_infinite`, `is_finite`, `is_zero`](#quick-start) |
| round a value to fewer digits of its own radix | [`Floating::with_precision`](#change-precision-generically) |
| read the result of an IEEE comparison | [`PartialOrder`](#read-an-ieee-comparison) |
| compare decimal cohorts by their printed form | [`Floating::normalized`](#normalize-before-comparing-representations) |
| handle checked errors without importing `arithmetic` | [`ArithmeticError`](#use-the-re-exported-arithmetic-types) |
| make my own type usable by generic code | [`impl @def.Floating`](#implement-floating-for-your-own-type) |

## Quick start

Add the module and import `def` next to the representation you use:

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/def",
  "Luna-Flow/floating/bin_float",
}
```

The smallest useful program asks a value what it is:

```moonbit
///|
test "quick start: observe a value" {
  let x = @bin_float.BinFloat::from_double(-2.5)
  inspect(@def.is_finite(x), content="true")
  inspect(@def.Floating::sign(x) == @def.Sign::Negative, content="true")
  inspect(@def.Floating::precision(x), content="53")
}
```

## Everyday tasks

### Write one function for every representation

A function bounded by `F : @def.Floating` accepts binary, IEEE decimal, GDA
decimal and interval values. Call the trait methods in their qualified form,
`@def.Floating::classify(x)`, because MoonBit no longer turns trait methods
into dot methods of a type parameter.

```moonbit
///|
fn[F : @def.Floating] summary(x : F) -> String {
  if @def.is_nan(x) {
    return "nan"
  }
  let sign = match @def.Floating::sign(x) {
    Negative => "negative"
    Zero => "zero"
    Positive => "positive"
  }
  let kind = if @def.is_infinite(x) { "infinite" } else { "finite" }
  "\{kind} \{sign} at precision \{@def.Floating::precision(x)}"
}

///|
test "one summary for four representations" {
  inspect(
    summary(@bin_float.BinFloat::from_int(7)),
    content="finite positive at precision 53",
  )
  inspect(
    summary(@decimal.Decimal::from_string("-0.00").unwrap()),
    content="finite zero at precision 34",
  )
  inspect(
    summary(@decimal_gda.Decimal::from_string("-Infinity").unwrap()),
    content="infinite negative at precision 34",
  )
  inspect(summary(@ball_float.BallFloat::empty()), content="nan")
}
```

The interval case shows why the NaN test comes first: the empty interval
classifies as `NaN`, and `BallFloat::sign` aborts on it.

### Change precision generically

`with_precision` rounds to the requested number of significant digits of the
value's own radix, bits for binary and digits for decimal:

```moonbit
///|
fn[F : @def.Floating] three_digits(x : F) -> F {
  @def.Floating::with_precision(x, 3, @lf_arith.RoundingMode::ToNearestEven)
}

///|
test "round to three significant digits of the radix" {
  let d = three_digits(@decimal.Decimal::from_string("3.14159").unwrap())
  inspect(d.to_string(), content="3.14")
  let b = three_digits(@bin_float.BinFloat::from_int(11))
  inspect(b.to_string(), content="3p2")
}
```

Eleven is `1011` in binary; three significant bits round it to `1100`, which
`to_string` prints as $3 \cdot 2^2$.

### Read an IEEE comparison

Comparisons that follow IEEE 754 return a `PartialOrder`, whose fourth value
`Unordered` reports a NaN operand:

```moonbit
///|
fn relation(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> String {
  match a.compare_quiet(b).0 {
    Less => "less"
    Equal => "equal"
    Greater => "greater"
    Unordered => "unordered"
  }
}

///|
test "four-way comparison" {
  let one = @bin_float.BinFloat::from_int(1)
  let two = @bin_float.BinFloat::from_int(2)
  inspect(relation(one, two), content="less")
  inspect(relation(@bin_float.BinFloat::nan(), @bin_float.BinFloat::nan()), content="unordered")
  inspect(
    relation(@bin_float.BinFloat::from_double(-0.0), @bin_float.BinFloat::zero()),
    content="equal",
  )
}
```

### Normalize before comparing representations

Decimal values with the same value can differ in their stored exponent
(`1.5` and `1.500` belong to one *cohort*). `normalized` picks the canonical
member, so the printed forms agree:

```moonbit
///|
test "normalize a decimal cohort" {
  let a = @decimal.Decimal::from_string("1.500").unwrap()
  let b = @decimal.Decimal::from_string("1.5").unwrap()
  inspect(a.to_string(), content="1.500")
  inspect(
    @def.Floating::normalized(a).to_string() ==
    @def.Floating::normalized(b).to_string(),
    content="true",
  )
}
```

## Going further

### Use the re-exported arithmetic types

`@def.ArithmeticContext`, `@def.ArithmeticError`, `@def.RoundingMode` and the
other aliases are the types of [Luna-Flow/arithmetic](https://lunaflow.cn/en/arithmetic/).
Code that only needs the vocabulary can import `def` instead of `arithmetic`:

```moonbit
///|
fn describe_error(e : @def.ArithmeticError) -> String {
  if e.is_division_by_zero() {
    "division by zero: " + e.message
  } else if e.is_domain_error() {
    "domain error: " + e.message
  } else {
    "other: " + e.message
  }
}

///|
test "handle a checked result through def" {
  let result = @bin_float.BinFloat::from_int(1).div_checked(
    @bin_float.BinFloat::zero(),
  )
  match result {
    Ok(_) => fail("expected an error")
    Err(e) => inspect(describe_error(e), content="division by zero: division by zero")
  }
}
```

### Implement `Floating` for your own type

The trait is open. A wrapper type can delegate to an existing implementation;
it must then keep the laws listed in the design page (for example, `normalized`
must not change the value):

```moonbit
///|
struct Measured {
  value : @bin_float.BinFloat
  unit : String
}

///|
impl @def.Floating for Measured with classify(self) {
  @def.Floating::classify(self.value)
}

///|
impl @def.Floating for Measured with sign(self) {
  @def.Floating::sign(self.value)
}

///|
impl @def.Floating for Measured with precision(self) {
  @def.Floating::precision(self.value)
}

///|
impl @def.Floating for Measured with with_precision(self, precision, mode) {
  { ..self, value: @def.Floating::with_precision(self.value, precision, mode) }
}

///|
impl @def.Floating for Measured with normalized(self) {
  { ..self, value: @def.Floating::normalized(self.value) }
}

///|
test "a user type joins the generic code" {
  let m = { value: @bin_float.BinFloat::from_int(-4), unit: "m" }
  inspect(summary(m), content="finite negative at precision 53")
  inspect(@def.is_zero(m), content="false")
  let coarse = @def.Floating::with_precision(m, 1, @lf_arith.RoundingMode::TowardZero)
  inspect(coarse.unit, content="m")
}
```

## Common pitfalls

- `Sign::Zero` does not mean "the value is zero". It is also returned for NaN
  by the scalar types and for any interval that contains zero. Test
  `@def.is_nan` first, and for intervals use `BallFloat::contains_zero` or the
  bounds.
- `@def.is_zero` on a `BallFloat` is true for $[-1, 1]$: the predicate is
  defined through `sign`, which for an interval means "contains zero".
- `Sign` cannot tell $-0$ from $+0$. Use the concrete package
  (`BinFloat::is_negative_zero`, `Decimal::is_signed`) when the sign bit
  matters.
- `PartialOrder` is not an ordering you can sort with: `Unordered` breaks
  trichotomy. Use the total orders of the concrete packages
  (`BinFloat::total_order_compare`, `Decimal::compare_total`) for sorting.
- `with_precision` reports no flags and ignores context exponent limits (a
  `BinFloat` still overflows at its implementation range of about
  $2^{\pm 2^{30}}$). When rounding must be observed, use the `*_ctx` operations
  of the concrete package.
- On a `BallFloat`, `normalized` and `with_precision` return an enclosure that
  can be wider than the input, even at the same precision. Apart from
  endpoints more than about $2^{16}$ binary orders of magnitude apart at a
  precision above about 65536 bits ([#44](https://github.com/Luna-Flow/floating/issues/44), with a fix proposed in [#68](https://github.com/Luna-Flow/floating/pull/68)) they never
  lose a member, but do not expect the bounds to stay the same (tracked in
  [#69](https://github.com/Luna-Flow/floating/issues/69); a fix is proposed in [#91](https://github.com/Luna-Flow/floating/pull/91)).
- `with_precision(x, 0, mode)` is not an error: the precision is clamped to 1.

## Next steps

- [`def` design](../design/def.md): the trait laws and the order theory of
  `PartialOrder`.
- [`def` API](../api/def.md): every item with its signature.
- [`semantic` tutorial](semantic.md): compare values of different
  representations exactly.
- [Numeric semantics guide](../numeric_semantics.md) for the shared vocabulary
  of the repository.
