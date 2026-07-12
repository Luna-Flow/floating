# `bin_float_checked` 设计

`BinFloatResult` 是封闭的 `Result[BinFloat, ArithmeticError]` 流水线。构造器在边界校验；一元操作只映射成功值；二元操作按从左到右保留首个错误，仅在双方成功时调用 checked 标量算法。`bind` 可引入新错误，`map` 不可；`flat_map` 只是 deprecated 别名。

本包不新增算术、IEEE flags、互换或恢复策略，所有数值语义委托给 `bin_float`。上下文 IEEE 流程仍应直接使用底层 `(value, flags)` API。

每个 wrapper 步骤除底层数值操作外只增加 `O(1)` 成本。独立 wrapper 避免把错误
状态塞进 `BinFloat`，使普通代数值与显式短路流水线保持两个清晰契约。
