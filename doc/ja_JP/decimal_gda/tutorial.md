# `decimal_gda` チュートリアル

GDA rounding、sticky status、defined trap result、trap precedence が必要な場合に使います。
IEEE `(value,flags)` model は `decimal` です。

## 覚えるべき一つの規則

全 operation は `GdaOutcome` を返します。Status を累積する場合は `next_context()` を次へ渡します。
`raised()` は current operation、`next_context().status()` は threaded history です。

## Parse と計算

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let divided = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(divided.value().to_string(), content="6.1700")
```

Parse は cohort を保持し、returned context を渡すことで parse condition も sticky status に残ります。

## Raised / Sticky Status の確認

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
inspect(
  outcome.raised().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
inspect(
  outcome.next_context().status().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
```

`clear_status()` は traps を保持して observation window を開始、`reset()` は両方を default に戻します。

## Trap の設定と処理

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let outcome = @decimal_gda.divide(
  @decimal_gda.Decimal::one(),
  @decimal_gda.Decimal::zero(),
  context,
)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected a trap")
}
```

Defined infinity は残り、trap は control flow を変えるだけです。

## Dynamic Context の検証

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

Configuration/user input は `try_new` で validation error を通常 channel にします。

## Quantize と Cohort

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let value = @decimal_gda.Decimal::from_string("12.3456").unwrap()
let cents = @decimal_gda.Decimal::from_string("0.00").unwrap()
let outcome = @decimal_gda.quantize(value, cents, context)
inspect(outcome.value().quantum(), content="-2")
```

Rounded/Inexact/invalid を確認し next context を thread。Canonical cohort が必要な場合だけ `reduce`。

## Mathematical Function

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let nine = @decimal_gda.Decimal::from_int(9)
let root = @decimal_gda.sqrt(nine, context)
inspect(root.value().to_string(), content="3")
```

GDA surface は sqrt/power/exp/ln/log10。Trig/hyperbolic/inverse/atan2/hypot/pi-scaled は別 domain です。

## Comparison の選択

`compare` は quiet numeric、`compare_signal` は signaling、`compare_total` は NaN/cohort を含む
representation order、`compare_total_magnitude` は magnitude total order、`same_quantum` は exponent。
Total comparison を numerical equality の代わりにしないでください。

## 長い Chain は Checked Pipeline

```moonbit check
///|
test "GDA checked pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "9",
    @decimal_gda.GdaContext::decimal64(),
  ).sqrt()
  inspect(checked.value().to_string(), content="3")
  inspect(checked.is_trapped(), content="false")
}
```

Application が defined result からの継続を明示的に認めた場合のみ `resume_defined()` を使います。

## よくある誤り

- Sticky accumulation が必要なのに original context を再利用；
- `Trapped` を no value と扱う；
- flags combine だけで context status が変わったと考える；
- 二つの Decimal type を混ぜる；
- GDA に IEEE `decimal_checked` を使う。

## 推奨事項

1. Calculation boundary で context を検証。
2. Manual workflow は常に next context を thread。
3. Control boundary で raised/status の両方を確認。
4. Recovery 前に trap/defined result を記録。
5. Linear chain は wrapper、branching policy は raw outcome。

## 次に読む

[Design](./design.md)、[API](./api.md)、[Conformance](./conformance.md)、
[`decimal_gda_checked`](../decimal_gda_checked/tutorial.md) を参照してください。
