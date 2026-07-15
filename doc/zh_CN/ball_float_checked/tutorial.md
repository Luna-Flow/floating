# `ball_float_checked` 教程

`BallFloatResult` 将 `Result[BallFloat, ArithmeticError]` 保留在 fluent pipeline 中。
非法 bounds、非有限 exact source 或 checked elementary proof failure 会停止后续操作。

## 一次验证构造

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

后续操作短路首个 error。Infallible transform 用 `map`，可能构造 checked interval 的
callback 用 `bind`；`flat_map` 已 deprecated。

## 区分宽 Success 与 Failure

Entire 是能包络结果的合法 success。提取成功 interval 后，用 `is_entire/width/boundedness`
执行应用 tightness policy。contains/subset/overlaps 等 relation 应在提取后调用。

## Decoration 与 Flags 保持显式

Wrapper 只存 bare interval，不保留 `BallFloatDecorated` 或 `BallFlags`。契约包含
decoration、NaI、inexact、overflow、underflow 时使用 raw `ball_float` API。

## 推荐做法

1. 用 wrapper 验证不可信构造并保留首错。
2. Entire 先视为正确 enclosure，再单独检查 tightness。
3. Set relation/decorated operation 前提取一次。
4. 需要结构化 certification detail 时直接用 raw `try_*`。

参见 [Design](./design.md) 与 [`ball_float` 教程](../ball_float/tutorial.md)。
