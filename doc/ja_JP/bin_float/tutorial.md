# `bin_float` チュートリアル

## dyadic 値の構築と正規化

```moonbit
let raw = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(12UL),
  0,
  32,
)
inspect(raw.coefficient().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

`12 * 2^0` は `3 * 2^2` に正規化されます。

## IEEE context で計算する

format 境界と status flag が重要なときは host float ではなく
`BinaryContext` と interchange bit を使います。

```moonbit
let format = @bin_float.BinaryInterchangeFormat::Binary16
let context = @bin_float.BinaryContext::binary16()
let x = @bin_float.BinaryInterchange::from_hex("3C00", format).unwrap().to_bin_float()
let y = @bin_float.BinaryInterchange::from_hex("4000", format).unwrap().to_bin_float()
let (sum, flags) = x.add_ctx(y, context)
let (bits, encoding_flags) = sum.to_interchange(format)
inspect(bits.to_hex(), content="4200")
inspect(flags.combine(encoding_flags).to_testfloat_bits(), content="0")
```

`*_ctx` は一回だけ正しく丸めた値と IEEE status を返します。通常の演算子は無界
nearest-even context を使うため、format conformance の代わりにはなりません。

## 特殊値

`negative_zero`、`quiet_nan`、`signaling_nan` は明示的な constructor です。
`is_negative_zero`、`is_quiet_nan`、`is_signaling_nan`、`nan_payload` で表現状態を
観測します。NaN に順序 `compare` を使わないでください。

## Precision の再調整

`with_precision` は新しい working precision へ明示的に丸めます。binary16/32/64/128 format の選択とは別です。

## `ulp` で spacing を見る

`ulp()` は現在の表現の spacing を返し、granularity の分析に使います。

## 比較と状態

有限値は `compare`、NaN は `classify` と専用 predicate で観測し、全順序を仮定しません。

## Context status

flags が必要な場合は `*_ctx` の `(value, BinaryFlags)` をそのまま保持します。

## Signed Zero と NaN payload

負の零、qNaN/sNaN、payload は観測可能な表現です。専用 constructor と predicate を使い、通常比較から推測しません。
