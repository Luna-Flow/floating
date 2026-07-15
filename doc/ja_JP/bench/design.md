# `bench` 設計

## 責務

不変 Maremark plan を構築し、数値パッケージを benchmark コードへ結合せずに versioned observation を集約します。

## データフロー

データ型 fixture が入力を作り、Maremark が参照等価性を検証し、balanced block が observation を出力し、純粋な reducer が hotspot と tuning winner を計算します。

## 不変条件

setup は timed payload の外に置き、ペア比較は dataset と block を一致させ、auto-tune は意味的に等価な候補だけを比較します。

## 副作用

共有層は明示的 async runner 境界以外を純粋に保ち、JSONL とファイル IO はテストと `tools/benchmark.py` に限定します。

