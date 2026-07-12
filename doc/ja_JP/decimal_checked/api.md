# `decimal_checked` API

`DecimalResult` は `Result[Decimal, ArithmeticError]` を包み、checked 10 進演算を閉じて合成します。

## 構築と観測

`ok`、`err`、`from_result`、`result` が生の結果境界を接続します。`from_int`、`from_bigint`、`from_float`、`from_double`、`parse` が値を作り、不正な入力は `Err` になります。

## 合成と算術

`map`、`bind`、`flat_map` は既存エラーを保持します。`abs`、`neg`、四則演算、`sqrt`、整数べき、`normalized`、`with_precision`、`min`、`max`、`clamp` は `Self` を返し、標準演算子も実装されています。

context と flags を返す Decimal 演算は `@decimal.Decimal` に残ります。この wrapper は `ArithmeticError` だけをモデル化します。

完全な数値メソッド名は `abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、
`pow_nat`、`pow_int`、`normalized`、`with_precision`、`min`、`max`、`clamp` です。
