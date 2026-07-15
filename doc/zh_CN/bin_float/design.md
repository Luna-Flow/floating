# `bin_float` 设计

`bin_float` 是 0.7.0 的二进制数值核心，同时追求任意精度 dyadic 精确语义与
`BinaryContext` 下声明范围内的 IEEE 754-2019 行为。公开名称由
`src/bin_float/pkg.generated.mbti` 确定；limb 布局、阈值与 scratch storage
属于私有实现。

## 设计契约

实现把三类职责分开：`BinCoeff` 负责精确非负整数算术，`BinFloat` 表示 dyadic
值或特殊状态，`BinaryContext` 为一次操作施加 precision、exponent range、
rounding、tininess 与 flags。kernel 算法只改变精确 coefficient 的计算成本，
只有 context finalization 能改变最终浮点表示。

## 表示与不变量

有限值表示 `(-1)^negative × coefficient × 2^exponent2`。非零 coefficient
经 normalization 后为奇数，sign 独立存储，因此保留 signed zero。Infinity、qNaN、
sNaN 与 payload 绕过有限值模型并保持可观察。

非 JS target 使用 inline 64/128-bit 或 little-endian 32-bit limbs；JS 在同一公开
契约后使用 host `bigint`。调用者不能观察 storage form 或算法选择。

## 标准对齐

IEEE 路径固定为：特殊值分类 → 精确 dyadic/rational 或认证 enclosure → 按目标方向
一次舍入 → exponent/tininess 处理 → value + `BinaryFlags`。`BinaryInterchange`
直接处理 binary16/32/64/128，不经 host Float/Double。

固定 TestFloat 矩阵覆盖四种格式上的 add/sub/mul/div/sqrt、五种 rounding direction
与两种 tininess policy；MPFR 4.2.2 覆盖文档声明的 sqrt、integer power 与 elementary
边界。有限矩阵通过不等于覆盖全部 IEEE 754 操作与实数输入。

## Coefficient 算法选择

乘法同时依赖短边 limb 数 `n`、长边 `m`、target 与 proof precondition：

| 决策 | 条件 | 路径 | 原因 |
| --- | --- | --- | --- |
| 小输入 | `n < 96` | inline/schoolbook | 避免递归与分配成本 |
| Transform | 达到 NTT 阈值且 CRT bounds 成立 | 双素数 Montgomery NTT + CRT | 大规模 dense product |
| Oversized transform | 完整 transform 不适用但 overlap 合法 | overlap-add NTT | 保留 transform 扩展性 |
| 不平衡 | transform 检查后 `m > 2n` | 分块长 operand | 避免矩形乘法 padding |
| 大型平衡 | 达到 Toom-3 阈值 | Toom-3 | 降低递归乘法数 |
| 中型平衡 | 其余 | scratch-backed Karatsuba | 低于 transform 的设置成本 |

| Target | Karatsuba | Toom-3 / NTT mul | NTT square | recursive square |
| --- | ---: | ---: | ---: | ---: |
| native | 96 | 2,048 | 768 | 512 |
| LLVM | 96 | 2,048 | 768 | 768 |
| Wasm / Wasm-GC | 96 | 4,096 | 3,072 | 768 |

平方拥有专用 schoolbook kernel。NTT 选择前检查 transform 与 reconstruction bounds，
失败时切换精确 fallback。除法依次使用 inline/word、48 limbs 以下 Knuth、48 起
Burnikel-Ziegler、1,024 起 reciprocal Newton；近等短商可使用 bounded high-product
search。所有路径满足 `n = qd + r`、`0 <= r < d`。Sqrt 在 512 bits 内使用 fixed-width，
更大时用 divide-and-conquer；GCD 从 Euclid 过渡到 Lehmer batching。

## 认证初等函数

`try_*_ctx` 计算 directed lower/upper enclosure，将两端按目标 context 舍入，仅在
value 与 flags 均一致时接受。最多 refinement 12 次，每次按
`max(32, work / 2)` 增长工作精度。Range reduction 或 rounding cell 无法证明时返回
结构化 `ArithmeticError::CertificationFailure`；非 `try` API 使用同一证明路径，
不会退化为 host transcendental 猜测。

## 优化与边界调优

Maremark 按 balanced、unbalanced、sparse、dense、square 与 target 分别测量，
而非只看渐近复杂度。新路径必须同时通过阈值前/点/后的精确差分/property test，
并在 paired benchmark protocol 下显示实际收益。调优可以移动私有 dispatch boundary，
不能移动公开数值契约。

## 复杂度与取舍

Schoolbook 为 `O(n^2)`，Karatsuba 为 `O(n^log2(3))`，Toom-3 为
`O(n^log3(5))`，NTT 约为 `O(n log n)`但常数与临时内存更高。大型
Burnikel-Ziegler/Newton division 逐步接近 multiplication cost。实现是在 exactness
约束下优化期望成本，而不是为了速度降低 exactness。

## 证据映射

- [API](./api.md) 给出 0.7.0 公开面。
- [Tutorial](./tutorial.md) 给出推荐构造与 context 流程。
- [Conformance](./conformance.md) 限定 TestFloat/MPFR 声明。
- [Performance](./performance.md) 记录 target-specific dispatch 与固定发布对比基线。
