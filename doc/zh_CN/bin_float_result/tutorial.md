# `bin_float_result` 教程

## 构建 checked 流水线

```moonbit check
///|
test "checked binary pipeline" {
  let value = @bin_float_result.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_result.BinFloatResult::from_int(3, precision=48))
  inspect(value.result().unwrap().to_string(), content="3p0")
}
```

在调用方准备处理 `ArithmeticError` 之前保持包装状态。确定不会失败的变换用 `map`，回调自身可能失败时用 `bind`。
