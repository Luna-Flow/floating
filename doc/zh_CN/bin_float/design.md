# `bin_float` 设计

## 职责与表示

`bin_float` 负责任意精度二进制标量、IEEE 上下文/互换格式，以及二进制和区间层共用的非负 `BinCoeff`。有限值表示为独立符号、系数、`2^exponent2` 和工作精度；非零系数会移除可约的 2 次幂。带符号零、无穷大、qNaN/sNaN 和 payload 都是可观察状态。

非 JS 后端使用 inline 值或小端 limb；JS 在同一接口后隐藏宿主 `bigint`。布局不是 API。`Decimal`/`Semantic` 的 `BigInt` 边界不随此次迁移改变。

## 系数算法选型

乘法按 limb 规模和形状分派：96 以下用 schoolbook，96 起用 Karatsuba；长宽比超过 2 时用不平衡分块；大型平衡输入用 Toom-3；满足变换长度和系数界时用双素数 Montgomery NTT+CRT，并为过长输入提供 overlap-add。Native/LLVM 的 Toom/NTT 乘法阈值为 2048、NTT 平方为 768； Wasm/Wasm-GC 为 4096 和 3072。这些是基准调参，不是稳定承诺。

除一 limb 外，除法依次选择 Knuth（<48 limbs）、Burnikel–Ziegler（≥48）和 Newton reciprocal（≥1024）；近等长短除法先做有界高乘积搜索。平方根在 512 bit 内使用定宽核，以上使用分治；大整数 GCD 使用 Lehmer 批处理。

## 数学模型与舍入流水线

有限非零值表示为 `(-1)^negative × coefficient × 2^exponent2`。`coefficient`
非负且规范化会移除全部因子 2，因此同一 dyadic 只有一个规范表示。上下文运算
按“特殊值分派 → 精确 dyadic/rational → 商余数舍入 → 指数编码 → flags”执行；
inexact 由非零余数决定，overflow、underflow 和 tininess 在目标指数范围上计算。

## API 边界

普通运算适合任意精度值；`*_ctx` 才表达 IEEE 格式、舍入和状态，
`BinaryInterchange` 才是 binary16/32/64/128 的位级边界。`precision` 不等于
IEEE 格式，有限 TestFloat/MPFR 矩阵也不代表完整 IEEE 754。

## 舍入与边界

上下文运算先解析特殊值，形成精确 dyadic/rational 结果，再用商/余数、guard/sticky 一次舍入，最后处理指数界限和 tininess。整数幂先尝试有界近似与 can-round 判定，精确系数幂始终作为正确性回退。已验证矩阵只覆盖文档列出的 TestFloat/MPFR 操作，不等于完整 IEEE 754。阈值、limb、NTT 素数和 scratch arena 均属实现细节。

## 复杂度与算法取舍

`n` 个 limb 的 schoolbook、Karatsuba、Toom-3 和 NTT 复杂度约为 `O(n²)`、
`O(n^1.585)`、`O(n^1.465)` 和 `O(n log n)`。小输入选择常数更低的路径，大而
均衡的输入才承担变换和临时内存；大除法通过 Burnikel–Ziegler/Newton 趋近
`M(n)`。所有快速路径都有精确回退，因此性能分派不改变结果。
