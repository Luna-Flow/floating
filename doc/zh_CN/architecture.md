# 架构

`floating` 0.7.1 由显式数值域及其外部的轻量组合、解析和验证层组成。核心原则是：
数值语义保持纯函数与显式数据流，文件系统、进程、语料和 benchmark effect 留在仓库边缘。

## 分层图

| 层 | 包 | 职责 |
| --- | --- | --- |
| 共享词汇 | `def` | classification、sign、partial order、算术类型重导出、最小 `Floating` trait |
| 标量域 | `bin_float`、`decimal`、`decimal_gda` | binary、IEEE decimal、GDA decimal 值与 context 语义 |
| 区间域 | `ball_float` | bare/decorated 外向舍入实数包络 |
| Checked 组合 | `*_checked` | 在闭合管线中保留各域的 error、flag 或 trap 状态 |
| 语义投影 | `semantic` | 与表示无关的精确观察 |
| 语法 | `numeric_expr` | source span、literal、primitive call、callback evaluation |
| 格式前端 | `frontend/*` | 解析单一语料 grammar 并执行 typed case |
| 运行适配 | `internal/conformance`、`internal/runner_cli`、`cli/*` | summary、shard、文件、JSON/text、exit status |
| 证据 | `consistency`、`doc_examples`、`bench/*`、`tools/`、`testdata/` | law、文档、conformance、performance、orchestration |

包边界由 `moon.pkg` 决定；同一包内的文件名只用于组织实现，不创建 namespace。

## 标准边界

仓库不把所有语义压成一个“通用浮点值”。每个标准面保留自身可观察状态：

| 数值域 | 0.7.1 表示的规范模型 | 操作结果 |
| --- | --- | --- |
| `bin_float` | 声明范围内的 IEEE 754-2019 binary | value + `BinaryFlags` |
| `decimal` | 声明范围内的 IEEE 754-2019 decimal/interchange | value + `DecimalFlags` |
| `decimal_gda` | GDA 1.70 标量操作模型 | 含 raised flags、sticky next context、可选 trap 的 `GdaOutcome` |
| `ball_float` | 声明范围内的 IEEE 1788-2015 bare/decorated interval | enclosure、decoration/NaI、可选 `BallFlags` |

因此 GDA trap 不会被压成 IEEE flag，IEEE 定义好的 infinity 不会被当作通用错误，
Entire、Empty 与 NaI 也不会混为一种失败。

## 数值核心流水线

三个标量核心都采用相同的架构分解：

```text
public immutable value(s) + explicit context
  -> special-state/domain classification
  -> exact coefficient or certified interval computation
  -> one domain-owned finalization
  -> public value + explicit effect data
```

`BinFloat` 保存 sign、非负二进制 coefficient、exponent、precision 与特殊状态；
IEEE/GDA 两个 Decimal 各自保存 package-owned base-`10^9` coefficient、
exponent/quantum 与特殊状态；`BallFloat` 保存两个外向舍入 endpoint 以及
Empty/Entire，decorated interval 再加入 decoration 与 NaI。

Finalization 是语义防火墙：kernel 只产生精确整数事实，不决定标准 flag、cohort、
trap、decoration 或 endpoint 方向。

## 算法选择架构

大整数 kernel 使用分阶段选择器：

```text
size + shape + target + proof preconditions
  -> inline / schoolbook / Comba
  -> Karatsuba -> Toom-3 -> NTT + exact CRT
  -> exact fallback when a precondition fails
```

除法从 word/Knuth D 过渡到 Burnikel-Ziegler 与 reciprocal Newton；稀疏、平方和
不平衡形状采用独立路径。切换阈值是 target-specific 私有策略，由 Maremark 在
dense、sparse、square、balanced、unbalanced 数据集上测量，并在阈值前、阈值点、
阈值后进行精确差分测试。Native、LLVM、Wasm、Wasm-GC、JS 可以选择不同算法，
但必须返回相同公开结果。

## 认证初等函数架构

Binary、decimal 与 interval 栈共享同一 proof contract：

1. 在工作精度上生成 directed lower/upper enclosure；
2. 将两个 endpoint 舍入到目标数值域；
3. 仅当目标 value 与可观察 flags 同时一致时接受；
4. 否则按 `max(32, work / 2)` 增长精度；
5. 12 次 refinement 后返回结构化 certification detail。

`bin_float` 负责标量 dyadic certificate，`ball_float` 将其提升到 endpoint、
critical point、pole 与 domain，decimal 两包通过精确整数转换在 decimal 与 dyadic
enclosure 间往返。Total interval API 可安全放宽到 `[-1,1]` 或 Entire；`try_*`
则暴露 proof/resource failure。

## Context 与 Effect 流

数值包均不依赖环境舍入模式：Binary/IEEE decimal context 是不可变输入，flags
是显式输出；GDA 返回含 sticky status 的新 context 并按固定 precedence 选择 trap；
`BallContext` 控制 endpoint 界限。Binary/interval checked wrapper 保留首个
`ArithmeticError`，`DecimalChecked` 累积 IEEE flags，`GdaDecimalChecked` 在线性
管线中保留单一 outcome 并在 trap 后停止。

这些 wrapper 只组合已有语义，不增加算法，也不合并不兼容的 effect channel。

## 解析与执行

`numeric_expr` 只包含语法数据与 post-order callback evaluation，不做 IO、不选后端。
`gda_expr`、`testfloat_expr`、`mpfr_expr`、`itl_expr` 分别拥有各自外部 grammar。
Frontend 返回 typed summary；CLI 负责文件、filter、shard、render 与 exit code；
Python 工具负责 checksum-pinned 数据、隔离 target/process 与汇总，不替代 MoonBit
数值实现。

## 稳定与内部边界

应用面是 `def`、具体数值包和 checked wrapper；`semantic`、`numeric_expr` 为
provisional integration surface。Frontend 的兼容承诺仅限声明语料与生成接口。
`internal/*`、CLI、`bench/*`、`consistency`、`doc_examples` 属于实现/验证基础设施。
符号出现在 `pkg.generated.mbti` 不自动等于长期应用契约。

## 不变量

- sign 与非负 coefficient 分离；
- binary normalization 只移除二因子；
- decimal parsing 保留 quantum，直到显式 normalization/reduction；
- context finalization 是唯一 bounded rounding/status 决策点；
- interval lower 向下、upper 向上舍入；
- Empty、Entire、NaI、NaN、signed zero、infinity 均为显式状态；
- fast path/fallback 不得改变公开 value 或 effect data；
- conformance summary 完整分割所选 case，sharding 可重复；
- IO、下载、进程与并行调度位于 tooling 边缘。

## 扩展规则

行为应加入拥有其语义的包；新增 umbrella trait 前先组合现有 arithmetic capability。
保持 kernel 私有、context/effect 显式，外部格式解析应留在数值类型之外，除非该格式
本身就是稳定 interchange contract。

扩展 conformance 面时，parser、executor、support classification、CLI schema、manifest、
test、generated interface 与三语文档必须共同更新。能解析新操作不等于已支持；strict
execution 必须拥有定义好的比较与可复现证据。
