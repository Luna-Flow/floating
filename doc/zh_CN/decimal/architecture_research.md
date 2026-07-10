# Decimal 架构研究

本文记录 `0.4.0` Decimal 架构的背景、已落地边界与后续评估方向。它不是未来 API 承诺；公开能力以 [`api.md`](./api.md) 与生成接口为准。

## 当前实现

- `Decimal` 区分符号、magnitude coefficient、十进制 exponent/quantum、precision 与特殊值 payload。
- `DecimalContext` 与 `DecimalFlags` 承载 GDA 舍入、指数边界、clamp、extended 和 condition 状态。
- context 运算覆盖核心算术、量化、比较、逻辑数字、相邻值、初等函数、格式化与整数转换。
- `DecimalInterchange` 提供 decimal32、decimal64、decimal128 编解码和 canonicalization。
- `numeric_expr`、`gda_expr` 与 native CLI 组成运行时 `.decTest` 解析和执行路径。

## 架构原则

- 将精确表示、context finalization、flags、checked `ArithmeticError` 投影分层处理。
- 保留 quantum 与规范化 cohort 的区别。
- 把表达式语法、GDA 前端、Decimal 后端、语料调度分开。
- 以生成接口、white-box 测试与官方语料共同约束公开行为。

## 后续研究边界

性能内核、更多语义投影、额外 interchange 诊断和更广泛的生态集成仍需按代码与测试逐项落地；在进入实现与生成接口之前，不应在 API 文档中写成已发布能力。
