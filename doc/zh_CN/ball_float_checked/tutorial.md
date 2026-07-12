# `ball_float_checked` 教程

## 组合包络

```moonbit check
///|
test "checked interval construction" {
  let x = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  )
  let y = @ball_float_checked.BallFloatResult::from_int(3, precision=32)
  inspect((x + y).result().is_ok(), content="true")
}
```

`contains`、`overlaps` 等关系 observer 不在包装层：先处理 checked 结果，再对区间值执行观察。
