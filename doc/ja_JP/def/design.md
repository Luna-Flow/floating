# `def` 設計

共有語彙として arithmetic の context/error/rounding/classification と `BigInt` を再公開し、`Sign`、`PartialOrder`、小さな open `Floating` trait を定義します。trait は classify、sign、precision、with_precision、normalized のみを要求します。

算術、順序、解析、flags、区間関係は表示ごとに法則が違うため含めません。`Floating` 実装だけでは field、全順序、IEEE 形式、checked error を意味しません。

## 責務

この package は表現をまたいで成立する観測と capability 名だけを提供し、数値 algorithm は concrete package に残します。

## Capability の選択

generic code は実際に必要な arithmetic trait だけを要求し、`Floating` から rounding、error、interval semantics を推測しません。
