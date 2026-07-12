# `bin_float_checked` Tutorial

## Build A Checked Pipeline

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

Keep the wrapper through transformations and call `result()` only where the
caller is ready to handle `ArithmeticError`. Use `map` for a guaranteed
value-to-value transform and `bind` when the callback can fail.
