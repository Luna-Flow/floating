# `decimal` 设计

## 职责与表示

`decimal` 负责任意精度十进制值、General Decimal Arithmetic context/flags，
以及 decimal32/64/128 interchange。有限值具有独立符号、系数、十进制指数、
cohort 和工作精度；负零、无穷、qNaN/sNaN 与 payload 都是可观察语义。

系数内核是私有实现：使用小端 base-1e9 `UInt` limb，并用 `UInt64` 做宽中间值。
单 limb 系数使用 inline 表示，更大的系数使用 limb-backed 数组；零只有一种
canonical 形式，数组无前导零，十进制位数精确。公开 API 不暴露这些布局。
BigInt 仅保留在公开转换/序列化边界以及测试 oracle/debug 边界，Decimal 热路径
直接消费私有系数。

解析和量子敏感操作可以保留尾零/指数 cohort；`normalized()`/`reduce_ctx()` 只
移除不影响数学值的十次幂。普通数值 equality 与 `compare_total` 因而不同。

## 系数与舍入算法

小规模操作使用 inline arithmetic、checked 加减、Comba/schoolbook 乘法、专用
square、单 limb 除法、精确幂、GCD、整数 `sqrt_rem` 和平方求幂。稀疏操作数先压缩
非零项；短边足够大时，强不平衡操作数按平衡 block 拆分，小尺寸形状则保留单一
规范化 accumulator。

平衡乘法分派同时考虑长度、density、平衡比、是否 square 和 target-specific
threshold。生产阶梯为 schoolbook、Karatsuba、Toom-3、双模数 NTT convolution。
Karatsuba/Toom-3 使用有界递归和 scratch；Toom-3 的负中间值只存在内部 signed
scratch，并检查插值中的 exact division。NTT 使用更小的十进制工作 digit、CRT
重建和显式长度/系数上界，不满足条件时回退。

除法依次选择 word division、归一化 Knuth Algorithm D、Burnikel–Ziegler block
递归或 Newton reciprocal。每条路径检查商/余数不变量，并可回退到更保守的算法。
scratch arena 复用临时 limb buffer，但 rewind 后的 buffer 不会逃逸到结果。

Context 操作先处理特殊值，计算精确系数/指数，再按八种 rounding 舍入，最后应用
指数界限、subnormal、clamp 和 `DecimalFlags`。FMA 保持乘积精确直到加法；sqrt
和初等函数使用系数原生 guard digit 与迭代/级数 refinement，最后只做一次 context
finalization。quantize 固定目标指数，结果系数无法适配 context 时报告
`invalid_operation`。

## Context 与 interchange 边界

`DecimalContext` 是不可变输入，`*_ctx` 返回 `(Decimal, DecimalFlags)`；flags 是
显式累积数据，不依赖 ambient mutable state。`DecimalInterchange` 让 DPD 与 BID
decimal32/64/128 共用同一 Decimal 语义层，统一处理 canonicalization、非 canonical
有限编码、NaN payload、Infinity 和 signed zero。编码选择不会复制 arithmetic 或
rounding 语义。

## 能力与合规边界

公共能力包含算术、FMA、整除/余数、quantize/rescale、total compare、逻辑数字、
邻接值、分类、格式化、interchange 和初等函数。GDA 与 IEEE gate 分开统计：固定
`official`/`official0` 覆盖合法标量语义，独立 IEEE decimal32/64/128 vectors 覆盖
操作、flags、特殊值、total order、格式转换以及 DPD/BID bit pattern。支持的 target
要求两套 gate 都是零 failed/unsupported。

## 复杂度与权威参考

对 `n` 个 base-1e9 limb，加减、比较、移位、规范化和单 limb 除法为 `O(n)`；
schoolbook 与 Knuth 除法为 `O(n²)`。Karatsuba、Toom-3、NTT、Burnikel–Ziegler、
Newton 只在实测 crossover 值得 setup 成本时启用。所有算法出口都做 canonicalize
和精确 carry 检查，优化不能改变 Decimal rounding 或 cohort 语义。

算法与语义参考：Knuth《The Art of Computer Programming》Vol.2 Algorithm D、
Karatsuba 乘法、Bodrato Toom-Cook 插值、Burnikel–Ziegler《Fast Recursive
Division》、Brent–Zimmermann《Modern Computer Arithmetic》、Cowlishaw 的 GDA
规范与 decNumber，以及 IEEE 754-2019 / ISO 60559。

## 证据映射

[IEEE 一致性](./conformance.md)、[`decimal_gda` 一致性](../decimal_gda/conformance.md)与[性能](./performance.md)是三份独立证据账本，避免混淆 GDA status、IEEE flags 和 benchmark threshold。
