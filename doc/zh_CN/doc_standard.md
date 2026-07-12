# 文档标准

仓库文档只描述**当前分支中的真实实现**。截至 `2026-07-12`，发布基线为
**`0.5.0`**。

## 文档类型与职责

1. **API 参考（`api.md`）**：说明公开类型、函数、方法、错误和可观察语义。
2. **教程（`tutorial.md`）**：提供短小、可执行的使用流程与实践建议。
3. **设计文档（`design.md`）**：说明表示、不变量、职责边界和实现取舍。
4. **README**：只负责当前基线定位、包入口和阅读路径。
5. **CHANGELOG**：负责历史版本说明与迁移记录。

## 结构与本地化

- 文档树必须镜像每个 `moon.pkg` 路径。文件名不会创建 MoonBit 模块，包边界由 `moon.pkg` 决定。
- `en_US`、`zh_CN`、`ja_JP` 应保持相同的 Markdown 文件集合和一级章节职责。
- 深度研究笔记可以保留原始语言；包 API、教程、设计、索引和标准页必须对齐。
- 英文是结构基准，中文和日文应自然本地化。不要翻译标识符、包名、路径、命令和版本号。
- README 只说明当前基线；被替代的版本叙述必须移入 `CHANGELOG.md`。
- 不要把计划中的 API 写成现有能力。`pkg.generated.mbti` 是公开接口清单，源码和测试定义行为。
- 每个包都应有 `design.md`；即使没有 API/教程，也必须明确 `internal`、CLI、测试和一致性基础设施边界。

## 数值文档规则

- 统一使用 `precision`、`rounding`、`classify`、`sign`、`normalized`、
  `quantum`、`context` 和 `flags`。
- 区分存储表示、精确值、舍入结果、状态标志、checked 错误与区间包络语义。
- 说明解析何时保留 quantum，以及规范化何时只改变 cohort 而不改变数学值。
- 不要暗示带 NaN 的标量或区间值具有普通全序。
- `*_ctx` API 必须同时说明返回值与累计 flags。
- `*_checked` API 必须说明短路行为，以及值变换组合与 observer 结果之间的区别。
- 示例应短小且可检查。MoonBit 导入示例中，`Luna-Flow/luna-generic` 固定使用
  `@lf_alg`，`Luna-Flow/arithmetic` 固定使用 `@lf_arith`。

## 审核清单

- 执行 `moon info` 后，用 `pkg.generated.mbti` 对照包文档。
- 检查链接以及三语文件集合是否对齐。
- 按改动范围运行 `moon fmt`、`moon check --target all`、相关测试、文档示例或 `just pr`。
- 发布抬版时同步更新基线日期、版本与 changelog。
