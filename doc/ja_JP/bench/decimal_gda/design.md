# `bench/decimal_gda` 設計

## 責務

GDA コア演算と sticky-context checked 合成を測定します。

## データフロー

正確で trap しない入力により add、multiply、divide、fma、parse を評価します。

## 不変条件

コア値と checked 値は hotspot 分析前に一致しなければなりません。

## 副作用

context 作成、入力 parse、JSONL、report は timed payload の外に置きます。

