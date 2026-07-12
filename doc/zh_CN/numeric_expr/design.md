# `numeric_expr` 设计

这是只含语法的私有 IR：literal、命名 operation、source span 和调用树。`evaluate` 做深度优先后序遍历，literal/operation 语义由回调提供，节点失败会带回原节点，未知形式显式返回 `UnsupportedExpression`。

它不分词、不选数值类型、不定义 arity、不舍入、不做 IO 或调度。前端负责源码策略，后端负责数值语义。

## 纯遍历与复杂度

`evaluate` 是后序遍历：节点数为 `n` 时调用成本 `O(n)`，额外栈空间为树深度 `O(h)`；具体数值运算的成本由 callback 决定。

## 稳定边界

构造和 callback 接口属于临时集成面，树布局保持私有。这样前端语法演进不会迫使数值后端改变表示。
