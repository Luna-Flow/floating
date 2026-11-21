# interval_checked tutorial

This tutorial shows how to run an interval computation in which invalid input
and uncertifiable steps are reported as errors while every valid result stays a
guaranteed enclosure: you build intervals with validating constructors, chain
interval arithmetic and elementary functions in an `IntervalResult`, add your
own checks with `bind`, and read the outcome once. The arithmetic comes from
[`interval`](interval.md); the [design page](../design/interval_checked.md)
explains which outcomes are errors; the [API reference](../api/interval_checked.md)
lists every method.

| I want to | Use |
| --- | --- |
| build an enclosure from untrusted bounds or a `Double` | `from_bounds`, `from_double`, `exact` ([Validate measurements](#validate-measurements-at-the-boundary)) |
| push uncertain inputs through a formula | `+ - * /` on `IntervalResult` ([Propagate uncertainty](#propagate-uncertainty-through-a-formula)) |
| treat an empty or unbounded result as a success or as a failure | `is_ok`, `bind` ([No information is not an error](#know-that-no-information-is-not-an-error), [Application rules](#turn-an-application-rule-into-an-error)) |
| find out why an elementary function failed | `error()`, `certification_failure_detail()` ([Certification failures](#certification-failures)) |
| square an interval that contains 0 tightly | `pown`, not `x * x` ([Powers](#powers-through-the-arithmetic-traits)) |
| decide a comparison at the end of a pipeline | `result()` and the enclosure traits ([Generic code](#generic-code-with-the-enclosure-relations)) |

## Quick start

Add the module:

```bash
moon add Luna-Flow/floating@0.11.0
```

Import the wrapper and the endpoint package (the later examples also use
`Luna-Flow/floating/interval` and `Luna-Flow/arithmetic` as `@lf_arith`):

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/interval",
  "Luna-Flow/floating/interval_checked",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

Enclose $\ln 2$ at 53 bits:

```moonbit
///|
test "quick start: an enclosure of ln 2" {
  let r = @interval_checked.IntervalResult::from_int(2, precision=53).ln()
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
prints as `centre +/- radius` in exact binary notation (`to_midpoint_radius_string`; `to_string` is the
portable literal `[l, u]`):

```moonbit
///|
fn show(r : @interval_checked.IntervalResult) -> String {
  match r.result() {
    Ok(v) => v.to_midpoint_radius_string()
    Err(e) => "error: " + e.message
  }
}
```

### Validate measurements at the boundary

Input data enters through `from_bounds`, `from_double` or `exact`. Reversed
bounds and non-finite sources become errors before any computation runs:

```moonbit
///|
fn reading(lo : Double, hi : Double) -> @interval_checked.IntervalResult {
  @interval_checked.IntervalResult::from_bounds(
    @bin_float.BinFloat::from_double(lo),
    @bin_float.BinFloat::from_double(hi),
  )
}

///|
test "validated readings" {
  inspect(show(reading(1.0, 3.0)), content="1p1 +/- 1p0")
  inspect(show(reading(3.0, 1.0)), content="error: interval lower bound must not exceed upper bound")
  inspect(
    show(reading(0.0 / 0.0, 1.0)),
    content="error: interval bounds must not be NaN",
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
  let negative = @interval_checked.IntervalResult::from_int(-2)
  inspect(show(negative.ln()), content="[empty]")
  inspect(negative.ln().is_ok(), content="true")
  let one = @interval_checked.IntervalResult::from_int(1)
  inspect(show(one / reading(-1.0, 1.0)), content="[-inf, inf]")
}
```

When an empty or unbounded result means failure in *your* application, say so
with `bind`.

### Turn an application rule into an error

```moonbit
///|
fn require_nonempty(
  x : @interval.Interval,
) -> @interval_checked.IntervalResult {
  if x.is_empty() {
    @interval_checked.IntervalResult::err(
      @lf_arith.ArithmeticError::domain_error("no admissible value"),
    )
  } else {
    @interval_checked.IntervalResult::ok(x)
  }
}

///|
test "reject empty enclosures" {
  let r = @interval_checked.IntervalResult::from_int(-2).ln().bind(require_nonempty)
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
  let huge = @interval_checked.IntervalResult::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 8000000, 53),
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

`pown` goes through the `PowIntChecked` trait of Luna-Flow/arithmetic. It
computes the power of one point of the interval (`Interval::pown`); for an
interval containing zero this is tighter than repeated multiplication, which
treats the two factors as independent:

```moonbit
///|
test "a power is tighter than a product" {
  let x = reading(-1.0, 1.0)
  match (x.pown(2).result(), (x * x).result()) {
    (Ok(square), Ok(product)) => {
      inspect(square.lower_bound().to_string(), content="-0")
      inspect(product.lower_bound().to_string(), content="-1p0")
    }
    _ => fail("unexpected error")
  }
}
```

### Generic code with the enclosure relations

`Interval` implements the enclosure relations of Luna-Flow/arithmetic
(`Contains`, `DefinitelyLt`, …). Extract the interval at the end of a pipeline
and test it:

```moonbit
///|
test "decide with an enclosure" {
  match reading(1.0, 3.0).rootn(2).result() {
    Ok(root) => {
      let two = @interval.Interval::from_int(2, precision=53)
      inspect(@lf_arith.DefinitelyLt::definitely_lt(root, two), content="true")
    }
    Err(e) => fail(e.message)
  }
}
```

## Common pitfalls

- **Default precision.** `from_int` and `from_coefficient` default to 53 bits.
  A coefficient that needs more bits is still enclosed, but by a two-point
  interval rather than a point; pass a larger precision for such values.
- **A product is not a power.** Use `pown` for even powers of an interval
  that contains 0; `x * x` treats the two factors as independent.
- **Empty and whole are successes.** Test `is_empty` / `is_entire` on the
  final interval, or add a `bind` check.
- **No decorations or flags.** The wrapper keeps neither IEEE 1788
  decorations nor `IntervalFlags`; use the decorated and contextual APIs of
  `interval` when you need them.
- **Only the first error survives**, as in every checked wrapper.
- **`[+inf, +inf]` is rejected.** IEEE 1788 intervals are subsets of the real
  line; use `entire()` or a half-infinite interval instead.

## Next steps

- [`interval_checked` design](../design/interval_checked.md): errors
  versus enclosures, and the composition laws.
- [`interval_checked` API](../api/interval_checked.md): every method.
- [`interval` tutorial](interval.md): decorations, contexts and the
  interval operations themselves.
- [`semantic` tutorial](semantic.md): check an enclosure against an exact
  reference value.
