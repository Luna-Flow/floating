# `cli/mpfr_expr_cli` 設計

## 責務

二つの固定 MPFR witness grammar 用 command adapter です。

## データフロー

sqrt と integer-power input を識別し、parse/execution を委譲して single-file summary を出力します。

## アルゴリズムと不変条件

grammar selection は transport metadata であり数値 heuristic ではありません。unsupported file は実行前に失敗します。

## 失敗と副作用

file read と rendering が effect で、MPFR format parse と binary comparison は `frontend/mpfr_expr` に残ります。

## 実装上のトレードオフ

自動 grammar 選択で command は短くなりますが、repository-pinned format だけを対象にします。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
