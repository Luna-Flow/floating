# `ball_float_result` Tutorial

## Compose Enclosures

```moonbit check
///|
test "checked interval construction" {
  let x = @ball_float_result.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  )
  let y = @ball_float_result.BallFloatResult::from_int(3, precision=32)
  inspect((x + y).result().is_ok(), content="true")
}
```

Keep relation observers such as `contains` and `overlaps` outside the wrapper:
extract the checked result, then apply the observer to the resulting interval.
