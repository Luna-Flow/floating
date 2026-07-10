# `numeric_expr` 教程

## 分离语法与数值语义

用 `Literal` 与 `Operation` 构造表达式，再向 `evaluate` 提供两个回调：一个把字面量文本解析为后端值，另一个按操作名处理已求值参数。

同一表达式树可面向 `Decimal`、`BinFloat`、语义值或测试替身。前端诊断应保留 `SourceSpan`，不要把文件系统策略塞入表达式包。
