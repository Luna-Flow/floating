# `cli/testfloat_expr_cli` 設計

## 責務

Berkeley TestFloat vector file 用 command adapter です。

## データフロー

function、rounding、tininess、shard option を検証し、parse/execution を `frontend/testfloat_expr` に委譲します。

## アルゴリズムと不変条件

metadata は明示し、filename から推測しません。JSON field と exit status は tooling 向けに安定させます。

## 失敗と副作用

file access、option parsing、rendering、exit status をこの edge に隔離します。

## 実装上のトレードオフ

明示 metadata は冗長ですが、誤った format/rounding policy が別 oracle contract を黙って選ぶことを防ぎます。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
