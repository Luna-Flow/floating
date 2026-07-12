# Decimal アーキテクチャ調査

この文書は `0.4.0` から始まった Decimal architecture の歴史的研究です。`0.5.0` の能力契約や将来 API の約束ではなく、公開能力は [`api.md`](./api.md) と生成 interface を基準にします。

## 現在の実装

- `Decimal` は符号、magnitude coefficient、10 進 exponent/quantum、precision、特殊値 payload を区別します。
- `DecimalContext` と `DecimalFlags` は GDA の丸め、指数境界、clamp、extended、condition 状態を保持します。
- context 演算は基本算術、量子化、比較、論理 digit、隣接値、初等関数、書式化、整数変換を扱います。
- `DecimalInterchange` は decimal32、decimal64、decimal128 の encode/decode と canonicalization を提供します。
- `numeric_expr`、`gda_expr`、native CLI が実行時 `.decTest` parser/executor を構成します。

## アーキテクチャ原則

- 厳密表現、context finalization、flags、checked `ArithmeticError` 投影を分離します。
- quantum と正規化 cohort の違いを保持します。
- 式構文、GDA frontend、Decimal backend、corpus scheduling を分けます。
- 生成 interface、white-box test、official corpus の三つで公開挙動を制約します。

## 今後の調査境界

性能 kernel、追加の意味投影、interchange 診断、広い ecosystem 統合は、code と test を伴って段階的に実装します。生成 interface に現れる前の項目を API 文書で公開済みとして扱いません。
