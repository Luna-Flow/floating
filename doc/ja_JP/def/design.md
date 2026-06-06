# `def` 設計ノート

`@def` はこのリポジトリのプロトコル層です。

## なぜ trait が小さいのか

現在の `Floating` には四則演算、全順序比較、解析、整形は入っていません。

理由は次の通りです。

- 四則演算は既存の演算子 trait で表現できる
- `ball_float` は自然な全順序を持たない
- 静的コンストラクタはこの trait に入れにくい

## 役割

`@def` はリポジトリ全体で共通の語彙を定義します。

- `Sign`
- `FpClass`
- `RoundingMode`
- `precision`
- `normalized`
