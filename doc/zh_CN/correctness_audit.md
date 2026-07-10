# 正确性审计

本审计把 **`0.4.0`** 公开接口映射到当前实现和验证边界。生成接口负责列出 API，源码和测试定义行为。

## 核心数值包

| 范围 | 契约 | 证据 | 状态 |
| --- | --- | --- | --- |
| `def` | `Floating` 只包含分类、符号、精度、精度调整和规范化；算术 capability 保持独立。 | `src/def/pkg.generated.mbti`、consistency tests | 已验证 |
| `bin_float` | 有限值采用规范化 dyadic 表示；精度变化显式舍入；checked 除法、比较、平方根与幂返回 `ArithmeticError`。 | `src/bin_float`、`src/consistency` | 在舍入边界内已验证 |
| `decimal` 表示 | 有限值保留符号、magnitude、exponent/quantum 与 precision；signed zero 和 qNaN/sNaN payload 可观察。 | `src/decimal`、Decimal white-box tests | 已验证 |
| `decimal` context | `*_ctx` 应用 precision、rounding、指数、clamp、extended 设置，并返回累计 `DecimalFlags`。 | `src/decimal/*_ctx.mbt`、smoke 与 official cases | 在各操作语料边界内已验证 |
| `decimal` interchange | 通过 `DecimalInterchange` 公开 decimal32/64/128 编解码，显式报告 canonicalization 与 status。 | `src/decimal/interchange.mbt`、interchange phase | 在一致性边界内已验证 |
| `ball_float` | 边界向外舍入；算术包络真实结果；关系按区间定义；除数含零时返回 whole-real enclosure。 | `src/ball_float`、consistency tests | 在包络边界内已验证 |

## 组合与语义包

| 范围 | 契约 | 证据 | 状态 |
| --- | --- | --- | --- |
| `*_result` | 已有错误短路；产出数值的 checked 运算保持返回 `Self`；`result()` 恢复原始边界。 | 三个生成接口与实现包 | 已验证 |
| `semantic` | 具体有限值投影为精确有理数；无穷、NaN、区间和算术失败投影为显式语义 variant。 | `src/semantic`、consistency tests | 已验证 |
| `numeric_expr` | 表达式存储私有；回调负责 literal 与 operation 语义；求值错误保留节点类别。 | `src/numeric_expr`、package tests | 已验证 |
| `gda_expr` | 解析诊断、legacy、unsupported 与可执行结果错误分别记录；公开确定性 options 与 summaries。 | parser/execution tests、smoke fixture | 已验证 |

## 验证门禁

- `just smoke`：仓库内 parser/backend 端到端 fixture。
- `just ci`：定向 Decimal coefficient kernel white-box 门禁。
- `just pr`：all-target 检查、生成接口刷新、native interpreter 构建与分阶段 official corpus 执行。

官方语料是外部固定输入，不进入版本库。unsupported 与 diagnostic 会保留在汇总中；需要把它们作为失败时启用 strict mode。详见[一致性测试流程](../../testdata/decimal/README.md)。
