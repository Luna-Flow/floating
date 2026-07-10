# `bin_float_result` 设计

## 职责

原始 checked 方法返回 `Result`，会打断数值链式组合。该包装把成功和失败都保留在返回 `Self` 的数值对象中。

## 边界

`result()` 显式恢复普通 checked 边界。自然返回非 `BinFloat` 的 observer 不会被强行纳入该代数；错误按从左到右的顺序短路。
