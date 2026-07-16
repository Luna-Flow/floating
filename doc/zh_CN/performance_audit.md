# 0.7.1 性能与语义审计

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.0 -->

本文是 0.7.1 优化审计的中文结构源。它记录 0.7.0 之后的四个优化提交、
发布复核中发现并修复的语义问题，以及性能声明的证据边界。

## 范围

审计覆盖提交 `69084bc`、`7904016`、`23005ed`、`4fd41ad`，以及本发布树中
待纳入的 GDA 系数辅助函数和区间回归修复。审计明确区分观察结果、规范要求、
实现选择和验收证据。

## 问题矩阵

| 行 | 分类 | 观察结果 | 预期 | 变更 | 验收证据 |
| --- | --- | --- | --- | --- | --- |
| GDA 系数内核 | 实现缺口 | GDA 快路径加入小表示、仅余数除法和半十进制幂比较 | 系数恒等式、cohort、flags、trap 和 sticky status 不变 | 使用规范化 `GdaCoeff` 操作并保留统一 GDA finalizer | 93 个包测试、8 个前端测试、`official` 64,986/64,986、`official0` 16,124/16,124 |
| IEEE decimal 路径 | 语义风险优化 | exact/bounded division 路径绕过了重复通用工作 | 精确结果、舍入、quantum、flags 和特殊值行为与 IEEE 一致 | 用有限域、因子、边界和 finalizer 条件保护快路径；不满足时回退 | 94 个包测试、四目标 IEEE 15,763/15,763 |
| Binary IEEE 路径 | 语义风险优化 | exact-top、round/sticky 提取和系数分派替代了更宽的中间结果 | context 下的值、舍入、flags、signed zero 和 interchange bits 不变 | 保留精确系数构造，所有结果仍经 contextual rounding | 68 个包测试、binary 7,464,503/7,464,503 |
| 区间端点分派 | 已发现并修复的语义偏差 | 优化后的 `pown` 在不同符号区域复用端点方向，负区间可能得到 `lo > hi` 或少一个 ulp | 每个区间有序并包含数学像集 | 按单调性选择端点并逐项向外舍入；加入负半轴覆盖 | 42 个包测试、integer-power 174/174、strict ITF1788 4,656/4,656 |
| 发布文档 | 文档缺口 | module、manifest 和本地化正文仍以 0.7.0 为当前基线 | 当前引用统一指向 0.7.1，历史说明保持历史身份 | 更新当前元数据并加入同步审计页 | `python3 tools/doc_quality.py` |

## 优化证明

### 精确系数路径

对于非负系数 `a` 和正除数 `d`，余数为
`r = a - floor(a / d) * d`，且满足 `0 <= r < d`。因此，用只计算余数的
内核替换 quotient/remainder 调用不会改变任何可观察余数，也不会改变欧几里得
算法中的步骤。GDA 半十进制幂谓词通过最高位十进制数字和其后的非零尾部比较
`a` 与 `5 * 10^(digits(a) - 1)`，不是浮点近似。

IEEE decimal 的 exact-division 路径先消去系数 GCD；只有约分后的分母不含 2、5
以外的素因子时才允许进入。路径构造精确的十进制系数/指数后仍调用原有 finalizer；
因子、边界或特殊值条件不满足就回到通用算法。因此优化改变的是到达精确值的路线，
不是 IEEE 的舍入或 flag 规则。

### Binary contextual 路径

有限 dyadic 值写作 `c * 2^e` 时，`binary_exact_top(c, e)` 给出最高有效精确位。
比较这些 top 等价于对齐前比较幅值，也适用于带有不同尾随二次幂的系数。远距离加法
丢弃低位时，split 操作保留首个丢弃位和其后所有位的 OR；这正是 contextual rounding
函数所需的 round/sticky 谓词。快路径因此保持相同的精确舍入输入，同时避免构造巨大
对齐系数。

### 有向区间路径

区间操作必须保持集合包含不变量 `image(X) subset [lo, hi]` 与存储不变量
`lo <= hi`。对精确端点候选 `y`，`RoundTowardNegative(y)` 是下界证书，
`RoundTowardPositive(y)` 是上界证书。`pown` 分支使用以下单调性表：

| 定义域 | 正奇次幂 | 正偶次幂 | 负奇次幂 | 负偶次幂 |
| --- | --- | --- | --- | --- |
| 负半轴 | 递增 | 递减 | 递减 | 递增 |
| 正半轴 | 递增 | 递增 | 递减 | 递减 |
| 含零区间 | 端点顺序 | 零到向外舍入的最大值 | 极点/全实数分支 | 极点/全实数分支 |

实现现在先选择数学端点，再应用其角色所需的方向。跨零时，两个有限极值候选都用
向正无穷舍入来形成上界；`quantize_interval` 再做一次向外舍入。该证明局限于已声明
的操作和精度契约，不代表未支持的 reverse 操作。

## 性能证据

| 领域 | 测量 | 解释 |
| --- | --- | --- |
| Binary、decimal、GDA、interval 内核 | `just bench all --target native` | 当前树的四套 Maremark 基准都生成了合法 artifact |
| Binary square 策略 | `just bench auto-tune --target native` | 生成目标相关策略 artifact；原始观测可能非单调，不是通用阈值声明 |
| IEEE/GDA 快路径 | benchmark 包测试与 conformance gate | 只有语义 oracle 继续通过时，性能路径才可接受 |
| 区间端点分派 | `src/bench/ball_float` 与 strict ITF1788 | 只有有序且向外舍入的包络成立时，降低成本才可接受 |

生成 artifact 位于 `.tmp/bench/`，有意不作为 API 数据发布。提升 crossover 前，应在
目标硬件上重新执行命令。benchmark workload 只证明当前树上的测量，不证明整个发行版、
所有目标的速度等价或普遍延迟上界。

## 验收矩阵

| 检查 | 结果 |
| --- | --- |
| `sh tools/run_moon_clean_exec.sh test src/decimal_gda --target native --deny-warn --frozen --no-parallelize` | 93/93 通过 |
| `sh tools/run_moon_clean_exec.sh test src/decimal --target native --deny-warn --frozen --no-parallelize` | 94/94 通过 |
| `sh tools/run_moon_clean_exec.sh test src/bin_float --target native --deny-warn --frozen --no-parallelize` | 68/68 通过 |
| `sh tools/run_moon_clean_exec.sh test src/ball_float --target native --deny-warn --frozen --no-parallelize` | 42/42 通过 |
| `just gate binary 8` | 7,464,503/7,464,503 通过 |
| `just gate decimal 8` | 15,763/15,763 通过 |
| `just gate decimal_gda 8` | 64,986/64,986 与 16,124/16,124 通过 |
| `just gate interval 8` | 4,656/4,656 通过 |
| `python3 tools/doc_quality.py` | 版本、审计页和设计证明变更后通过 |

## 审阅者自检

- 贡献：通过——记录了具体优化边界和真实语义故障修复，没有把无法解释的
  benchmark 结果包装成速度承诺。
- 写作清晰度：通过——每个证明段分别说明表示、单调性、舍入方向和证据。
- 实验强度：需要复现——native artifact 有效，但应在提升阈值前重复非单调的
  auto-tune 观测。
- 评估完整性：对声明的固定语料通过；不表示支持所有标准操作或任意实数输入。
- 方法健全性：通过——负半轴回归与完整 1788 gate 已覆盖修复后的分支。

## 声明—证据映射

| 声明 | 证据 | 状态 |
| --- | --- | --- |
| 快速系数路径保持声明的数值结果 | 精确内核恒等式、包测试、IEEE/GDA conformance | 在声明 API 与前置条件内支持 |
| 区间 `pown` 保持有序的向外包络 | 单调性表、负半轴回归、4,656 条 strict ITF1788 | 对声明的正向区间面支持 |
| 本版本完成了性能审计 | native Maremark `all` 与 `auto-tune` artifact | 作为测量证据支持，不是通用速度声明 |
| 所有未来目标和操作具有等价性能 | 本审计没有跨目标 paired artifact | 需要证据；明确不声明 |

## 限制

语义声明受固定语料、公开操作面、目标相关精度规则和显式 fallback 契约限制。
`0.6.1` elementary manifest 仍是历史比较基线，`0.7.1` 是当前 candidate release。
任何 API、舍入规则、错误信号或区间契约都不会仅为改善 benchmark 而改变。
