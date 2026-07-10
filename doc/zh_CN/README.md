# FLOATING 文档

本目录描述当前 **`0.4.0`** 实现。历史版本说明统一收录在
[CHANGELOG.md](../../CHANGELOG.md)，README 只说明当前基线。

## 阅读路径

- 需要具体数值类型时，从 `bin_float`、`decimal` 或 `ball_float` 开始。
- 需要让 checked 算术在链式调用中保持闭合时，使用对应的 `*_result` 包。
- 需要跨表示的精确公共边界时，阅读 `semantic`。
- 构建数值表达式前端时阅读 `numeric_expr`；处理 GDA `.decTest` 与 Decimal
  一致性测试时阅读 `gda_expr`。
- `internal` 与 `consistency` 属于实现和验证层，不是稳定的应用层接口。

## 核心文档

- [文档标准](./doc_standard.md)
- [正确性审计](./correctness_audit.md)
- [版本历史](../../CHANGELOG.md)
- [一致性测试流程](../../testdata/decimal/README.md)

## 包文档

- [`def`](./def/api.md)：[API](./def/api.md)、[教程](./def/tutorial.md)、[设计](./def/design.md)
- [`bin_float`](./bin_float/api.md)：[API](./bin_float/api.md)、[教程](./bin_float/tutorial.md)、[设计](./bin_float/design.md)
- [`decimal`](./decimal/api.md)：[API](./decimal/api.md)、[教程](./decimal/tutorial.md)、[设计](./decimal/design.md)、[架构研究](../en_US/decimal/architecture_research.md)
- [`ball_float`](./ball_float/api.md)：[API](./ball_float/api.md)、[教程](./ball_float/tutorial.md)、[设计](./ball_float/design.md)
- [`bin_float_result`](./bin_float_result/api.md)：[API](./bin_float_result/api.md)、[教程](./bin_float_result/tutorial.md)、[设计](./bin_float_result/design.md)
- [`decimal_result`](./decimal_result/api.md)：[API](./decimal_result/api.md)、[教程](./decimal_result/tutorial.md)、[设计](./decimal_result/design.md)
- [`ball_float_result`](./ball_float_result/api.md)：[API](./ball_float_result/api.md)、[教程](./ball_float_result/tutorial.md)、[设计](./ball_float_result/design.md)
- [`semantic`](./semantic/api.md)：[API](./semantic/api.md)、[教程](./semantic/tutorial.md)、[设计](./semantic/design.md)
- [`numeric_expr`](./numeric_expr/api.md)：[API](./numeric_expr/api.md)、[教程](./numeric_expr/tutorial.md)、[设计](./numeric_expr/design.md)
- [`gda_expr`](./gda_expr/api.md)：[API](./gda_expr/api.md)、[教程](./gda_expr/tutorial.md)、[设计](./gda_expr/design.md)
- [`internal`](./internal/api.md)：[API](./internal/api.md)、[教程](./internal/tutorial.md)、[设计](./internal/design.md)

英文目录是结构基准；中文和日文目录保持相同的 Markdown 文件集合与文体职责。
