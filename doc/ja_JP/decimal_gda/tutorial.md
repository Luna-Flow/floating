# `decimal_gda` チュートリアル

General Decimal Arithmetic の rounding、sticky status、trap behavior が必要な計算で
この package を使います。IEEE `(value, flags)` model には `decimal` を使います。

## Parse と計算

Context を作り、その context で parse し、返された context を thread します。

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let result = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(result.value().to_string(), content="6.1700")
```

`result.raised()` は division の condition だけ、`result.next_context().status()` は
parsing と division の condition を含みます。

## Raised と sticky status を観測

Condition を explicit に query します。

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
let rounded = outcome.raised().contains(@decimal_gda.GdaSignal::Rounded)
let sticky = outcome.next_context().status().contains(
  @decimal_gda.GdaSignal::Rounded,
)
inspect((rounded, sticky), content="(true, true)")
```

`clear_status()` は trap を保持したまま新 status window を始めます。Status と trap の
両方を default に戻す場合だけ `reset()` を使います。

## Trap を設定

Trap set は immutable です。Context で一つの signal を有効化します。

```moonbit nocheck
let trapped_context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let one = @decimal_gda.Decimal::one()
let zero = @decimal_gda.Decimal::zero()
let outcome = @decimal_gda.divide(one, zero, trapped_context)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected trap")
}
```

Defined infinity は利用可能なままです。Trap は control information を変えますが、
numeric result を消しません。

## Checked context construction

Context parameter が configuration/user input から来る場合は `try_new` を使います。

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

非正 precision や逆転 exponent bound で abort することを避けられます。

## 正しい comparison を選ぶ

- `compare` は quiet numeric comparison で decimal comparison value を返します。
- `compare_signal` は signaling comparison behavior を使います。
- `compare_total` は NaN/cohort を含む完全な representation を順序付けます。
- `compare_total_magnitude` は magnitude に total order を適用します。

Deterministic sorting/protocol canonicalization には total comparison を使い、通常の
numeric equality の代わりにはしません。

## よくある誤りを避ける

- Sticky status を蓄積する場合に original context を再利用しない。
- `Trapped` を「値なし」とせず defined result を確認する。
- `GdaFlags` を手で combine して context status が変わったと仮定せず、
  `next_context()` を thread する。
- `decimal` と `decimal_gda` の値を交換可能と扱わない。
- Closed pipeline が GDA signal、sticky status、trap を保持する場合は IEEE
  `decimal_checked` ではなく `decimal_gda_checked` を使います。
