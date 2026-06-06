# @decimal.Decimal

このページは現在の `0.1.0` 基準における `@decimal.Decimal` を説明します。

## 表現

有限値は:

`coefficient * 10^exponent10`

として保存されます。

## コンストラクタ

- `Decimal::make`
- `Decimal::zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_string`

## 参照・分類

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent10`
- `is_zero`

## 正規化と精度制御

- `normalized`
- `with_precision`

## 算術

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

## 変換

- `to_bin_float`
- `Decimal::from_bin_float`

非 dyadic な 10 進値は 2 進へ変換すると近似になることがあります。
