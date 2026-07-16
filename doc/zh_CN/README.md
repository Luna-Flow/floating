# FLOATING 0.7.1 文档

本页是快速索引。公开名称以各包的 `pkg.generated.mbti` 为准；Tutorial
说明推荐用法，Design 解释标准对齐、算法选择、优化与切换边界。

## 快速入口

- 初次使用：[入门指南](./getting_started.md)
- 共享数值术语：[数值语义](./numeric_semantics.md)
- 包与分层模型：[架构](./architecture.md)
- 实际验证范围：[验证](./verification.md)
- 文档规则：[文档标准](./doc_standard.md)
- 优化证据：[0.7.1 性能与语义审计](./performance_audit.md)

## 应用包

| 需求 | 包 | 先读 | 深入资料 |
| --- | --- | --- | --- |
| 二进制有理数 / IEEE binary | `bin_float` | [Tutorial](./bin_float/tutorial.md) | [API](./bin_float/api.md) · [Design](./bin_float/design.md) · [Conformance](./bin_float/conformance.md) · [Performance](./bin_float/performance.md) |
| IEEE decimal / DPD / BID | `decimal` | [Tutorial](./decimal/tutorial.md) | [API](./decimal/api.md) · [Design](./decimal/design.md) · [Conformance](./decimal/conformance.md) · [Performance](./decimal/performance.md) |
| GDA sticky status 与 trap | `decimal_gda` | [Tutorial](./decimal_gda/tutorial.md) | [API](./decimal_gda/api.md) · [Design](./decimal_gda/design.md) · [Conformance](./decimal_gda/conformance.md) · [Performance](./decimal_gda/performance.md) |
| 认证区间 / IEEE 1788 | `ball_float` | [Tutorial](./ball_float/tutorial.md) | [API](./ball_float/api.md) · [Design](./ball_float/design.md) · [Conformance](./ball_float/conformance.md) · [Performance](./ball_float/performance.md) |
| 首错即停的二进制组合 | `bin_float_checked` | [Tutorial](./bin_float_checked/tutorial.md) | [API](./bin_float_checked/api.md) · [Design](./bin_float_checked/design.md) |
| 累积 IEEE decimal flags | `decimal_checked` | [Tutorial](./decimal_checked/tutorial.md) | [API](./decimal_checked/api.md) · [Design](./decimal_checked/design.md) |
| sticky/trapping GDA 组合 | `decimal_gda_checked` | [Tutorial](./decimal_gda_checked/tutorial.md) | [API](./decimal_gda_checked/api.md) · [Design](./decimal_gda_checked/design.md) |
| 首错即停的区间组合 | `ball_float_checked` | [Tutorial](./ball_float_checked/tutorial.md) | [API](./ball_float_checked/api.md) · [Design](./ball_float_checked/design.md) |
| 共享词汇 | `def` | [Tutorial](./def/tutorial.md) | [API](./def/api.md) · [Design](./def/design.md) |
| 与表示无关的观察 | `semantic` | [Tutorial](./semantic/tutorial.md) | [API](./semantic/api.md) · [Design](./semantic/design.md) |

## 集成与维护包

- 表达式 IR：[`numeric_expr`](./numeric_expr/api.md)
- 语料前端：[`frontend/gda_expr`](./frontend/gda_expr/api.md)、
  [`frontend/itl_expr`](./frontend/itl_expr/api.md)、
  [`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md)、
  [`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- CLI 适配器：[`cli`](./cli/api.md) 及其后端子包
- 运行与验证：[`internal`](./internal/api.md)、
  [`internal/conformance`](./internal/conformance/api.md)、
  [`internal/runner_cli`](./internal/runner_cli/api.md)、
  [`consistency`](./consistency/api.md)、[`bench`](./bench/api.md)

这些包因仓库工具组合需要而发布接口，但其 Design 会声明比应用包更窄的稳定性边界。

## 证据快照

- 固定 GDA `official` 语料的 **64,986/64,986 legal executable scalar
  rows** 全部通过；`official0` 为 16,124/16,124。其余 141 条 `#`
  placeholder/non-scalar 行是诊断性排除项。
- 固定 strict ITF1788 汇总的 4,656/4,656 条选定区间用例全部通过。
- Binary 与 IEEE decimal 的声明按 operation/format 矩阵限定，并包含固定
  MPFR elementary-function 证据。

这些有限结果不表示支持所有未来 directive、标准操作或实数输入。对外宣称兼容前，
必须阅读对应 conformance 页面。

## 阅读规则

用 `api.md` 查找可调用名称，用 `tutorial.md` 选择安全工作流，用 `design.md`
理解不变量与实现取舍。若文字与公开清单冲突，以 `pkg.generated.mbti` 为准。
