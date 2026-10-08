# ball_float_checked tutorial

This tutorial shows how to run an interval computation in which invalid input
and uncertifiable steps are reported as errors while every valid result stays a
guaranteed enclosure: you build intervals with validating constructors, chain
interval arithmetic and elementary functions in a `BallFloatResult`, add your
own checks with `bind`, and read the outcome once. The arithmetic comes from
[`ball_float`](ball_float.md); the [design page](../design/ball_float_checked.md)
explains which outcomes are errors; the [API reference](../api/ball_float_checked.md)
lists every method.

| I want to | Use |
| --- | --- |
| build an enclosure from untrusted bounds or a `Double` | `from_bounds`, `from_double`, `exact` ([Validate measurements](#validate-measurements-at-the-boundary)) |
| push uncertain inputs through a formula | `+ - * /` on `BallFloatResult` ([Propagate uncertainty](#propagate-uncertainty-through-a-formula)) |
| treat an empty or unbounded result as a success or as a failure | `is_ok`, `bind` ([No information is not an error](#know-that-no-information-is-not-an-error), [Application rules](#turn-an-application-rule-into-an-error)) |
| find out why an elementary function failed | `error()`, `certification_failure_detail()` ([Certification failures](#certification-failures)) |
| square an interval that contains 0 tightly | `pow_int`, not `pow_nat` or `x * x` ([Powers](#powers-through-the-arithmetic-traits)) |
| decide a comparison at the end of a pipeline | `result()` and the enclosure traits ([Generic code](#generic-code-with-the-enclosure-relations)) |

## Quick start

Add the module:

```bash
moon add Luna-Flow/floating@0.8.0
```

Import the wrapper and the endpoint package (the later examples also use
`Luna-Flow/floating/ball_float` and `Luna-Flow/arithmetic` as `@lf_arith`):

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/ball_float_checked",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

Enclose $\ln 2$ at 53 bits:

```moonbit
///|
test "quick start: an enclosure of ln 2" {
  let r = @ball_float_checked.BallFloatResult::from_int(2, precision=53).ln()
  match r.result() {
    Ok(x) => {
      inspect(x.lower_bound().to_string(), content="6243314768165359p-53")
      inspect(x.upper_bound().to_string(), content="390207173010335p-49")
    }
    Err(e) => fail(e.message)
  }
}
```

The upper bound printed in lowest terms is $6243314768165360 \cdot 2^{-53}$, so the two bounds
are adjacent 53-bit numbers, and $\ln 2$ lies between them.

## Everyday tasks

The remaining examples print results with this helper; a bounded interval
prints as `centre +/- radius` in exact binary notation:

```moonbit
///|
fn show(r : @ball_float_checked.BallFloatResult) -> String {
  match r.result() {
    Ok(v) => v.to_string()
    Err(e) => "error: " + e.message
  }
}
```

### Validate measurements at the boundary

Input data enters through `from_bounds`, `from_double` or `exact`. Reversed
bounds and non-finite sources become errors before any computation runs:

```moonbit
///|
fn reading(lo : Double, hi : Double) -> @ball_float_checked.BallFloatResult {
  @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_double(lo),
    @bin_float.BinFloat::from_double(hi),
  )
}

///|
test "validated readings" {
  inspect(show(reading(1.0, 3.0)), content="1p1 +/- 1p0")
  inspect(show(reading(3.0, 1.0)), content="error: ball lower bound must not exceed upper bound")
  inspect(
    show(reading(0.0 / 0.0, 1.0)),
    content="error: ball bounds must not be NaN",
  )
}
```

### Propagate uncertainty through a formula

Operators work on wrappers. The result encloses every value the formula can
take for inputs in the intervals:

```moonbit
///|
test "area of an uncertain rectangle" {
  let width = reading(1.0, 3.0)
  let height = reading(2.0, 2.5)
  let area = width * height
  match area.result() {
    Ok(x) => {
      inspect(x.lower_bound().to_string(), content="1p1")
      inspect(x.upper_bound().to_string(), content="15p-1")
    }
    Err(e) => fail(e.message)
  }
}
```

The area lies in $[2, 7.5]$, the product of the two ranges.

### Know that "no information" is not an error

Interval operations follow set semantics: points outside a function's domain
are dropped, and an operation that can say nothing returns the whole line.
These are successes, because they are correct enclosures:

```moonbit
///|
test "empty and whole results are successes" {
  let negative = @ball_float_checked.BallFloatResult::from_int(-2)
  inspect(show(negative.ln()), content="[empty]")
  inspect(negative.ln().is_ok(), content="true")
  let one = @ball_float_checked.BallFloatResult::from_int(1)
  inspect(show(one / reading(-1.0, 1.0)), content="[-inf, inf]")
}
```

When an empty or unbounded result means failure in *your* application, say so
with `bind`.

### Turn an application rule into an error

```moonbit
///|
fn require_nonempty(
  x : @ball_float.BallFloat,
) -> @ball_float_checked.BallFloatResult {
  if x.is_empty() {
    @ball_float_checked.BallFloatResult::err(
      @lf_arith.ArithmeticError::domain_error("no admissible value"),
    )
  } else {
    @ball_float_checked.BallFloatResult::ok(x)
  }
}

///|
test "reject empty enclosures" {
  let r = @ball_float_checked.BallFloatResult::from_int(-2).ln().bind(require_nonempty)
  inspect(show(r), content="error: no admissible value")
  let ok = reading(1.0, 3.0).ln().bind(require_nonempty)
  inspect(ok.is_ok(), content="true")
}
```

## Going further

### Certification failures

Elementary functions are evaluated with certified error bounds. When the
library cannot certify an enclosure within its budget it reports a
`CertificationFailure` with a detail record instead of returning a wrong or
needlessly wide interval:

```moonbit
///|
test "certification failure carries a detail record" {
  let huge = @ball_float_checked.BallFloatResult::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 70000, 53),
  )
  match huge.sin().error() {
    Some(e) => {
      inspect(e.is_certification_failure(), content="true")
      inspect(e.certification_failure_detail().unwrap().operation(), content="sin")
    }
    None => fail("expected a failure")
  }
}
```

### Powers through the arithmetic traits

`pow_nat` and `pow_int` go through the `PowNatChecked` and `PowIntChecked`
traits of Luna-Flow/arithmetic. `pow_int` computes the power of one point of
the interval (`BallFloat::pown`); for an interval containing zero this is
tighter than repeated multiplication, which treats the two factors as
independent. `pow_nat` *is* repeated multiplication, so it is as wide as the
product:

```moonbit
///|
test "a power is tighter than a product" {
  let x = reading(-1.0, 1.0)
  match (x.pow_int(2).result(), (x * x).result()) {
    (Ok(square), Ok(product)) => {
      inspect(square.lower_bound().to_string(), content="0")
      inspect(product.lower_bound().to_string(), content="-1p0")
    }
    _ => fail("unexpected error")
  }
  match x.pow_nat(2U).result() {
    Ok(power) => inspect(power.lower_bound().to_string(), content="-1p0")
    _ => fail("unexpected error")
  }
}
```

### Generic code with the enclosure relations

`BallFloat` implements the enclosure relations of Luna-Flow/arithmetic
(`Contains`, `DefinitelyLt`, …). Extract the interval at the end of a pipeline
and test it:

```moonbit
///|
test "decide with an enclosure" {
  match reading(1.0, 3.0).rootn(2).result() {
    Ok(root) => {
      let two = @ball_float.BallFloat::from_int(2)
      inspect(@lf_arith.DefinitelyLt::definitely_lt(root, two), content="true")
    }
    Err(e) => fail(e.message)
  }
}
```

## Common pitfalls

- **Small default precision.** `from_int` and `from_coefficient` default to 16
  bits. An integer that needs more bits is still enclosed, but by a two-point
  interval rather than a point. Pass `precision=53` (or more) for large
  integers.
- **`pow_nat` is not tighter than a product.** Use `pow_int` for even powers
  of an interval that contains 0.
- **Empty and whole are successes.** Test `is_empty` / `is_entire` on the
  final interval, or add a `bind` check.
- **No decorations or flags.** The wrapper keeps neither IEEE 1788
  decorations nor `BallFlags`; use the decorated and contextual APIs of
  `ball_float` when you need them.
- **Only the first error survives**, as in every checked wrapper.
- **`[+inf, +inf]` is rejected.** IEEE 1788 intervals are subsets of the real
  line; use `whole()` or a half-infinite interval instead.
- **`flat_map` is deprecated.** Use `bind`.

## Next steps

- [`ball_float_checked` design](../design/ball_float_checked.md): errors
  versus enclosures, and the composition laws.
- [`ball_float_checked` API](../api/ball_float_checked.md): every method.
- [`ball_float` tutorial](ball_float.md): decorations, contexts and the
  interval operations themselves.
- [`semantic` tutorial](semantic.md): check an enclosure against an exact
  reference value.
