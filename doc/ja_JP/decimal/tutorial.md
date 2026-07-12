# `decimal` チュートリアル

## 文字列から作る

```moonbit
let amount = @decimal.Decimal::from_string("12.3400", precision=32).unwrap()
inspect(amount.to_string(), content="12.34")
```

## 10 進算術

## Context と flags

GDA の status や conformance が必要なら `DecimalContext` を使い、返された `DecimalFlags` を確認します。

```moonbit
let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
inspect((a + b).to_string(), content="3.75")
```

## 2 進へ変換する

## Precision の再調整

`with_precision` は明示的な rounding を行い、元の値の数学的 exactness を暗黙に保証しません。

## Interchange と特殊値

decimal32/64/128 は explicit interchange constructor を使い、NaN、無限大、符号付き零は classification observer で確認します。

```moonbit
let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
let x = d.to_bin_float(precision=24)
let back = @decimal.Decimal::from_bin_float(x, precision=10)
inspect(back.to_string(), content="0.09999999404")
```

## Context workflow

合法な GDA 行では一つの明示的 context で parse と operation を行い、value と累積 flags の両方を確認します。

## Cohort と exact semantics

parse は末尾零と quantum を保持できます。canonical 表現が必要なら `normalized()` または `reduce_ctx()` を明示的に呼びます。
