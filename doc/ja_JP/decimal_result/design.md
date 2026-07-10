# `decimal_result` 設計

## 責務

このパッケージは checked 合成アダプターであり、別の Decimal context ではありません。`ArithmeticError` を使う演算だけを持ち上げ、`(Decimal, DecimalFlags)` API は包みません。

## エラーの流れ

最初の `Err` が後続処理を短絡します。`map` は新しいエラーを導入せず、`bind` と `flat_map` は導入できます。`result()` が wrapper からの明示的な出口です。
