# `internal/conformance` 設計

## 責務

conformance location、disposition、shard、summary の pure shared model です。

## データフロー

frontend が immutable case result を構築し、summary fold が category を数え、merge が disjoint shard を結合し、success は executable failure だけで決まります。

## アルゴリズムと不変条件

shard selection は case index により deterministic です。unsupported/diagnostic row は passed executable row を装いません。

## 失敗と副作用

parse、arithmetic、IO、scheduling effect はありません。

## 実装上のトレードオフ

shared model で runner 間の count drift を防ぎ、frontend wrapper は domain-specific public name を保持します。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
