# `decimal_gda` 设计

`decimal_gda` 是 0.7.1 的独立 General Decimal Arithmetic 1.70 引擎，以固定
testcase suite 2.62 验证。它不依赖 IEEE-oriented `decimal`；value、coefficient、
context、flags、interchange 与 finalization 均由本包拥有。

## 设计目标

GDA 操作不仅产生数值，还会产生 conditions、更新 sticky status，并可能按 trap
转移控制，同时保留 defined result。因此操作被建模为纯状态转换：operand/context →
exact operation + finalization → value/raised/next context → fixed-precedence trap →
`Completed` 或 `Trapped`。Trap 不是抹掉 value 的 exception，status 也不是 ambient state。

## 值与 Coefficient 表示

有限 `Decimal` 保存 classification、sign、package-owned `GdaCoeff`、exponent、
precision、sNaN state 与 payload。`Small(UInt64)` 覆盖 `10^18-1` 以内，
`Limbs(Array[UInt], digits)` 使用 little-endian base-`10^9`。公开值不共享可变 scratch。

表示保留 cohort、signed zero、qNaN/sNaN 与 payload，以支持 copy、class、total-order、
same-quantum、formatting 与 interchange；不能只保留数学相等关系。

## Context、Status 与 Trap 对齐

`GdaContext` 直接保存 precision、八种 rounding、exponent bounds、clamp、extended、
sticky status 与 trap set。每次操作产生 `raised`，合并到 next context，再按固定 GDA
precedence 选出至多一个 trap。`Completed` 与 `Trapped` 都保留 defined value、next
context 与 raised flags。显式 threading 保证 deterministic precedence、无 thread-local
状态，并允许无损恢复。

## 算术与 Finalization

有限算术先形成精确 signed coefficient 与 preferred exponent，再由共享 GDA finalizer
决定 rounding、cohort、clamp、subnormal、underflow、overflow、signed zero 与 flags。
FMA 保留 exact product 到 addition 后一次舍入。Coefficient kernel 不直接设置 GDA flags。

1–18 digit 的 parse/add/sub/mul/FMA 有 proved wrapper fast path，但仅在 finite、`Small`、
precision/exponent 内、无需 clamp 且 flag-free 时启用；任一 predicate 失败都回到通用
finalizer。White-box differential test 比较 value、flags、sticky context、trap 与 fallback。

## Coefficient 算法选择

本地引擎包含 schoolbook/Comba、Karatsuba、Toom-3、dual-modulus NTT、Knuth D、
Burnikel-Ziegler 与 reciprocal Newton，并同时考虑 size、density、balance、square、
transform length 与 target。

| Target | Karatsuba mul/square | Toom-3 | 首个 NTT mul/square | BZ | Newton |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | 2,816 起分段 | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

Native NTT/BZ boundary 随 transform/block 增长至 8,192/10,240。NTT bounds、CRT、
Toom exact division 与 quotient/remainder identity 均被检查，失败使用精确 fallback。
阈值数值虽与 IEEE decimal 当前相同，两套代码与测试仍独立，避免未来 IEEE 改动泄漏。

## 认证初等函数

Sqrt 使用本地 integer-sqrt；integer power 用 exact/bounded exponentiation。Non-integer
power、`exp/ln/log10` 使用 directed binary interval 认证最终 decimal rounding cell。
低成本初始精度只用于普通 bounded operand，inconclusive 时回到保守 refinement；
`ln(10)` 使用不可变单项 cache。任何 approximate candidate 都必须经过 GDA finalization。

GDA mathematical-function 边界只暴露 sqrt、power、exp、ln、log10。Trigonometric、
hyperbolic、inverse、atan2、hypot 与 pi-scaled 不属于该 GDA adapter。

## 非算术与 Interchange 操作

包实现固定语料使用的 legal scalar inventory：comparison/total order、extrema、logB、
same-quantum、adjacent、copy/class/predicate、logical digits、shift/rotate、integral
conversion、scientific/engineering formatting。Concrete decimal32/64/128 interchange
由本包以 DPD 实现；BID 属于 IEEE package，故有意缺席。

## 优化与切换边界

候选优化首先必须在 value、cohort、raised、next status、trap 上完全一致，其次才需要
target benchmark 收益。Boundary test 覆盖阈值前/点/后以及 sparse、square、unbalanced。
Small fast path 是 semantic predicate；large kernel selector 是 performance policy，二者
不能混淆。

## Effect 与验证边界

`.decTest` parsing、directive snapshot、sharding、JSON、filesystem 与 process status
位于 frontend/CLI/Python tooling；本包是 deterministic value/context transformation。
0.7.1 验收组合 package/property tests、all-target、dependency scan、IEEE isolation 与
两套固定语料：`official` 64,986/64,986 legal rows，`official0` 16,124/16,124；141 条
`#` placeholder/non-scalar 为分母外 diagnostic。

## 0.7.1 语义保持证明

GDA 系数余数路径计算的仍是相同的欧几里得余数 `r = a - floor(a / d) * d`，并满足 `0 <= r < d`。
因此 GCD、exact division 和 half-power comparison 看到的规范化系数事实不变。半幂谓词通过最高位十进制
数字和剩余非零 limb 与 `5 * 10^(digits - 1)` 比较，绝不把系数转换成二进制近似。

小值算术路径只有在有限结果适合 `Small`、context 边界且满足无 flag 条件时才进入；随后仍使用同一 GDA
finalizer 和 trap precedence。语义验收元组是 value/cohort、raised flags、next sticky context、defined result
和 selected trap。包测试、前端测试、边界 differential test 及两套 decTest 语料覆盖声明面；系数阈值仍是性能策略，
不是 GDA 规则。

## 证据映射

- [API](./api.md) 列出 GDA value/context/outcome 面。
- [Tutorial](./tutorial.md) 演示 context threading、trap 与恢复。
- [Conformance](./conformance.md) 定义固定语料与隔离检查。
- [`decimal` Design](../decimal/design.md) 说明独立 IEEE 模型。
