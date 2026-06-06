# @decimal.Decimal

このページは現在の `0.1.0` 基準における `@decimal.Decimal` を説明します。

## 表現

有限値は次の形で保存されます。

`coefficient * 10^exponent10`

加えて作業精度 `precision` を持ちます。

## コンストラクタと解析

- `Decimal::make`
- `Decimal::zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_bin_float`

補足:

- 公開された有限コンストラクタは取り除ける `10` の因子を除去します。
- `from_string` は通常の 10 進表記と科学記法を受け付けます。
- 不正な文字列は `None` を返します。

## 参照・正規化・比較

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent10`
- `is_zero`
- `normalized`
- `with_precision`
- `compare`
- `min`
- `max`
- `clamp`

補足:

- `compare` は `NaN` に対して abort します。
- `clamp` は境界が無順序または `NaN` を含むと abort します。

## 算術と変換

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`
- `to_bin_float`

対応演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

変換の意味:

- 非 dyadic な 10 進値を 2 進へ変換すると近似になることがあります。
- 2 進から 10 進への変換は、現在 `BinFloat` に保存されている有限値を正確に移します。

## Trait 面

`Decimal` は現在次を実装します。

- `@def.Floating`
- `@arithmetic.Constants`
- `@arithmetic.Sqrt`
- `@arithmetic.Cbrt`
- `@arithmetic.Radical`
- `@arithmetic.Exponential`
- `@arithmetic.Logarithmic`
- `@arithmetic.Power`
- `@arithmetic.Trigonometric`
- `@arithmetic.InverseTrigonometric`
- `@arithmetic.Hyperbolic`
- `@arithmetic.InverseHyperbolic`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.Num`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `@luna-generic.Field`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`

補足:

- 定数と超越関数の trait は共有 arithmetic interface を通して公開され、現在の実装では精度付きの 10 進/2 進ブリッジを経由して計算されます。
