# `ball_float_result` API

`BallFloatResult` は区間意味論を保ちながら `Result[BallFloat, ArithmeticError]` を包みます。

## 構築と観測

`ok`、`err`、`from_result`、`result` が生の結果を接続します。`exact`、`from_bounds`、`whole` と各 `from_*` が区間を構築し、不正な境界は `Err` になります。

## 合成と算術

`map`、`bind`、`flat_map` は既存エラーを短絡します。絶対値、符号反転、四則演算、整数べき、正規化、精度変更は `Self` を返し、標準演算子も実装されています。

0 を含む区間による除算は `BallFloat` と同じく whole-real enclosure を返し、`Err` にはなりません。

完全な数値面には `from_int`、`from_bigint`、`from_float`、`from_double`、
`abs`、`neg`、`add`、`sub`、`mul`、`div`、`pow_nat`、`pow_int`、
`normalized`、`with_precision` が含まれます。
