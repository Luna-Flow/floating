# `decimal_result` 设计

## 职责

该包是 checked 组合适配器，不是第二套 Decimal context。它提升以 `ArithmeticError` 为错误边界的运算，不包装 `(Decimal, DecimalFlags)` API。

## 错误流

第一个 `Err` 会短路后续运算。`map` 不产生新错误；`bind` 与 `flat_map` 可以。`result()` 是离开闭合包装的显式出口。
