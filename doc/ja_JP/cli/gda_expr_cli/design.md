# `cli/gda_expr_cli` 設計

## 責務

GDA `.decTest` 実行の filesystem/rendering adapter です。

## データフロー

input を展開して各 source を一度だけ読み、parse と execution を `frontend/gda_expr` に委譲し、text または schema-versioned JSON を出力します。

## アルゴリズムと不変条件

filter と shard は deterministic です。strict mode は unsupported row を失敗にし、diagnostic は別分類のままです。

## 失敗と副作用

file read、argument handling、JSON rendering、exit status を pure frontend から隔離します。

## 実装上のトレードオフ

transport 分離で parser test は deterministic になりますが、main CLI 専用の小さな adapter API が残ります。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
