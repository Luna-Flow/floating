# `decimal_checked` チュートリアル

`DecimalChecked` は current defined Decimal、IEEE context、latest flags、accumulated flags、optional
certification error を保持します。

## IEEE Flags の累積

```moonbit check
///|
test "IEEE checked decimal pipeline" {
  let context = @decimal.DecimalContext::new(precision=3)
  let checked = @decimal_checked.DecimalChecked::parse("1.2345", context)
    .add(@decimal.Decimal::one())
  inspect(checked.value().to_string(), content="2.23")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::Inexact),
    content="true",
  )
  inspect(
    checked.flags().contains(@decimal.DecimalSignal::Rounded),
    content="true",
  )
}
```

`raised()` は last operation、`flags()` は combined history、`outcome()` は value + combined flags。

## Defined Exceptional Result の保持

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
  inspect(checked.is_ok(), content="true")
}
```

`is_ok()` は ArithmeticError がない意味で flags empty ではありません。Certification failure は
`error()` へ入り short-circuit、IEEE conditions は value+flags を保持します。

## Status Window の Reset

`clear_flags()` は value/context を保持して flags を clear。`with_context` は new IEEE context で current
value を再 apply し flags を記録する observable step です。

## Independent Pipeline を Merge しない

Binary method は plain `Decimal` を受け、二つの context/history を暗黙 merge しません。合流時は
application が context と merge policy を決めます。

## 推奨事項

1. Step policy は `raised()`、end-to-end は `flags()`。
2. `is_ok()` と `flags().has_error()` を区別。
3. Status consumption 後に clear。
4. Outer boundary で `result()`。
5. GDA trap は `decimal_gda_checked`。

[Design](./design.md) と [`decimal` Tutorial](../decimal/tutorial.md) を参照してください。
