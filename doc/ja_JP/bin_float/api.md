# @bin_float.BinFloat

このページは現在の `0.1.0` 基準における `@bin_float.BinFloat` を説明します。

## 表現

有限値は:

`significand * 2^exponent2`

として保存されます。

## 主なコンストラクタ

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::from_int`
- `BinFloat::from_bigint`

## 参照・分類

- `classify`
- `precision`
- `sign`
- `significand`
- `exponent2`
- `is_zero`

## 正規化と精度制御

- `normalized`
- `with_precision`
- `ulp`

## 算術

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

## 比較

- `compare`

`NaN` には順序を定義しません。
