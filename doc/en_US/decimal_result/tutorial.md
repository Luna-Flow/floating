# `decimal_result` Tutorial

## Parse And Calculate

```moonbit check
///|
test "checked decimal pipeline" {
  let result =
    @decimal_result.DecimalResult::parse("2.25", precision=40)
    .sqrt()
    .mul(@decimal_result.DecimalResult::from_int(2, precision=40))
  inspect(result.result().unwrap().to_string(), content="3.0")
}
```

Use `DecimalResult` for scalar checked pipelines. Use `Decimal::*_ctx` directly
when rounding flags, exponent bounds, clamp behavior, or GDA conditions are part
of the required output.
