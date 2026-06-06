# @bin_float.BinFloat

このページは現在の `0.1.0` 基準における `@bin_float.BinFloat` を説明します。

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

## 定数と超越関数 API

現在直接公開されている helper:

- `pi_for_precision`
- `tau_for_precision`
- `half_pi_for_precision`
- `quarter_pi_for_precision`
- `ln2_for_precision`
- `e_for_precision`
- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `cbrt_for_precision`
- `exp_for_precision`
- `exp2_for_precision`
- `ln_for_precision`
- `log2_for_precision`
- `log10_for_precision`
- `sin_for_precision`
- `cos_for_precision`
- `tan_for_precision`
- `atan_for_precision`
- `atan2_for_precision`
- `asin_for_precision`
- `acos_for_precision`
- `sinh_for_precision`
- `cosh_for_precision`
- `tanh_for_precision`
- `asinh_for_precision`
- `acosh_for_precision`
- `atanh_for_precision`
- `pow_for_precision`
- `bin_floor_integer`
- `bin_ceil_integer`
- `bin_nearest_integer`

定義域メモ:

- `sqrt*` は非負の有限入力を必要とします。
- `ln*` は正の有限入力を必要とします。
- `asin` / `acos` は `[-1, 1]` の内部が必要です。
- `atanh` は `(-1, 1)` の内部が必要です。
- `acosh` は `>= 1` を必要とします。
- `pow_for_precision` は非整数指数かつ非正の底で abort します。
- `tan_for_precision` は計算上の余弦がゼロになると abort します。

## Trait 面

`BinFloat` は現在次を実装します。

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
