# semantic tutorial

The goal of this tutorial is to compare values across representations without
rounding: you project a binary float, an IEEE decimal or an interval onto exact
rationals, test equality, order rationals with integer arithmetic, check
whether an interval contains a decimal, and turn checked results into a common
error vocabulary. The projection is useful in cross-representation tests,
diagnostics and protocol boundaries; arithmetic stays in the concrete packages.
The mathematics is in the [design page](../design/semantic.md); every item is
listed in the [API reference](../api/semantic.md).

| I want to | Use |
| --- | --- |
| test whether a binary and a decimal value are the same number | [`SemanticScalar::from_bin_float`, `from_decimal`](#quick-start) |
| see the exact rational behind a float | [`ExactRational::numerator`, `denominator`](#see-the-exact-value-of-a-float) |
| ignore cohorts, precision and signed zeros | [the projection](#ignore-cohorts-precision-and-signed-zeros) |
| order two values exactly | [cross-multiplication](#order-two-values-exactly) |
| check that an interval encloses a decimal | [`SemanticInterval::from_ball_float`](#check-that-an-interval-encloses-a-decimal) |
| compare errors of different packages | [`semantic_scalar_result`](#compare-checked-results-across-packages) |
| cross-check two implementations | [`SemanticResult`](#cross-check-two-implementations) |

## Quick start

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/semantic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/decimal",
}
```

Three represented as a 32-bit binary float and as a decimal is the same number:

```moonbit
///|
test "quick start: same value, different representations" {
  let binary = @bin_float.BinFloat::from_int(3, precision=32)
  let decimal = @decimal.Decimal::from_int(3, precision=32)
  inspect(
    @semantic.SemanticScalar::from_bin_float(binary) ==
    @semantic.SemanticScalar::from_decimal(decimal),
    content="true",
  )
}
```

## Everyday tasks

### See the exact value of a float

The examples below print a projected scalar with this helper:

```moonbit
///|
fn exact(s : @semantic.SemanticScalar) -> String {
  match s {
    Rational(q) => q.numerator().to_string() + "/" + q.denominator().to_string()
    Infinity(@def.Sign::Negative) => "-inf"
    Infinity(_) => "+inf"
    NaN => "nan"
  }
}

///|
test "the double nearest to one tenth" {
  let tenth = @bin_float.BinFloat::from_double(0.1)
  inspect(
    exact(@semantic.SemanticScalar::from_bin_float(tenth)),
    content="3602879701896397/36028797018963968",
  )
  let decimal = @decimal.Decimal::from_string("0.1").unwrap()
  inspect(exact(@semantic.SemanticScalar::from_decimal(decimal)), content="1/10")
}
```

The denominator of the binary value is $2^{55}$; the decimal value is exactly
$1/10$. The projections differ, so binary64 `0.1` is not one tenth.

### Ignore cohorts, precision and signed zeros

Decimal `1.5`, `1.50` and `1.500` are different representations of one value
(a cohort); a binary value carries a precision; zero has two signs. The
projection forgets all of this:

```moonbit
///|
test "the projection keeps only the value" {
  let a = @decimal.Decimal::from_string("1.500").unwrap()
  let b = @bin_float.BinFloat::from_double(1.5)
  inspect(
    @semantic.SemanticScalar::from_decimal(a) ==
    @semantic.SemanticScalar::from_bin_float(b),
    content="true",
  )
  let negative_zero = @bin_float.BinFloat::from_double(-0.0)
  let zero = @decimal.Decimal::zero()
  inspect(
    @semantic.SemanticScalar::from_bin_float(negative_zero) ==
    @semantic.SemanticScalar::from_decimal(zero),
    content="true",
  )
}
```

### Order two values exactly

The package provides equality only. Because a projected rational exposes a
reduced numerator and a positive denominator, you can order two of them with
the cross-multiplication rule $a/b < c/d \iff ad < cb$ (valid because $b, d >
0$):

```moonbit
///|
fn rational_less(a : @semantic.ExactRational, b : @semantic.ExactRational) -> Bool {
  a.numerator() * b.denominator() < b.numerator() * a.denominator()
}

///|
test "binary 0.1 lies above one tenth" {
  let binary = match
    @semantic.SemanticScalar::from_bin_float(@bin_float.BinFloat::from_double(0.1)) {
    Rational(q) => q
    _ => fail("finite")
  }
  let tenth = @semantic.ExactRational::new(1N, 10N)
  inspect(rational_less(tenth, binary), content="true")
}
```

### Check that an interval encloses a decimal

`SemanticInterval::from_ball_float` exposes the exact endpoints of a ball. With
the comparison above you can check an enclosure against a decimal reference
value without any rounding:

```moonbit
///|
fn encloses(x : @semantic.SemanticInterval, q : @semantic.ExactRational) -> Bool {
  let above_lower = match x.lower {
    Rational(l) => !rational_less(q, l)
    Infinity(@def.Sign::Negative) => true
    _ => false
  }
  let below_upper = match x.upper {
    Rational(u) => !rational_less(u, q)
    Infinity(@def.Sign::Positive) => true
    _ => false
  }
  above_lower && below_upper
}

///|
test "a ball for one tenth" {
  let ball = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(0.09375),
    @bin_float.BinFloat::from_double(0.125),
  )
  let projected = @semantic.SemanticInterval::from_ball_float(ball)
  inspect(encloses(projected, @semantic.ExactRational::new(1N, 10N)), content="true")
  inspect(encloses(projected, @semantic.ExactRational::new(1N, 5N)), content="false")
  let empty = @semantic.SemanticInterval::from_ball_float(@ball_float.BallFloat::empty())
  inspect(encloses(empty, @semantic.ExactRational::new(0N, 1N)), content="false")
}
```

The empty interval projects to the reversed pair $(+\infty, -\infty)$, so the
helper rejects every value without a special case.

## Going further

### Compare checked results across packages

`semantic_scalar_result` maps a `Result[T, ArithmeticError]` to a
`SemanticResult`, so an error from one package and the same error from another
compare equal although their messages differ:

```moonbit
///|
test "errors compare by kind" {
  let binary = @semantic.semantic_scalar_result(
    @bin_float.BinFloat::from_int(1).div_checked(@bin_float.BinFloat::zero()),
    @semantic.SemanticScalar::from_bin_float,
  )
  let decimal = @semantic.semantic_scalar_result(
    @decimal.Decimal::from_int(1).div_checked(@decimal.Decimal::zero()),
    @semantic.SemanticScalar::from_decimal,
  )
  inspect(binary == decimal, content="true")
  inspect(
    binary == @semantic.SemanticResult::Error(@semantic.SemanticError::DivisionByZero),
    content="true",
  )
}
```

### Cross-check two implementations

A typical consistency test computes one result in two representations, rounds
both to values that are exactly representable in each, and compares the
projections. Square roots of perfect squares are exact in both radices:

```moonbit
///|
test "binary and decimal agree on exact square roots" {
  for n in [1, 4, 9, 144, 1024] {
    let b = @semantic.semantic_scalar_result(
      @bin_float.BinFloat::from_int(n).sqrt(),
      @semantic.SemanticScalar::from_bin_float,
    )
    let d = @semantic.semantic_scalar_result(
      @decimal.Decimal::from_int(n).sqrt(),
      @semantic.SemanticScalar::from_decimal,
    )
    assert_true(b == d)
  }
}
```

## Common pitfalls

- `NaN == NaN` is `true` for `SemanticScalar`. The projection is a value model,
  not IEEE comparison; use the concrete packages for IEEE predicates.
- The projection drops the sign of zero, NaN payloads and signalling state,
  decimal cohorts, precision and flags. Do not use it to test those. Decorated
  intervals are not accepted at all.
- There is no ordering in the package. Write the cross-multiplication yourself
  as above; never convert to `Double` to compare.
- Projecting a value with a huge exponent (for example decimal `1E+999999`, or
  a `BinFloat` near its exponent limit $2^{30}$) builds a `BigInt` with as many
  digits or bits as the exponent. Keep projections to values of moderate
  exponent.
- Only `@decimal.Decimal` has a projection; convert a `@decimal_gda.Decimal`
  through its string form if you need one.
- `ExactRational::new` aborts on a zero denominator.

## Next steps

- [`semantic` design](../design/semantic.md): the exact projection, the
  canonical form and the interval model.
- [`semantic` API](../api/semantic.md): every item with its signature.
- [`def` tutorial](def.md) for the shared vocabulary (`Sign`, `Floating`).
- [`ball_float` tutorial](ball_float.md) for computing the enclosures you
  project.
