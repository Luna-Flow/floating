# `numeric_expr` API

`numeric_expr` 提供与宿主语言无关的数值表达式核心，表达式存储保持私有。

## 语法类型

`SourceSpan` 保存来源、行和列；`Literal` 保存原始文本与 span；`Operation` 保存操作名与 span；`Expr::literal`、`Expr::invoke` 构造字面量和原语调用。

对应 accessor 为 `SourceSpan::{new,source,line,column}`、
`Literal::{new,raw,span}` 和 `Operation::{new,name,span}`。

## 求值

`evaluate(expr, literal_callback, operation_callback)` 先求值子节点，再调用操作回调，返回 `Result[V, EvalError[E]]`。错误区分字面量失败、操作失败和当前求值器不支持的表达式形态。
