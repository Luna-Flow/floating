# `decimal_checked` 教程

## 累计 IEEE Flags

```moonbit check
///|
test "IEEE checked decimal pipeline" {
  let context = @decimal.DecimalContext::new(precision=3)
  let checked = @decimal_checked.DecimalChecked::parse("1.2345", context)
    .add(@decimal.Decimal::one())
  inspect(checked.value().to_string(), content="2.23")
  inspect(
    checked.flags().contains(@decimal.DecimalSignal::Rounded),
    content="true",
  )
}
```

## 保留定义异常结果

```moonbit check
///|
test "IEEE checked defined result" {
  let checked = @decimal_checked.DecimalChecked::from_int(
    1,
    @decimal.DecimalContext::decimal64(),
  ).div(@decimal.Decimal::zero())
  inspect(checked.value().is_infinite(), content="true")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::DivisionByZero),
    content="true",
  )
}
```
