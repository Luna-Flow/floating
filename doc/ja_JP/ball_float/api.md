# `ball_float` API

## 安定性

bare/decorated interval 構築、relation、forward arithmetic、context、flags は
`0.5.0` API です。reverse operation と tightness 保証は契約外です。

このページは `0.5.0` 基準における `@ball_float.BallFloat`、
`@ball_float.Decoration`、`@ball_float.BallFloatDecorated` を説明します。

## 意味

`BallFloat` は次の包絡を表します。

`center +/- radius`

現在の実装ではこれを `BinFloat` の下界・上界として保持し、できるだけ狭い区間よりも、包絡を絶対に落とさないことを優先します。

## 構築

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_bounds`
- `BallFloat::from_coefficient`
- `BallFloat::from_int`
- `BallFloat::from_float`
- `BallFloat::from_double`

`from_coefficient` は非負の `@bin_float.BinCoeff` と独立した `negative?` 符号を
受け取ります。二進 stack の `BigInt` constructor は廃止され、Decimal の
`BigInt` 境界は維持されます。

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
- `abs`
- `neg`
- `pow_interval`
- `sin_interval`
- `cos_interval`
- `tan_interval`

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
- 一般の冪は IEEE 1788 の非負底定義域に従い、負底の整数冪は引き続き `pown` が担います。
- このパッケージは双曲・逆三角関数、微積分、行列、複素 ball、特殊関数をまだ公開しません。

## Decorated interval

`BallFloatDecorated` は `BallFloat` と同じ `ball_float` パッケージに属します。
利用側が import するのは `Luna-Flow/floating/ball_float` だけであり、独立した
`Luna-Flow/floating/decorated_ball_float` パッケージはありません。bare
interval、decorated interval、context、IEEE 1788 の集合意味論は一つの
パッケージ境界を共有します。

`Decoration` は弱い順に `Ill`、`Trv`、`Def`、`Dac`、`Com` です。
`BallFloatDecorated` は underlying `BallFloat`、decoration、独立した NaI
状態を保持します。

- `BallFloatDecorated::new` は bare interval を包みます。
- `BallFloatDecorated::nai` は NaI を構築します。NaI は `Ill` ですが Empty
  ではありません。
- `interval`、`decoration`、`is_nai` で三つの状態を観測できます。
- Empty は `Trv` に正規化され、non-common interval の `Com` は `Dac` に
  下がります。
- 演算結果は入力と演算自身の最も弱い decoration を取るため、評価中に
  等級が上がることはありません。
- 部分定義域、0 除算の可能性、三角関数の極では演算等級が `Trv` に下がります。
- 数値演算は NaI を伝播し、NaI を含む Boolean relation は `false`、
  `overlap_state` は `Undefined` を返します。

decorated 型は集合演算、relation、算術、cancellation、初等関数、FMA、
整数冪、極値、context 操作を公開し、`+`、`-`、`*`、`/`、`Show` に対応します。

## Trait 面

## Context と status

`BallContext` は端点を directed rounding し、`BallFlags` は inexact、overflow、underflow を返します。set semantics は変わりません。

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
