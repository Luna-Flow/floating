# 文档标准

仓库文档只描述**当前分支中的真实实现**。截至 `2026-07-14`，发布基线为
**`0.6.1`**。

## 文档类型与职责

1. **API 参考（`api.md`）**：说明公开类型、函数、方法、错误和可观察语义。
2. **教程（`tutorial.md`）**：提供短小、可执行的使用流程与实践建议。
3. **设计文档（`design.md`）**：说明表示、不变量、职责边界和实现取舍。
4. **一致性文档（`conformance.md`）**：定义数值核心的固定有限证据及排除范围。
5. **性能文档（`performance.md`）**：记录可复现测量和 target-specific 调度证据，不作 API 承诺。
6. **README**：只负责当前基线定位、包入口和阅读路径。
7. **CHANGELOG**：负责历史版本说明与迁移记录。

每个 locale 根目录还提供四份跨包指南：`getting_started.md` 说明包选择，
`numeric_semantics.md` 统一数值术语，`architecture.md` 说明职责边界，
`verification.md` 说明 conformance 范围与可复现命令。

## 结构与本地化

- 文档树必须镜像每个 `moon.pkg` 路径。文件名不会创建 MoonBit 模块，包边界由 `moon.pkg` 决定。
- `en_US`、`zh_CN`、`ja_JP` 应保持相同的 Markdown 文件集合和一级章节职责。
- 不保留 locale-only 研究页；把耐久结论提升为三语设计、一致性或性能文档，把被替代历史移入 `CHANGELOG.md`。
- 英文是结构基准，中文和日文应自然本地化。不要翻译标识符、包名、路径、命令和版本号。
- README 只说明当前基线；被替代的版本叙述必须移入 `CHANGELOG.md`。
- 不要把计划中的 API 写成现有能力。`pkg.generated.mbti` 是公开接口清单，源码和测试定义行为。
- 每个包都必须提供 `api.md`、`tutorial.md` 与 `design.md`；没有应用 API 的包仍需公布生成接口、维护流程和稳定性边界。

## 数值文档规则

- 统一使用 `precision`、`rounding`、`classify`、`sign`、`normalized`、
  `quantum`、`context` 和 `flags`。
- 区分存储表示、精确值、舍入结果、状态标志、checked 错误与区间包络语义。
- 说明解析何时保留 quantum，以及规范化何时只改变 cohort 而不改变数学值。
- 不要暗示带 NaN 的标量或区间值具有普通全序。
- `*_ctx` API 必须同时说明返回值与累计 flags。
- `*_checked` API 必须说明所属数值域的状态转移：result error、IEEE flags 累计，
  或 GDA trap 短路与恢复。
- 必须把 `decimal` 与 `decimal_gda` 写成两个独立合同：IEEE 运算返回逐 operation
  flags，GDA 运算通过 `GdaOutcome` 传递 sticky status 与 traps。
- 示例应短小且可检查。MoonBit 导入示例中，`Luna-Flow/luna-generic` 固定使用
  `@lf_alg`，`Luna-Flow/arithmetic` 固定使用 `@lf_arith`。

## 审核清单

- 执行 `moon info` 后，用 `pkg.generated.mbti` 对照包文档。
- 检查链接以及三语文件集合是否对齐。
- 按改动范围运行 `moon fmt`、`moon check --target all`、相关测试、文档示例或 `just pr`。
- 发布抬版时同步更新基线日期、版本与 changelog。
