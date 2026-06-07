# @ball_float.BallFloat

このページは現在の `0.2.0` 基準における `@ball_float.BallFloat` を説明します。

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

制約:

- 中心値は有限でなければなりません。
- 半径は有限かつ非負でなければなりません。
- `exact`、`from_float`、`from_double` は非有限入力で abort します。

補足:

- 中心値の再量子化で生じる変位は半径へ加えられ、包絡が縮まないようにします。
- 半径の量子化は常に外向きに丸められます。

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
- `separated_from`
- `definitely_lt`
- `definitely_le`
- `definitely_gt`
- `maybe_eq`

補足:

- これらは enclosure relation であり、scalar の全順序を装いません。

## 算術と checked capability の挙動

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

checked 挙動メモ:

- checked division は分母包絡が `0` を含むと whole-real enclosure へ広がることがあります。
- checked integer power は enclosure の正しさを保ち、零交差を含む逆冪でも同じ whole-real fallback を使います。
- `BallFloat` は scalar `CompareChecked` を実装しません。
- このパスでは非整数冪、超越関数、微積分、行列、複素 ball、特殊関数は公開しません。

## Trait 面

`BallFloat` は現在次を実装します。

- `@def.Floating`
- `@arithmetic.Contains`
- `@arithmetic.Overlaps`
- `@arithmetic.DefinitelyLt`
- `@arithmetic.DefinitelyLe`
- `@arithmetic.MaybeEq`
- `@arithmetic.DivChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`
