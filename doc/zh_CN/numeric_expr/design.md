# `numeric_expr` 设计

## 职责边界

该包负责语法构造、来源位置、遍历和通用求值顺序，不负责读文件、解析完整格式、解析操作名或选择具体数值类型。

## 私有表示

`Expr` 隐藏由 type-theory 支撑的内部 term 表示。调用方只依赖 `literal`、`invoke` 与 `evaluate`，未来扩展语法时不暴露底层编码。
