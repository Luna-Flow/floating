# `ball_float` Tutorial

Use `ball_float` when a result must enclose every mathematically possible real
value, not merely provide a rounded point estimate. The package exposes bare
intervals, IEEE 1788 decorations, outward-rounded contexts, and certified
elementary functions.

## Choose The Right Entry Point

| Need | Recommended API |
| --- | --- |
| exact dyadic point | `BallFloat::exact` |
| measured/uncertain range | `from_bounds` or `new(center, radius)` |
| invalid constructor as data | `try_from_bounds` / `try_exact` |
| contextual endpoint limits and flags | `*_ctx` + `BallContext` |
| observable proof failure | `try_*_interval` |
| standard decoration/NaI propagation | `BallFloatDecorated` |
| first-error composition | `ball_float_checked` |

## Embed An Exact Dyadic Point

`exact` means exact with respect to the supplied `BinFloat` value.

```moonbit check
///|
test "exact dyadic interval" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  let interval = @ball_float.BallFloat::exact(x)
  inspect(interval.is_singleton(), content="true")
  inspect(interval.contains(x), content="true")
}
```

If a smaller interval precision is requested, construction rounds the lower
endpoint downward and upper endpoint upward. It never silently drops the source
dyadic point.

## Build A Valid Range

Use `from_bounds` when endpoints are already known. Use `try_from_bounds` when
input order or finiteness is not trusted.

```moonbit check
///|
test "bounded interval" {
  let interval = @ball_float.BallFloat::try_from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  ).unwrap()
  inspect(interval.contains_zero(), content="false")
  inspect(interval.width().to_string(), content="1p0")
}
```

`new(center, radius)` is useful for measurements, but remember that storage and
all set operations use lower/upper endpoints.

## Enclose A Decimal Real Value Correctly

A nearest-rounded decimal-to-binary conversion followed by `exact` encloses
only the resulting binary point. To enclose the original decimal, convert in
both directions and use both bounds.

```moonbit check
///|
test "outward decimal embedding" {
  let decimal = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let lower = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardNegative,
  )
  let upper = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardPositive,
  )
  let interval = @ball_float.BallFloat::from_bounds(lower, upper, precision=32)
  inspect(interval.is_empty(), content="false")
  inspect(interval.lower_bound().compare(interval.upper_bound()) <= 0, content="true")
}
```

Use this pattern at decimal/binary boundaries, then keep calculations in the
interval domain.

## Read Set Relations

```moonbit check
///|
test "interval relations" {
  let a = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(9, precision=32),
    @bin_float.BinFloat::from_int(11, precision=32),
  )
  let b = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(14, precision=32),
    @bin_float.BinFloat::from_int(16, precision=32),
  )
  inspect(a.disjoint(b), content="true")
  inspect(a.definitely_lt(b), content="true")
  inspect(a.overlaps(b), content="false")
}
```

Use `contains` for point inclusion, `subset`/`interior` for set containment,
`overlap_state` for geometry, and `definitely_lt`/`definitely_gt` only when an
order statement must hold for every point. Do not sort intervals with a scalar
comparison rule.

## Perform Outward-Rounded Arithmetic

Ordinary interval arithmetic preserves enclosure:

```moonbit nocheck
let sum = a + b
let product = a * b
let quotient = a / b
```

Division by an interval that crosses zero returns Entire because every real
value may be approached. A denominator with a one-sided zero endpoint may yield
a half-infinite enclosure. These are valid set results, not generic failures.

Use `BallContext` when endpoint precision/exponent limits and flags matter:

```moonbit nocheck
let context = @ball_float.BallContext::binary64()
let (result, flags) = a.mul_ctx(b, context)
// Inspect flags.inexact(), flags.overflow(), and flags.underflow().
```

## Choose Total Or Checked Elementary Operations

Total operations always return a valid enclosure. If certification cannot
establish a tight trigonometric range, `sin_interval`/`cos_interval` may return
`[-1, 1]`, and `tan_interval` may return Entire.

```moonbit check
///|
test "certified interval sine" {
  let input = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=64),
    @bin_float.BinFloat::one(precision=64),
  )
  match input.try_sin_interval() {
    Ok(result) => {
      inspect(result.is_empty(), content="false")
      inspect(result.is_bounded(), content="true")
    }
    Err(_) => abort("sine enclosure could not be certified"),
  }
}
```

Choose the family according to application policy:

- use `try_*_interval` when resource/range proof failure must stop or be logged;
- use total `*_interval` when continued calculation with a conservative
  enclosure is preferred;
- test `is_entire()` or width when tightness is an acceptance criterion.

## Use Decorations When Domain Quality Matters

```moonbit check
///|
test "decorated interval" {
  let bare = @ball_float.BallFloat::from_int(4, precision=32)
  let decorated = @ball_float.BallFloatDecorated::new(
    bare,
    decoration=@ball_float.Decoration::Com,
  )
  let root = decorated.sqrt_interval()
  inspect(root.is_nai(), content="false")
}
```

Decorations can weaken after domain clipping or discontinuity. NaI is distinct
from Empty: NaI records an invalid decorated operation, while Empty is a valid
set with no members.

## Recommended Practice

1. Construct intervals from outward-rounded bounds at every representation
   boundary.
2. Keep all intermediate calculations in `BallFloat`; extracting a midpoint
   loses enclosure information.
3. Use set relations rather than scalar equality/order.
4. Decide explicitly whether proof failure should produce an error (`try_*`) or
   a conservative range (total API).
5. Check width/Entire separately from correctness: an enclosure can be correct
   but too wide for the application.
6. Use decorated intervals only when decoration/NaI semantics are actually part
   of the contract; otherwise bare intervals are simpler.

## Next Reading

- [Design](./design.md) explains endpoint selection, critical points, poles,
  certification, and fallback boundaries.
- [Conformance](./conformance.md) defines the pinned ITF1788 evidence.
- [`ball_float_checked` tutorial](../ball_float_checked/tutorial.md) shows
  first-error construction and composition.
