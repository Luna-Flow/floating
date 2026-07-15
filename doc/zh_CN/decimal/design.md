# `decimal` 设计

`decimal` 是 0.7.0 的 IEEE-oriented 任意精度十进制核心，组合 quantum-preserving
value、显式 context/flags、decimal32/64/128 interchange 与认证初等函数。独立的
[`decimal_gda`](../decimal_gda/design.md) 拥有 GDA sticky status 与 traps；两种
Decimal 不是 alias。

## 设计契约

Coefficient kernel 只计算精确整数事实，共享 finalization 才决定 bounded decimal
结果：operand/context → 特殊值分类 → 精确 sign/coefficient/preferred exponent →
一次舍入 → exponent/subnormal/tininess/clamp → value + `DecimalFlags`。因此更快的
mul/div 不能改变 rounding、quantum、signed zero、NaN payload 或 flags。

## 表示与 Cohort

有限值表示 `(-1)^negative × coefficient × 10^exponent10`。同一个数可有多个 cohort：
`1.2300` 的 quantum 为 -4，而 `1.23` 为 -2。若 coefficient 能装入 precision，parse
保留输入 exponent；只有显式 `normalized()`/`reduce_ctx()` 才移除十因子。
Numeric comparison 与 `compare_total` 因而是不同关系。

私有 `DecCoeff` 对小值使用 inline storage，对大值使用 canonical little-endian
base-`10^9` limbs，并保存精确 digit count。`BigInt` 只留在公开转换/序列化边界与
test oracle；hot path 直接操作 `DecCoeff`。

## IEEE 754 对齐

`DecimalContext::ieee754()` 与 decimal32/64/128 preset 显式给出 precision、rounding、
exponent、clamp、tininess。`*_ctx` 返回 `(Decimal, DecimalFlags)`，不存在 ambient
flag register。FMA 保持 exact product 到 aligned addition 后只舍入一次。

`DecimalInterchange` 同时实现 DPD/BID，并保留 signed zero、infinity、qNaN/sNaN 与
payload。IEEE matrix 由 `testdata/decimal/ieee/conformance_matrix.json` 限定。
需要 GDA sticky status、trap precedence 或 `.decTest` 行为时必须使用 `decimal_gda`。

## Coefficient 算法选择

选择器考虑 limb count、density、balance ratio、square shape、transform length 与
target。Dense balanced 路径为 schoolbook/Comba → Karatsuba → Toom-3 → dual-modulus NTT；
sparse 与 strongly unbalanced operand 使用专门路径。

| Target | Karatsuba mul/square | Toom-3 mul | 首个 NTT mul/square | BZ division | Newton |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | 2,816 起分段 | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

Native NTT mul 阈值随 transform 依次为 1,728、2,816、4,608、7,680、8,192；
square 为 640、1,040、1,824、3,648、7,296、8,192。BZ boundary 由 2,816 过渡到
5,120/10,240。Native Newton 虽已实现并测试，但 0.7.0 测量不足以支持 production
crossover，所以保持禁用；其他 target 自 4,096 启用。

Karatsuba/Toom 限制 recursion depth 并用 scratch arena；Toom 检查 interpolation
exact division；NTT 检查 transform/coefficient bounds 与 CRT exact reconstruction；
division 检查 quotient/remainder identity 并可退回 Knuth D。临时 buffer 不得逃逸。

## 舍入、指数与 Quantum

Finalization 从精确 signed coefficient 与 preferred exponent 计算 guard/sticky，
然后决定 overflow、underflow、subnormal、rounded、inexact、clamped。`quantize`
固定目标 exponent，装不下时报告 `invalid_operation`，不会偷偷选择另一 scale。

`parse/from_string` 在 precision 允许时保留 quantum；更长 coefficient 只舍入一次。
`from_string_ctx` 还施加 exponent policy 并返回 conversion/rounding flags。

## 认证初等函数

输入被分别向负无穷与正无穷转为 dyadic interval，经 `ball_float` 认证计算后，两端
通过精确整数算术转回 Decimal；只有两端得到相同 target value 与 flags 才接受。
初始工作精度至少 128 bits，共享 12-step refinement budget。`try_*_ctx` 在无法证明
唯一 rounding cell 时返回结构化失败。

固定 MPFR 4.2.2 oracle 用 768-bit directed bounds，覆盖 29 operations、三种格式与
八种 rounding mode 的 2,784 rows；libmpdec `allcr=1` 独立检查 GDA-compatible
`exp/ln/log10`。这属于有限证据，不是所有实数输入的证明。

## 优化与边界调优

Maremark 分离 dense、sparse、balanced、unbalanced、square、kernel 与 full context
路径，并旋转 candidate/baseline 顺序。Production path 必须同时满足精确差分测试与
实际性能收益。Precision/exponent/rounding/quantum 是公开 semantic boundary；
1,152/1,728 等 limb 数是可重调的私有 dispatch boundary。

## 复杂度与取舍

Addition、comparison、normalization、shift、single-limb division 为 `O(n)`；schoolbook
与 Knuth 为二次；Karatsuba、Toom-3、NTT、BZ、Newton 在大规模时降低渐近成本但增加
setup、storage 与 precondition。实现直到实测 crossover 才选择更复杂算法。

## 证据映射

- [API](./api.md) 是公开面清单。
- [Tutorial](./tutorial.md) 解释 quantum、context、interchange 与认证操作。
- [IEEE conformance](./conformance.md) 定义有限 IEEE 声明。
- [Performance](./performance.md) 记录 dispatch protocol。
- [`decimal_gda` conformance](../decimal_gda/conformance.md) 保持 GDA 声明独立。
