# `decimal_result` 教程

## 解析并计算

```moonbit check
///|
test "checked decimal pipeline" {
  let result = @decimal_result.DecimalResult::parse("2.25", precision=40)
    .sqrt()
    .mul(@decimal_result.DecimalResult::from_int(2, precision=40))
  inspect(result.result().unwrap().to_string(), content="3.0")
}
```

普通 checked 标量链使用 `DecimalResult`；当舍入 flags、指数边界或 GDA condition 属于结果时，直接使用 `Decimal::*_ctx`。
