# FLOATING 文档

本文档描述 `0.5.0` 发布基线；公开名称以各包的 `pkg.generated.mbti` 为准。

## 包入口

- 核心：[`def`](./def)、[`bin_float`](./bin_float)、[`decimal`](./decimal)、[`ball_float`](./ball_float)
- Checked：[`bin_float_checked`](./bin_float_checked)、[`decimal_checked`](./decimal_checked)、[`ball_float_checked`](./ball_float_checked)
- 语义与 IR：[`semantic`](./semantic)、[`numeric_expr`](./numeric_expr)
- 前端：[`frontend/gda_expr`](./frontend/gda_expr)、[`frontend/itl_expr`](./frontend/itl_expr)、[`frontend/mpfr_expr`](./frontend/mpfr_expr)、[`frontend/testfloat_expr`](./frontend/testfloat_expr)
- 运行与验证：[`internal`](./internal)、[`internal/conformance`](./internal/conformance)、[`internal/runner_cli`](./internal/runner_cli)、[`consistency`](./consistency)、[`bin_float_bench`](./bin_float_bench)
- CLI：[`cli`](./cli)、[`cli/gda_expr_cli`](./cli/gda_expr_cli)、[`cli/itl_expr_cli`](./cli/itl_expr_cli)、[`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli)、[`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli)

每个包都有自己的 `design.md`；库包还提供 API/教程，内部、CLI 和测试包明确说明边界，而不伪装成应用 API。

## 公开面与稳定性

`0.5.0` 仍是 1.0 之前的版本。“稳定”表示本版本明确支持的应用入口，不表示
未来版本的 ABI 永久不变。

| 包 | 可用公开面 | 本版本状态 | 明确不包含 |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`、`BinCoeff`、context/flags、interchange | 稳定发布面 | 完整 IEEE 754 全部操作 |
| `decimal` | `Decimal`、context/flags、GDA 运算、interchange | 稳定发布面 | 仅排除 `#` 占位/非标量非法输入 |
| `ball_float` | bare/decorated 区间、关系、有向舍入算术 | 稳定发布面 | reverse interval operations、必然 tight |
| `*_checked` | `Result[..., ArithmeticError]` 短路流水线 | 稳定组合面 | context flags、decoration、恢复策略 |
| `semantic` | 精确有理数/无穷/NaN/区间投影 | 临时集成面 | 表示元数据与算术本身 |
| `numeric_expr` | 语法节点和 callback evaluation | 临时集成面 | 文本解析与具体数值语义 |
| `frontend/*`、`cli/*` | conformance parser、runner、命令 | 验证基础设施 | 通用文件/格式兼容承诺 |
| `internal/*`、`consistency`、`*_bench` | 实现与验证辅助 | 非应用 API | 兼容性保证 |

`api.md` 是可调用名称清单，`design.md` 解释不变量、算法和取舍，`tutorial.md`
给出最短使用流程；若正文与清单冲突，以 `pkg.generated.mbti` 为准。

## GDA 结论

官方 144 文件语料中，64,986/64,986 条合法 executable 标量行通过，unsupported
和 legacy 为零；另外 141 条全部是 `#` placeholder/non-scalar 非法输入，故不进入
合法语义分母。official0 的 16,124 条合法行同样全部通过。

## 验证

`just smoke` 或 `just conformance smoke <backend>` 使用仓库内 fixture；完整语料和支持范围见 `testdata/*/README.md`。通过固定语料不等于完整支持 IEEE 754、GDA 或 ITF1788。
