# `bin_float_result` 設計

## 責務

生の checked メソッドは `Result` を返し、数値の連続合成を中断します。この wrapper は成功と失敗を、各演算が `Self` を返す数値オブジェクト内に保持します。

## 境界

`result()` が通常の checked 境界を明示的に復元します。自然に `BinFloat` 以外を返す observer はこの代数へ持ち込まず、エラーは左から短絡します。
