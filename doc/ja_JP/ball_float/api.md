# @ball_float.BallFloat

このページは現在の `0.1.0` 基準における `@ball_float.BallFloat` を説明します。

## 意味

`BallFloat` は次の包絡を表します。

`center +/- radius`

現在の実装ではこれを `BinFloat` の下界・上界として保持し、できるだけ狭い区間よりも、包絡を絶対に落とさないことを優先します。

## 構築

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_int`
- `BallFloat::from_bigint`
- `BallFloat::from_float`
- `BallFloat::from_double`
- `BallFloat::from_decimal`

制約:

- 中心値は有限でなければなりません。
- 半径は有限かつ非負でなければなりません。
- `exact`、`from_float`、`from_double`、`from_decimal` は非有限入力で abort します。

補足:

- 中心値の再量子化で生じる変位は半径へ加えられ、包絡が縮まないようにします。
- 半径の量子化は常に外向きに丸められます。
- `from_decimal` は `BinFloat` ベースの包絡を構築するもので、10 進値の薄い正確ラッパではありません。

## アクセサと区間形状

- `lower_bound`
- `upper_bound`
- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `is_bounded`
- `is_entire`
- `contains_zero`
- `normalized`
- `with_precision`

補足:

- `center()` と `radius()` は非有界区間では abort します。
- 包絡が負値と正値の両方をまたぐと `sign()` は `Sign::Zero` を返します。
- `classify()` は非有界区間に対して `Infinity` を返します。

## 関係と比較

- `contains`
- `overlaps`
- `maybe_overlap`
- `separated_from`
- `definitely_lt`
- `definitely_gt`
- `compare`
- `min`
- `max`
- `clamp`

補足:

- `compare` は重なっている区間や比較不能な区間で abort します。
- `clamp` は `min` と `max` が順序付けできないと abort します。

## 算術と超越関数の挙動

- `add`
- `sub`
- `mul`
- `div`
- `pow`

対応演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

定義域メモ:

- 除算は分母包絡が `0` を含むと abort します。
- `pow` は指数包絡が厳密な一点でないと abort します。
- `pow` は非整数指数かつ底区間が厳密に正でないと abort します。
- `sqrt`、`ln`、`log2`、`log10`、`asin`、`acos`、`acosh`、`atanh` は定義域外で abort します。
- `atan2` は入力矩形が負の実軸の分岐切替をまたぐか、原点を含む場合、主値角全体の包絡 `[-pi, pi]` まで広がります。これは精度低下ではなく、包絡の正しさを優先した結果です。

## Trait 面

`BallFloat` は現在次を実装します。

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
