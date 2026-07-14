# FLOATING 文档

本文档描述 `0.6.1` 发布基线；公开名称以各包的 `pkg.generated.mbti` 为准。

建议先阅读[快速上手](./getting_started.md)、[数值语义](./numeric_semantics.md)、
[架构](./architecture.md)和[验证](./verification.md)，再进入具体包的参考页。

## 包入口

- 核心：[`def`](./def/api.md)、[`bin_float`](./bin_float/api.md)、[`decimal`](./decimal/api.md)、[`decimal_gda`](./decimal_gda/api.md)、[`ball_float`](./ball_float/api.md)
- Checked：[`bin_float_checked`](./bin_float_checked/api.md)、[`decimal_checked`](./decimal_checked/api.md)、[`decimal_gda_checked`](./decimal_gda_checked/api.md)、[`ball_float_checked`](./ball_float_checked/api.md)
- 语义与 IR：[`semantic`](./semantic/api.md)、[`numeric_expr`](./numeric_expr/api.md)
- 前端：[`frontend/gda_expr`](./frontend/gda_expr/api.md)、[`frontend/itl_expr`](./frontend/itl_expr/api.md)、[`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md)、[`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- 运行与验证：[`internal`](./internal/api.md)、[`internal/conformance`](./internal/conformance/api.md)、[`internal/runner_cli`](./internal/runner_cli/api.md)、[`consistency`](./consistency/api.md)、[`bin_float_bench`](./bin_float_bench/api.md)
- CLI：[`cli`](./cli/api.md)、[`cli/gda_expr_cli`](./cli/gda_expr_cli/api.md)、[`cli/itl_expr_cli`](./cli/itl_expr_cli/api.md)、[`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli/api.md)、[`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli/api.md)

每个包都提供 `api.md`、`tutorial.md` 与 `design.md`。基础设施、CLI、benchmark
和测试包用这些页面说明维护入口，并明确声明它们不是稳定应用 API。

## 公开面与稳定性

`0.6.1` 仍是 1.0 之前的版本。“稳定”表示本版本明确支持的应用入口，不表示
未来版本的 ABI 永久不变。

| 包 | 可用公开面 | 本版本状态 | 明确不包含 |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`、`BinCoeff`、context/flags、interchange | 稳定发布面 | 完整 IEEE 754 全部操作 |
| `decimal` | `Decimal`、IEEE context/flags、interchange | 稳定发布面 | 完整 IEEE 754 全部运算 |
| `decimal_gda` | GDA `Decimal`、context、sticky flags、traps、outcome | 稳定 GDA 面 | 未固定的未来 directive 与非标量占位行 |
| `ball_float` | bare/decorated 区间、关系、有向舍入算术 | 稳定发布面 | reverse interval operations、必然 tight |
| `bin_float_checked`、`ball_float_checked` | `Result[..., ArithmeticError]` 短路流水线 | 稳定组合面 | context flags 与 decoration |
| `decimal_checked` | IEEE context、定义结果、本步与累计 flags | 稳定 IEEE 组合面 | GDA sticky status 与 traps |
| `decimal_gda_checked` | sticky context、trap 短路、显式定义结果恢复 | 稳定 GDA 组合面 | IEEE 逐 operation context 模型 |
| `semantic` | 精确有理数/无穷/NaN/区间投影 | 临时集成面 | 表示元数据与算术本身 |
| `numeric_expr` | 语法节点和 callback evaluation | 临时集成面 | 文本解析与具体数值语义 |
| `frontend/*`、`cli/*` | conformance parser、runner、命令 | 验证基础设施 | 通用文件/格式兼容承诺 |
| `internal/*`、`consistency`、`*_bench` | 实现与验证辅助 | 非应用 API | 兼容性保证 |

`api.md` 是可调用名称清单，`design.md` 解释不变量、算法和取舍，`tutorial.md`
给出最短使用流程；若正文与清单冲突，以 `pkg.generated.mbti` 为准。

## 数值证据

- [`bin_float` 一致性](./bin_float/conformance.md)与[性能](./bin_float/performance.md)
- [`decimal` IEEE 一致性](./decimal/conformance.md)与[性能](./decimal/performance.md)
- [`decimal_gda` 一致性](./decimal_gda/conformance.md)
- [`ball_float` 一致性](./ball_float/conformance.md)

性能阈值是实现证据，不是公开保证；一致性页会列出有限声明及其排除范围。

## GDA 结论

官方 144 文件语料中，64,986/64,986 条合法 executable 标量行通过，unsupported
和 legacy 为零；另外 141 条全部是 `#` placeholder/non-scalar 非法输入，故不进入
合法语义分母。official0 的 16,124 条合法行同样全部通过。

## 验证

`just conformance smoke <backend>` 使用仓库内 fixture；完整语料和支持范围见 `testdata/*/README.md`。通过固定语料不等于完整支持 IEEE 754、GDA 或 ITF1788。
