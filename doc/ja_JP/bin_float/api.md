# @bin_float.BinFloat

このページは現在の `0.2.0` 基準における `@bin_float.BinFloat` を説明します。

## 表現

有限値は次の形で保存されます。

`significand * 2^exponent2`

加えて作業精度 `precision` を持ちます。

## コンストラクタと保存形

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::from_int`
- `BinFloat::from_bigint`
- `BinFloat::from_float`
- `BinFloat::from_double`

補足:

- 公開された有限コンストラクタは正規化を行います。
- `compare` は `NaN` に対して abort します。
- 現在の実装では `sign()` は `NaN` に対して `Sign::Zero` を返します。

## 参照・正規化・比較

- `classify`
- `precision`
- `sign`
- `significand`
- `exponent2`
- `is_zero`
- `normalized`
- `with_precision`
- `ulp`
- `compare`
- `min`
- `max`
- `clamp`

補足:

- `clamp` は境界が無順序または `NaN` を含むと abort します。
- `ulp()` は非有限入力に対して `NaN` を返します。

## 算術と変換

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

対応演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

特殊値の挙動:

- `NaN` は通常そのまま伝播します。
- 符号が反対の `inf - inf` は `NaN` になります。
- ゼロ除算は分子のクラスに応じて `inf` または `NaN` になります。

## checked 算術 API

現在直接公開されている checked helper:

- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `compare_checked`
- `div_checked`
- `sqrt`
- `pow_int`

checked 挙動メモ:

- `sqrt*` は非負の有限入力を必要とします。
- `compare_checked` は `NaN` に対して unordered-comparison error を返します。
- `div_checked` はゼロ除算で structured error を返します。
- `pow_int` は負指数かつゼロの底で division-by-zero error を返します。

## Trait 面

`BinFloat` は現在次を実装します。

- `@def.Floating`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
