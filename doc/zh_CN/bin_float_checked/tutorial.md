# `bin_float_checked` 教程

`BinFloatResult` 把 `Result[BinFloat, ArithmeticError]` 保留在 fluent pipeline 中。
适用于首次构造/算术错误应停止后续步骤的场景；它不是 IEEE flag accumulator。

## 构建 Pipeline

```moonbit check
///|
test "checked binary pipeline" {
  let value =
    @bin_float_checked.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_checked.BinFloatResult::from_int(3, precision=48))
  inspect(value.result().unwrap().to_string(), content="3p0")
}
```

保持 wrapper 到应用边界；用 `is_ok/is_err/error` 分支，准备处理错误时再 `result()`。

## 理解首错短路

错误上的每次 transformation 都是 identity；binary method 先保留 left error。它保证
deterministic first-error，但不会收集多个错误。`map` 用于 infallible transform，
callback 也可能失败时用 `bind`；`flat_map` 已 deprecated。

## Context 操作不保留 Flags

`add_ctx/exp_ctx` 会保留 certification/arithmetic failure，但 wrapper 只保存 value/error。
IEEE `BinaryFlags` 属于契约时，应直接调用 `BinFloat::*_ctx` 并显式携带 tuple。

## 推荐做法

1. 用它表达 first-error，而不是 status accumulation。
2. Binary combinator 的 operand 均保持 wrapped。
3. 只在外部边界提取一次。
4. 需要 flags/interchange 时使用原始 `bin_float` API。

参见 [Design](./design.md) 与 [`bin_float` 教程](../bin_float/tutorial.md)。
