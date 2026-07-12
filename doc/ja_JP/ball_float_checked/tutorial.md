# `ball_float_checked` チュートリアル

## 包絡を合成する

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

`contains` や `overlaps` などの関係 observer は wrapper 外にあります。checked 結果を処理してから区間値を観測します。
