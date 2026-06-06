# `decimal` 設計ノート

`Decimal` はこのリポジトリの 10 進優先表現です。

## 不変条件

- 有限値は `coefficient * 10^exponent10`
- `coefficient` から除去可能な 10 因子を取り除く
- 零は一意な正規形を使う

## 解析経路

`Decimal::from_string` は `@internal.split_decimal_string` を使って:

- 符号処理
- 小数点除去
- 科学表記指数の折り込み

を行ってから正規化された値を構築します。
