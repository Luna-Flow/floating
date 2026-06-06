# @ball_float.BallFloat

このページは現在の `0.1.0` 基準における `@ball_float.BallFloat` を説明します。

## 意味

`BallFloat` は:

`center +/- radius`

という包絡値です。

## 構築

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_decimal`

制約:

- `center` は有限でなければなりません。
- `radius` は有限・非負・非 NaN でなければなりません。

補足:

- `new` は中心値を低精度へ量子化するとき、中心の変位を半径へ加えて包絡の縮小を防ぎます。
- 半径自身の量子化は常に外向きに丸められます。
- `from_decimal` は `BinFloat` ベースの包絡を構築するのであり、10 進値をそのまま正確に包む薄いラッパではありません。

## 参照と共有 floating 能力

- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `normalized`
- `with_precision`

補足:

- 半径が 0 のとき、`sign()` は中心値の符号と一致します。
- 包絡が負値と正値の両方をまたぐとき、現在の実装は `Sign::Zero` を返します。
- `with_precision` は中心の再量子化で変位が生じた場合、その分だけ半径を広げて元の包絡を保持します。

## 関係判定

- `contains`
- `overlaps`
- `separated_from`
- `definitely_lt`
- `definitely_gt`
- `maybe_overlap`

## 算術

- `add`
- `sub`
- `mul`
- `div`

補足:

- 分母 ball が 0 を含むとき、除算は拒否されます。
- 算術結果は包絡伝播の誤差だけでなく、出力中心の量子化で生じた変位も半径へ織り込みます。
