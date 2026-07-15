# `decimal_gda_checked` チュートリアル

`GdaDecimalChecked` は一つの GDA outcome と sticky context を linear calculation に保持し、
trap 後は explicit recovery まで停止します。

## Sticky Status の Thread

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

`raised()` は latest operation、`status()` は cumulative next context、`outcome()` は full state。

## Trap で停止

```moonbit check
///|
test "GDA checked trap short-circuit" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  inspect(trapped.is_trapped(), content="true")
  inspect(trapped.value().is_infinite(), content="true")
  inspect(trapped.trapped_signal() is Some(_), content="true")
  inspect(trapped.add(@decimal_gda.Decimal::one()).is_trapped(), content="true")
}
```

Defined infinity は残り、trapped state の後続 operation は identity transition です。

## Policy に基づく Resume

```moonbit check
///|
test "GDA checked explicit recovery" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  let resumed = trapped.resume_defined()
  inspect(resumed.is_trapped(), content="false")
  inspect(resumed.value().is_infinite(), content="true")
}
```

`resume_defined()` は value/sticky context を保持し current raised を clear。Application が trap を処理し、
defined result からの継続を認めた場合のみ呼びます。

## Binary Operand は Plain Value

`add/multiply/quantize` は plain GDA Decimal を受け independent sticky contexts を merge しません。
Pipeline 合流時は external policy が controlling context を選びます。

## 推奨事項

1. Business boundary で `is_trapped/trapped_signal`。
2. Recovery 前に raised/status/value を記録。
3. 継続目的だけで resume しない。
4. Branching trap policy は raw outcome、linear composition は wrapper。

[Design](./design.md) と [`decimal_gda` Tutorial](../decimal_gda/tutorial.md) を参照してください。
