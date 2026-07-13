# `internal/runner_cli` 設計

## 責務

native conformance command adapter が共有する effect boundary です。

## データフロー

common option を解析し、file を収集・読取し、diagnostic を整形し、backend CLI 用 JSON value を構築します。

## アルゴリズムと不変条件

file order と JSON encoding は deterministic で、shard parameter は frontend 実行前に検証します。

## 失敗と副作用

filesystem read と rendering をここに閉じ込め、conformance model と numeric frontend を pure に保ちます。

## 実装上のトレードオフ

effect helper の共有で CLI 重複を除きますが、general-purpose command framework にはしません。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
