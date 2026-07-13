# `cli` 設計

## 責務

repository conformance backend の native executable dispatcher です。

## データフロー

`--backend` だけを消費し、残りの引数をそのまま一つの backend adapter に渡し、return code を process exit status に変換します。

## アルゴリズムと不変条件

backend 名は明示的で dispatch は一回だけです。corpus grammar と数値意味論は所有しません。

## 失敗と副作用

argument parsing と process exit が effect であり、parse、arithmetic、sharding、summary は import 先に残します。

## 実装上のトレードオフ

単一 executable は保守 workflow を統一しますが、repository verification 用途だけを公開します。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
