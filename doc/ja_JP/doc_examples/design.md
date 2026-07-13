# `doc_examples` 設計

## 責務

localized documentation が共有する example の executable home です。

## データフロー

MoonBit `check` block で binary、decimal、GDA、interval、checked、semantic、expression、frontend workflow を検証します。

## アルゴリズムと不変条件

example は compact contract witness であり、大規模 matrix と performance measurement は置きません。

## 失敗と副作用

test 時だけ実行され、filesystem/process effect はありません。

## 実装上のトレードオフ

example を集中すると translation drift を防ぎつつ、各 locale の prose は同じ挙動を自然に説明できます。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
