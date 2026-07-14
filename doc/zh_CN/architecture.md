# 架构

`floating` 由边界明确的数值域，以及薄的组合、解析和验证层组成。架构将纯数值
变换与文件系统、进程和语料库等副作用分开。

## 分层映射

| 层 | 包 | 职责 |
| --- | --- | --- |
| 共享词汇 | `def` | 分类、符号、偏序、重导出的算术类型、最小 `Floating` trait |
| 标量数值域 | `bin_float`、`decimal`、`decimal_gda` | 二进制、IEEE 十进制与 GDA 十进制语义 |
| 区间数值域 | `ball_float` | bare/decorated 外向舍入包络 |
| Checked 组合 | `bin_float_checked`、`ball_float_checked`、`decimal_checked`、`decimal_gda_checked` | 分别保留 error、IEEE flags 或 GDA outcome 的封闭流水线 |
| 语义投影 | `semantic` | 与表示无关的精确观察 |
| 语法 | `numeric_expr` | source span、literal、primitive call 与 callback evaluation |
| 格式前端 | `frontend/*` | 解析一种语料格式并执行类型化 case |
| 运行适配 | `internal/conformance`、`internal/runner_cli`、`cli/*` | summary、sharding、文件、JSON、退出码 |
| 验证 | `consistency`、`doc_examples`、`*_bench`、`tools/`、`testdata/` | 定律、可执行文档、性能与语料编排 |

包边界由 `moon.pkg` 决定。包内文件名只组织实现职责，不创建命名空间。

## 数值核心

`BinFloat` 保存独立符号、非负 `BinCoeff`、二进制指数、precision 和特殊值状态。
非 JS target 使用私有 inline/limb 系数内核；JS 使用隐藏的 host `bigint` 适配器，
公开合同保持一致。

`Decimal` 保存符号、私有十进制系数、十进制指数、precision、cohort 信息和特殊值
状态。系数内核按 target 校准乘除法调度；公开行为由十进制值、quantum、context
和 flags 定义，而不是由 limb 布局定义。

`BallFloat` 保存二进制下界、上界以及 Empty/Entire 状态。有向舍入产生包络。
`BallFloatDecorated` 增加 IEEE 1788 decoration 与 NaI，但不改变 bare interval 表示。

## Context 与 Effect 流

普通算术是纯值变换。contextual 算术仍然是纯函数：context 是显式输入，结果与
flags 是显式输出，不依赖环境中的全局舍入状态。

```text
value(s) + immutable context
          -> classify special states
          -> exact or guarded finite computation
          -> one bounded-format finalization
          -> rounded value + operation flags
```

`decimal_gda` 增加不可变状态传递。每次运算把新 raised flags 合并进 context 的
sticky status，再按固定优先级选择已启用 trap。若要累计状态，调用方必须把返回的
context 传入下一步。

checked wrapper 保留所属数值域的 effect 通道。二进制与区间 wrapper 保留第一个
`ArithmeticError`；`decimal_checked` 固定 IEEE context、累计 flags，并保留异常的
定义结果；`decimal_gda_checked` 传递 next sticky context，遇到 `Trapped` 后停止，
只有显式恢复才能从定义结果继续。

## 解析与执行

`numeric_expr` 只包含语法数据与后序 callback evaluation，不执行 IO，也不选择
具体数值后端。

每个 `frontend/*` 包拥有一种外部语法：

- `gda_expr` 解析 `.decTest` directive/case 并执行 GDA 行；
- `testfloat_expr` 解析 TestFloat vector，并绑定 function/rounding/tininess；
- `mpfr_expr` 解析固定 MPFR sqrt 与整数幂数据；
- `itl_expr` 解析 interval test language 并分类支持范围。

前端返回类型化 summary。CLI 负责读文件、选择 shard/filter、序列化 JSON/文本，
并把 summary 映射为进程状态。Python 工具负责下载固定数据、规划任务、运行多个
进程/target 与汇总；它们不替代 MoonBit 数值实现。

## 稳定与内部边界

应用层发布面是 `def`、具体数值包和 checked wrapper。`semantic` 与
`numeric_expr` 是临时集成面。前端公开是为了组合仓库 runner，但兼容承诺只覆盖
声明的语料与生成接口。

`internal/*`、CLI、benchmark、`consistency` 与 `doc_examples` 属于实现或验证
基础设施。某个符号即使出现在 `pkg.generated.mbti`，也未必属于稳定应用合同；
依赖前应阅读对应 design 文档。

## 不变量

- 系数符号与非负 magnitude 分离；
- finite normalized form 只移除表示冗余，不改变数学值；
- Decimal 解析可保留 cohort/quantum，直到显式规范化；
- 只有 context finalization 应用 bounded precision、指数、clamp 与状态策略；
- 区间下界向下舍入，上界向上舍入；
- Empty、Entire、NaI、NaN 与 infinity 保持为显式状态；
- summary count 对所选 case 构成分区，sharding 可确定复现；
- IO、进程状态、下载和并行调度留在工具边界。

## 扩展规则

行为应加入拥有其语义的包。新增 umbrella trait 前先组合现有算术能力 trait。
数值内核保持私有，context 与 flags 保持显式；除非格式本身属于值类型的稳定
interchange 合同，否则格式解析应留在具体数值类型之外。

扩展 conformance 面时，需要同时更新 parser model、executor、支持分类、CLI schema、
corpus manifest、测试和三语文档。能够解析一个 operation 不等于已经支持；只有
strict execution 具备已定义结果比较和可复现证据后，才能声明支持。
