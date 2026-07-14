# `decimal_gda_checked` Tutorial

## Thread Sticky Status

```moonbit check
///|
test "GDA checked sticky pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "1.2345",
    @decimal_gda.GdaContext::new(precision=3),
  ).add(@decimal_gda.Decimal::one())
  inspect(
    checked.status().contains(@decimal_gda.GdaSignal::Rounded),
    content="true",
  )
}
```

## Stop And Resume A Trap

```moonbit check
///|
test "GDA checked trap recovery" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  inspect(trapped.is_trapped(), content="true")
  inspect(trapped.value().is_infinite(), content="true")
  inspect(trapped.add(@decimal_gda.Decimal::one()).is_trapped(), content="true")
  inspect(
    trapped.resume_defined().add(@decimal_gda.Decimal::one()).is_trapped(),
    content="false",
  )
}
```
