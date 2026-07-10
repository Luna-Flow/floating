# `bin_float_result` API

`BinFloatResult` は `Result[BinFloat, ArithmeticError]` を包み、checked 2 進演算を同じ型の中で合成します。

## 構築と観測

- `ok`、`err`、`from_result` は既存結果を包み、`result` は生の `Result` を取り出します。
- `from_int`、`from_bigint`、`from_float`、`from_double` は成功値を作ります。

## 合成

`map` は失敗しない値変換、`bind` と `flat_map` は `BinFloatResult` を返す変換を適用します。既存エラーはコールバックを実行せず短絡します。

## 数値演算

`abs`、`neg`、四則演算、`sqrt`、整数べき、`normalized`、`with_precision`、`ulp`、`min`、`max`、`clamp` はすべて `Self` を返し、標準演算子も実装されています。

四則演算と整数べきの正確なメソッド名は `add`、`sub`、`mul`、`div`、
`pow_nat`、`pow_int` です。
