# `ball_float_checked` Tutorial

`BallFloatResult` keeps `Result[BallFloat, ArithmeticError]` inside a fluent
pipeline. Use it when invalid bounds, non-finite exact construction, or a
checked elementary proof failure should stop later interval operations.

## Validate Construction Once

```moonbit check
///|
test "checked interval construction" {
  let x = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  )
  let y = @ball_float_checked.BallFloatResult::from_int(3, precision=32)
  let result = (x + y).result().unwrap()
  inspect(result.is_empty(), content="false")
}
```

Later operations short-circuit the first error. Use `map` for an infallible
interval transform and `bind` when a callback may construct another checked
interval. `flat_map` is deprecated.

## Distinguish Wide Success From Failure

Entire is a valid success because it still encloses the mathematical result.
For example, division by an interval crossing zero may produce Entire rather
than `ArithmeticError`. After extracting a successful interval, apply an
application tightness policy with `is_entire()`, `width()`, or boundedness.

Relation observers such as `contains`, `subset`, and `overlaps` remain outside
the wrapper. Extract the checked interval, then apply the observer; a Boolean
relation has no meaningful first-error pipeline state.

## Decorations And Flags Stay Explicit

`BallFloatResult` stores bare intervals only. It does not retain
`BallFloatDecorated` state or `BallFlags`. Use raw `ball_float` APIs when
decoration, NaI, inexact, overflow, or underflow is part of the result contract.

## Recommended Practice

1. Use the wrapper to validate untrusted construction and retain first failure.
2. Treat Entire as successful enclosure, then evaluate tightness separately.
3. Extract once before set relations or decorated operations.
4. Use raw `try_*_interval` when structured certification detail must be handled
   directly.

See [Design](./design.md) and the raw
[`ball_float` tutorial](../ball_float/tutorial.md).
